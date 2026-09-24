---
name: mercury-connector
description: Operate the wallet owner's Mercury business bank account through the `mercury` connector — pay a recipient, issue and cancel invoices, read accounts, recipients, transactions and payment status — under the owner's spending policy, and send the owner to connect the account at app.outlayer.ai/connect/mercury. Use when an agent with an OutLayer wallet must move USD out of, or invoice into, a Mercury account, or when the owner talks about paying a contractor, invoicing a client or what the company spent.
---

# Mercury connector

You act on the owner's real bank account. Two layers gate every payment and
neither can waive the other: the owner's `MERCURY_POLICY` (enforced in the
enclave, before anything reaches the bank) and Mercury's own approval rules. A
refusal tells you which layer refused — read it rather than retrying.

When to offer this, and how to say it so the owner can refuse, is in
[`outlayer-connectors/references/offering.md`](https://skills.outlayer.ai/outlayer-connectors/references/offering.md).

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

Answers are `{"success": bool, "output": {...}, "error": "..."}`.

## Where the credential comes from

The owner connects once, at **<https://app.outlayer.ai/connect/mercury>**. You
cannot do it for them — it needs a token from their Mercury settings and their
wallet signature — so your job is to send them there **and tell them what
happens before they paste anything**. A wrong token scope means a new token,
not a setting, so the scope is the thing to say first.

### What they need first

* The NEAR wallet that will own the credential, connected on the dashboard,
  with a little NEAR in it: the last step is a transaction and pays for storage.
* **The right network** — the page writes to whichever the dashboard is
  switched to. Ask them to connect on the network your payment key belongs to.
* **A Mercury API token**, created at Mercury → Settings → API Tokens →
  *Custom*. Its scope cannot be edited afterwards:
  * *Read + Send Money with Approval* — every payment you make waits for a
    person in Mercury's app. The usual choice, and the safe first one.
  * *Read + Send Money* — payments go out directly, inside the policy. Mercury
    then requires an IP allowlist on the token, and the addresses to allow are
    OutLayer's enclave nodes, not the owner's: the connector names the address
    to add the first time a payment is refused with `ipNotWhitelisted`.
  * *Read* only — accounts, payees, the ledger and invoices, nothing else.

### What they will see, in order

1. **A page that explains the scopes, then one field: the token.** They paste
   it and press *Continue with this token*. The token stays in that browser tab
   — nothing is sent to us — and the page asks Mercury, from their browser,
   which accounts it reaches.
2. **A deliberate stop. Nothing is stored yet.** The page says so in those
   words, lists the accounts the token reaches, and shows the policy form:
   most per payment, budget per 30 days, payees, rails, account, the two
   switches (new payees, invoicing), and which operations at all. An empty
   policy is **read-only**; both amounts are needed before any payment runs.
   With one account the page pins it; with several, payments are refused until
   they name one.
3. **One button, *Finish: store the encrypted credential on the contract*.**
   Their wallet opens only when they press it. The token and the policy are
   sealed in their browser to a key that exists only inside the keystore
   enclave, and stored under their account with a rule naming them alone.
4. **Mercury connected**, and a link to grant an agent. If their wallet is
   closed or refuses, they land back on step 2: one more click, no new paste.

### What it means, in their words

* A token alone moves nothing. Until the policy names a budget, you can only
  read.
* The token is encrypted before it leaves their browser. We cannot read it
  afterwards, and neither can you: the connector opens it inside the enclave.
* Nobody can use it until they grant an agent, and removing the grant — or the
  row, or the token in Mercury — ends it at once.
* Payments you queue are approved in Mercury's app by a **different Mercury
  user** from the one who created the token, and only if an **approval rule**
  names that approver for the amount. A request no rule covers exists in the
  API and appears to nobody. Say this before the first payment, not after.
* **Mercury deletes a token unused for 45 days.** Your `status` call is a use.
  If you hold this connection, call `status` at least every few weeks.

### Then ask to be granted

The row is stored under the profile **`mercury`**, readable by the owner alone.
To let you act, they open the secrets page —
`https://app.outlayer.ai/secrets?project=connectors.outlayer.near/mercury&profile=mercury&access=1`
(the testnet pair on testnet) — and add your **payer account** under Access,
optionally with an expiry. Your payer account is the 64-character account of
the wallet that owns your payment key: `GET /wallet/v1/address?chain=near`,
the `address`. Then you name
`{"account_id": "<their account>", "profile": "mercury"}` in `secrets_ref`.

A grant made seconds ago can still be refused: the condition is read from the
chain. Wait a minute, repeat the free `status`, then conclude.

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
 "payment_method": "ach", "note": "invoice 2026-09"}
