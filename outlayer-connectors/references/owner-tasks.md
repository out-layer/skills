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

**`awaiting_owner` is a success, and nothing was done yet.** You did your
part; nothing was sent, written, paid or changed. `expires_at` is Unix seconds.
**Do not call the operation again while the task is `open`** — every call is
another task in the owner's inbox and another fee, and the owner would be asked
the same thing twice.

## Which connectors ask first, and for what

| connector | operations that can wait for the owner |
|---|---|
| `gmail` | `send` |
| `github` | the thirteen writes: `branch_create`, `file_put`, `commit`, `issue_create`, `issue_comment`, `issue_update`, `pr_create`, `pr_review`, `pr_merge`, `gist_create`, `gist_update`, `repo_star`, `repo_unstar` |

Owner confirmation is available in `gmail` and `github`. Every other connector
acts when you call it.

**The owner chooses, in their policy's `confirm` member**: a list of operation
names. `status` reports it under `policy.confirm`, exactly as the policy holds
it:

| `policy.confirm` | a listed operation |
|---|---|
| `null` or `[]` | nothing waits: every operation acts when you call it |
| `["send"]`, `["pr_merge", "pr_review"]`, … | the operations named answer `awaiting_owner`; the rest act at once |

**Call `status` before a write**, so that you know whether it will act or wait,
and say which in the message you send the person who asked: "I'll send it now"
and "I'll prepare it for your confirmation" are different promises. You do not
choose: a policy is the owner's, and a write the policy lists always waits.

## Whose key you call with, and who carries the task out

You call with a payment key of **your own** account, over HTTPS: a task can
only be opened by a call with a payment key, because that key is what pays
for carrying it out. When the owner approves, **the platform runs the
operation the task names as you** — the same connector, the same key, the
same wallet, within the compute limit of the call that prepared the task.
The owner signs one message and sends no transaction; nobody else can start
that run. So:

* keep the key alive and funded until the task is answered or expires: a key
  deleted, spent, out of scope or unable to cover the run ends the task
  `failed` with `preparer_key_unavailable`, and the owner's yes is lost;
* the run's compute is yours to pay, at most what your preparing call was
  allowed;
* a key of the owner's account does not answer tasks either: nothing
  answers a task by calling. If the owner offers you one, tell them it gains
  nothing here and ask for a key of your account, or buy one.

Never call the operation a task is answered through (`confirm`, or the one
the task names) yourself: without the owner's signature in the input it is
refused `task_answer_invalid`, and the call is still paid for.

## What you do next

1. **Tell the owner, and give them `link`.** Say what you prepared in one
   sentence. They read it in their inbox and approve it with one signature of
   their wallet, with a note for you if they want; you cannot do that step for
   them, and you never ask them for a key or a signature yourself.

   > I prepared the email to bob@example.com and it is waiting for your
   > confirmation: https://app.outlayer.ai/inbox/0b9c…-0
   > It waits until 14:00 UTC.

2. **Keep `task_id`.** It is how you learn what happened.
3. **Ask for the outcome when you next have a reason to** — when the owner
   says they answered, or before you report the work as done. Nothing notifies
   you; you ask. `task_status` is free (you pay compute only), but it is still
   a call: do not poll it in a tight loop.

```json
{"operation": "task_status", "task_id": "0b9c1a52-7c1e-4a53-9c58-2f0c8f6f3b11-0"}
```

Call it exactly as you called the operation that made the task: the same
connector, the same `secrets_ref`, the same key.

## Reading `task_status`

```json
{"task_id": "0b9c1a52-7c1e-4a53-9c58-2f0c8f6f3b11-0", "kind": "confirm",
 "state": "rejected", "created_at": 1790000000, "expires_at": 1790003600,
 "reason": "Too long. Three sentences, and no attachment."}
```

`state` is always there; `run` on `approved`, `answering`, `done` and
`failed`; `result` on `done`; `failure_reason` on `failed`; `reason` on
`rejected` when the owner wrote one. `created_at` and `expires_at` are Unix
seconds.

`state` is one of nine values. Branch on it; a value you do not know is not a
success.

| `state` | what happened | what you do |
|---|---|---|
| `open` | the owner has not answered | wait; remind them once if it matters, with the same `link`. Do not prepare it again |
| `approved` | the owner approved; the platform queued a run of yours, named in `run`, which has not acted yet | ask again shortly |
| `answering` | that run took the answer and is carrying the action out now | ask again shortly |
| `done` | the action was carried out. `result` is what the connector reports — for a send, the message id — with the owner's `note` when they wrote one | report it to the owner as done |
| `failed` | the run could not be started, did not start, refused the task, or ended without reporting the action; `failure_reason` says which. The action may have happened in part | read `failure_reason` (below); tell the owner, with `run`; do not assume either way. If the work is still wanted, prepare it again — a new task |
| `rejected` | the owner said no. `reason` is what they wrote, when they wrote something | act on the reason: rewrite the action as they asked and call the operation again — a new task, with a new `link` to give them. Without a reason, ask what they want changed. Never prepare the same thing again unchanged |
| `cancelled` | you withdrew it | — |
| `expired` | it waited past `expires_at` | ask the owner whether it is still wanted, then prepare it again |
| `void` | the owner changed their policy after the task was made, or the integration was updated since and the owner answered with the new build | call `status`, read the policy, prepare again |

A task never returns to `open`. An outcome is kept 30 days; after that
`task_status` answers `task_not_found`.

