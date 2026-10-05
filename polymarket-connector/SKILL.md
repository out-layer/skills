---
name: polymarket-connector
description: Trade Polymarket prediction markets from an OutLayer custody wallet through the `polymarket` connector — find markets, buy and sell outcome shares, manage positions, claim resolved markets, fund and withdraw — under the wallet owner's policy. Use when an agent with an OutLayer wallet needs to take or close a position on a real-world outcome.
---

# Polymarket connector

You trade from a deposit wallet that your custody wallet owns. You never see a
key and you never pay gas: orders are signed inside the TEE, and every on-chain
step is paid for by Polymarket's relayer. The owner's policy caps what you may
do; when it refuses, the answer says so — read it, do not retry. This skill is
the `polymarket` operations, policy, limits and prices. It does not cover how
any connector call is paid or refused (keys, the trial, the platform's refusal
codes): [`outlayer-connectors`](https://skills.outlayer.ai/outlayer-connectors/SKILL.md);
nor wallet operations (address, balances, intents deposits):
[`agent-custody`](https://skills.outlayer.ai/agent-custody/SKILL.md).

Every number in this file was observed on mainnet with real money. Where it
says "seen", that is what happened. Mainnet only: there is no testnet
Polymarket.

## Where to read what

Fetched over HTTP, the relative links below resolve against
`https://skills.outlayer.ai/polymarket-connector/`.

| the task in front of you | read |
|---|---|
| fund, trade, withdraw; the policy; a `polymarket` refusal | this file |
| search markets and read books at Polymarket, without a call | [`references/finding-markets.md`](references/finding-markets.md) |
| a withdrawal stuck under the bridge's floor | [`references/stranded-withdrawal.md`](references/stranded-withdrawal.md) |
| a payment key, the trial, a `/call` refusal `reason` | [`outlayer-connectors`](https://skills.outlayer.ai/outlayer-connectors/SKILL.md) |

## Call shape

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/polymarket
X-Payment-Key: <a payment key the custody wallet owns>
X-Wallet-Id: <your wallet's id — GET /wallet/v1/address, `wallet_id`>
Content-Type: application/json

{"input": {"operation": "<op>", ...}}
```

**Send no `secrets_ref`, and always send `X-Wallet-Id`** — without it the
run has no wallet. If your wallet has an owner, OutLayer attaches their policy
row (`{owner, "polymarket"}`) itself; any other account's row, your own
included, is refused `403 policy_row_not_owner`, and naming such rows can
block your wallet on both trading connectors for a while
(`403 calls_suspended`). If your owner gave you a profile of theirs, name it:
`secrets_ref: {"account_id": "<owner>", "profile": "<it>"}`. If the owner's
row does not name your wallet you get `Access denied by access condition`:
ask them to add your wallet's account.

**`policy_row_missing`.** A row you name under a profile other than
`polymarket` that nobody stored is refused, never run with no policy: the
answer is `status: "failed"` with the top-level `error` starting
`policy_row_missing:` and no `output` — do not look for `output.success`.
Name a row that exists, or none. Only the `{owner, "polymarket"}` row may be
absent: then the built-in default applies.

The connector's answer is `{success, operation, output, error}` inside the
platform's `output`. **Its refusal is HTTP 200 with `output.success:
false`**; the word before the colon in `output.error` is the contract —
`policy_denied`, `invalid`, `region_blocked` — and the sentence after it names
the rule or the number.

**After a `408 timeout` on `order`** (the refusal itself: `outlayer-connectors`,
"Reading a refusal") the order may still have reached the venue. Read `orders`
and `positions` before placing it again.

## What you need before the first call

* **A payment key the wallet owns** — the trial or a funded key:
  [`outlayer-connectors`](https://skills.outlayer.ai/outlayer-connectors/SKILL.md),
  "Which key pays". Every call counts on a trial, free ones included; a full
  round trip — `setup` ×3, a deposit and its polls, a few orders, positions, a
  withdrawal — fits in it, a polling loop does not.
* **USDC on the wallet's intents balance** — that is what `deposit_start`
  draws from, and where withdrawals return. The plain balance is a different
  pot. Ask the owner for funds with `dest=intents` (the fund link:
  [`agent-custody`](https://skills.outlayer.ai/agent-custody/references/funding-and-payment-keys.md)).
  USDC already on the **confidential** (shielded) balance works too:
  `"source": "confidential"` on `deposit_start` — the NEAR wallet never shows
  on Polygon. If the owner set a wallet policy, it must allow the
  `confidential` capability. Withdrawing back to `confidential` needs a stored
  policy that allows it ("Getting money back out").
* **A policy, if the owner wants caps.** With none you trade on the built-in
  default ("The policy"); `status` shows which applies. The owner stores
  `POLYMARKET_POLICY` in a row under THEIR account that names your wallet, at
  **<https://app.outlayer.ai/connect/polymarket>**: a form for the caps, a field
  for your wallet's account, one wallet transaction. Send them there with your
  account (`GET /wallet/v1/address?chain=near`, the `address`) and say what you
  need — a stored policy opens orders only when both `max_order_usd` and
  `max_daily_volume_usd` are set. It applies to your next call; you name
  nothing.

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
   wallet's intents balance into collateral. **`amount` is decimal USDC**
   (`"2.5"`, or the number `2.5`), not minimal units. **At least $2.10**: the bridge's
   floor is $2 judged on what arrives, and the one-click leg takes a few
   cents whatever the amount (quoted 5 → 4.98, 100 → 99.96).
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

Polymarket's public APIs need no key and no call: search and read there,
place and settle through the connector —
[`references/finding-markets.md`](references/finding-markets.md).

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
  the shares then show on `positions`. Poll when something should have
  changed, not in a loop — each read is a paid call.
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
withdrawals are not affected.

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
* **After you sell**: the row leaves `positions`; the result is what the
  sell returned (`makingAmount`, minus the fees) less what you paid. Note it
  at the time — the connector keeps no trade history.
* **Collateral is the bottom line**: `status.collateral_usd` plus
  `currentValue` of open positions, against what was deposited.

## The policy (owner's `POLYMARKET_POLICY`)

**No policy is the built-in default:** every market, any size and volume,
deposits from the wallet's balance, withdrawals only to `intents`. No row, an
empty value and `{}` all mean no policy. `status.policy` then reads
`present: false` and the default's `effect`.

**A stored policy replaces the default whole**, and is fail-closed:

| field | in a stored policy |
|---|---|
| `max_order_usd` | cap on one order's notional. Absent: no orders |
| `max_daily_volume_usd` | cap on what is ordered per UTC day, filled or not. Absent: no orders |
| `max_open_notional_usd` | cap on open orders plus positions, read from the venue. Absent: no cap |
| `markets` | condition ids or token ids you may trade. Absent or `["any"]`: every market. Another is refused `policy_denied: the owner's policy does not allow market <condition_id> (token <token_id>)` |
| `allow_deposit`, `max_deposit_usd` | `allow_deposit` is `false` unless set `true` — then `deposit_start` is refused. `max_deposit_usd` absent: no cap |
| `allow_withdraw`, `withdraw_to` | `allow_withdraw` is `false` unless set `true` — then `withdraw_start` is refused. `withdraw_to` pins the destination; absent: `intents` only |

An unknown field makes the policy unreadable, and an unreadable policy refuses
every write. `cancel` needs no policy. Read `status.policy` first — the fields
above sit at its top level, beside `present: true` — and size orders inside
them: a refused call is still billed.

**Per-wallet profiles** (`{owner, "<profile>"}`, one per wallet, named in
`secrets_ref`) bind only while the owner's `{owner, "polymarket"}` row exists
too: a call that names no row runs that one, and with none stored, the
uncapped default. If your owner caps per
wallet and has not stored it, tell them: "Your per-wallet policy only binds
while a policy under the `polymarket` profile exists too — store one there,
strict or admitting no wallet, at https://app.outlayer.ai/connect/polymarket."

## Getting money back out — read this twice

```json
{"operation": "withdraw_start", "amount": "3.164179"}
```

then `{"operation": "withdraw_status", "id": "<id>"}` until `step: "done"`,
`delivered_usd` set. `amount` is decimal USDC, not minimal units. Seen:
3.164179 sent, **3.163539 on intents about 60 seconds after the call** — fee
0.02 %.

`destination` is `intents` (the default) or `confidential` (the shielded
balance), nothing else. **With no policy only `intents` is allowed.**
`confidential` needs a stored policy with `"allow_withdraw": true` and
`"withdraw_to": "confidential"` — a stored policy without `withdraw_to` allows
`intents` only.

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
  [`references/stranded-withdrawal.md`](references/stranded-withdrawal.md).

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
| the owner's policy | every field in "The policy" | `policy_denied:` before signing, still billed |
| calls | the key: `outlayer-connectors`, "Which key pays" | `402` |
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
0.02 % out. On a fill: the venue's category fee; the builder fee is 0.

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