```

Two outcomes, both normal:

* **sent** — the answer carries a `transaction_id`; poll it with
  `payment_status`.
* **queued for approval** — Mercury's rules cover this payment, or the token's
  scope only queues: the answer says so and carries a `request_id`. A human
  approves it in Mercury's app; you poll `payment_status` with that id. You
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

## Invoicing

`send_invoice` creates a REAL Mercury invoice and Mercury emails it to the
customer; `cancel_invoice` cancels an unpaid one and cannot be undone. Both
need `allow_invoicing` in the policy. `create_invoice` only renders a document
with the account's ACH coordinates — it sends nothing and is the safe choice
when the customer pays by bank transfer.

## What the policy caps

| field | absent means | set means |
|---|---|---|
| `max_payment_usd` + `max_spend_usd_month` | **no payments at all** — both are needed | the largest single payment, and everything paid or queued in a rolling 30 days, counted from Mercury's own ledger (every outgoing transaction on the account by default, not only yours) |
| `allowed_recipients` | any payee saved in Mercury | only these recipient ids; a list here also makes `add_recipient` impossible |
| `allow_new_recipients` | **off**: only payees already saved | `add_recipient` and inline payees allowed |
| `payment_methods` | ACH only | only the rails named; a wire is never on unless named |
| `account_id` | the login's only account; with several, no payments | everything runs against this account |
| `allow_invoicing` | **off**: read invoices and render a document only | `send_invoice` and `cancel_invoice` allowed |
| `allowed_operations` | every operation, subject to the rest | only these, reads included; `status` always answers |

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
| `add_recipient`, `pay_invoice`, `send_invoice`, `cancel_invoice` | $0.01 | ~$0.001 |

A run that started is charged whether the bank or the policy then refused; only
a platform refusal before the guest runs costs nothing. The connector's own
technical caps, there against a runaway loop and far above ordinary use: 50
`pay_invoice`, 50 `add_recipient` and 20 `send_invoice` in a day, answered as
`operation_limit_reached` with `retry_after_seconds`.

## When it refuses

`{"success": false, "error": "<sentence>"}`. The sentence names the layer.

| the sentence says | do |
|---|---|
| `no MERCURY_POLICY stored`, `names no spending budget`, `not in the policy's` | stop; the owner changes the policy at the connect page — quote the sentence |
| `exceeds the per-payment limit`, `over the … monthly budget` | stop; smaller, or ask the owner — the numbers are in the sentence |
| `is HTTPS-only` | call the same operation over HTTPS |
| `ipNotWhitelisted` and an address | the owner adds that address to the token's allowlist in Mercury, or uses a *with Approval* token |
| `tokenNotInScope` | the token's scope does not cover this; a scope cannot be edited — the owner creates a new token and replaces it on the connect page |
| `did not recognise the token` (401) | the token was revoked or expired; the owner replaces it on the connect page |
| `invalidApproval` | Mercury's rule names the token's own user as approver; the owner fixes the rule |
| `operation_limit_reached` | wait `retry_after_seconds`; look for a loop |
| Mercury's own text | act on it; the platform did its part |

## Do not

- Do not retry a payment whose answer you did not read: a `transaction_id` or
  a `request_id` means the money is already moving or already queued.
- Do not use a wire unless the owner allowed that method by name.
- Do not put a third party's bank details into an on-chain call — those
  operations refuse there by design; call them over HTTPS.
- Do not expect to approve your own payment: that is a human in Mercury's app.
- Do not let the token go idle for 45 days: `status` now and then keeps it.
