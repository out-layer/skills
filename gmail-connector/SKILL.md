---
name: gmail-connector
description: Send email from the owner's own Gmail address through the `gmail` connector — to the recipients the owner's policy allows, with attachments if it allows them. Use when an agent with an OutLayer wallet needs to write to someone by email as its owner. It cannot read the mailbox. Also covers a send the owner chose to confirm first, which answers `awaiting_owner`.
---

# Gmail connector

You send mail as the owner's Gmail account. You never see the credential, you can
only write where the owner's policy allows, and **you cannot read the mailbox** —
there is no operation for it, and the credential could not do it anyway: it
carries the single scope `gmail.send`, which does not even permit reading back
which address it belongs to. Do not plan a task around finding a reply.

There is also no way to set the `From` address. Every message leaves as the
connected account. How any connector is called and paid — which key, the trial,
the platform's own refusals — is not here: it is in
<https://skills.outlayer.ai/outlayer-connectors/SKILL.md>.

## Which file to read

The relative links below resolve against `https://skills.outlayer.ai/gmail-connector/`.

| the task in front of you | read |
|---|---|
| send a message, read `status`, a refusal | this file |
| the owner has not connected, or has not granted you | [`references/connect.md`](references/connect.md) |
| the owner asks about their page: reading or changing the policy, reconnecting | [`references/owner-page.md`](references/owner-page.md) |
| `send` answered `awaiting_owner`, or you follow a task | [`references/confirmed-sends.md`](references/confirmed-sends.md) |
| any task state or `failure_reason` | <https://skills.outlayer.ai/outlayer-connectors/references/owner-tasks.md> |

## Where it runs

| network | `{api_host}` | `{connectors_account}` | state |
|---|---|---|---|
| testnet | `testnet-api.outlayer.ai` | `connectors.outlayer.testnet` | live |
| mainnet | `api.outlayer.ai` | `connectors.outlayer.near` | live |

Use the pair for the network your payment key belongs to; a key of one network
cannot pay on the other.

## Call shape

```
POST https://{api_host}/call/{connectors_account}/gmail
X-Payment-Key: <a payment key the calling wallet owns>
Content-Type: application/json

{
  "input": {"operation": "<op>", ...},
  "secrets_ref": {"account_id": "<the mailbox owner>", "profile": "gmail"}
}
```

`secrets_ref` is what brings the owner's credential into the run. Without it the
connector starts with nothing and says so. Which key pays, and how to ask to be
granted a credential somebody else owns, are the same for every connector and
live in <https://skills.outlayer.ai/outlayer-connectors/SKILL.md>.

## Where the credential comes from

The mailbox owner connects their account once, at
<https://app.outlayer.ai/connect/gmail>, and then grants your payer account on
the secrets row `gmail`. You cannot do either for them: it takes their Google
consent and their wallet signature. Say what will happen before they click —
someone who does not know stops at Google's warning screen and reports that it
is broken:

> To let me send mail as you: connect your account at
> https://app.outlayer.ai/connect/gmail — one Google consent for sending only,
> then one transaction from your wallet; the credential is encrypted in your own
> browser and stays yours. After that, add my account `<your payer account>`
> under Access on the secrets row named `gmail`:
> https://app.outlayer.ai/secrets?project=connectors.outlayer.near/gmail&profile=gmail&access=1
> I never see the credential itself: it is opened inside the enclave, and I only
> get what an operation answers.

What they need first, each screen they will see, the errors they may report,
and how the grant works: [`references/connect.md`](references/connect.md).

## Start here

```json
{"operation": "status"}
```

Free — you pay only compute, about $0.001. It proves the credential by fetching
an access token from Google, so its answer is evidence, not a guess. Read it
before paying for a send.

One optional field, `reply_pubkey`: a secp256k1 public key in hex — 33 bytes
compressed, the form `eciesjs` gives.
Given one, the policy comes back **sealed to that key** in `policy_sealed`
(base64) and the open `policy` says only `{"present": …, "sealed": true}`. Over
HTTPS you do not need it. **On chain you do**: the output of an on-chain run is
public for ever, so without a key the connector withholds the policy's fields
and answers `{"present": …, "sealed": false, "note": …}` — that is by design,
not a failure. The seal is the `ecies` crate's — secp256k1, the same pair
near.email uses — and `eciesjs` opens it.

