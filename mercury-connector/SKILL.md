---
name: mercury-connector
description: Operate the wallet owner's Mercury business bank account through the `mercury` connector — pay a recipient, issue and cancel invoices, read accounts, recipients, transactions and payment status — under the owner's spending policy. Use when an agent with an OutLayer wallet must move USD out of, or invoice into, a Mercury account.
---

# Mercury connector

You act on the owner's real bank account. Two layers gate every payment and
neither can waive the other: the owner's `MERCURY_POLICY` (enforced in the
enclave, before anything reaches the bank) and Mercury's own approval rules. A
refusal tells you which layer refused — read it rather than retrying.

## Call shape

```
POST https://api.outlayer.ai/call/connectors.outlayer.near/mercury
X-Payment-Key: <a payment key the custody wallet owns>
X-Wallet-Id: <the wallet id>
X-Use-Owner-Secret: 1
Content-Type: application/json

{"input": {"operation": "<op>", ...}}
```

Answers are `{"success": bool, "output": {...}, "error": "..."}`.

## Start here

`{"operation": "status"}` — says whether the token works, whether a policy is
stored, how much of the 30-day budget is already used, and which account is
pinned. Without a policy the connector is read-only; ask the owner to store
one. Check the remaining budget before planning a payment.

## Reading

| do | call |
|---|---|
| accounts and balances | `{"operation": "accounts"}` (account numbers masked) |
| saved payees | `{"operation": "recipients"}` |
| recent ledger | `{"operation": "transactions", "days": 30, "limit": 50}` (`days` ≤ 90, `limit` ≤ 200) |
| one payment | `{"operation": "payment_status", "transaction_id": "…"}` or `"request_id"`, or neither for recent approval requests |
| AR customers / invoices | `{"operation": "customers"}`, `{"operation": "invoices"}`, `{"operation": "invoice_status", "invoice_id": "…"}` |

## Paying

```json
{"operation": "pay_invoice", "recipient_id": "<from `recipients`>", "amount_usd": 120.50,
 "payment_method": "ach", "note": "invoice 2026-09"}
```

Two outcomes, both normal:

* **sent** — the answer carries a `transaction_id`; poll it with
  `payment_status`.
* **queued for approval** — Mercury's rules cover this payment, so it became
  an approval request: the answer says so and carries a `request_id`. A human
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

`max_payment_usd` per payment, `max_spend_usd_month` over a rolling 30 days
counted from Mercury's own ledger (every outgoing transaction by default, not
only yours), `allowed_recipients`, `payment_methods` (ACH only unless the
owner named more — a wire is expensive and irreversible), `allowed_operations`,
`account_id`, `allow_new_recipients`, `allow_invoicing`. Read the caps from
`status` and size payments inside them.

## Do not

- Do not retry a payment whose answer you did not read: a `transaction_id` or
  a `request_id` means the money is already moving or already queued.
- Do not use a wire unless the owner allowed that method by name.
- Do not put a third party's bank details into an on-chain call — those
  operations refuse there by design; call them over HTTPS.
- Do not expect to approve your own payment: that is a human in Mercury's app.
