---
name: hyperliquid-connector
description: Trade Hyperliquid perpetuals from an OutLayer custody wallet through the `hyperliquid` connector — leverage, limit and market orders, cancels, positions — under the wallet owner's policy. Use when an agent with an OutLayer wallet needs to open, manage or close perp positions on Hyperliquid.
---

# Hyperliquid connector

You trade from the wallet's `trading` sub-key. You never see a key; every
action is signed inside the TEE and checked against the owner's policy before
it is sent. If the policy says no, the answer says why — read it, do not retry.

## Call shape

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/hyperliquid
X-Payment-Key: <a payment key the custody wallet owns>
X-Wallet-Id: <the wallet id>
X-Use-Owner-Secret: 1
Content-Type: application/json

{"input": {"operation": "<op>", ...}}
```

Testnet: `https://testnet-api.outlayer.ai/call/connectors.outlayer.testnet/hyperliquid`
with `HYPERLIQUID_TESTNET=1` in the agent secret.

The answer is `{"success": bool, "output": {...}, "error": "..."}`. A refusal
by the policy starts with `policy_denied:`; a venue refusal starts with
`Hyperliquid rejected` / `Hyperliquid refused`.

## Before trading — once per coin

1. `{"operation": "status"}` — check `policy.present`, `perp.account_value_usd`,
   `activation.user_exists`. No policy → you are read-only; ask the owner.
2. Funds in `spot` but not `perp`? `{"operation": "class_transfer", "amount": "100", "to": "perp"}`.
3. `{"operation": "leverage", "coin": "ETH", "leverage": 3}` — **required
   before the first order in a coin**; without it the order is refused
   (a fresh account would otherwise trade at the market's maximum).

## Trading

| do | call |
|---|---|
| see markets | `{"operation": "markets", "coins": ["ETH", "BTC"]}` → `mark_px`, `sz_decimals`, `max_leverage` |
| limit order | `{"operation": "order", "coin": "ETH", "side": "buy", "size": "0.01", "kind": "limit", "price": "2500", "tif": "Gtc"}` (`tif`: `Gtc`, `Ioc`, `Alo` = post-only) |
| market order | `{"operation": "order", "coin": "ETH", "side": "buy", "size": "0.01", "kind": "market"}` (IOC at mark ± `slippage_bps`, default 50) |
| close | the opposite side with `"reduce_only": true` — size caps do not apply to a close |
| your own id | `"cloid": "0x<32 hex>"` on an order; cancel with it |
| cancel | `{"operation": "cancel", "coin": "ETH", "oid": 123}` or `"cloid": "0x…"` |
| open orders | `{"operation": "orders"}` |
| positions | `{"operation": "positions"}` → size, entry, `liquidation_px`, uPnL, funding |

Numbers are decimal strings: `size` to the market's `sz_decimals`, `price`
with at most 5 significant figures (integers always allowed). `1e-3`,
signs and spaces are refused.

## What the policy caps (owner's `HYPERLIQUID_POLICY`)

`max_order_usd` per order, `max_position_notional_usd` after the order,
`max_daily_volume_usd` per UTC day (a resting order counts when placed),
`max_leverage`, `coins`. A `reduce_only` order is never blocked by the size
caps, so you can always close. Read `status.policy.caps` first and size
orders inside them instead of discovering the caps by refusal.

## Costs

Reads are $0.001, `order` $0.01, `cancel`/`leverage`/`class_transfer`
$0.001, plus compute. A write takes 3–7 seconds; do not place orders in a
tight loop.

## Do not

- Do not send more than one `order` per call — one call, one order.
- Do not retry an `order` whose answer you did not read: if `success` is
  true the order is live even when `warning` is set.
## Funding (mainnet only)

Deposit: `{"operation": "deposit_start", "amount": "25", "source": "intents"}`
(`"confidential"` to draw from the shielded balance) → note the `id`, then
call `{"operation": "deposit_continue", "id": "<id>"}` every 20–30 s until
`step` is `done`. Each continue advances one step; `advanced: false` means
wait and call again. Expect ~2–5 minutes end to end. The perp account is
credited; use `class_transfer` only if you want funds on spot.

Withdraw: funds must be on **spot** (`class_transfer` perp → spot first).
`{"operation": "withdraw_start", "amount": "20", "destination": "intents"}`
(or `"confidential"`, or a `0x` address the policy allows) → then
`withdraw_continue` with the `id` until `done`. The first withdrawal of an
account also pays a one-time 1 USDC activation; `status.activation` shows it.

Both refuse on testnet and without `allow_deposit` / `allow_withdraw` in the
policy. Never start a second deposit or withdrawal while one is not `done`
or `failed`.
