---
name: polymarket-connector
description: Trade Polymarket prediction markets from an OutLayer custody wallet through the `polymarket` connector — find markets, buy and sell outcome shares, manage positions, claim resolved markets, fund and withdraw — under the wallet owner's policy. Use when an agent with an OutLayer wallet needs to take or close a position on a real-world outcome.
---

# Polymarket connector

You trade from a deposit wallet that your custody wallet owns. You never see a
key and you never pay gas: orders are signed inside the TEE, and every on-chain
step is paid for by Polymarket's relayer. The owner's policy caps what you may
do; when it refuses, the answer says so — read it, do not retry.

Every number in this file was observed on mainnet with real money. Where it
says "seen", that is what happened.

## Call shape

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/polymarket
X-Payment-Key: <a payment key the custody wallet owns>
Content-Type: application/json

{"input": {"operation": "<op>", ...},
 "secrets_ref": {"account_id": "<owner's account>", "profile": "polymarket"}}
```

`secrets_ref` names the owner's row: the policy, stored under the owner's
account with your wallet in its access rule. Every call carries it, reads
included — without it the connector sees no policy and can only read and
cancel.

Two envelopes come back. The platform's: `{call_id, status, output,
compute_cost, time_ms}`. Inside its `output`, the connector's: `{success,
operation, output, error}`. **A connector refusal arrives as HTTP 200 with
`output.success: false`**; the word before the colon in `output.error` is the
contract — `policy_denied`, `invalid`, `region_blocked` — and the sentence
after it names the rule or the number. Mainnet only.

## What you need before the first call

* **A payment key the wallet owns.** The trial key (`POST /trial-key` with the
  wallet's `wk_`) gives 10 connector calls in the wallet's first week — and
  **the free operations count**: `status` spends one. Ten is `status`, `setup`
  ×3, `deposit_start`, `deposit_status`, `markets`, `order` and two spare, not
  enough to also cancel, read positions and withdraw. A funded key has no call
  limit. Creating one (`POST /wallet/v1/create-payment-key
  {"initial_deposit_usdc": "0.50"}`) takes USDC from the wallet's **plain**
  balance and needs the wallet's NEAR account to hold **≥ 0.3 NEAR** — with 0.2
  the chain refuses the transaction, with 0 the account does not exist yet.
* **USDC on the wallet's intents balance** — that is what `deposit_start`
  draws from, and where withdrawals return. The plain balance is a different
  pot. Ask the owner for funds with `dest=intents`.
* **The owner's policy**, `POLYMARKET_POLICY`, in a row under the OWNER's
  account that names your wallet. Without it only reads and `cancel` work;
  `status` shows it. The owner stores it at
  **<https://app.outlayer.ai/connect/polymarket>**: a form for the caps, a field
  for your wallet's account, one wallet transaction. Send them there with your
  account (`GET /wallet/v1/address?chain=near`, the `address`) and say what you
  need: orders open only when both `max_order_usd` and `max_daily_volume_usd`
  are set. Then name their row in `secrets_ref`.

## First calls, in order

1. `{"operation": "status"}` — free. `owner` (your trading address),
   `deposit_wallet`, `setup_done`, `builder_credentials`, `collateral_usd`,
   `intents_usdc`, `volume_today_usd`, the policy, and `next`, a sentence that
   says what to call. Read `next`. About 3 s.
2. `{"operation": "setup"}` — one step per call, each a paid call: `deploying`
   (the relayer deploys your deposit wallet) → `approving` (seven approvals in
   one relayer batch, with the Polygon `tx_hash`) → `done`. Wait a few seconds
   between calls; three calls is normal. Nobody pays gas: the relayer does.
3. `{"operation": "deposit_start", "amount": "2.5"}` — moves USDC from the
   wallet's intents balance into collateral. **At least $2.10**: the bridge's
   floor is $2 judged on what arrives, and the one-click leg takes ~0.3 %.
   The call itself takes ~30 s (it waits for the intents withdrawal to be
   accepted); the collateral appeared within 75 s after that. Then
   `{"operation": "deposit_status", "id": "<id>"}` → `step: "done"` with
   `credited_usd` and the Polygon transaction. Seen: 2.50 in, 2.491823 credited.

## Finding something to trade

`{"operation": "markets", "query": "fed rate"}` searches the public index.
`{"operation": "markets", "market": "<condition_id>"}` returns `tokens:
[{outcome, price, token_id}]`, `tick_size`, `min_order_size`, `neg_risk`,
`accepting_orders`, `end_date`.

**An order names a `token_id`, not a market.** One token is one outcome,
priced 0–1; one share pays $1 if that outcome wins.

**`min_order_size` is in shares** — 5 on every market seen — so the smallest
order costs `5 × price`. For a one-dollar trade, find an outcome priced near
0.20; at 0.50 the minimum is already $2.50.

Public data needs no call: `https://gamma-api.polymarket.com/markets` carries
`bestBid`, `bestAsk`, `spread`, `liquidityNum`, `orderMinSize`, `endDate`,
`sportsMarketType`. For a sports market `endDate` is the game's start, not
its resolution: it keeps accepting orders through the game and resolves
hours later. Crypto up/down markets are the fastest and carry the highest
fee. An order you may want to cancel later belongs on a market that is
neither.

