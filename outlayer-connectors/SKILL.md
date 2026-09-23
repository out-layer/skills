---
name: outlayer-connectors
description: The OutLayer connector library — how an agent calls any connector (auth, the `operation` field, secrets, fees, the trial, refusal codes) and what each connector does. Use when an agent with an OutLayer custody wallet needs to reach a bank, a trading venue or another outside service, or when a connector call is refused and the reason has to be read.
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
* **`X-Use-Owner-Secret: 1`** (a switch: any value but empty, `0` or `false`) brings the secrets stored under your own wallet
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
| the wallet is less than a week old and has not had its trial | **the trial** — `POST /trial-key` with the wallet's `wk_`: ten connector calls, free |
| the trial is spent or the week is over | a funded key — `POST /wallet/v1/create-payment-key`. **A key with money on it has no call limit** |
| you need to run your own WASI module, not a connector | a funded key; the trial does not reach anything else |

## The trial: ten calls, in the wallet's first week

That is the whole rule. `POST /trial-key` answers with the key, `calls` (ten) and
`expires_at`; send the key as `X-Payment-Key`.

```bash
curl -s -X POST -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.ai/trial-key"
```

```json
{
  "payment_key": "a1b2…8f90:0:4c1d…9ab3",
  "owner": "a1b2…8f90",
  "nonce": 0,
  "calls": 10,
  "expires_at": "2026-09-25T19:01:00Z",
  "project_ids": ["connectors.outlayer.near/*"],
  "note": "Send this as the X-Payment-Key header. It is shown once…"
}
```

**Store `payment_key` immediately.** It is shown once and cannot be recovered or
re-issued. If you lose it, your only route forward is a funded payment key.

* **The week is counted from the wallet's registration, not from the claim.** A
  trial claimed on day six works for one day; on day seven there is nothing left
  to claim (`403 trial_window_closed`, terminal). Claim it in the same breath as
  `POST /register` and keep the string — it is shown once.
* **Ten calls means ten calls that were accepted.** Any operation counts, the free
  `status` included, and so does a run that then fails or times out. A call
  refused up front (a 4xx answer) does not.
* **The eleventh answers `402 trial_exhausted`, and any call after the week
  `402 trial_expired`. Both are terminal** — waiting changes nothing. The next
  step is a funded key.
* **There is no balance to watch.** A trial is not measured in money. To see what
  is left, `GET /subscription/status` with the key: `trial.calls_left`.
* It reaches connectors only; anything else is `project_not_allowed`.
* It cannot pay a developer: `X-Attached-Deposit` on a trial call → `403 no_deposit`.
  It cannot be withdrawn or topped up — it is not money.
* **`Bearer near:` callers** claim nothing — a trial is claimed with a `wk_`.
* A trial stops starting calls shortly before `expires_at`, so none is cut off mid-run.

Spend them on purpose: one `status` to see that the credential works, then the
calls the task needs. Polling `status` in a loop is how a trial disappears
without having done anything.

Two more refusals are terminal and worth recognising rather than retrying:
`409 trial_already_claimed` (this wallet has had its one) and `403 trial_unavailable` (no
trial is offered to this caller). The way forward from either is a funded key.

## Paying: no quota

A caller who pays is not limited by any count of calls. A funded key is bounded
by the money on it, a subscription by its allowance. No quota counts a paying
caller's connector calls — so if a task needs more than the trial, fund a key; do
not look for a way to wait the limit out, because there is none to wait for.

The one ceiling that remains is each connector's own technical cap on a single
operation (Gmail: 500 sends a day per wallet), there against a runaway loop. It
answers `operation_limit_reached` with `retry_after_seconds`, and is far above
ordinary use. An attempt it refuses still counts toward it — wait out
`retry_after_seconds` rather than retrying into it.

## Reading a refusal

Every refusal carries a machine-readable `reason` next to the human sentence.
**Branch on `reason`.** The sentence is written for a person and gets reworded;
the reason is the contract.

```json
{ "error": "Project not allowed for this payment key", "reason": "project_not_allowed" }
```

Note the shape differs from `/wallet/v1/*`, which puts the code in `error` and
the sentence in `message`:

| door | machine-readable | human |
|---|---|---|
| `/call/{owner}/{project}` | `reason` | `error` |
| `/wallet/v1/*` | `error` | `message` |

