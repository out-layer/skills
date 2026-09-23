# Subscription: a flat rate for connector calls

> Part of the `outlayer-connectors` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/outlayer-connectors/`.

Paying per call is the default: every call takes the compute it used, plus the
connector's price for the operation, out of a key's balance. A **subscription**
replaces that with an **allowance** — one price for the period the plan runs,
spent by the same calls, with nothing to top up in between.

### It belongs to a KEY, not to a wallet

A subscription sits on whichever payment key you bought it for, addressed by
`owner` and `nonce`. There is no special key to create first: the key an agent
already presents is the key a subscription is bought for.

That is also why the purchase is an on-chain payment rather than an API call —
it names the key instead of presenting it:

```bash
# Read the agent's key first: `owner` and `nonce` are what the payment names.
# The key reports on itself — a `wk_` here is refused.
curl -s -H "X-Payment-Key: $PAYMENT_KEY" \
  "https://api.outlayer.ai/subscription/status"
# → { "owner": "<agent account>", "nonce": 1, "wallet_account": "<agent account>",
#     "has_subscription": false, "allowance_available_usd": "0", ... }

# Then anyone — usually the human who owns the agent — pays for it.
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

### What the `wk_` can and cannot do

| With `Authorization: Bearer wk_` | |
|---|---|
| Run the wallet, claim its trial, create a payment key | Yes |
| Read the subscription | **No** — `GET /subscription/status` takes `X-Payment-Key` |
| Call a connector | **No** — `401 wk_is_not_a_payer`; `/call` takes `X-Payment-Key` |
| **Buy or extend the subscription** | **No** |

Buying is the owner's act, not the agent's: a compromised agent must not be able
to spend money on your behalf. The same applies to choosing where expiry
warnings are sent.

### Rules worth knowing before you buy

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