| `failure_reason` | what happened | what you do |
|---|---|---|
| `preparer_key_unavailable` | your payment key could not pay for the run: deleted, spent, expiring, out of scope, over its own ceiling, or in a vault the platform does not serve | fix the key, then prepare again |
| `operation_limit_reached` | the answering operation's limit for your key is reached | prepare again later |
| `operation_priced`, `operation_unknown`, `wallet_unresolved`, `queue_unavailable`, `run_not_started` | the platform could not start or run the run: the connector's price list, your wallet, or the queue | report it; `queue_unavailable` and `run_not_started` are worth one more try |
| `run_refused:<reason>` | your run refused the task: `hash-mismatch`, `expired`, `void`, `unreported`, … — the host's reason | as the reason says: `void` means the owner's policy changed, read it and prepare again; `unreported` means the action may have happened |

## What the owner confirms is what happens

The connector seals the exact action when it prepares the task, and shows the
owner every value it will use. The run of `confirm` the platform starts on
their approval carries out that sealed action and nothing else: it takes no
amount, recipient, text or flag from its input, and nothing you send
afterwards changes it. To change a prepared action, `task_cancel` it and
prepare the new one.

At `confirm` the action is judged again against the owner's policy and limits
as they are at that moment, and counted then — in your own daily count, as a
confirmed action beside your direct ones. A refusal at that point closes the
task as `failed`; the owner sees why.

You pay the preparing operation's price when the task is made, and it is not
returned if the owner says no or the task expires. `confirm` and the task
operations are free; the compute of the run that carries the task out is
yours, as any call's.

Which values each connector shows, and what binds the owner's yes to the state
of the world they saw (GitHub's pull request head, for instance), are in that
connector's skill.

## The operations every such connector has

| `operation` | input | what it does |
|---|---|---|
| `task_status` | `task_id` | where one of your tasks stands |
| `tasks` | — | all your tasks for this owner: `{"tasks": [ … ]}`, each shaped as `task_status` answers, empty when there are none |
| `task_cancel` | `task_id` | withdraw a task that is still `open`: `{"task_id", "state": "cancelled"}` |
| `task_delete` | `task_id` | delete one of your tasks, in any state: `{"task_id", "deleted": true}` |

They see **your** tasks only: the ones made by your account, in this connector,
for this owner — the later turns of a conversation you started included (below).
Another agent of the same owner is not shown yours, and you are not shown
theirs.

`tasks_unlock` is the owner's: called by you it is refused `not_the_owner`.
`confirm`, and any operation a task names to answer it, run only when the
platform starts them on the owner's approval: called by you they are refused
`task_answer_invalid` (no approval in the input), and the call is still paid
for.

## Conversations: a task that follows a task

A task may ask the owner for text instead of a yes, and the run that takes
their answer may open the next task at once. That next task is the next
**turn** of the same conversation:

* it carries the same `thread` — the `task_id` of the conversation's first
  task;
* it belongs to **the agent that started the conversation**: it is yours in
  `tasks` and in `task_status`, it shows in the owner's inbox as from you, and
  it counts toward your share of the owner's inbox and under a mute of you;
* its id reaches you in the `result` of the turn it followed, where the
  project puts it.

Follow a conversation turn by turn: read a turn's outcome, then call
`task_status` on the next turn's id. The same rules hold on every turn: start
no second conversation for the same thing while a turn is `open`, and act on
a `rejected` turn's `reason`.

### Worked example: the guessing game

`connector-probe` is the platform's test connector, on testnet only
(`connectors.outlayer.testnet/connector-probe`). Its guessing game is a whole
conversation: you pick nothing, the owner guesses in the inbox, and neither of
you reads the number.

1. **You start it.** The owner's row must admit your account **by name** (a
   whitelist that lists you); a row open to everyone is refused
   `not_granted_by_name`. `max` is a whole number from 2 to 1000, 100 when
   absent. The price is $0.01.

   ```bash
   curl -s https://testnet-api.outlayer.ai/call/connectors.outlayer.testnet/connector-probe \
     -H "X-Payment-Key: $PAYMENT_KEY" -H 'Content-Type: application/json' \
     -d '{"input": {"operation": "guess_start", "max": 100},
          "secrets_ref": {"account_id": "<owner>.testnet", "profile": "<profile>"}}'
   ```

   The output is `ok`, `detail` and the task as above: `status:
   "awaiting_owner"`, `task_id`, `task_hash`, `thread`, `expires_at`, `link`.
   Give the owner the link: "I picked a number from 1 to 100 — guess it in
   your inbox: <link>".

2. **The owner guesses in the inbox.** Their page seals the text they type
   and signs the approval; the platform runs `guess` as you, on your key. It
   judges the guess, reports the turn to you, and — unless the guess was
   right — opens the next task of the same thread, which shows the guess,
   the answer and the attempts so far.

3. **You read each turn** with `task_status` on its `task_id`. A turn that is
   `done` has the `result`:

   ```json
   {"attempt": 2, "guess": 40, "verdict": "higher", "max": 100,
    "detail": "attempt 2: 40 is wrong, the number is higher",
    "next_task_id": "5e1f…-0"}
   ```

   | `verdict` | means | the game |
   |---|---|---|
   | `higher`, `lower` | the number is above, below the guess | goes on: `next_task_id` is the next turn, yours to follow |
   | `not_a_number` | the owner typed something that is not a whole number from 1 to `max` | goes on, the same way |
   | `right` | guessed; `detail` says in how many attempts | over: no `next_task_id` |

   `next_error` in place of `next_task_id` means the guess was judged and the
   next turn could not be opened (its refusal, e.g. `inbox_full: …`): the
   game stops there.

Every turn after the first was opened by the run the platform started for
the owner's approval — a run of yours — so it is yours like the first: it is
in your `tasks`, and `task_status` on `next_task_id` answers it.

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
