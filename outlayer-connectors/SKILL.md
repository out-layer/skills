---
name: outlayer-connectors
description: The OutLayer connector library — how an agent calls any connector (auth, the `operation` field, secrets, fees, quotas, refusal codes) and what each connector does. Use when an agent with an OutLayer custody wallet needs to reach a bank, a trading venue or another outside service, or when a connector call is refused and the reason has to be read.
---

# OutLayer connectors

A connector is a curated WASI module that runs inside the same TEE as your
wallet. It holds the credential for an outside service, it is priced per named
operation, and it can only reach the hosts its signed manifest declares. You
call it like any project; what makes it a connector is that the platform knows
its name and its prices.

## The call

```
POST https://{api_host}/call/{connectors_account}/<connector>
X-Payment-Key: <a payment key the calling wallet owns>
Content-Type: application/json

{"input": {"operation": "<name>", ...}}
```

| | mainnet | testnet |
|---|---|---|
| `{api_host}` | `api.outlayer.ai` | `testnet-api.outlayer.ai` |
| `{connectors_account}` | `connectors.outlayer.near` | `connectors.outlayer.testnet` |

The two move together. A testnet key against `connectors.outlayer.near` is not a
half-configured call — nothing about it works, and the refusal will talk about
the project rather than the network.

* **`operation` is mandatory and is the unit of price.** The contract, the
  coordinator and the worker all read that one field; a call without it is
  refused before anything runs and costs nothing.