| `reason` / prefix | meaning | what to do |
|---|---|---|
| `missing_payment_key` | you sent no payment credential | send `X-Payment-Key` |
| `wk_is_not_a_payer` | you sent your `wk_`. It names your wallet; it buys nothing | send `X-Payment-Key` with a key that wallet owns |
| `project_not_allowed` | the key's scope does not reach this project — a trial reaches connectors only | funding it changes nothing; use a key whose scope does |
| `insufficient_balance`, `out_of_funds` | the key has no money left | top the key up |
| `rate_limit_exceeded` | too many calls in a window | back off and retry |
| `wallet_not_yours` | `X-Wallet-Id` named a wallet your credential does not identify — terminal | drop the header, or send your own wallet's id |
| `policy_denied:` | the owner's policy refused (cap, coin, method, missing policy) | do not retry; change the request inside the caps, or ask the owner |
| `invalid_label:` / `sub_key_unavailable:` | a sub-key label was malformed, or this project has none | fix the label; only connectors have sub-keys |
| `wallet_busy` | another operation holds the wallet | poll `in_flight_request_id` if present, then retry once |
| `trial_exhausted` | the trial key has made its ten calls — **terminal** | create a funded key (`POST /wallet/v1/create-payment-key`); it has no call limit |
| `trial_expired` | the trial key is past the wallet's first week — **terminal**, calls left or not | same |
| `operation_limit_reached` | a connector's own technical cap on one operation | wait `retry_after_seconds`; it is far above ordinary use, so look for a loop |
| `unknown_operation` / "does not sell operation" | the operation is not priced | read the connector's skill for the list |
| `invalid_secrets_ref` | the `secrets_ref` names no possible row: the account id is not one, or the profile is not 1–64 bytes or holds an ASCII character other than a letter, digit, `-` or `_` | fix the reference — `{"account_id": "<owner>", "profile": "<name>"}` |
| `Access denied by access condition` | the row exists but its condition does not admit your wallet | ask the owner to whitelist your wallet's 64-character account (`outlayer secrets access`), or name a row that does |
| `… its time limit passed at <date>` | you WERE granted and the grant has expired | ask the owner to grant again with a later date; being named again without one does not help |
| `… its AccountPattern \`…\` cannot be compiled as a regular expression` | the owner's condition holds a pattern the engine will not compile; the row refuses everyone, whatever its other branches say, until the owner fixes it | ask the owner to fix the pattern (`outlayer secrets access`) |
| the venue's own text | the outside service refused | act on it; the platform did its part |

## Subscription: a flat rate for connector calls

A subscription replaces per-call payment with an allowance on one payment key.
How it is bought (an on-chain payment naming the key's `owner` and `nonce`), what
the `wk_` can and cannot do about it, and the rules on spending order, renewal,
concurrency (`429 call_already_in_flight`) and one-per-agent are in
[`references/subscription.md`](references/subscription.md).

## What a call costs

Compute (about $0.001 a call) plus the operation's fee on top. A run that
started is charged even when it answers an error — that is how a refusal by a
bank or a venue stays visible. Only a platform refusal before the guest runs
(no `operation`, unpriced, a spent trial) costs nothing. A module that traps or times
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

## Asking the user to store a credential under your wallet

A connector often needs a credential that is **yours to use but not yours to
hold** — an API token for the service it talks to. It is stored under YOUR
agent account, sealed to the keystore, and a connector reads it only when the
call asks for it. You never see the value, and neither does the browser page
that stores it: it is encrypted before it leaves.

You cannot store it yourself. Your wallet has no NEAR to pay for the write, and
the key that authorises it never leaves the TEE — so the coordinator prepares
the transaction and a **human sends and pays for it**.

Send them the link:

> The <service> connector needs its API token. Store it here — it is encrypted
> in your browser and I never see it:
> https://app.outlayer.ai/secrets?project={connector_project_id}&name={VAR_NAME}

The link may propose WHICH secret to create — `project`, `name`, `profile`,
`generate` — and deliberately **cannot** carry its value or your key: those
would end up in browser history, referrers and proxy logs. On the page they
paste your `wk_` (or pick it, if that browser already saved it), choose the
scope, and sign one call. Cost is ~0.1 NEAR, the excess refunded.

Then ask for it per call with `x-use-owner-secret: true` — without that header
nothing is fetched, because most calls need no secret and a lookup that always
runs is a keystore round trip on every call:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-Payment-Key: $PAYMENT_KEY" -H "x-use-owner-secret: true" \
  -d '{"input":{"operation":"send", ...}}' \
  "https://api.outlayer.ai/call/connectors.outlayer.near/<connector>"
```

Which route you get is the owner's choice, not yours. For a leased account
(`hos_lease`) it is the only one available: storing a secret under your wallet
needs that wallet's `wk_`, and the human holding the lease does not have it.

**Say what you are asking for and why.** "I need your SendGrid key to send the
mail you asked for" is a sentence a person can refuse. A bare link is not.

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
| `github` | work in the owner's GitHub account, as the owner: issues, comments, files, commits, pull requests, reviews and gists, under the owner's policy | https://skills.outlayer.ai/github-connector/SKILL.md |
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
