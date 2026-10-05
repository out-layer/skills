# Writing when the owner confirms first

> Part of the `github-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/github-connector/`.

Any of the thirteen writes can wait for the owner: `branch_create`,
`file_put`, `commit`, `issue_create`, `issue_comment`, `issue_update`,
`pr_create`, `pr_review`, `pr_merge`, `gist_create`, `gist_update`,
`repo_star`, `repo_unstar`. The owner names the ones they want to see in the
policy's `confirm`, and `status` reports it as `policy.confirm`: `null` or
`[]` means every write is made at once; a read is never listed.

**Read `policy.confirm` before a write**, and tell the person which it will
be: "I'll open the pull request" and "I'll prepare the merge for your
confirmation" are different promises.

## What a listed write answers

Your call is checked exactly as it would be before writing — the action, the
repository, the branch and the default-branch rule, the paths, `allow_merge`,
`allow_approve`, `allow_public_gists`, that `max_writes_per_day` is set — and
instead of writing, the connector leaves a task for the owner:

```json
{"success": true,
 "output": {"status": "awaiting_owner", "task_id": "…", "task_hash": "…",
            "thread": "…", "expires_at": 1790003600,
            "link": "https://app.outlayer.ai/inbox/…"}}
```

That is a success, and **nothing was written yet**. You paid the write's price
($0.01) now; it is not returned if the owner says no. Give the owner `link`,
keep `task_id`, and **do not call the write again while the task is open** — a
second call is a second task and a second fee, and two confirmed tasks are two
writes.

> I prepared the merge of pull request #8 in outlayer-ai/sandbox (squash). It
> waits for your confirmation, and nothing is merged until you confirm:
> https://app.outlayer.ai/inbox/…

The owner reads the write in their inbox and approves it with one signature
of their wallet; the platform then runs `confirm` as you — on your payment
key, within the compute limit of the call that prepared it — and that run
makes the write. Keep the key alive and funded until then: a key that cannot
pay for the run ends the task `failed` with `preparer_key_unavailable`. You
learn the outcome with `task_status` (free):

```json
{"operation": "task_status", "task_id": "…"}
```

`done` carries in `result` the write's whole answer, as the write would have
answered you directly — for a `commit`, its `commit`, `url` and
`writes_today` — and the owner's `note` when they wrote one. `rejected` carries the owner's `reason` when they wrote one ("request
changes instead of approving", "put it on a branch"): do what it says and call
the write again — a new task, with a new `link` to give them. Never prepare the
same write again unchanged. How a GitHub task can fail is below; every other
state and `failure_reason`, what `task_delete` may delete, and what to do in
each: https://skills.outlayer.ai/outlayer-connectors/references/owner-tasks.md

## What the owner is shown

Every value the write will use, and whose words each is — yours, or what the
connector read from GitHub:

| write | shown |
|---|---|
| `branch_create` | repository, branch, the branch it starts from, and the commit it starts at, read when the task is made |
| `file_put` | repository, branch, path, commit message, the blob it replaces, the content |
| `commit` | repository, branch, commit message, each changed path with its size — and each content |
| `issue_create` | repository, title, body with its marker, labels, assignees |
| `issue_comment` | repository, number, the comment with its marker |
| `issue_update` | repository, number, and each of state, title, body, labels, assignees it changes — an empty list as "every label is removed" |
| `pr_create` | repository, from and into branch, title, body, draft |
| `pr_review` | repository, number, the pull request's title and head commit, verdict, summary, each line comment with its path, line and side |
| `pr_merge` | repository, number, the pull request's title, its branches, the head commit, the method |
| `gist_create`, `gist_update` | visibility or gist id, description, each file — and each content |
| `repo_star`, `repo_unstar` | repository |

A file's content is shown in a field when it is text a field draws exactly as
written — no carriage return, no character that is invisible or reorders text,
at most 50000 characters — and there is room: a task shows 12 fields, and the
contents shown together hold at most 128 KiB. Any other content is given to
the owner as a file of the task, named `<n>-<name>` after its place in the
list, byte for byte. A review's line comments that do not fit a field each are
given together as `review-comments.json`.

A write the owner cannot be shown whole is refused before any task is made,
never shown in part: over 20 changed files, 10 files to open, or 6 MiB of
them together — `display_invalid:` or `task_too_large:`. Split it into
smaller writes.

Texts are shown and posted with `\n` line ends; a file's content is written as
it was given.

## The owner's yes is bound to what they saw

The run of `confirm` the platform starts makes exactly the write the task
holds; nothing you call afterwards changes it. To change a prepared write,
`task_cancel` it and prepare the new one. The write is judged again at
`confirm`, under the same policy, with the default-branch rule asked of
GitHub again, and counted then — in your own daily count, as a confirmed
write.

| write | bound to |
|---|---|
| `pr_merge` | the head commit shown: the merge is made with that `sha`, so GitHub refuses it if the pull request moved |
| `pr_review` | the head commit shown: an approval of any other head is refused `conflict` |
| `branch_create` | the commit shown: the branch is created there |
| `commit` | the branch's head as it is at confirmation; the branch moves without force |

A pull request that moved between your call and the owner's yes ends the task
`failed` with `failure_reason: run_failed`, and `result.error` starting
`conflict:`. Nothing was merged or approved. Read it again (`pr_get`,
`pr_files`), review what is there now, and prepare the merge or the review
again — a new task the owner sees with the new head. Do not tell the owner it
was merged or approved.

## How a confirmed write fails

| `state` / `failure_reason` | for this write | do |
|---|---|---|
| `failed`, `run_refused:<reason>` or `run_refused:unreported` | refused before the owner's answer was taken — the policy gone or unreadable, a task that no longer holds: nothing was written | prepare it again if it is still wanted — a new task |
| `failed`, `run_failed` | refused after the answer was taken, before anything changed on GitHub: the policy, the day's count, the token, or GitHub's own 4xx refusal. `result.error` is the connector's sentence, ending "The task is closed: to make this write, prepare it again" | quote `result.error` to the owner; prepare again only if still wanted |
| `failed`, `run_unreported` | a request reached GitHub and its outcome is not known — GitHub answered 5xx, its answer was lost, or a later step failed after an earlier one was made — or the write was made and its result could not be kept. There is no `result`. **The write MAY have been made** | check GitHub first (`issue_list`, `pr_get`, `branch_list`, `file_get`, `gist_list`); prepare it again only if nothing is there |
| `failed`, `operation_limit_reached` | `confirm` met its ceiling of 200 runs a day; nothing was written | prepare it again later, if still wanted |

## The daily cap

`max_writes_per_day` bounds the writes you make yourself and the writes the
owner confirms for you as two counts, each against the same number.
`writes_today` in `status` and in a write you make yourself is the first; in a
confirmed write's `result` it is the second.

## Operations that are not yours to call

`tasks_unlock` is the owner's, from their inbox: called by you it is refused
`not_the_owner:`. `confirm` runs only when the platform starts it on the
owner's approval: called by you it is refused `task_answer_invalid:`. It has
no fee, and the run's compute is still yours. Never ask the owner to give you anything that
would let you call them.
