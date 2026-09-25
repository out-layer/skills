# Subscription: a flat rate for connector calls

> Part of the `outlayer-connectors` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/outlayer-connectors/`.

Paying per call is the default: every call takes the compute it used, plus the
connector's price for the operation, out of a key's balance. A **subscription**
replaces that with an **allowance** — one price for the period the plan runs,
spent by the same calls, with nothing to top up in between.

### It belongs to a KEY, not to a wallet

A subscription sits on one payment key, addressed by `owner` and `nonce`. Buy it
for the key the agent already presents — **unless that key is the trial
(`nonce` 0)**, which cannot be bought on. An agent on the trial creates a
payment key (`POST /wallet/v1/create-payment-key`, nonce ≥ 1), funds it, and
buys on that one.

There are two ways to pay, and both end in the same allowance on the same key.

**1. From money already on the key — `POST /subscription/purchase`.** The key
presents itself and turns part of its own balance into allowance:

```bash
curl -s -X POST -H "X-Payment-Key: $PAYMENT_KEY" -H "Content-Type: application/json" \
  -d '{"amount_usd": "10000000", "plan": 0}' \
  "https://api.outlayer.ai/subscription/purchase"
# → { "plan": "<plan name>", "allowance_purchased_usd": "…", "allowance_total_usd": "…",
#     "spent_usd": "10000000", "expires_at": "<RFC 3339>", "days_added": 30 }
```

* `amount_usd` (required) — a string in USDC minimal units (6 decimals;
  `"10000000"` is $10), the most you are willing to spend. `plan` (optional) —
  the plan's index; absent means the cheapest plan on sale.
* Only the plan's **price** is spent (`spent_usd`). Anything above it stays on
  the key as balance.
* An `amount_usd` short of the named plan is not refused: it buys the best plan
  the amount does cover. Read `plan` in the answer — it is the plan sold.
* The key's balance must hold the plan's price at the moment of the purchase.

Refusals (`reason` next to the sentence in `error`, as on `/call`):

| Status | `reason` | What clears it |
|---|---|---|
| 400 | `trial_key_not_purchasable` | the key is the trial (`nonce` 0). Terminal for that key — create a payment key (nonce ≥ 1), fund it, buy on it |
| 400 | `bad_key_format` | the `X-Payment-Key` header is malformed. Fix the header |
| 400 | `invalid_request` | `amount_usd` is not an integer, is zero, or buys no plan on sale (the sentence names the cheapest). Fix the request |
| 401 | `missing_payment_key` / `wk_is_not_a_payer` / `invalid_key` | send the key itself as `X-Payment-Key`, not the `wk_` |
| 402 | `insufficient_balance` | the key's balance is below the plan's price. Fund the key first, then buy |

`GET /wallet/v1/subscription/purchase-info` (with the wallet's `wk_`) says which
step the wallet is on in `next_action`: `fund_wallet`, `create_key`,
`top_up_key`, or `purchase_allowance` — the last one means "call
`POST /subscription/purchase` with that key". It lists only keys with nonce ≥ 1,
and `instruction` is a sentence you can relay to a person verbatim.

**2. On chain — `buy_subscription`.** The payment names the key instead of
presenting it, so anyone can pay, usually the human who owns the agent:

```bash
# Read the agent's key first: `owner` and `nonce` are what the payment names.
# The key reports on itself — a `wk_` here is refused.
curl -s -H "X-Payment-Key: $PAYMENT_KEY" \
  "https://api.outlayer.ai/subscription/status"
# → { "owner": "<agent account>", "nonce": 1, "wallet_account": "<agent account>",
#     "has_subscription": false, "allowance_available_usd": "0", ... }

# The token is USDC (the contract named below); `amount` is in its minimal units.
near call 17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1 ft_transfer_call '{
  "receiver_id": "outlayer.near",
  "amount": "10000000",
  "msg": "{\"action\":\"buy_subscription\",\"nonce\":1,\"owner\":\"<agent account>\",\"plan\":0}"
}' --depositYocto 1 --gas 100000000000000 --accountId payer.near
```

`owner` defaults to the sender, so spell it out: the subscription belongs to the
AGENT, and the sender is the person paying. The allowance is granted against the
event the contract emits, so it appears a moment after the transaction — read
`GET /subscription/status` again rather than assuming.

### What the agent may do

| | |
|---|---|
| Run the wallet, claim its trial, create a payment key — with `Authorization: Bearer wk_` | Yes |
| Read where a purchase stands — `GET /wallet/v1/subscription/purchase-info` with the `wk_` | Yes |
| Read the subscription | only with `X-Payment-Key` (`GET /subscription/status`); a `wk_` is refused |
| Call a connector | only with `X-Payment-Key`; a `wk_` is `401 wk_is_not_a_payer` |
| Turn the key's own balance into allowance — `POST /subscription/purchase` | Yes, **when the owner asked for a subscription** |
| Put new money on a key | No — the owner or another payer sends it |

The purchase endpoint spends only money that is already on the key, which the
agent could spend on calls anyway. It still changes what that money is: an
allowance cannot be withdrawn, cannot be attached as `X-Attached-Deposit`
(`allowance_no_deposit`), and what is left when the period ends is lost. So buy
when the owner said to, not because `purchase-info` offers the step. Choosing
where expiry warnings are sent is the owner's too.

### A subscription OutLayer gives

OutLayer may give a key a subscription: what the key can spend is set to an
amount OutLayer chooses — usually $10 — for at least 30 days from that day.
It may give one again later, which tops the key back up to that amount. Nothing about
the key changes for the agent: same string, still connectors only. The
allowance is not money — it cannot be withdrawn or attached as
`X-Attached-Deposit`.

On the trial key this **converts** the trial: `GET /subscription/status` then
shows no `trial` block, `has_subscription: true`, and no call count. A
converted trial is still `nonce` 0, so it cannot be bought on — only OutLayer
extends it. To pay for more yourself, create a payment key (nonce ≥ 1) and buy
on that one.

### Rules worth knowing before you buy

* **never on the trial key** (`nonce` 0 — the key `POST /trial-key` gave you,
  including after OutLayer converted it). `POST /subscription/purchase`
  answers `400 trial_key_not_purchasable`; an on-chain purchase naming it has
  no record to land on and is refunded, gas lost. Buy on a payment key
  (nonce ≥ 1);
* the allowance is **spent before any balance** the key also holds, so a key with
  both keeps working after the allowance runs out;
* **buying again never shortens** what is already paid for — validity extends
  from whichever is later, today or the current expiry, and the allowance adds;
* paying **above** a plan's price leaves the difference as spendable balance
  rather than absorbing it;
* new calls stop being admitted slightly **before** the expiry, so a call already
  running is never cut off mid-flight;
* what is left when the period ends **does not carry over**;
* **one call at a time** while the allowance is paying. A subscription is a flat
  rate, so what bounds it is how much can be in flight. A second concurrent call
  is answered out of the key's BALANCE if it has one, and refused with
  `429 call_already_in_flight` (`"terminal": false`) if it does not — the move
  there is to wait for the call in flight, or to fund the key.

### One subscription per agent

A subscription is not a separate class of key — an ordinary payment key can
carry one too, and the same plans apply. But an account can hold many ordinary
keys, and each could carry its own subscription: nothing merges them and nothing
warns, so two subscribed keys is paying twice for one agent's worth of work.

Several subscriptions across several agents are possible and sometimes wanted —
one per agent, one budget each — but at today's prices that rarely pays for
itself. If you are not sure, subscribe the agent that does the work and leave the
others paying per call.
