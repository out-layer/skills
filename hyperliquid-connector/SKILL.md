---
name: hyperliquid-connector
description: Trade Hyperliquid perpetuals from an OutLayer custody wallet through the `hyperliquid` connector — leverage, limit and market orders, cancels, positions, funding in and out — under the wallet owner's policy. Use when an agent with an OutLayer wallet needs to open, manage or close perp positions on Hyperliquid.
---

# Hyperliquid connector

You trade from the wallet's `trading` sub-key: an address Hyperliquid knows
as the account. You never see a key and you never pay gas — every action is
signed inside the TEE, checked against the owner's policy before it is sent,
and HyperCore has no gas. If the policy says no, the answer says why: read
it, do not retry. This skill is the `hyperliquid` operations, policy, limits
and prices. It does not cover how any connector call is paid or refused
(keys, the trial, the platform's refusal codes):
[`outlayer-connectors`](https://skills.outlayer.ai/outlayer-connectors/SKILL.md);
nor wallet operations (address, balances, intents deposits):
[`agent-custody`](https://skills.outlayer.ai/agent-custody/SKILL.md).

Every number in this file was observed on mainnet with real money. Where it
says "seen", that is what happened.

## Where to read what

Fetched over HTTP, the relative links below resolve against
`https://skills.outlayer.ai/hyperliquid-connector/`.

| the task in front of you | read |
|---|---|
| fund, trade, withdraw; the policy; a `hyperliquid` refusal | this file |
| a withdrawal 1Click refunded to the wallet's own EVM address | [`references/refund-recovery.md`](references/refund-recovery.md) |
| a payment key, the trial, a `/call` refusal `reason` | [`outlayer-connectors`](https://skills.outlayer.ai/outlayer-connectors/SKILL.md) |

## Call shape

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/hyperliquid
X-Payment-Key: <a payment key the custody wallet owns>
X-Wallet-Id: <your wallet's id — GET /wallet/v1/address, `wallet_id`>
Content-Type: application/json

{"input": {"operation": "<op>", ...}}
```

**Send no `secrets_ref`, and always send `X-Wallet-Id`** — without it the
run has no wallet. If your wallet has an owner, OutLayer attaches their policy
row (`{owner, "hyperliquid"}`) itself; any other account's row, your own
included, is refused `403 policy_row_not_owner`, and naming such rows can
block your wallet on both trading connectors for a while
(`403 calls_suspended`). If your owner gave you a profile of theirs, name it:
`secrets_ref: {"account_id": "<owner>", "profile": "<it>"}`. If the owner's
row does not name your wallet you get `Access denied by access condition`:
ask them to add your wallet's account.

**`policy_row_missing`.** A row you name under a profile other than
`hyperliquid` that nobody stored is refused, never run with no policy: the
answer is `status: "failed"` with the top-level `error` starting
`policy_row_missing:` and no `output` — do not look for `output.success`.
Name a row that exists, or none. Only the `{owner, "hyperliquid"}` row may be
absent: then the built-in default applies.

The connector's answer is `{success, operation, output, error}` inside the
platform's `output`. **Its refusal is HTTP 200 with `output.success:
false`**; the word before the colon in `output.error` is the contract —
`policy_denied`, `invalid`, `signature_mismatch` — and a venue refusal reads
`Hyperliquid rejected …` / `Hyperliquid refused …` with the venue's own
sentence.

**After a `408 timeout`** (the refusal itself: `outlayer-connectors`, "Reading
a refusal") the order may still have reached the venue. Read `orders` and
`positions` before placing it again.

Testnet: substitute `testnet-api.outlayer.ai` and `connectors.outlayer.testnet`;
the owner's page stores `HYPERLIQUID_TESTNET=1` in the same row there. Trading
works on testnet; funding does not (1Click has no testnet).

## What you need before the first call

* **A payment key the wallet owns** — the trial or a funded key:
  [`outlayer-connectors`](https://skills.outlayer.ai/outlayer-connectors/SKILL.md),
  "Which key pays".
* **USDC on the wallet's intents balance** — what `deposit_start` draws from
  and where withdrawals return by default. The plain balance is a different
  pot. Ask the owner to fund with `dest=intents`.
* **A policy, if the owner wants caps.** With none you trade on the built-in
  default (below); `status` shows which applies. The owner stores
  `HYPERLIQUID_POLICY` in a row under THEIR account that names your wallet, at
  **<https://app.outlayer.ai/connect/hyperliquid>**: a form for the caps, a
  field for your wallet's account, one wallet transaction. Send them there with
  your account (`GET /wallet/v1/address?chain=near`, the `address`) and say what
  you need — a stored policy opens orders only when all three of
  `max_order_usd`, `max_daily_volume_usd` and `max_leverage` are set. It
  applies to your next call; you name nothing.

## Funding the wallet — how to ask for it

`deposit_start` draws from the wallet's **intents** USDC (native USDC,
`17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1`). Ask the
owner with the fund link and `dest=intents` — without it the USDC lands on the
plain balance, a different pot; the link and the other ways in are
[`agent-custody`](https://skills.outlayer.ai/agent-custody/references/funding-and-payment-keys.md).
Seen: 11 USDC arrived on intents within a minute. Do not route NEAR-side money
through a 1Click quote to reach intents: it adds a fee for nothing.

## First calls, in order

1. `{"operation": "status"}` — free, ~3 s. `addresses.trading` (your
   account), `perp.account_value_usd`, `perp.withdrawable_usd`, `spot.usdc`,
   `activation` (`user_exists`, `next_outbound_fee_usdc`), `policy`,
   `today.volume_usd`, and `limits` — the floors below.
2. `{"operation": "deposit_start", "amount": "15"}` — moves USDC from the
   wallet's intents balance to your Hyperliquid account through 1Click.
   **`amount` is decimal USDC as a string** (`"15"`, `"2.5"`), not minimal
   units — on every operation that takes one.
   **At least 2 USDC**; the fee is a flat ~0.33 USDC whatever the amount
   (seen: 15 → 14.683633; quoted 5 → 4.68, 50 → 49.67, 100 → 99.66). So
   fund once with what you need — one deposit of 20 costs half of two of 10,
   and a 5 USDC deposit loses over 6 %.
   The money lands on **perp**, ready to trade, in about a minute. Poll
   `{"operation": "deposit_status", "id": "<id>"}` (a read) until `step` is
   `done` or `unlanded`; it carries `landed_usdc`, `landed_in`,
   `account_existed`. A deposit that has not landed within three days closes
   as `unlanded` at the next poll (or when the next deposit starts). The
   deposit is what creates a new account — nothing else is needed.
   `"to": "spot"` parks it on spot instead (`deposit_continue` then does the
   class transfer). USDC on the **confidential** (shielded) balance works
   too: `"source": "confidential"` — the NEAR wallet never shows on
   HyperCore. Pick the one that holds the money; a wallet policy, if the
   owner set one, must allow the `confidential` capability. Withdrawing back
   to `confidential` needs a stored policy that allows it ("Getting money
   back out").
3. `{"operation": "leverage", "coin": "ETH", "leverage": 2}` — **required
   once per coin before the first order in it**: a fresh account trades at
   the market's maximum otherwise, and the connector refuses an order
   without a recorded leverage. `"cross": false` for isolated.

If `deposit_start` answers with a `warning` that the wallet did not confirm
in time, the transfer may still be in flight: poll `deposit_status` for a few
minutes before starting another. Seen once — the money had moved.

**Money operations run one at a time, never in parallel.** Wait for the
answer to one `deposit_*`, `withdraw_*` or `class_transfer` before sending the
next, and do not re-send a call that timed out: poll its `*_status` instead.
Two `deposit_continue` calls at once can move the same amount from perp to
spot twice.

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
* `{"type": "candleSnapshot", "req": {"coin": "ETH", "interval": "1h",
  "startTime": <ms>, "endTime": <ms>}}` → OHLCV.

Show the user `https://app.hyperliquid.xyz/trade/<COIN>`. The connector's
own `markets {"coins": [...]}` gives the same numbers for a tenth of a cent,
without delisted markets.

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

## The policy (owner's `HYPERLIQUID_POLICY`)

**No policy is the built-in default:** every coin, any size and volume,
leverage up to the market's cap, deposits from the wallet's balance,
withdrawals only to `intents`. No row, an empty value and `{}` all mean no
policy. `status.policy` then reads `present: false` and the default's
`effect`.

**A stored policy replaces the default whole**, and is fail-closed:

| field | in a stored policy |
|---|---|
| `max_order_usd` | cap on one order's notional (at the limit price, or mark ± slippage for a market order); not applied to a reduce-only close. Absent: no orders |
| `max_daily_volume_usd` | cap per UTC day; a resting order counts when placed, a reduce-only order counts but is never refused. Absent: no orders |
| `max_leverage` | cap on `leverage`. Absent: no `leverage`, so no orders |
| `max_position_notional_usd` | cap on a coin's position after the order. Absent: no cap |
| `coins` | the coins you may trade. Absent or `["any"]`: every listed market |
| `allow_deposit`, `max_deposit_usd` | `allow_deposit` is `false` unless set `true` — then `deposit_start` is refused. `max_deposit_usd` absent: no cap |
| `allow_withdraw`, `withdraw_to` | `allow_withdraw` is `false` unless set `true` — then `withdraw_start` is refused. `withdraw_to` pins one destination (`intents`, `confidential` or a HyperCore `0x` address); absent: any destination |

An unknown field makes the policy unreadable, and an unreadable policy refuses
every write. Read `status.policy` first — the fields above sit at its top
level, beside `present: true` — and size orders inside them instead of
discovering the caps by refusal: a refused call is still billed.

**Per-wallet profiles** (`{owner, "<profile>"}`, one per wallet, named in
`secrets_ref`) bind only while the owner's `{owner, "hyperliquid"}` row exists
too: a call that names no row runs that one, and with none stored, the
uncapped default. If your owner caps per
wallet and has not stored it, tell them: "Your per-wallet policy only binds
while a policy under the `hyperliquid` profile exists too — store one there,
strict or admitting no wallet, at https://app.outlayer.ai/connect/hyperliquid."

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
(done at once, no 1Click). **With no policy only `intents` is allowed**; any
other needs a stored policy with `"allow_withdraw": true` and `withdraw_to`
set to that destination or absent.

* **The account's first outbound transfer costs 1 USDC on top of the
  amount**, taken from spot; `status.activation.next_outbound_fee_usdc` says
  `"1.0"` until then and `"0.0"` ever after. Seen: 14.6 on spot − 13.6 sent
  − 1.0 = 0.
* 1Click deducts a flat **0.2 USDC** from what arrives and pays out its quote
  (seen: 13.6 sent → 13.4 deposited → 13.39788 on intents).
* **At least 2 USDC** to the wallet: 1Click answers a bare server error under
  that, and the connector refuses first with `invalid:`. The transfer inside
  HyperCore is exact, so the floor is on what you send.
* **If the answer carries a `warning` that the transfer was not confirmed**,
  it may still have gone out: poll `withdraw_status` — it reads the account's
  ledger and settles the record (`sending` → `bridging`, or `done` for a
  HyperCore address, or `failed` when
  nothing left). Until it is settled no other withdrawal starts, so a retry
  does not send twice.
* **A route 1Click fails is refunded on HyperCore**, to the wallet's own EVM
  address rather than your trading account: `withdraw_status` stays
  `bridging` past `expires_at` with the balance unchanged. Bring it back with
  [references/refund-recovery.md](references/refund-recovery.md).
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
| deposit / withdraw (policy) | `allow_deposit`, `max_deposit_usd`, `allow_withdraw`, `withdraw_to` — "The policy" | `policy_denied:` |
| calls | the key: `outlayer-connectors`, "Which key pays"; `order` 500/day, `leverage` 100/day per wallet | `operation_limit_reached` |

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