## Finding markets without spending a call

Polymarket's public APIs need no key, and a keyword search is cheaper there
than through the connector. The pattern: search and read at Polymarket, place
and settle through the connector.

* Search: `GET https://gamma-api.polymarket.com/public-search?q=<words>&limit_per_type=5`
  → `events[]`, each with `title`, `slug` and `markets[]` carrying
  `question`, `conditionId`, `bestBid`, `bestAsk`. One event can hold many
  markets (dates, thresholds): pick the market, not the event.
* One event in full: `GET https://gamma-api.polymarket.com/events?slug=<slug>`
  → `markets[]` with `conditionId`, `clobTokenIds` and `outcomes` (both are
  JSON **strings** — parse them; the n-th token is the n-th outcome),
  `outcomePrices`, `bestBid`, `bestAsk`, `orderMinSize`,
  `orderPriceMinTickSize`, `negRisk`, `endDate`, `feesEnabled`.
* The live book for a token: `GET https://clob.polymarket.com/book?token_id=<token_id>`
  → `bids[]`, `asks[]` with `price` and `size`; sort them yourself.
* Show the user `https://polymarket.com/event/<slug>` — the same page the
  search found.

Then `order` names the `token_id`. The connector's own `markets {"query"}`
/ `markets {"market"}` give the same facts for a tenth of a cent when a call
is simpler than an HTTP fetch.

## Trading

```json
{"operation": "order", "token_id": "5511…", "side": "buy", "size": 5, "price": 0.10}
```

* `size` is always in shares — for `kind: "market"` too. `price` on the
  market's `tick_size` (0.01 on those seen). A limit below the bid
  rests (seen: 5 at 0.10 on a 0.14 bid → `status: "live"`); a limit through
  the ask fills at the ask, not at your limit (seen: 7 at 0.16 on a 0.15 ask →
  `matched`, $1.05). The venue's answer carries `orderID`, `status`,
  `takingAmount`, `makingAmount` and the settlement `transactionsHashes`.
* `"kind": "market"` sweeps the book (sent as FOK: all or nothing) and refuses
  `price`. Without `tif` a limit is GTC. `"tif": "FOK"` / `"FAK"` and
  `"expiration"` (unix seconds, a GTD) exist in the code and were not
  exercised live.
* `min_order_size` applies to every order this connector sends, market ones
  included: a holding smaller than it cannot be sold through the connector.
* `"side": "sell"` closes what you hold: 7 shares at 0.13 on a 0.14 bid →
  `matched`. A sell's `maker_amount_units` is the share count.
* **Two fees on a fill, both taken from the notional.** The venue's:
  `shares × rate × price × (1 − price)`, rate by market category (crypto 7 %,
  sports 5 %, politics/finance/tech 4 %, economics/culture 5 %, geopolitics
  0), makers pay nothing; `markets {"market"}` returns the market's
  `taker_fee_bps` / `maker_fee_bps`. OutLayer adds no builder fee of its
  own: the connector's builder rate is 0 on both sides.

`{"operation": "orders"}` lists resting orders — each with `id`, `asset_id`
(the token), `side`, `price`, `original_size`, `size_matched`, `status`,
`created_at`; a long book comes with `next_cursor`. `{"operation": "cancel",
"order_id": "0x…"}` answers `result.canceled: [id]` — one call per order,
there is no cancel-all. Cancelling works even if the owner has since removed
your policy, and from any region.

### Did it fill?

* The venue's answer to `order` says so at once: `status: "matched"` with
  `takingAmount`/`makingAmount` is a fill; `status: "live"` is a resting order.
* A resting order later: it is on `orders` while it rests (`size_matched`
  grows on a partial fill) and gone from `orders` once filled or cancelled;
  the shares then show on `positions`. So "did my bid fill?" is `orders`
  (still there → no), then `positions` (there → yes). Poll when something
  should have changed, not in a loop — each read is a paid call.
* Cancelling takes the unfilled remainder off the book. Whatever
  `size_matched` had already filled stays as a position, and its collateral
  is spent; only an untouched order costs nothing.
