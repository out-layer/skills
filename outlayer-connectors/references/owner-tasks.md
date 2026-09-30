# When a connector asks the owner first

> Part of the `outlayer-connectors` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/outlayer-connectors/`.

An owner can tell a connector to ask them before certain operations. When you
call such an operation the connector does not act. It checks your request
against the owner's policy, prepares the action, leaves it as a **task** in the
owner's inbox, and answers you at once:

```json
{"success": true,
 "output": {"status": "awaiting_owner",
            "task_id": "0b9c1a52-7c1e-4a53-9c58-2f0c8f6f3b11-0",
            "task_hash": "92067502…",
            "thread": "0b9c1a52-7c1e-4a53-9c58-2f0c8f6f3b11-0",
            "expires_at": 1790003600,
            "link": "https://app.outlayer.ai/inbox/0b9c1a52-7c1e-4a53-9c58-2f0c8f6f3b11-0"}}
```

**`awaiting_owner` is a success.** You did your part; nothing was sent, paid or
changed yet. Do not retry the operation — every retry is another task in the
owner's inbox and another fee.

## Whose key you call with

You call with a payment key of **your own** account. A call is made as the
account whose key pays for it, so a key of the owner's account acts as the
owner — it answers the owner's tasks, the ones you prepared among them.

If the owner offers you a payment key of their own account, tell them what it
means before you take it: with it your calls are theirs, and nothing you
prepare waits for them. Ask for a key of your account instead, or buy one.
Never call the operation a task is answered through (`confirm`, or the one
the task names): the answer is the owner's.

## What you do next

1. **Tell the owner, and give them `link`.** Say what you prepared in one
   sentence. They read it in their inbox and act with their own wallet; you
   cannot do that step for them, and you never ask them for a key or a
   signature yourself.

   > I prepared the email to bob@example.com and it is waiting for your
   > confirmation: https://app.outlayer.ai/inbox/0b9c…-0
   > It waits until 14:00 UTC.

2. **Keep `task_id`.** It is how you learn what happened.
3. **Ask for the outcome when you next have a reason to** — when the owner
   says they answered, or before you report the work as done. Nothing notifies
   you; you ask.

```json
{"operation": "task_status", "task_id": "0b9c1a52-7c1e-4a53-9c58-2f0c8f6f3b11-0"}
```

Call it exactly as you called the operation that made the task: the same
connector, the same `secrets_ref`, the same key.

## Reading `task_status`

`output.state` is one of eight values. Branch on it; a value you do not know is
not a success.

| `state` | what happened | what you do |
|---|---|---|
| `open` | the owner has not answered | wait; remind them once if it matters, with the same `link` |
| `answering` | the owner answered and the action is being carried out now, by the call in `run` | ask again shortly |
| `done` | the action was carried out. `result` is what the connector reports — for a send, the message id | report it to the owner as done |
| `failed` | the owner answered and the call in `run` ended without reporting the action. It may have happened in part | tell the owner, with `run`; do not assume either way. If the work is still wanted, prepare it again — a new task |
| `rejected` | the owner said no. `reason` is what they wrote, when they wrote something | act on the reason; do not prepare the same thing again unchanged |
| `cancelled` | you withdrew it | — |
| `expired` | it waited past `expires_at` | ask the owner whether it is still wanted, then prepare it again |
| `void` | the owner changed their policy after the task was made, or the integration was updated since and the owner answered with the new build | call `status`, read the policy, prepare again |

A task never returns to `open`. An outcome is kept 30 days; after that
`task_status` answers `task_not_found`.

## The operations every such connector has

| `operation` | input | what it does |
|---|---|---|
| `task_status` | `task_id` | where one of your tasks stands |
| `tasks` | — | all your tasks for this owner: `{"tasks": [ … ]}`, empty when there are none |
| `task_cancel` | `task_id` | withdraw a task that is still `open` |
| `task_delete` | `task_id` | delete one of your tasks, in any state |

They see **your** tasks only: the ones made by your account, in this connector,
for this owner. Another agent of the same owner is not shown yours, and you are
not shown theirs.

`confirm`, and any operation a task names to answer it, is the owner's. Called
by you it is refused `not_the_owner`, fee included.

## Limits you can meet

| the error starts with | what happened | retry? |
|---|---|---|
| `inbox_full:` | the owner has as many open tasks as an inbox holds or stores, or you left as many as one agent may | not until the owner answers some. Cancel what is no longer wanted |
| `muted:` | the owner muted you or this connector | no. Only the owner can undo it; do not ask through another channel |
| `not_granted_by_name:` | the owner's row admits you by a rule open to many accounts, not by naming yours | no. The owner grants your account by name |
| `no_owner:` | the call named no `secrets_ref`, or the row did not open | fix the call |
| `relayed:` | the call reached OutLayer through a contract, not from the account that signed it | call OutLayer directly |
| `display_invalid:` | what you asked for cannot be shown to the owner whole: too long, or it holds characters that are not drawn or that reorder text. The message names which | shorten or clean the request |
| `task_too_large:` | the prepared action is over what a task holds: more than 10 files, or more than 6 MB of them together | make it smaller |
| `task_not_found:` | no such task of yours: never made, deleted, or older than 30 days | no |
| `task_closed:`, `task_expired:` | `task_cancel` on a task that is no longer `open` | no |
| `task_run_limit:` | this call opened as many tasks, or asked about tasks as many times, as one call may | not in this call. Another call starts from nothing |
| `task_internal_error:` | the platform could not do what was asked, and will not do better on a repeat. Read `tasks`: a task you did not get an id for may be there | no. Report it |
| `task_store_unavailable:` | the platform could not reach the task store or the chain | yes, later. This is the only one worth repeating as it is |

`task_store_unavailable` is never "you have no tasks": an empty `tasks` list is
the only answer that means none.
