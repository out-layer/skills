---
name: hyperliquid-connector
description: Trade Hyperliquid perpetuals from an OutLayer custody wallet through the `hyperliquid` connector — leverage, limit and market orders, cancels, positions, funding in and out — under the wallet owner's policy. Use when an agent with an OutLayer wallet needs to open, manage or close perp positions on Hyperliquid.
---

# Hyperliquid connector

You trade from the wallet's `trading` sub-key: an address Hyperliquid knows
as the account. You never see a key and you never pay gas — every action is
signed inside the TEE, checked against the owner's policy before it is sent,
and HyperCore has no gas. If the policy says no, the answer says why: read
it, do not retry.

Every number in this file was observed on mainnet with real money. Where it
says "seen", that is what happened.

## Call shape

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/hyperliquid
X-Payment-Key: <a payment key the custody wallet owns>
X-Wallet-Id: <the wallet id>
X-Use-Owner-Secret: 1
Content-Type: application/json

{"input": {"operation": "<op>", ...}}
```

Two envelopes come back. The platform's: `{call_id, status, output,
compute_cost, time_ms}`. Inside its `output`, the connector's: `{success,
operation, output, error}`. **A connector refusal arrives as HTTP 200 with
`output.success: false`**; the word before the colon in `output.error` is
the contract — `policy_denied`, `invalid`, `signature_mismatch` — and a venue
refusal reads `Hyperliquid rejected …` / `Hyperliquid refused …` with the
venue's own sentence.

Testnet: `https://testnet-api.outlayer.ai/call/connectors.outlayer.testnet/hyperliquid`
with `HYPERLIQUID_TESTNET=1` stored next to the policy. Trading works there;
funding does not (1Click has no testnet).

## What you need before the first call