* The connector keeps no order history and `orders` has no lookup by id:
  write down the `orderID` the venue returns at placement, and the token —
  two orders on one token are otherwise indistinguishable later.

### Closing out

* Resting bids: `cancel` each id from `orders`. Do this before you stop
  working — a bid left on the book is a position you may wake up holding.
* Held shares: `order` with `"side": "sell"` at or through the bid, or
  `"kind": "market"`. A sell's proceeds arrive as collateral at once. The bid
  is not in `markets` (which gives one `price` per token); read it from
  `https://clob.polymarket.com/book?token_id=<token_id>` (`bids`, `asks`) or
  gamma's `bestBid`/`bestAsk`.

## When an order comes back `region_blocked`

Polymarket's edge refuses the order route (`POST /order`) from US nodes, and
OutLayer runs nodes on both sides of that line. Reads, cancels, deposits and
withdrawals are not affected. Seen: five order runs in a row on the US node,
then a sell placed straight from the European one.

* Without `submit_mode`: `success: false`, `error: "region_blocked: …"`. The
  call is billed. Retry — another node may take it.
* With `"submit_mode": "auto"`: on a refused node the answer is `success:
  true`, `submitted: false`, `code: "region_blocked"` and an `envelope` —
  the signed request: `method`, `url`, `headers`, `body`, `expires_at` (5
  minutes). POST it yourself, exactly as given, from anywhere outside the
  fence; the venue answered `live` / `matched` to envelopes posted that way.
  The headers are credentials for that one request: never log them. On a
  node that can place, `auto` just places (`submitted: true`).
* `"submit_mode": "self"` returns the envelope every time and sends nothing.
* No place to POST from outside the fence? Then only the retry is left — the
  next run lands on the other node about half the time.

An envelope you were handed counts toward `max_daily_volume_usd` whether or
not you post it.

## Positions and winnings

`{"operation": "positions"}` → `collateral_usd` and one row per holding:
`asset` (the token), `conditionId` (what `redeem` takes), `outcome`, `size`,
`avgPrice`, `curPrice`, `currentValue`, `cashPnl`, `redeemable`, `endDate`,
`slug`, `eventSlug`.

