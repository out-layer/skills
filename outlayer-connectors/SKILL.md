---
name: outlayer-connectors
description: The OutLayer connector library — how an agent calls any connector (auth, the `operation` field, secrets, fees, the trial, the complete `/call` refusal set), what each connector does, and what an agent can offer its owner with them. Use when an agent with an OutLayer custody wallet needs to reach a bank, a trading venue or another outside service, when a connector call is refused and the reason has to be read, or when an agent wants to know what it could do for its owner. Not for wallet operations (agent-custody) or one connector's operations (its own skill).
---

# OutLayer connectors

A connector is a WASI module curated by the OutLayer team — reviewed, priced
and kept working — that runs inside the same TEE as your wallet: the
credential is sealed in the enclave, the owner's policy is checked on every
call, and the module reaches only the hosts its signed manifest declares. This
skill is how any connector is called, paid and refused. It does not cover
wallet operations — balances, transfers, swaps, creating a payment key:
[`agent-custody`](https://skills.outlayer.ai/agent-custody/SKILL.md) — nor one
connector's operations, policy and prices: that connector's own skill, listed
in "The library".

## Where to read what

Fetched over HTTP, the relative links below resolve against
`https://skills.outlayer.ai/outlayer-connectors/`.

| the task in front of you | read |
|---|---|
| call a connector, choose the key, read a refusal | this file |
| offer your owner something a connector does | [`references/offering.md`](references/offering.md) |
| a credential: the owner's row, or one under your own wallet (`X-Use-Owner-Secret`) | [`references/credentials.md`](references/credentials.md) |
| a subscription, or a sponsor code (`spn_…`) | [`references/subscription.md`](references/subscription.md) |
| a call answered `awaiting_owner` or `notified`; `task_status` | [`references/owner-tasks.md`](references/owner-tasks.md) |
| one connector's operations | its skill — "The library" |

## The call

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/<connector>
X-Payment-Key: <a payment key the calling wallet owns>
Content-Type: application/json

{"input": {"operation": "<name>", ...}}
```

Testnet: substitute `testnet-api.outlayer.ai` and `connectors.outlayer.testnet`.
The two move together: a testnet key against `connectors.outlayer.near` fails,
and the refusal names the project, not the network.

* **`operation` is mandatory and is the unit of price.** A call without it is
  refused before anything runs and costs nothing.
* **`X-Payment-Key` must be a key the wallet itself owns** (created from the
  wallet's own `wk_`), or the connector cannot see the secrets stored for you.
* **`X-Wallet-Id` opens your wallet to the call.** A connector that signs or
  moves funds (`hyperliquid`, `polymarket`) needs it — without it the run has
  no wallet. Send `wallet_id` from `GET /wallet/v1/address`; another id is
  refused `wallet_not_yours`.
* **`secrets_ref` names the owner's row** (not on the trading connectors) — the
  credential or policy your owner stored under THEIR account, with your wallet
  in its access rule:
  `{"input": {...}, "secrets_ref": {"account_id": "owner.near", "profile": "gmail"}}`.
  The profile is the connector's id unless the owner chose another. A grant
  may expire, so a call that worked yesterday can be refused today with the
  date it lapsed on. Without `secrets_ref` the connector has no secrets.
* **`X-Use-Owner-Secret: 1` reads a credential from your own wallet** — the row
  stored under your wallet's account for that connector. It takes effect only
  on a curated connector and only when the call sends no `secrets_ref`; on a
  project that is not a connector it does nothing — name the row in
  `secrets_ref` there. Storing that row:
  [`references/credentials.md`](references/credentials.md).
* **Trading connectors take only the owner's policy** (`hyperliquid`,
  `polymarket`): send no `secrets_ref` — if your wallet has an owner, OutLayer
  attaches their row `{owner, "<connector>"}`; a row of the owner's that they
  named for you is accepted; any other account's row, yours included, is
  refused `policy_row_not_owner`. Naming another account's row can block your
  wallet on both trading connectors for a while (`403 calls_suspended`,
  `terminal: false`) — one block per wallet, covering both. A wallet with no
  owner may name its own row. With no policy they trade on a built-in default.

### The answer

`{call_id, status, output, error, compute_cost, instructions, time_ms,
poll_url, attestation_url}`, fields with nothing to say absent. `status` is
`completed` or `failed` (`pending` on an `async: true` call, with `poll_url`).
`compute_cost` is USDC minimal units (6 decimals). `attestation_url` is the
run's TEE attestation, absent on a failed call. **The connector's own answer,
`{success, operation, output, error, logs}`, is inside `output`**; a
connector's refusal is HTTP 200 with `output.success: false`. A run the
platform refused (e.g. `policy_row_missing:`) is `status: "failed"` with the
top-level `error` and no `output` — do not read `output.success` there.

## Which key pays

Every connector call needs `X-Payment-Key`, free operations included: a free
operation still reserves compute.

| Your situation | Take |
|---|---|
| the wallet is less than a week old and has not had its trial | **the trial** — `POST /trial-key`: fifty connector calls, free |
| somebody gave you a sponsor code (`spn_…`) | **redeem it** — `POST /wallet/v1/sponsorship`: a subscription on the nonce-0 key, paid by the sponsor |
| the trial is spent or the week is over | a funded key — `POST /wallet/v1/create-payment-key`. **A key with money on it has no call limit** |
| you run your own WASI module, not a connector | a funded key; the trial reaches nothing else |

## The trial: fifty calls, in the wallet's first week

That is the whole rule. `POST /trial-key` with the wallet's credential answers
with the key, `calls` (fifty) and `expires_at`; send the key as `X-Payment-Key`.

```bash
curl -s -X POST -H "Authorization: Bearer $API_KEY" "https://api.outlayer.ai/trial-key"
```

```json
{"payment_key": "a1b2…8f90:0:4c1d…9ab3", "owner": "a1b2…8f90", "nonce": 0, "calls": 50,
 "expires_at": "2026-09-25T19:01:00Z", "project_ids": ["connectors.outlayer.near/*"],
 "note": "Send this as the X-Payment-Key header. …"}
```

* **Read the key again any time** with `GET /wallet/v1/payment-key`, with the
  credential that claimed it. If that `wk_` is revoked the key stops working,
  and another `wk_` of the wallet cannot read it
  (`payment_key_other_credential`). `409 payment_key_not_recoverable`: an older
  random key — your copy is the only one; a sponsor code redeem that sends it
  as `X-Payment-Key` moves the slot to a key you can read again.
* **The week is counted from the wallet's registration, not from the claim.**
  Claim it in the same breath as `POST /register`.
* **A call counts once it is accepted** — any operation, the free `status`
  included, and a run that then fails or times out. A 4xx refusal does not.
* **The fifty-first answers `402 trial_exhausted`, any call after the week
  `402 trial_expired`. Both are terminal** — the next step is a funded key.
* What is left is `trial.calls_left` in `GET /subscription/status`.
* **OutLayer may turn this key into a subscription** (keep the key): no
  `trial` block, `has_subscription: true`. Only OutLayer extends it — never
  buy on nonce 0.
* It reaches connectors only (`project_not_allowed`), cannot pay a developer
  (`X-Attached-Deposit` → `403 no_deposit`), and cannot be withdrawn or topped
  up — it is not money. It stops starting calls shortly before `expires_at`.
* `Bearer near:` works as `wk_` does on `POST /trial-key`,
  `GET /wallet/v1/payment-key` and `POST /wallet/v1/sponsorship`.

Spend it on purpose: one `status`, then the calls the task needs. Polling
`status` in a loop is how a trial disappears.

`POST /trial-key` answers its own refusals with `reason` and `terminal`; a
credential refused before them answers as `/wallet/v1/*` does.

| status | `reason` | terminal | what to do |
|---|---|---|---|
| 404 | `trial_disabled` | true | no trial is offered here — create a funded key |
| 403 | `trial_window_closed` | true | past the wallet's first week — create a funded key |
| 409 | `trial_already_claimed` | true | read it with `GET /wallet/v1/payment-key` |
| 403 | `trial_unavailable` | true | no trial for this caller — create a funded key |
| 401 | `unauthorized` | true | send the wallet's valid `wk_` or `near:` credential |
| 503 | `internal_error` | false | send the same request again later |

## A sponsor code

**If your human mentions a voucher, a code (`spn_…`) or sponsored premium, ask
for the code and redeem it:** [references/subscription.md](references/subscription.md),
"A sponsor code".

## Paying: no quota

A paying caller is bounded by the money on the key or the subscription's
allowance, never by a count of calls — if a task needs more than the trial,
fund a key; there is no limit to wait out. The one ceiling left is each
connector's technical cap on one operation (Gmail: 500 sends a day per
wallet), against a runaway loop: `operation_limit_reached` with
`retry_after_seconds`. A refused attempt still counts — wait it out.

## Reading a refusal

A refusal before the run is an HTTP 4xx/5xx whose body has a machine-readable
`reason` beside the sentence in `error`, and often `terminal`. **Branch on
`reason`**; the sentence gets reworded. (`/wallet/v1/*` puts the code in
`error` and the sentence in `message`.)

```json
{ "error": "Project not allowed for this payment key", "reason": "project_not_allowed" }
```

Every `reason` `/call` answers — **this list is complete**. `terminal` is the
body's field; `—` means the body has none.

| HTTP | `reason` | terminal | meaning → what to do |
|---|---|---|---|
| 401 | `missing_payment_key` | — | no payment credential → send `X-Payment-Key` |
| 401 | `wk_is_not_a_payer` | — | you sent a `wk_`; it pays for nothing → send a payment key the wallet owns |
| 400 | `bad_key_format` | — | `X-Payment-Key` is not `owner:nonce:key` → fix it |
| 401 | `invalid_key` | — | no such key on this network, deleted, or a wrong secret → use a live key of this network |
| 400 | `invalid_request` | — | the sentence names the field → fix it |
| 400 | `invalid_version_key` | — | malformed, or sent to a connector (connectors run their active version) → drop it |
| 400 | `invalid_secrets_ref` | — | names no possible row: the account id is not a NEAR account id, or the profile is not 1–64 bytes or holds an ASCII character other than a letter, digit, `-`, `_` → fix it |
| 403 | `policy_row_not_owner` | true | a trading connector got a row that is not your owner's → send no `secrets_ref`; try no other rows |
| 403 | `calls_suspended` | false | your wallet is blocked on both trading connectors for a while; the same call works after → stop naming other accounts' rows; tell your owner |
| 403 | `wallet_not_yours` | true | `X-Wallet-Id` is not your wallet → send yours (`GET /wallet/v1/address`) |
| 403 | `project_not_allowed` | — | the key's scope does not reach this project → use a key whose scope does; funding changes nothing |
| 404 | `project_not_found` | — | no such project on this network → check the name and the host pair |
| 400 | `unknown_operation` | true | no `operation`, or an unpriced one → see the connector's skill |
| 402 | `insufficient_balance` | — | the key's money does not cover the run → top it up; the trial key takes none — create a funded key |
| 402 | `out_of_funds` | true | allowance spent or expired, no money on the key → fund the key or extend the subscription |
| 402 | `insufficient_allowance` | true | allowance below this operation's price, no money → same |
| 402 | `expires_too_soon` | true | the subscription ends before this operation could finish → same |
| 402 | `allowance_no_deposit` | true | `X-Attached-Deposit` on a call the allowance pays → attach deposits only from a funded key |
| 402 | `trial_exhausted` | true | fifty calls made → create a funded key; it has no call limit |
| 402 | `trial_expired` | true | past the wallet's first week → same |
| 403 | `no_deposit` | — | `X-Attached-Deposit` on a trial or granted key → drop it, or pay from a funded key |
| 400 | `trial_key_not_purchasable` | true | `POST /subscription/purchase` with the trial key → buy on a key with nonce ≥ 1 |
| 400 | `max_per_call_exceeded` | — | the key's per-call ceiling is below the run's compute → another key, or less compute |
| 400 | `compute_limit_too_low` | — | `X-Compute-Limit` below the minimum the sentence names → raise it |
| 429 | `rate_limit_exceeded` | — | too many calls on this key; no `Retry-After` → pause, then send slower |
| 429 | `call_already_in_flight` | false | the subscription has a call in flight, the key has no money → wait for it, or fund the key |
| 429 | `operation_limit_reached` | false | a connector's cap on one operation → wait `retry_after_seconds`; look for a loop |
| 408 | `timeout` | — | not finished in the synchronous window; it may still execute and is charged → do not resend; `GET https://api.outlayer.ai/calls/{call_id}` (the body's `poll_url`) with the same key; send long work with `async: true` |
| 409 | `no_bound_identity` | true / false | `use_bound_identity` with nothing to run as: `true`, the key names no wallet; `false`, no active binding yet → drop the flag, or the owner binds an account |
| 423 | `vault_unlocked` | — | the secret's vault was recovered by its customer → its owner moves the secret |
| 403 | `vault_not_verified` | — | the secret's vault is not verified by the keystore DAO → its owner re-registers it or moves the secret |
| 503 | `upstream_unavailable` | false | a dependency is briefly down → wait `Retry-After`, send again |
| 503 | `keystore_error` | false | the keystore could not answer → same |
| 500 | `internal_error` | — | platform fault; the call may still run → do not resend (it pays twice); report it |
| 404 | `call_not_found` | — | `GET /calls/{call_id}`: no such call for this key → check both |
| 403 | `tee_session_required` | — | worker-only endpoint; a caller never meets it |

A run the platform started and refused is `status: "failed"`; the top-level
`error` starts with:

| `error` | meaning → what to do |
|---|---|
| `policy_row_missing:` | trading connector: the named row's profile is not the connector's id and nobody stored it → name a stored row, or none |
| `Access denied by access condition` | the row's condition does not admit your wallet → ask the owner to whitelist your 64-character account |
| `… its time limit passed at <date>` | your grant expired → ask the owner for a new one |
| `… its AccountPattern \`…\` cannot be compiled as a regular expression` | the row refuses everyone → ask the owner to fix the pattern |
| `This project's manifest …` | the project does not admit this door → call it as the sentence says |

In `output.error`: `policy_denied:` — the owner's policy refused (a cap, a
coin, a market, a method, a destination): do not retry; change the request or
ask the owner. `invalid_label:` / `sub_key_unavailable:` — the connector's own
sub-key fault: report it. Anything else is the outside service's refusal: act
on it.

## Subscription

An allowance on one payment key (nonce ≥ 1, never the trial) in place of
per-call payment — buying it, OutLayer's gift, the rules:
[`references/subscription.md`](references/subscription.md).

## What a call costs

Compute (about $0.001 a call) plus the operation's fee. A run that started is
charged even when it answers an error, such as a venue's refusal. Only a
refusal before the guest runs costs nothing. A module that traps or times out
has its operation fee refunded.

## Secrets and keys

* **The owner's row** (a credential, a policy) reaches only that connector's
  runs; the row's on-chain access condition decides what you may read.
* **The connector author's own credential** is named in its manifest and is
  never yours to see or set.
* **Sub-keys.** A venue connector signs with a distinct key of your wallet per
  purpose — `trading` (the venue account), `bridge` (funding legs) — under the
  owner's policy; no other connector reaches them, and the wallet's own EVM key
  is never signable from a connector.

## The library

| connector | what it is | skill |
|---|---|---|
| `hyperliquid` | perpetuals: markets, leverage, orders, cancels, positions; funding through 1Click from the intents or confidential balance | https://skills.outlayer.ai/hyperliquid-connector/SKILL.md |
| `polymarket` | prediction markets: find markets, buy and sell outcome shares, positions, claim, fund and withdraw | https://skills.outlayer.ai/polymarket-connector/SKILL.md |
| `gmail` | send mail from the owner's Gmail address under their recipient policy; cannot read the mailbox | https://skills.outlayer.ai/gmail-connector/SKILL.md |
| `github` | issues, comments, files, commits, pull requests, reviews and gists in the owner's account, under their policy | https://skills.outlayer.ai/github-connector/SKILL.md |
| `mercury` | business banking: pay a recipient, issue and cancel invoices, read the ledger | https://skills.outlayer.ai/mercury-connector/SKILL.md |
| `connector-probe` | the platform's test connector: pricing, limits, secrets, allowlist, traps, timeouts | https://github.com/out-layer/outlayer/blob/main/connectors/connector-probe/README.md |
| `subkey-probe` | EVM sub-keys end to end | https://github.com/out-layer/outlayer/blob/main/connectors/subkey-probe/README.md |

Networks: `hyperliquid` on mainnet and testnet, its funding legs
(`deposit_*`, `withdraw_*`) on mainnet only. `polymarket`: mainnet only.
`gmail`, `github`, `mercury`: both. Probes: testnet only.

## Working with any connector

1. Call `status` first: it is free or cheap, and says whether a policy is
   stored and what it allows.
2. Size the request inside the caps `status` reports — a refusal still costs
   the fee, because your call ran.
3. Long flows are step-shaped: an operation returns an `id`; call
   `*_continue` until `step` is `done`. Never start a second flow while one is
   unfinished.
4. One call does one thing. Do not batch orders or payments.
5. `awaiting_owner` and `notified` are success; do not retry:
   [`references/owner-tasks.md`](references/owner-tasks.md).