| what comes back | what it means | what to do |
|---|---|---|
| refused, `no Gmail credential reached this run` | nothing reached the run: not connected, not granted to you, or `secrets_ref` names the wrong account or profile | send the owner the connect link, or ask to be granted |
| `credential: "ok"`, `policy.present: false` | connected but not permitted to send yet. **Half done, not broken** | ask for a policy, below |
| `credential: "ok"`, `policy.readable: false` | the owner's stored policy is not valid JSON, so sending is refused until they fix it | pass them the `error` text verbatim |
| `credential: "ok"`, `policy.present: true` | ready | send |
| `credential: "ok"`, `policy.sealed: false` with a `note` | you called on chain without `reply_pubkey`; the fields are withheld on purpose | pass a key, or read the policy over HTTPS |
| refused, `credential_expired` or `credential_rejected` | the stored token is dead | the owner reconnects at the page above; retrying does nothing |

The full answer:

```json
{"credential": "ok",
 "scope": "gmail.send: this connector sends as the connected account and cannot read its mailbox",
 "policy": {"present": true, "recipient_domains": null, "recipients": null,
            "max_per_day": null, "max_recipients": null,
            "max_attachment_kb": null, "subject_prefix": null, "confirm": null},
 "sent_today": 0,
 "next": "`send` with `to`, `subject` and `body`"}
```

`sent_today` counts the messages you sent yourself today, in UTC days — not
the ones the owner confirmed for you, which count apart. Only a send made while
the policy sets `max_per_day` is counted: with no cap nothing counts, and it
reads 0.

## Sending

```json
{"operation": "send",
 "to": "boss@example.com",
 "subject": "Weekly numbers",
 "body": "Revenue is up 4%.\n\n— the agent"}
```

* `to` — required. One address as a string, or several as an array:
  `["a@example.com", "b@example.com"]`.
* `cc` — optional, same shape.
* `subject`, `body` — optional strings; absent means empty. `body` is plain text.
* `attachments` — optional:
  `[{"filename": "r.csv", "content_type": "text/csv", "data": "<base64>"}]`.
  Allowed only if the owner set `max_attachment_kb`.

Addresses must be **bare**: `name@example.com`, no display name, no angle
brackets, no comment, one address per entry. A string is never split on commas —
a comma inside it makes it a malformed address, not a list. This is deliberate:
a display name is where a second recipient could hide from the owner's policy
check, so the only accepted form is the one whose checked value is the value
sent.

The answer:

```json
{"message_id": "199…", "thread_id": "199…", "to": ["boss@example.com"], "cc": [],
 "subject": "[agent] Weekly numbers", "attachments": 0,
 "sent_today": 3, "remaining_today": 17}
```

`subject` comes back as it was sent — the owner's `subject_prefix`, if they set
one, is already on it. `sent_today` and `remaining_today` are `null` when the
owner set no `max_per_day`: no cap of theirs is counting.

### When the owner confirms every message

Read `policy.confirm` in `status` before you send. `null` or `[]`: `send`
sends at once. `["send"]`: `send` answers
`{"status": "awaiting_owner", "task_id": …, "link": …}` and sends nothing: the
message waits for the owner. That is a success. Give them `link`, do not call
`send` again while the task is open, and learn the outcome with `task_status`.
The limits of such a message, and what to do when the owner rejects it:
[`references/confirmed-sends.md`](references/confirmed-sends.md).

## What the policy permits

`status` reports it, and it is written by the owner, not by you.

**`present: true` is the owner's consent that this credential may send at all —
not a statement that they restricted anything.** The fields are optional
narrowings on top of that consent, so a policy whose every field is `null`
permits any recipient, any number of messages a day, any number of addresses in
one message. The empty policy `{}` is what the connect page writes, so a freshly
connected account arrives at the widest setting there is. The one field that
works the other way is `max_attachment_kb`: absent, attachments are refused.
Everything else is allow-by-default; that one is deny-by-default.

| field | absent means | set means |
|---|---|---|
| `recipient_domains` | with `recipients` also absent: anywhere | only these domains (plus `recipients`); `["any"]` means anywhere |
| `recipients` | see above | these exact addresses, whatever their domain |
| `max_per_day` | the owner is not capping you | that many messages a day, counted per calling wallet in UTC days |
| `max_recipients` | any number | that many `to` and `cc` together |
| `max_attachment_kb` | **no attachments at all** | that many KB, summed over the message's files |
| `subject_prefix` | subjects go as written | prepended when not already there |
| `confirm` | you send without asking | `["send"]`: every message waits for the owner's confirmation |

One disallowed address refuses the whole message: a message goes to all of its
recipients or none. Size the request inside those limits rather than discovering
them by refusal — see the costs below for why.

If there is no policy, ask for the narrowest one that does the job rather than a
blank cheque:

