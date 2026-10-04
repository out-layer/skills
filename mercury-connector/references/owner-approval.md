# Writes the owner approves first

> Part of the `mercury-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/mercury-connector/`.

## How the owner's rules decide

`status` reports the owner's `policy.rules`. For a write the rest of the
policy allows, they decide whether it runs, waits for the owner, or is
refused — the first rule that matches decides, and with none matching the
write runs. A rule never lets through what the other fields refuse. A rule
matches on `op` (`pay_invoice`, `add_recipient`, `send_invoice`,
`cancel_invoice`) and on what the call carries:

| condition | matches |
|---|---|
| `min_usd`, `max_usd` | the amount, inclusive; for an invoice, its lines' total before tax |
| `methods` | the payment's rail: `ach`, `check`, `domesticWire`, `internationalWire` |
| `payee` | `saved`: you named a `recipient_id`; `new`: you named the payee inline |

When a rule says `ask`, the write answers
`{"status": "awaiting_owner", "task_id": …, "task_hash": …, "link": …}` and
nothing happens at the bank: no payment, no payee saved, no invoice, no
cancellation. That is a success. The owner sees every value the bank will be
sent and the rule that asked. Give them `link`, do not send the same write
again while the task is open, and learn the outcome with `task_status`.

A write that waits for the owner is made over HTTPS: a call on chain carries
no payment key to pay for the run their yes starts, and is refused
`no_payment_key`.

When a rule says `refuse`, the answer is `policy_denied: the owner's rule N
(…) refuses …`. Stop, and quote it to the owner.

## What the outcome means

| `task_status` state | what happened | do |
|---|---|---|
| `open` | waiting for the owner | wait; the task lives up to 24 hours |
| `approved`, `answering` | the owner said yes; the run is making it | poll again |
| `done` | made, once, exactly as shown. `result` is what the write answers: for a payment `transaction_id` (sent) or `request_id` (queued by Mercury's own approval rules — poll `payment_status` with it) | report it |
| `rejected` | the owner said no; `reason` is theirs | stop; do not prepare it again unless they ask |
| `failed` | `failure_reason: run_failed` — nothing was made after the owner's yes, and `result.error` says why: the budget used up meanwhile, the account no longer the policy's, the bank's refusal. `run_unreported` — the run ended without saying what it did: the payment may have been made | `run_failed`: quote `result.error`, prepare again only if they still want it. `run_unreported`: check `transactions` / `payment_status` before anything else |
| `void` | the owner changed the policy after the task was made | prepare it again under the policy as it is now, if still wanted |
| `expired`, `cancelled` | it waited too long, or you withdrew it | prepare it again if still wanted |

A task that waits counts nothing toward the 30-day budget. Two tasks that
each fit may not both fit, and the second one fails when its turn comes.

## The task operations

| operation | what it does |
|---|---|
| `task_status` | `{"task_id": …}` → the state above |
| `tasks` | the tasks you made for this owner |
| `task_cancel` | `{"task_id": …}` — withdraw one still open, when the owner no longer needs it |
| `task_delete` | `{"task_id": …}` — remove one, in any state |
| `tasks_unlock` | the owner's own call, from their page: opens waiting tasks on a device that was not signed in when they were made. Not yours to call |
| `confirm` | the platform's: it runs it on your key when the owner says yes. Never call it yourself |

All of them are free; the write was paid when you made it.