* **`X-Payment-Key` must be a key the wallet itself owns** (create it from the
  wallet's own `wk_`), or the connector cannot see the secrets stored for you.
* **`X-Wallet-Id` is optional.** The wallet is taken from the credential; the
  header, when sent, is only compared against it and a mismatch is refused with
  `wallet_not_yours` (terminal). You do not need to look a wallet id up to make
  a call.
* **`X-Use-Owner-Secret: 1`** brings the secrets stored under your own wallet
  (policy, API tokens) into the run. To use a credential your owner stored under
  THEIR account and whitelisted you for, name it instead:
  `{"input": {...}, "secrets_ref": {"account_id": "owner.near", "profile": "gmail"}}`.
  Such a grant may carry an expiry, so a call that worked yesterday can be
  refused today with the date it lapsed on. With neither, the connector starts
  with no secrets and says so.

The answer is always `{"success": bool, "output": {...}, "error": "...", "logs": []}`.

## Which key pays

Every connector call needs `X-Payment-Key`, free operations included: a free
operation still reserves compute, and a key with nothing behind it is refused
with `402`. There are two sources, and for a new agent it is almost always the
first.

| Your situation | Take |
|---|---|
| the wallet was registered recently (the window is in `/register`'s answer) | **the trial** — `POST /trial-key` with the wallet's `wk_`. A real key, scoped to connectors, and what connectors are meant to be called with |
| the trial is spent or expired, or the wallet is older than the window | a funded key — `POST /wallet/v1/create-payment-key` |
| you need to run your own WASI module, not a connector | a funded key; the trial does not reach anything else |

**Claim the trial in the same breath as `POST /register`, not later.** The window
is counted from registration and the refusal is terminal — a wallet registered
three weeks ago cannot get one, and retrying changes nothing. An agent that
expects to live a while claims at birth and keeps the string.

### What a trial actually buys, and why the dollars mislead

A trial holds **$1.00 and lives 7 days**, and neither is the limit you will meet.
The limit is the **daily connector quota**: a wallet minted today gets about ten
calls a day, per connector, and the allowance grows with the wallet's age.

Count in calls per day, not in money. At roughly a cent a call, a dollar is some
ninety calls — nine days of quota against a key that expires in seven. The
balance will still read almost $1.00 when the agent has been stuck for a week.

Three things make the count go faster than it looks:

* **free operations still count.** `status` costs no fee and still spends a tick,
  which is what makes "just poll `status` until it works" the expensive mistake;
* **refusals count.** The counter moves before the limit is compared, so an
  attempt that was denied has spent the same tick as one that worked;
* **a run that started is charged** even when the service then refuses it, so a
  loop retrying a terminal refusal burns fee and quota together and converges on
  nothing.

Read the refusal before retrying it. `connector_quota_exceeded` names both
numbers ("11 of 10 calls") and clears at the day's end; nothing else about it is
worth waiting through.

Two refusals here are terminal and worth recognising rather than retrying:
`trial_already_claimed` (this wallet has had its one) and `trial_ip_limit` (the
network address has had its few). Neither passes with time, and registering
another wallet from the same address does not move the second one. The way
forward from either is a funded key.

## Reading a refusal

| prefix | meaning | what to do |
|---|---|---|
| `policy_denied:` | the owner's policy refused (cap, coin, method, missing policy) | do not retry; change the request inside the caps, or ask the owner |
| `invalid_label:` / `sub_key_unavailable:` | a sub-key label was malformed, or this project has none | fix the label; only connectors have sub-keys |
| `wallet_busy` | another operation holds the wallet | poll `in_flight_request_id` if present, then retry once |
| `Daily connector quota reached` | the wallet's daily call budget is spent (refused calls count too) | wait; the budget grows with wallet age |
| `unknown_operation` / "does not sell operation" | the operation is not priced | read the connector's skill for the list |
| `invalid_secrets_ref` | the `secrets_ref` names no possible row: the account id is not one, or the profile is not 1–64 bytes or holds an ASCII character other than a letter, digit, `-` or `_` | fix the reference — `{"account_id": "<owner>", "profile": "<name>"}` |
| `Access denied by access condition` | the row exists but its condition does not admit your wallet | ask the owner to whitelist your wallet's 64-character account (`outlayer secrets access`), or name a row that does |
| `… its time limit passed at <date>` | you WERE granted and the grant has expired | ask the owner to grant again with a later date; being named again without one does not help |
| `… its AccountPattern \`…\` cannot be compiled as a regular expression` | the owner's condition holds a pattern the engine will not compile; the row refuses everyone, whatever its other branches say, until the owner fixes it | ask the owner to fix the pattern (`outlayer secrets access`) |
| the venue's own text | the outside service refused | act on it; the platform did its part |

## What a call costs

Compute (about $0.001 a call) plus the operation's fee on top. A run that
started is charged even when it answers an error — that is how a refusal by a
bank or a venue stays visible. Only a platform refusal before the guest runs
(no `operation`, quota, unpriced) costs nothing. A module that traps or times
out has its operation fee refunded.

## Secrets and keys

* **Your secrets** (policies, venue tokens) are stored by the wallet owner for
  one connector and reach only that connector's runs — either under your wallet
  (`outlayer secrets set-for-agent '{"KEY":"value"}' --project connectors.outlayer.near/<connector> --api-key wk_…`)
  or under the owner's own account with a whitelist naming your wallet, which
  you then name in `secrets_ref`. What you may read is decided by the row's
  on-chain access condition.
* **The connector author's own credential** is named in its manifest and is
  never yours to see or set.
* **Sub-keys.** A venue connector signs with a distinct key of your wallet per
  purpose: by convention `trading` (the venue account) and `bridge` (the EVM
  address funding legs pass through). They are your wallet's addresses under
  the owner's policy, and no other connector can reach them. The wallet's own
  EVM key is never signable from inside a connector.

## Asking an owner to let you read their credential

The usual arrangement for a connector that acts on somebody's account — their
mailbox, their bank, their exchange — is that the OWNER stores the credential
once under their own account and names your wallet as a reader. You then name
their row in `secrets_ref`. The credential itself never reaches you: the
connector reads it inside the enclave.

**They cannot guess which account to name, and you must tell them.** Naming the
wrong one is refused in words identical to the secret not existing at all, so a
vague request costs a round trip at best and a wrong diagnosis at worst.

**Step 1 — read your own account.** It is the 64-character account of the wallet
that will PAY, i.e. the one that owns the `X-Payment-Key` you will send:

```
GET https://{api_host}/wallet/v1/address?chain=near
Authorization: Bearer <that wallet's wk_>
→ { "address": "0baa071c…56a1", "wallet_id": "…" }
```

It is the `address`. Not the `wallet_id`, which is a UUID and names nothing on
chain. Not a bound name like `alice.near`, which is the identity you ACT as and
never the one a grant names. Not another wallet you also hold — if you have
several, the payer is the one that matters.

**Step 2 — ask in a sentence a person can evaluate.** An identifier on its own
is not a request:

> To send that mail I need to read your Gmail credential. I never see its value —
> the connector opens it inside the enclave. Please grant read access to my
> wallet account `0baa071c…56a1` on the secret you stored for project
> `connectors.outlayer.testnet/gmail`, profile `gmail`.

**Step 3 — call, naming their row:**

```json
{"input": {"operation": "status"}, "secrets_ref": {"account_id": "owner.testnet", "profile": "gmail"}}
```

`profile` is a label the owner chose when storing the row. It is not derived
from anything and cannot be guessed; each connector's skill names the
conventional one, and if a call is refused it is worth asking which they used.

**A grant issued seconds ago can still be refused.** The condition is read from
the chain, and a refusal immediately after the owner says "done" proves nothing.
Wait a minute, repeat the free `status`, and only then conclude they named the
wrong account. Both cases say `Access denied by access condition` in the same
words.

## The library

| connector | what it is | skill |
|---|---|---|
| `hyperliquid` | Hyperliquid perpetuals: markets, leverage, limit and market orders, cancels, positions; funding over CCTP from the intents or the confidential balance | https://skills.outlayer.ai/hyperliquid-connector/SKILL.md |
| `polymarket` | Polymarket prediction markets: find markets, buy and sell outcome shares, positions, claim resolved markets, fund from the wallet and back | https://skills.outlayer.ai/polymarket-connector/SKILL.md |
| `gmail` | send mail from the owner's own Gmail address, under the owner's recipient policy; it cannot read the mailbox | https://skills.outlayer.ai/gmail-connector/SKILL.md |
| `mercury` | Mercury business banking: pay a recipient (with the bank's approval rules), issue and cancel invoices, read the ledger | https://skills.outlayer.ai/mercury-connector/SKILL.md |
| `connector-probe` | the platform's own test connector: pricing, limits, secrets, the outbound allowlist, traps and timeouts | https://github.com/out-layer/outlayer/blob/main/connectors/connector-probe/README.md |
| `subkey-probe` | EVM sub-keys end to end, for testing the signing path | https://github.com/out-layer/outlayer/blob/main/connectors/subkey-probe/README.md |

`polymarket` and the funding legs of `hyperliquid` run on mainnet only; the
probes are testnet only.

## Working with any connector

1. Call `status` first. Every connector has one, it is free or cheap, and it
   tells you whether a policy is stored and what it allows.
2. Size the request inside the caps `status` reports instead of discovering
   them by refusal — a refusal still costs the fee, because your call ran.
3. Long flows are step-shaped: an operation returns an `id` and you call
   `*_continue` until `step` is `done`. Never start a second flow while one is
   unfinished.
4. One call does one thing. Do not batch orders or payments into one call.
