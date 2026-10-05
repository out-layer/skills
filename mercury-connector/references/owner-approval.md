# Writes the owner approves first

> Part of the `mercury-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/mercury-connector/`.

The task model every connector shares — each state, each `failure_reason`,
what `task_delete` may delete, the inbox limits — is in
<https://skills.outlayer.ai/outlayer-connectors/references/owner-tasks.md>.
This file holds only what is Mercury's.

## How the owner's rules decide

`status` reports the owner's `policy.rules`. For a write the rest of the
policy allows, they decide whether it runs, waits for the owner, or is
refused: the first rule that matches decides, `then` being `allow`, `ask` or
`refuse`, and with none matching the write runs. A rule never lets through
what the other fields refuse. A rule's `when` names `op` — `pay_invoice`,
`add_recipient`, `send_invoice` or `cancel_invoice` — and any of these
conditions, every one present having to hold:

| condition | matches | allowed with |
|---|---|---|
| `min_usd`, `max_usd` | the amount in dollars, inclusive: a payment's `amount_usd`; an invoice's lines' total before tax | `pay_invoice`, `send_invoice` only |
| `methods` | the payment's rail: `ach`, `check`, `domesticWire`, `internationalWire` | `pay_invoice` only |
| `payee` | `saved`: you named a `recipient_id`; `new`: you named the payee inline | `pay_invoice` only |

A condition on any other operation — an amount on `cancel_invoice`, a rail on
`send_invoice` — a `min_usd` above `max_usd`, an empty or unknown `methods`,
or more than 50 rules makes the whole policy unreadable: `status` reports
`policy_mode: broken`, and every operation but `status` refuses with
`policy field rules: …` until the owner fixes it on the connect page.

## When a rule says `ask`

The write answers
`{"status": "awaiting_owner", "task_id": …, "task_hash": …, "link": …}` and
nothing happens at the bank: no payment, no payee saved, no invoice, no
cancellation. That is a success. The owner sees every value the bank will be
sent — the amount, the rail, the account, the payee, the memo, the wire
purpose, the budget before and after, the idempotency key — and the rule
that asked. Give them `link` in a sentence that says what waits:

> I prepared the payment of $120.50 to Acme Hosting by ACH; nothing is paid
> until you approve it in your OutLayer inbox:
> https://app.outlayer.ai/inbox/…

Do not send the same write again while the task is open, and learn the
outcome with `task_status`.

| refusal when you make the write | why | do |
|---|---|---|
| `task_no_payment_key:` | the call was made on chain, and a task needs the payment key that pays for the run the owner's yes starts | make the same call over HTTPS with your payment key |
| `display_invalid:` | an invoice to be confirmed holds at most 20 line items, so that it is shown whole | split the invoice, or ask the owner whether it should wait for them |

When a rule says `refuse`, the answer is `policy_denied: the owner's rule N
(…) refuses …`. Stop, and quote it to the owner.

## What the outcome means for a Mercury write

| `state` / `failure_reason` | for this write | do |
|---|---|---|
| `done` | made once, exactly as shown. `result` is what the write answers directly: a payment's `transaction_id` (sent) or `request_id` (queued by Mercury's own approval rules), an invoice's `invoice_id` | report it; follow a payment with `payment_status` |
| `failed`, `run_failed` | nothing was made after the owner's yes. `result.error` is the connector's or the bank's refusal — the 30-day budget used up meanwhile, the operation or the account no longer the policy's, Mercury's own words — ending "The task is closed: to make this payment, prepare it again" (`payee`, `invoice` or `cancellation` in place of `payment`) | quote `result.error` to the owner; prepare again only if still wanted |
| `failed`, `run_unreported`, `run_trapped` or `run_unfinished` | the run took the owner's yes and did not end cleanly: a request reached the bank and its answer was lost, a step failed after an earlier one was made, the run reported and then failed (`run_trapped`, `result` holds what it reported), or no word of its end came. **The payment, payee, invoice or cancellation MAY have been made** | check Mercury before anything else: `transactions` or `payment_status` for a payment, `recipients`, `invoices` or `invoice_status` for the rest; prepare it again only if nothing is there |
| `failed`, `operation_limit_reached` | `confirm` met its ceiling of 100 runs a day; nothing was made | prepare it again later, if still wanted |

A payment made on the owner's yes keeps the idempotency key of the call that
prepared it, and Mercury's own approval rules still apply to it: one they
cover is queued in Mercury after the owner's yes, as a direct payment is.

A task that waits counts nothing toward the 30-day budget. Two tasks that
each fit may not both fit, and the second fails `run_failed` when its turn
comes.

## The task operations

| operation | what it does |
|---|---|
| `task_status` | `{"task_id": …}` → where the task stands |
| `tasks` | the tasks you made for this owner |
| `task_cancel` | `{"task_id": …}` — withdraw one still `open`, when the owner no longer needs it |
| `task_delete` | `{"task_id": …}` — delete one nothing was carried out on: `open`, `cancelled`, `rejected`, `expired`, `void`, or `failed` with a reason that says nothing was done. Any other is refused `task_closed:` — it is the owner's record too |
| `tasks_unlock` | the owner's own call, from their page: opens waiting tasks on a device that was not signed in when they were made. Called by you it is refused `not_the_owner:` |
| `confirm` | the platform's: it runs it on your key when the owner says yes. Called by you it is refused `task_answer_invalid:` |

All of them are free; the write was paid when you made it, and the compute
of the run the owner's yes starts is yours.
