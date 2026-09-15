---
name: polymarket-connector
description: Trade Polymarket prediction markets from an OutLayer custody wallet through the `polymarket` connector — find markets, buy and sell outcome shares, manage positions, claim resolved markets, fund and withdraw — under the wallet owner's policy. Use when an agent with an OutLayer wallet needs to take or close a position on a real-world outcome.
---

# Polymarket connector

You trade from a deposit wallet that your custody wallet owns. You never see a
key and you never pay gas: orders are signed inside the TEE, and every on-chain
step is paid for by Polymarket's relayer. The owner's policy caps what you may
do; when it refuses, the answer says so — read it, do not retry.

## Call shape

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/polymarket
X-Payment-Key: <a payment key the custody wallet owns>
X-Wallet-Id: <the wallet id>
X-Use-Owner-Secret: 1
Content-Type: application/json

{"input": {"operation": "<op>", ...}}
```

Answers are `{"success": bool, "output": {...}, "error": "..."}`. Mainnet only.
A refusal by the policy starts with `policy_denied:`.

## First calls, in order

1. `{"operation": "status"}` — says whether the policy is present, whether
   `setup_done`, how much collateral you have, and what to do next. Read `next`.
2. `{"operation": "setup"}` — deploys your deposit wallet and approves the
   exchanges. **Call it repeatedly until `step` is `done`**: each call advances
   one step and reports `deploying`, `deployed`, `approving` or `done`. A few
   seconds between calls is enough.
3. `{"operation": "deposit_start", "amount": "5"}` — moves USD from your wallet's
   own balance into collateral. At least $2, or the bridge credits nothing.
   Then `{"operation": "deposit_status", "id": "<id>"}` until `step` is `done`.

## Finding something to trade

`{"operation": "markets", "query": "fed rate"}` returns matching markets with
their `condition_id`.

`{"operation": "markets", "market": "<condition_id>"}` returns the outcomes, each
with a `token_id`, plus `tick_size`, `min_order_size` and `accepting_orders`.

**An order names a `token_id`, not a market.** One token is one outcome, priced
between 0 and 1, and one share pays $1 if that outcome wins.

## Trading

```json
{"operation": "order", "token_id": "7132…", "side": "buy", "size": 10, "price": 0.43}
```

* `size` is in shares. Cost of a buy is `size × price`, so that example risks
  $4.30 to win $10.
* `price` between 0 and 1, on the market's tick. A limit order rests; add
  `"tif": "FOK"` to require an immediate full fill, `"FAK"` for partial.
* `{"kind": "market"}` instead of a price sweeps the book and sends the fill at
  the worst price it reaches. If the book is too thin the answer says how many
  shares are there.
* `side` `sell` closes a position you hold (or opens a short in the other
  outcome, which is the same thing in a binary market).
* Check the answer's `order.price`: a market order's price is the one the book
  gave, not one you chose.

`{"operation": "cancel", "order_id": "0x…"}` takes a resting order off the book.
`{"operation": "orders"}` lists them. Cancelling works even if the owner has
since removed your policy.

## Positions and winnings

`{"operation": "positions"}` lists what the wallet holds with current value and
a `redeemable` flag.

`{"operation": "redeem", "condition_id": "0x…"}` claims a resolved market. It
pays out as collateral you can trade or withdraw. A market that has not resolved
on chain is refused rather than burning your shares for nothing; a losing side
redeems for zero and clears the position.

## Getting money back out

`{"operation": "withdraw_start", "amount": "10"}` sends collateral home to your
wallet's own balance (`"destination": "confidential"` for the shielded one), then
`{"operation": "withdraw_status", "id": "<id>"}` until `step` is `done`. From
there the wallet's own withdrawal moves it anywhere the owner allows.

Expect less than you asked for to arrive: the bridge charges on the way out and
the final leg about 0.6 %.

## What the caps mean

`status` reports them. `max_order_usd` is one order's `size × price`.
`max_daily_volume_usd` counts every order you place in a UTC day **whether it
fills or not** — placing and cancelling still spends it.
`max_open_notional_usd` is what you have at risk right now, read from the venue.
`markets` may pin you to a list. Size the request inside the caps rather than
discovering them by refusal: a refused call still ran and still cost its fee.

## When an order comes back unsent

Polymarket refuses the order route from some regions. Two things can happen:

* `error` containing `region_blocked` — the node that ran your call is in a
  refused region. Retrying may land on another node.
* `submitted: false` with `code: "region_blocked"` and an `envelope` — only when
  you asked for `"submit_mode": "auto"`. The order is signed but not sent: POST
  the envelope yourself exactly as given (its `method`, `url`, `headers`, `body`)
  before `expires_at`. It is good for that one order.

`"submit_mode": "self"` always returns the envelope and sends nothing. Use it
only if you have somewhere to send it from; the default is for us to send it.

## Costs

| operation | price |
|---|---|
| `status`, `address` | free |
| `markets`, `orders`, `positions`, `cancel`, `deposit_status`, `withdraw_status` | $0.001 |
| `order`, `setup`, `deposit_start`, `withdraw_start`, `redeem` | $0.01 |

Plus compute, about $0.001 a call, and the venue's own taker fee on a fill. A run
that started is charged even when the venue then refuses it.

`status` is free but capped at 1000 calls a day. Poll it when something should
have changed, not in a loop.

## Refusals worth knowing

* `no deposit wallet yet` — run `setup` first; funds sent before it would sit at
  an address that cannot trade.
* `policy_denied: …` — the owner's caps. Change the request, or ask the owner.
* `this market's tick size is …` — an unusual market this build has no rounding
  rule for. Pick another.
* `the book holds N shares on that side` — your market order is larger than the
  depth.
* `has not resolved on chain yet` — wait before redeeming.
* `the builder credentials are missing` — an operator problem, not yours: the
  relayer-funded operations are unavailable until it is fixed.
