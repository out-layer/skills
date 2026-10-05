---
name: mercury-connector
description: Operate the wallet owner's Mercury business bank account through the `mercury` connector — pay a recipient, issue and cancel invoices, read accounts, recipients, transactions and payment status — under the owner's spending policy, and send the owner to connect the account at app.outlayer.ai/connect/mercury. Also covers writes the owner's rules make wait for their approval, which answer `awaiting_owner`. Use when an agent with an OutLayer wallet must move USD out of, or invoice into, a Mercury account, or when the owner talks about paying a contractor, invoicing a client or what the company spent.
---

# Mercury connector

You act on the owner's real bank account. Two layers gate every payment and
neither can waive the other: the owner's `MERCURY_POLICY` (enforced in the
enclave, before anything reaches the bank) and Mercury's own approval rules. A
refusal tells you which layer refused — read it rather than retrying.

Not here: cards, approving a payment Mercury queued (a person does that in
Mercury's app), and your own wallet's funds
(<https://skills.outlayer.ai/agent-custody/SKILL.md>). How any connector is
called and paid — which key, the trial, the platform's own refusals — is in
<https://skills.outlayer.ai/outlayer-connectors/SKILL.md>; when to offer this,
and how to say it so the owner can refuse, in
<https://skills.outlayer.ai/outlayer-connectors/references/offering.md>.

## Which file to read

The relative links below resolve against `https://skills.outlayer.ai/mercury-connector/`.

| the task in front of you | read |
|---|---|
| `status`, reading, paying, invoicing, a refusal | this file |
| the owner has not connected, or has not granted you | [`references/connect.md`](references/connect.md) |
| a write answered `awaiting_owner`, the owner's `rules`, or you follow a task | [`references/owner-approval.md`](references/owner-approval.md) |
| any task state or `failure_reason`; `inbox_full`, `muted` and the other task limits | <https://skills.outlayer.ai/outlayer-connectors/references/owner-tasks.md> |

## Where it runs

| network | `{api_host}` | `{connectors_account}` | state |
|---|---|---|---|
| mainnet | `api.outlayer.ai` | `connectors.outlayer.near` | live |
| testnet | `testnet-api.outlayer.ai` | `connectors.outlayer.testnet` | live |

Use the pair for the network your payment key belongs to; a key of one network
cannot pay on the other. Operations marked HTTPS-only below refuse on the
on-chain path whatever the network.

## Call shape

The owner connected their account once and named your wallet on the row; you
name their row in every call.

```
POST https://{api_host}/call/{connectors_account}/mercury
X-Payment-Key: <a payment key the custody wallet owns>
Content-Type: application/json

{"input": {"operation": "<op>", ...},
 "secrets_ref": {"account_id": "<owner's account>", "profile": "mercury"}}
```

The connector's answer is `{success, operation, output, error, logs}` inside the
platform's `output` — the envelope is in
[outlayer-connectors](https://skills.outlayer.ai/outlayer-connectors/SKILL.md).

## Where the credential comes from

The owner connects once, at <https://app.outlayer.ai/connect/mercury>, with a
Mercury API token they create, and then grants your payer account on the
secrets row `mercury`. You cannot do either for them: it takes their Mercury
settings and their wallet signature. Say what will happen before they paste
anything — a token's scope cannot be edited afterwards:

> To let me work with your Mercury account: create an API token in Mercury
> (Settings → API Tokens → Custom; "Read + Send Money with Approval" keeps
> every payment waiting for a person in Mercury's app) and connect it at
> https://app.outlayer.ai/connect/mercury — the token is encrypted in your own
> browser, you set what I may pay, and one transaction from your wallet
> stores it under your account. Then add my account `<your payer account>`
> under Access on the secrets row `mercury`:
> https://app.outlayer.ai/secrets?project=connectors.outlayer.near/mercury&profile=mercury&access=1
> I never see the token: it is opened inside the enclave.

Each scope, each screen they will see, what it means for them, and how the
grant works: [`references/connect.md`](references/connect.md).

## Start here

`{"operation": "status"}` — free, and the one call that is never gated. It says:

| field | meaning |
|---|---|
| `token_present`, `token_valid`, `token_note` | whether a token is stored and whether Mercury accepts it; the note says why not |
| `account_count` | how many accounts the token reaches |
| `policy_mode` | `read_only` (no policy), `active`, or `broken` (a policy the connector cannot read: everything but `status` refuses; `policy_note` says why) |
| `policy` | over HTTPS, the stored policy field by field, with `present`; on chain, only `present` and `sealed` — pass `reply_pubkey`, a secp256k1 public key in hex, and read `policy_sealed` |
| `payment_methods_in_effect` | what the policy's rails resolve to (ACH when it names none) |
| `budget` | with both amounts set: `monthly_limit_usd`, `spent_or_pending_usd`, `remaining_usd`, counted from Mercury's own ledger |

Check `remaining_usd` before planning a payment. Without a policy the
connector is read-only; ask the owner to store one at the connect page.

## Reading

All HTTPS-only but `payment_status`.

| do | call |
|---|---|
| accounts and balances | `{"operation": "accounts"}` (account numbers masked) |
| saved payees | `{"operation": "recipients"}` — the ids `allowed_recipients` and `pay_invoice` use |
| recent ledger | `{"operation": "transactions", "days": 30, "limit": 50}` (`days` ≤ 90, `limit` ≤ 200) |
| one payment | `{"operation": "payment_status", "transaction_id": "…"}` or `"request_id"`, or neither for recent approval requests |
| invoicing customers / invoices | `{"operation": "customers"}`, `{"operation": "invoices"}`, `{"operation": "invoice_status", "invoice_id": "…"}` |

## Paying

```json
{"operation": "pay_invoice", "recipient_id": "<from `recipients`>", "amount_usd": 120.50,
 "payment_method": "ach", "external_memo": "Invoice INV-2026-081", "note": "invoice 2026-09"}
```

| field | rule |
|---|---|
| `amount_usd` | required. A JSON number in **dollars**, not minimal units: `120.50` is $120.50. Rounded to cents; at least `0.01` |
| `recipient_id` or `recipient` | exactly one. `recipient_id` from `recipients`; `recipient` is an inline payee (the `add_recipient` fields), HTTPS-only, and needs `allow_new_recipients` |
| `payment_method` | `ach` (default), `check`, `domesticWire` or `internationalWire`, within the policy's rails. An `internationalWire` needs a `recipient_id` |
| `wire_purpose_category` | required for a wire, one of `employee`, `landlord`, `vendor`, `contractor`, `subsidiary`, `transferToMyExternalAccount`, `familyMemberOrFriend`, `forGoodsOrServices`, `angelInvestment`, `savingsOrInvestments`, `expenses`, `travel`, `other` |
| `wire_purpose_info` | required with `vendor`, `contractor` and `other` |
| `external_memo` | what the payee's bank statement shows |
| `note` | an internal note, kept with the connector's marker in front |
| `account_id` | optional, and it never chooses: a payment draws on the policy's account, or on the login's only one. An id other than that one is refused |
| `idempotency_key` | at most 200 characters. Defaults to this call's id, so a new call is a new payment: when you may repeat a payment, pass a key of your own and repeat it with the same key |

Mercury refuses an identical send — the same recipient, account and amount —
within 24 hours with HTTP 400, even under another idempotency key.

Two outcomes, both normal:

* **sent** — the answer carries a `transaction_id`; poll it with
  `payment_status`.
* **queued for approval** — Mercury's rules cover this payment, or the token's
  scope only queues: the answer says so and carries a `request_id`. This is
  success, and the safe path the owner chose: report it as done and hand over
  the last step —
  > Done: $120.50 to Acme Hosting is waiting for your approval in the Mercury
  > app.

  A human approves it there; you poll `payment_status` with that id. You
  cannot approve it, and neither can the owner's token.

Both count against the 30-day budget the moment they exist, so a queued
payment is already spent from your point of view.

**Every payment state says whether to keep waiting.** `payment_status` answers
carry `terminal`: `false` means poll again (`pendingApproval`, `approved`,
`pending`), `true` means stop — `sent` (the money left) or `rejected`,
`cancelled`, `failed`, `reversed`, `blocked` (it never will, and `next_step`
says so). A status this connector has never seen is reported as it came with
`terminal: false`, so you keep waiting rather than re-paying.

A payee that is not saved yet needs `add_recipient` first (and the policy's
`allow_new_recipients`); an inline recipient is HTTPS-only because it carries
account and routing numbers.

### When the owner wants to approve it first

Read `policy.rules` in `status` before a write. When a rule says `ask`, the
write answers `{"status": "awaiting_owner", "task_id": …, "link": …}` and
nothing happens at the bank. That is a success: give the owner `link` in a
sentence that says what waits —

> I prepared the payment of $120.50 to Acme Hosting by ACH. Nothing is paid
> until you approve it: https://app.outlayer.ai/inbox/…

— do not send the write again while the task is open, and learn the outcome
with `task_status`. When a rule says `refuse`, stop and quote the sentence. How
rules match, what each outcome of a task means, and the task operations:
[`references/owner-approval.md`](references/owner-approval.md).

## Invoicing

Three operations, all HTTPS-only. Pick by what the owner asked for:

| the owner wants | operation | needs `allow_invoicing` |
|---|---|---|
| a real invoice the customer receives by email and Mercury tracks | `send_invoice` | yes |
| an invoice document to deliver some other way | `create_invoice` | no |
| to withdraw an unpaid invoice | `cancel_invoice` | yes |

**`send_invoice`** creates the invoice in Mercury. Mercury emails it to the
customer at once and tracks it to `Paid`. It goes out under the owner's company
name: confirm the customer, the amount and the due date with the owner first.

```json
{"operation": "send_invoice",
 "customer": {"name": "Client Co", "email": "ap@client.example"},
 "line_items": [{"name": "Consulting, August", "unit_price_usd": 250.00, "quantity": 2}],
 "due_date": "2026-10-15"}
```

| field | rule |
|---|---|
| `customer` or `customer_id` | one of them. `customer` is `{name, email, address?}`: matched to an existing customer by email, created when absent. `customer_id` comes from `customers` |
| `line_items` | each `{name, unit_price_usd, quantity?, sales_tax_rate?}`; `quantity` defaults to 1, the tax rate is a percent. For a single line, `amount_usd` + `description` instead |
| `due_date` | required, `YYYY-MM-DD` |
| `invoice_date` | defaults to today |
| `invoice_number` | Mercury generates one when omitted |
| `payer_memo`, `po_number` | optional text on the invoice |
| `send_email` | `false` creates the invoice without emailing it |
| `ach_debit_enabled` | default on |
| `credit_card_enabled` | default off; card payments carry fees |
| `use_real_account_number` | default off: the payer sees a virtual account number |
| `account_id` | the account to be paid into. When the policy names an account, only that one; otherwise the login's only account, or the one you name |

Mercury computes the total. Read the answer for the invoice id, then follow it
with `{"operation": "invoice_status", "invoice_id": "…"}`.

**`create_invoice`** renders an invoice document with the account's real ACH
coordinates. It sends nothing and stores nothing: deliver it yourself.

```json
{"operation": "create_invoice", "amount_usd": 500.00, "description": "Consulting, August",
 "bill_to_name": "Client Co", "bill_to_email": "ap@client.example", "due_date": "2026-10-15"}
```

**`cancel_invoice`** takes `{"operation": "cancel_invoice", "invoice_id": "…"}`.
Only an unpaid invoice can be cancelled, and it cannot be undone.

## What the policy caps

| field | absent means | set means |
|---|---|---|
| `max_payment_usd` + `max_spend_usd_month` | **no payments at all** — both are needed | the largest single payment, and what you paid in a rolling 30 days, counted from Mercury's own ledger, plus every payment waiting for approval on the account |
| `allowed_recipients` | any payee saved in Mercury | only these recipient ids; a list here also makes `add_recipient` impossible |
| `allow_new_recipients` | **off**: only payees already saved | `add_recipient` and inline payees allowed |
| `payment_methods` | ACH only | only the rails named; a wire is never on unless named |
| `account_id` | reads may use any account; payments only on a login with a single account | every operation uses this account only. The owner enters the account number from the Mercury dashboard |
| `allow_invoicing` | **off**: read invoices and render a document only | `send_invoice` and `cancel_invoice` allowed |
| `allowed_operations` | every operation, subject to the rest | only these, reads included; `status` always answers |
| `count_all_outgoing` | **off**: the budget counts only your payments | the budget counts every payment leaving the account, the people's included |
| `sandbox` | **off**: the production bank | the token is a Mercury sandbox one; every call goes to Mercury's sandbox API and no real money moves |
| `rules` | every allowed write runs | per write: `allow`, `ask` (waits for the owner) or `refuse`, the first matching rule deciding; never wider than the fields above |

With several accounts and none in the policy, payments are refused. Call
`accounts` and tell the owner what you see — each account's name and
`account_number_masked` — and ask them to enter the full number of the one to
use on the connect page. The full number is in their Mercury dashboard; you
never see it.

`status` reports `sandbox`. When it is `true`, say so with every result you
report: those payments are simulated. The switch is the owner's, set on the
connect page; do not propose the sandbox unless the owner asks how to try the
connector without real money.

Size the request inside the caps `status` reports rather than discovering them
by refusal: a refused payment still costs its fee, because your call ran.

If there is no policy, or it does not reach what the task needs, ask for the
narrowest one that does, in the page's own words:

> I can't pay yet — the token works but there is no policy. For this task I
> need "Most per payment" 500 and "Budget per 30 days" 500, payees left to the
> ones already saved, ACH only. Set it at app.outlayer.ai/connect/mercury.

## Costs

| operation | fee | plus compute |
|---|---|---|
| `status` | free | ~$0.001 |
| every read | $0.001 | ~$0.001 |
| `add_recipient`, `pay_invoice`, `send_invoice`, `cancel_invoice` | $0.01 — also when it waits for the owner | ~$0.001 |
| `task_status`, `tasks`, `task_cancel`, `task_delete`, `tasks_unlock`; `confirm` (the platform runs it on the owner's yes, on your key) | free | ~$0.001 |

A run that started is charged whether the bank or the policy then refused; only
a platform refusal before the guest runs costs nothing. The connector's own
technical caps, there against a runaway loop and far above ordinary use: 50
`pay_invoice`, 50 `add_recipient` and 20 `send_invoice` in a day, answered as
`operation_limit_reached` with `retry_after_seconds`, and 100 `confirm` runs a
day — a task approved past that ends `failed` with `operation_limit_reached`.

## When it refuses

`{"success": false, "error": "<sentence>"}`. The sentence names the layer.

| the sentence says | do |
|---|---|
| `no MERCURY_POLICY stored`, `names no spending budget`, `not in the policy's` | stop; the owner changes the policy at the connect page — quote the sentence |
| `the owner's rule N (…) refuses` | stop; that write is the owner's no — quote the sentence |
| `policy field rules: rule N …` | the owner's policy cannot be read, so everything but `status` refuses; the owner fixes rule N on the connect page |
| `exceeds the per-payment limit`, `over the … monthly budget` | stop; smaller, or ask the owner — the numbers are in the sentence |
| `is HTTPS-only` | call the same operation over HTTPS |
| `ipNotWhitelisted` and an address | the owner adds that address to the token's allowlist in Mercury, or uses a *with Approval* token |
| `tokenNotInScope` | the token's scope does not cover this; a scope cannot be edited — the owner creates a new token and replaces it on the connect page |
| `did not recognise the token` (401) | the token was revoked or expired, or the policy's `sandbox` switch does not match where the token was created; the owner fixes it on the connect page |
| `invalidApproval` | nothing was sent: Mercury wants an approver and has none who can approve. The payment is ready; tell the owner the one step left in Mercury — a second user (the token's creator cannot approve) and an approval rule naming that user for this amount (Move money → Approval rules). Then send the same payment again. Never offer a token without approval as the way round |
| `operation_limit_reached` | wait `retry_after_seconds`; look for a loop |
| Mercury's own text | act on it; the platform did its part |

## Do not

- Do not retry a payment whose answer you did not read: a `transaction_id` or
  a `request_id` means the money is already moving or already queued.
- Do not use a wire unless the owner allowed that method by name.
- Do not put a third party's bank details into an on-chain call — those
  operations refuse there by design; call them over HTTPS.
- Do not expect to approve your own payment: that is a human in Mercury's app.
- Do not treat Mercury's approval as an obstacle, or suggest removing it or
  switching to a token without it. It is the owner's second layer of control.
- Do not let the token go idle for 45 days: `status` now and then keeps it.