`{"operation": "redeem", "condition_id": "<positions[].conditionId>"}` claims a
resolved market into collateral. `redeemable` comes from the venue's data
service; the connector itself reads the on-chain resolution (the conditional
tokens' `payoutDenominator`) and refuses while the chain has not resolved,
rather than burning shares — there can be a lag between the two. A losing
side redeems for zero and clears the row. Not exercised live yet.

### Wins and losses, where to read them

* **While you hold**: `positions[].cashPnl` and `percentPnl` are the
  unrealized result against `avgPrice`; `currentValue` is what the shares
  would fetch now; `initialValue` what they cost, `entryFeesUsdc` the fee paid.
* **After the market resolves**: `curPrice` goes to 1 for the winning outcome
  and 0 for the losing one, `redeemable` turns true, and `cashPnl` becomes the
  final result. `redeem` moves a win into collateral; a loss is a row that
  redeems to nothing.
* **After you sell**: the row leaves `positions`; the result is the
  difference between what the sell returned (`makingAmount` in the venue's
  answer, minus the fees) and what you paid. Note it yourself at the time
  — the connector keeps no trade history, and `positions` shows only what is
  held.
* **Collateral is the bottom line**: `status.collateral_usd` plus
  `currentValue` of open positions, against what was deposited.

## Getting money back out — read this twice

```json
{"operation": "withdraw_start", "amount": "3.164179"}
```

then `{"operation": "withdraw_status", "id": "<id>"}` until `step: "done"`,
`delivered_usd` set. Destination is the wallet's intents balance
(`"destination": "confidential"` for the shielded one). Seen: 3.164179 sent,
**3.163539 on intents about 60 seconds after the call** — fee 0.02 %.

The bridge processes nothing under **$2** (`minCheckoutUsd`, "for deposits
and withdrawals"). An amount under the floor sent to a withdraw address is not
refused, not returned and not even listed by `/status` — it waits on a
Polymarket-operated address until that address holds the floor. Seen with
$1.43. The connector refuses under $2.10, and the rule to plan by is:

* **Never split a withdrawal.** Sell down first, then take everything out in
  ONE call. `withdraw_start` returns `remainder_usd`, and a `warning` when what
  stays behind is under the floor. A sub-floor remainder in the deposit wallet
  is still collateral you can trade.
* **If a withdrawal is stranded anyway** (`withdraw_status` stays at
  `bridging`, `/status/<bridge_out>` empty), join its route:
  `{"operation": "withdraw_start", "amount": "0.67", "resume": "<its id>"}`.
  The bridge judges the address as a whole (seen: 1.43 + 0.67 → one transfer
  of 2.10, `COMPLETED`), so the original amount goes home. Join with the
  **minimum** that clears the floor — a too-small join is refused with the
  sentence "send at least N" — because the 1Click
  leg swaps only its original quote and refunds the rest as native USDC to the
  wallet's own Polygon address (`/wallet/v1/address?chain=polygon`). Seen:
  0.663 parked there for 0.67 joined. Getting that home is outside this
  connector: a 1Click deposit intent for it
  (`POST /wallet/v1/intents/deposit/cross-chain {"chain":"polygon","token":"USDC","amount":"<units>"}`),
  an ERC-20 `transfer` from that address signed through
  `POST /wallet/v1/evm/sign-transaction` and broadcast by you, and ~0.05 POL
  on the address for gas, which the owner sends there. The joined amount
  always ends up this way: it is the price of the rescue, not a side effect.
  The route is good for three days from the original call.

## Links to hand the user

Every answer that moves money carries an identifier; give the user a link,
not a hash to paste somewhere.

| what | link |
|---|---|
| a Polygon transaction (`setup.tx_hash`, order `transactionsHashes`, `withdraw_status.tx_hash`, `deposit_status.transfer.result.destination_tx_hash`) | `https://polygonscan.com/tx/<hash>` |
| the deposit wallet — holdings and activity | `https://polygonscan.com/address/<deposit_wallet>` and `https://polymarket.com/profile/<deposit_wallet>` |
| a market | `https://polymarket.com/event/<eventSlug>` (from `positions`) |
| a bridge leg, in or out | `https://bridge.polymarket.com/status/<bridge_in or bridge_out>` — JSON, one record per transfer, `DEPOSIT_DETECTED` → `PROCESSING` → `COMPLETED` / `FAILED` |
| the wallet on NEAR | `https://nearblocks.io/address/<near_account_id>` |
| the NEAR leg of a deposit or withdrawal | `https://1click.chaindefuser.com/v0/status?depositAddress=<address>` (JSON), then `https://nearblocks.io/txns/<hash>` for its NEAR transactions |

## Every limit, in one place

| where | limit | below it |
|---|---|---|
| deposit | $2.10, on what arrives | not credited (held until the address total reaches $2) |
| withdrawal | $2.10 per bridge address (its whole balance) | waits on the bridge address until the total reaches it — `resume` |
| order | `min_order_size` shares × price; `tick_size` | venue rejects |
| a fill | venue category fee; builder fee 0 | — |
| relayer | every `setup` step, deposit, withdrawal and redeem is a relayer operation, capped per day by the builder's tier (reported: 100/day unverified, 10,000 verified) | `setup`/`deposit_*`/`withdraw_*` refused by the relayer |
| order | `max_order_usd`, `max_open_notional_usd`, `max_daily_volume_usd` (counts what you asked, filled or not) | `policy_denied:` before signing, still billed |
| deposit / withdraw | `allow_deposit`, `max_deposit_usd`, `allow_withdraw`, `withdraw_to` | `policy_denied:` |
| calls | trial: 10 incl. free ones, 7 days; paid: the key's balance | `402` |
| region | `POST /order` from US nodes | `region_blocked` |
| withdrawal size | > $50,000: split, the bridge's pool is finite | slippage |

## Costs

| operation | price |
|---|---|
| `status`, `address` | free (compute only, ~$0.001) |
| `markets`, `orders`, `positions`, `cancel`, `deposit_status`, `withdraw_status` | $0.001 |
| `order`, `setup`, `deposit_start`, `withdraw_start`, `redeem` | $0.01 |

Plus compute (~$0.001–0.002 a call). A refused call — by the policy, by the
region, by the venue — still costs its price. Bridge fees seen: 0.33 % in,
0.02 % out. On a fill: the venue's category fee (0–7 %, `p(1−p)`-shaped); the
builder fee is 0.

`status` is free but capped at 1000 a day. Poll it when something should have
changed, not in a loop; balances move in about a minute.

## Refusals worth knowing

* `policy_denied: this order is $6.00, over the owner's max_order_usd of $5.00`
  — the owner's caps, with the numbers. Change the request or ask the owner.
* `invalid: a withdrawal must be at least 2.1 USDC …` — the bridge floor.
* `region_blocked: …` — see above.
* `no deposit wallet yet` — run `setup` first.
* `the book holds N shares on that side` — a market order larger than the depth.
* `has not resolved on chain yet` — wait before redeeming.
* `the builder credentials are missing` — an operator problem, not yours:
  the relayer-paid operations are unavailable until it is fixed.