* **A payment key the wallet owns.** The trial key (`POST /trial-key` with
  the wallet's `wk_`) gives 10 connector calls in the wallet's first week,
  free operations included. A funded key has no call limit; creating one
  needs the wallet's NEAR account to hold **≥ 0.3 NEAR**.
* **USDC on the wallet's intents balance** — what `deposit_start` draws from
  and where withdrawals return. The plain balance is a different pot. Ask the
  owner to fund with `dest=intents`.
* **The owner's policy**, `HYPERLIQUID_POLICY`, stored under your wallet for
  this connector. Without it you are read-only. `status` shows it.

## Funding the wallet — how to ask for it

`deposit_start` draws from the wallet's **intents** USDC. Three ways to put
it there, in order of convenience:

* **The dashboard**, one link for the owner to open with their NEAR wallet:
  `https://app.outlayer.ai/wallet/fund?to=<near_account_id>&token=17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1&amount=15&dest=intents`
  — `to` is the wallet's NEAR account (`GET /wallet/v1/address?chain=near`),
  `token` is native USDC, `dest=intents` puts it on the intents balance
  (without it the USDC lands on the plain balance, a different pot). Seen:
  11 USDC arrived on intents within a minute.
* **A direct transfer** from any NEAR account: `ft_transfer_call` on the
  USDC contract to `intents.near` with `msg` = the wallet's NEAR account id
  — that is exactly what the dashboard signs.
* **From the wallet's own plain balance**: `POST /wallet/v1/intents/deposit
  {"token": "<usdc>", "amount": "<units>"}` (needs NEAR for gas on the wallet).

Do not route NEAR-side money through a 1Click quote to reach intents: it
adds a fee and an amount-matching rule for nothing.

## First calls, in order

1. `{"operation": "status"}` — free, ~3 s. `addresses.trading` (your
   account), `perp.account_value_usd`, `perp.withdrawable_usd`, `spot.usdc`,
   `activation` (`user_exists`, `next_outbound_fee_usdc`), the policy caps,
   today's volume, and `limits` — the floors below.
2. `{"operation": "deposit_start", "amount": "15"}` — moves USDC from the
   wallet's intents balance to your Hyperliquid account through 1Click.
   **At least 2 USDC**; the flat fee is ~0.32 (seen: 15 → 14.683633).
   The money lands on **perp**, ready to trade, in about a minute. Poll
   `{"operation": "deposit_status", "id": "<id>"}` (a read) until `step:
   "done"`; it carries `landed_usdc`, `landed_in`, `account_existed`. The
   deposit is what creates a new account — nothing else is needed.
   `"to": "spot"` parks it on spot instead (`deposit_continue` then does the
   class transfer).
3. `{"operation": "leverage", "coin": "ETH", "leverage": 2}` — **required
   once per coin before the first order in it**: a fresh account trades at
   the market's maximum otherwise, and the connector refuses an order
   without a recorded leverage. `"cross": false` for isolated.

If `deposit_start` answers with a `warning` that the wallet did not confirm
in time, the transfer may still be in flight: poll `deposit_status` for a few
minutes before starting another. Seen once — the money had moved.

## Trading

| do | call |
|---|---|
| see markets | `{"operation": "markets", "coins": ["ETH", "BTC"]}` → `mark_px`, `mid_px`, `oracle_px`, `funding`, `open_interest`, `sz_decimals`, `max_leverage`, `only_isolated` |
| limit order | `{"operation": "order", "coin": "ETH", "side": "buy", "size": "0.004", "kind": "limit", "price": "2500", "tif": "Gtc"}` (`tif`: `Gtc`, `Ioc`, `Alo` = post-only) |
| market order | `{"operation": "order", "coin": "ETH", "side": "buy", "size": "0.004", "kind": "market"}` — IOC priced at mark ± `slippage_bps` (default 50, cap 500); fills at the book, not at that price (seen: priced 2672.4, filled 2660.2) |
| close | the opposite side with `"reduce_only": true` — the owner's size caps do not apply to a close |
| your own id | `"cloid": "0x<32 hex>"` on an order; cancel with it |
| cancel | `{"operation": "cancel", "coin": "ETH", "oid": 555397050502}` or `"cloid": "0x…"` |
| open orders | `{"operation": "orders"}` |
| positions | `{"operation": "positions"}` → `size`, `entry_px`, `position_value_usd`, `unrealized_pnl_usd`, `liquidation_px`, `leverage`, `margin_used_usd`, `funding`, plus `account_value_usd`, `withdrawable_usd` |
| spot ↔ perp | `{"operation": "class_transfer", "amount": "10", "to": "perp"}` — internal, free, instant |

Numbers are decimal strings: `size` to the market's `sz_decimals` (4 on
ETH), `price` with at most 5 significant figures (integers always allowed).
`1e-3`, signs and spaces are refused. The answer to `order` carries the
venue's `status`: `{"filled": {"avgPx", "oid", "totalSz"}}` or `{"resting":
{"oid"}}`; a venue refusal is `success: false` with its sentence.

**The venue's minimum order is $10 notional, and it applies to a reduce-only
close as well.** Seen: `Order must have minimum value of $10. asset=1` on a
0.003 ETH ($8) reduce-only sell, while the full 0.004 ($10.6) close went
through. So never open a position you cannot close in one order of ≥ $10,
and do not try to trim a small position in pieces.

### Finding a market without spending a call

Hyperliquid's info endpoint is public, no key, same host the connector
reads: `POST https://api.hyperliquid.xyz/info` with a JSON body. Search and
read there, place and settle through the connector.

* `{"type": "meta"}` → `universe[]`: every perp with `name`, `szDecimals`,
  `maxLeverage`, `onlyIsolated`, `isDelisted`. The coin name is what `order`
  takes.
* `{"type": "metaAndAssetCtxs"}` → the same list plus, in the same order,
  `markPx`, `midPx`, `oraclePx`, `funding`, `openInterest`, `dayNtlVlm`,
  `prevDayPx` — enough to rank by volume, funding or move.
* `{"type": "l2Book", "coin": "ETH"}` → `levels[0]` bids, `levels[1]` asks,
  each `{px, sz, n}` — the depth a market order will eat.
* `{"type": "allMids"}` → `{coin: mid}` for everything at once.
* `{"type": "candleSnapshot", "req": {"coin": "ETH", "interval": "1h",
  "startTime": <ms>, "endTime": <ms>}}` → OHLCV.

Show the user `https://app.hyperliquid.xyz/trade/<COIN>`. The connector's
own `markets {"coins": [...]}` gives the same numbers for a tenth of a cent
when a call is simpler than an HTTP fetch; it also filters out delisted
markets and is what the policy's `coins` list is checked against.

### Did it fill?

A market order says so at once (`status.filled`). A limit order rests
(`status.resting`, its `oid`) and is on `orders` until filled or cancelled;
then the position shows on `positions`. So "did my bid fill?" is `orders`
(still there → no), then `positions`. Poll when something should have
changed, not in a loop — each read is a paid call. The connector keeps no
order history: note the `oid` the venue returns.

### Closing out

Cancel every resting order (`orders` → `cancel` each `oid`), then close each
position with the opposite side, `reduce_only: true`, `kind: market`, for the
whole `size`. Check `positions` is empty before withdrawing.

## What the policy caps (owner's `HYPERLIQUID_POLICY`)

`max_order_usd` per order (at the limit price, or mark ± slippage for a
market order), `max_position_notional_usd` after the order,
`max_daily_volume_usd` per UTC day (a resting order counts when placed, a
reduce-only order counts but is never refused), `max_leverage`, `coins`;
`allow_deposit` + `max_deposit_usd`; `allow_withdraw` + `withdraw_to`.
Read `status.policy.caps` first and size orders inside them instead of
discovering the caps by refusal — a refused call is still billed.

## Wins and losses, where to read them

* While you hold: `positions[].unrealized_pnl_usd` against `entry_px`;
  `return_on_equity`; `funding.sinceOpen` is what funding has cost or paid.
* After you close: the row leaves `positions`; the result is in
  `account_value_usd` (seen: 14.683633 before the round trip, 14.679365
  after a $10.64 fill — the 0.045 % taker fee — and +0.0092 after the close
  at 2662.5 against 2660.2). Note it yourself at the time; the connector
  keeps no trade history.
* `withdrawable_usd` is what can leave without touching open positions'
  margin.

## Getting money back out

```json
{"operation": "withdraw_start", "amount": "13.6", "destination": "intents"}
```

then `{"operation": "withdraw_status", "id": "<id>"}` (a read) until `step:
"done"` with `delivered_units`. Seen: **13.39788 USDC on intents 1.7
minutes after the call.** What happens inside one call: what spot is short
of is moved from perp (`moved_from_perp`; refused, naming `withdrawable`,
when perp cannot release it — close positions first), the 1Click route is
quoted for exactly the amount (a refused quote moves nothing), and a
HyperCore spot transfer sends the amount to the quoted address. Destinations:
`intents`, `confidential` (the shielded balance), or a HyperCore `0x` account
(done at once, no 1Click).

* **The account's first outbound transfer costs 1 USDC on top of the
  amount**, taken from spot; `status.activation.next_outbound_fee_usdc` says
  `"1.0"` until then and `"0.0"` ever after. Seen: 14.6 on spot − 13.6 sent
  − 1.0 = 0.
* 1Click deducts a flat **0.2 USDC** from what arrives and pays out its quote
  (seen: 13.6 sent → 13.4 deposited → 13.39788 on intents).
* **At least 2 USDC** to the wallet: 1Click answers a bare server error under
  that, and the connector refuses first with `invalid:`. The transfer inside
  HyperCore is exact, so the floor is on what you send.
* `withdraw_start` returns `remainder_usd` — what stays in the account — and
  a `warning` when it is under the floor: it cannot leave on its own, but it
  is still collateral you can trade. Plan the LAST withdrawal to be ≥ 2 USDC
  and take everything in one call: `amount = account value − 1.0 (if not yet
  activated) − a few cents`.

## Links to hand the user

| what | link |
|---|---|
| the account — balances, positions, fills | `https://app.hyperliquid.xyz/explorer/address/<trading>` |
| the wallet on NEAR | `https://nearblocks.io/address/<near_account_id>` |
| the 1Click leg of a withdrawal | `https://1click.chaindefuser.com/v0/status?depositAddress=<withdrawal.recipient>` (JSON: `status`, `swapDetails.nearTxHashes`), then `https://nearblocks.io/txns/<hash>` |
| the 1Click leg of a deposit | the wallet's request: `GET /wallet/v1/requests/<deposit.request_id>` |

## Every limit, in one place

| where | limit | below / beyond it |
|---|---|---|
| deposit | 2 USDC sent (1Click delivers nothing under 1.31 arriving; fee ~0.32 flat) | refused before anything moves |
| deposit, to trade | $10 must land to place one order | `warning` on `deposit_start` |
| order | $10 notional, reduce-only included; `sz_decimals`; 5 significant figures in price | venue rejects, billed |
| leverage | the market's `max_leverage`; `only_isolated` markets need `cross: false`; the owner's `max_leverage` | refused before signing |
| first outbound transfer | 1 USDC once, from spot | `withdraw_start` reserves it |
| withdrawal to the wallet | 2 USDC sent; 1Click takes 0.2 flat | refused before anything moves |
| order (policy) | `max_order_usd`, `max_position_notional_usd`, `max_daily_volume_usd` (counts what you asked) | `policy_denied:` before signing, still billed |
| deposit / withdraw (policy) | `allow_deposit`, `max_deposit_usd`, `allow_withdraw`, `withdraw_to` | `policy_denied:` |
| calls | trial: 10 incl. free ones, 7 days; paid: the key's balance; `order` 500/day, `leverage` 100/day per wallet | `402` / refused |

## Costs

| operation | price |
|---|---|
| `status`, `address` | free (compute only, ~$0.001) |
| `markets`, `orders`, `positions`, `cancel`, `leverage`, `class_transfer`, `deposit_status`, `withdraw_status` | $0.001 |
| `order`, `deposit_start`, `deposit_continue`, `withdraw_start`, `withdraw_continue` | $0.01 |

Plus compute (~$0.001–0.002 a call). A refused call — by the policy or by
the venue — still costs its price. Venue fees: taker 0.045 %, maker 0.015 %
(tier 0). A write takes 3–8 s; do not place orders in a tight loop.

## Refusals worth knowing

* `policy_denied: no leverage has been set for ETH — call leverage first` —
  the one every new coin hits.
* `policy_denied: order notional 74.18 USD exceeds max_order_usd 50.00` —
  the owner's caps, with the numbers.
* `Hyperliquid rejected the order: Order must have minimum value of $10.` —
  the venue's floor, closes included.
* `Hyperliquid rejected the order: Reduce only order would increase position`
  — there is nothing to close on that side.
* `invalid: a withdrawal to intents must be at least 2 USDC` — the 1Click floor.
* `insufficient USDC: spot has …, the transfer needs … + 1 activation …, and
  perp can release only …` — close positions or ask for less.
* `signature_mismatch` — the platform's own check failed; nothing was sent.
