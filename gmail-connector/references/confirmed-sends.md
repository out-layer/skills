# Sending when the owner confirms every message

> Part of the `gmail-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/gmail-connector/`.

If `status` reports `confirm: ["send"]` in the policy, `send` sends nothing. It
checks the message against the policy — recipients, attachments — leaves it in
the owner's inbox and answers

```json
{"success": true,
 "output": {"status": "awaiting_owner", "task_id": "…", "task_hash": "…",
            "thread": "…", "expires_at": 1790003600,
            "link": "https://app.outlayer.ai/inbox/…"}}
```

That is a success: the message is prepared and waits, and nothing was sent.
Give the owner `link`, keep `task_id`, and **do not call `send` again while
the task is open** — a second call is a second message in their inbox and a
second fee.

> I wrote the email to boss@example.com, subject "Weekly numbers". It is
> waiting for your confirmation and nothing is sent until you confirm:
> https://app.outlayer.ai/inbox/…

The owner reads who it goes to, the subject and the body, opens every
attachment, and approves it with one signature of their wallet; the platform
then runs `confirm` as you — on your payment key, within the compute limit of
the `send` that prepared it — and that run sends it. Exactly the message you
prepared is sent — nothing you call afterwards changes it; to change it,
`task_cancel` it and `send` the new one. It is judged against the policy as
it is at that moment, and counted in your daily cap then, as a confirmed
send. Keep the key alive and funded until then: a key that cannot pay for the
run ends the task `failed` with `preparer_key_unavailable`.

## Learning what happened

```json
{"operation": "task_status", "task_id": "…"}
```

`done` carries in `result` the fields a direct send answers: `message_id`,
`thread_id`, `to`, `cc`, `subject`, `attachments`, `sent_today`,
`remaining_today`, and the owner's `note` when they wrote one. The owner's
daily cap counts what you send yourself and what the owner confirms for you
apart, each against the same number: in this `result`, `sent_today` and
`remaining_today` are the confirmed count, and `status`'s `sent_today` is
never it.

What a Gmail task's ending means:

| `state` / `failure_reason` | for this message | do |
|---|---|---|
| `failed`, `run_refused:<reason>` or `run_refused:unreported` | refused before the owner's answer was taken: nothing was sent | `send` it again if it is still wanted — a new task |
| `failed`, `run_failed` | the approved message did not leave; `result.error` is the connector's sentence — the daily cap reached meanwhile, the credential, Google's refusal — ending "The task is closed: to send this message, prepare it again" | quote `result.error` to the owner |
| `failed`, `run_unreported` | Gmail's answer to the send was lost, or Google failed after the request went out: **the message MAY have left**, and there is no `result` | ask the owner to look in their Sent folder; send it again only if it is not there |
| `failed`, `operation_limit_reached` | `confirm` met its ceiling of 500 runs a day; nothing was sent | `send` it again later, if still wanted |
| `rejected` | the owner said no; `reason` is what they wrote — "shorter", "not to Bob", "attach the PDF instead" | rewrite the message as they asked and call `send` again: a new task, with a new `link`. Never send the same message again unchanged |

Every other state and `failure_reason`, what `task_delete` may delete, and what
to do in each:
https://skills.outlayer.ai/outlayer-connectors/references/owner-tasks.md

## What a message to be confirmed must fit

The owner is shown the message whole, never in part.

| limit | refusal |
|---|---|
| `body` of at most 50000 characters | `display_invalid:` |
| `subject` of at most 500 characters | `display_invalid:` |
| at most 20 recipients in `to`, and 20 in `cc` | `display_invalid:` |
| no characters that are not drawn or that reorder text (control characters, zero-width, right-to-left overrides) in the subject, the body or a file name | `display_invalid:`, naming the character |
| at most 10 attachments, 6 MB together | `task_too_large:` |
| an attachment's `filename` without a path, its `content_type` a media type | `display_invalid:` |

Line ends in `body` are kept as `\n`. For a message over these, split it, or
ask the owner whether confirmation is what they want for it — the choice is
theirs, in their policy.

## Operations that are not yours to call

`tasks_unlock` is the owner's, from their inbox: called by you it is refused
`not_the_owner:`. `confirm` runs only when the platform starts it on the
owner's approval: called by you it is refused `task_answer_invalid:`. It has
no fee, and the run's compute is still yours. Never ask the owner to give you
anything that would let you call them.