> I can't send yet — the credential works but there is no policy. For this task
> I need `recipients: ["someone@example.com"]`, `max_recipients` 1, `max_per_day`
> 10, and no attachments.

## Costs

| operation | fee | plus compute |
|---|---|---|
| `status` | free | ~$0.001 |
| `send` | $0.01 | ~$0.001 |
| `task_status`, `tasks`, `task_cancel`, `task_delete` | free | ~$0.001 |
| `confirm` (the platform runs it on your key on the owner's yes), `tasks_unlock` (the owner's) | free | ~$0.001 |

A confirmed message is paid for once, by your `send`; the run of `confirm` the
platform starts on the owner's approval is yours too, and costs you its compute
only.

**A refused send costs exactly what a delivered one costs.** The fee is charged
before the run, so a message rejected for a malformed address, an unpermitted
recipient or a dead credential still spends $0.011 — measured, not estimated.
Check `status` first, and read which refusals below are terminal before retrying
any of them: a loop on a refusal that cannot clear spends money, or a trial's
calls, on nothing.

How much you may send is the owner's to decide, through `max_per_day` in their
policy: a send refused before it leaves gives its place back, so only mail that
actually left is counted there, in UTC calendar days. The platform adds no quota
for a caller who pays. The connector itself carries one technical ceiling against
a runaway loop — **500 sends in a rolling day per calling wallet** — answered as
`operation_limit_reached` with `retry_after_seconds`. An attempt that ceiling
refuses still counts toward it: wait, do not retry into it. `confirm` has a
ceiling of its own, 500 a day; a confirmed message over it ends its task
`failed` with `operation_limit_reached`.

## When it refuses

The answer is `{"success": false, "error": "…"}`. **Terminal** means no number of
retries will change it — somebody has to do something.

| the error starts with | what happened | terminal? |
|---|---|---|
| `no Gmail credential reached this run` | no credential arrived: not connected, not granted, or the wrong `secrets_ref` | yes, until the owner connects or grants |
| `a refresh token reached this run with no OAuth client to use it with` | an owner's own-client row is missing `GMAIL_CLIENT_ID`/`GMAIL_CLIENT_SECRET` | yes, the owner stores them or reconnects through the page |
| `credential_expired:` | Google refused the refresh token — revoked, six months unused, or minted by an OAuth client left in testing mode | yes, the owner reconnects |
| `credential_rejected:` | Gmail refused the access token; the token was probably revoked mid-flight | yes, the owner reconnects |
| `scope_missing:` | the credential was not granted `gmail.send` | yes, the owner consents again |
| `api_disabled:` | the Gmail API is switched off in the Google Cloud project behind the credential. It arrives as the same HTTP status as a throttle and is **not** one | yes — its owner enables it at `console.cloud.google.com/apis/library/gmail.googleapis.com`, named in the message |
| `rate_limited:` | Gmail is throttling; nothing was sent | no — wait, then retry |
| `policy_denied:` | the owner's rules: no policy, an unreadable policy, a recipient they do not allow, too many recipients, attachments they did not permit, or their daily cap | not by retrying; change the request, or ask the owner |
| `recipient N of M: the recipient is not a bare email address` | entry N of `to` or `cc` has a display name, angle brackets, a comma, a second `@`, or characters an address cannot hold | fix that address |
| `` `to` is required `` | no recipient | fix the request |
| `` `reply_pubkey` must be a secp256k1 public key `` | not 33 or 65 bytes of hex; refused before Google is asked | fix the key |
| `` `reply_pubkey` is not a point on secp256k1 `` | the bytes are the right length and not a public key | generate a fresh keypair |
| `an attachment is not base64` | `data` did not decode | fix the attachment |
| `Gmail could not be reached for /messages/send:`, `Gmail answer for /messages/send:`, `Gmail's answer for /messages/send is not JSON`, `Gmail refused /messages/send: HTTP 5…` | the request went out, or may have, and its outcome is unknown: **the message MAY have left** | do not send it again blind. Ask the owner to look in their Sent folder; send again only if it is not there |
| `Gmail refused …: HTTP 4…` | anything else Google refused, in its own words; nothing was sent | judge it by what Google said |

Refusals the platform answers before the run — an unknown operation, the key,
the trial — are read in <https://skills.outlayer.ai/outlayer-connectors/SKILL.md>
(*Reading a refusal*); the task limits (`inbox_full:`, `muted:`, …) in
<https://skills.outlayer.ai/outlayer-connectors/references/owner-tasks.md>
(*Limits you can meet*).
