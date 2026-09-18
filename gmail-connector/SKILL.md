---
name: gmail-connector
description: Send email from the owner's own Gmail address through the `gmail` connector — to the recipients the owner's policy allows, with attachments if it allows them. Use when an agent with an OutLayer wallet needs to write to someone by email as its owner. It cannot read the mailbox.
---

# Gmail connector

You send mail as the owner's Gmail account. You never see the credential, you can
only write where the owner's policy allows, and **you cannot read the mailbox** —
there is no operation for it, and the credential could not do it anyway: it
carries the single scope `gmail.send`, which does not even permit reading back
which address it belongs to. Do not plan a task around finding a reply.

There is also no way to set the `From` address. Every message leaves as the
connected account.

## Where it runs

| network | `{api_host}` | `{connectors_account}` | state |
|---|---|---|---|
| testnet | `testnet-api.outlayer.ai` | `connectors.outlayer.testnet` | live |
| mainnet | `api.outlayer.ai` | `connectors.outlayer.near` | **not published yet** — the project does not exist, and a call is refused before it runs |

The two halves of a row move together. Use the pair for the network your payment
key belongs to; a key of one network cannot pay on the other.

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
**<https://app.outlayer.ai/connect/gmail>**. You cannot do it for them — it needs
their Google consent and their wallet signature — so your job is to send them
there **and tell them what will happen before they click anything**. Someone who
does not know what the page does stops at Google's warning screen, or at the
wallet, and reports that it is broken.

### What they need first

* The NEAR wallet they want to own the credential, connected on the dashboard.
* A little NEAR in it: the last step is a transaction, and it pays for the
  storage it uses.
* **The right network.** The page writes to whichever network the dashboard is
  switched to — the Testnet / Mainnet toggle at the top; switching disconnects
  the wallet and asks them to reconnect. Ask them to connect on the network your
  payment key belongs to, or the credential lands where this connector cannot see
  it.

### What they will see, in order

1. A page saying "Google will ask you to allow one thing: sending mail." One
   button, *Connect Google account*.
2. **Google's consent screen**, asking for `gmail.send` and nothing else. The app
   is published but not verified by Google, so Google may first show an
   "unverified app" warning, and it admits at most 100 accounts. That screen is
   expected; continuing is *Advanced* → *Go to …*.
3. **Back on the page, with nothing to click.** It turns the consent into a
   long-lived credential and fetches the key it will be sealed to — a key whose
   private half exists only inside the keystore enclave. The page says "Google
   has granted the credential."
4. **A deliberate stop. Nothing is stored yet.** The page explains the
   transaction — the credential and the policy are sealed **in their own
   browser** on the click, and go onto the smart contract under their account,
   with a rule naming only them — and shows one line, *Policy:
   anyone, no limits — Customize*. They can narrow it there (who may be written
   to, how much, attachments, a subject prefix), or leave it and narrow it
   later. Then one button, *Finish: store the encrypted key on the contract*.
   Their wallet opens only when they press it, and not a moment before.
5. A green **Gmail connected**, and a link to the secrets page.

If their wallet is closed or refuses, they land back on step 4: one more click
finishes it, and the trip through Google is not repeated.

### What it means, in their words

Worth saying up front, because it is what a person hesitates over — and all of it
is checkable:

* What is stored is a Google credential **for sending only**. It cannot read
  their mail: the connector never asks for a scope that could, so no message of
  theirs can reach you.
* It is **encrypted before it leaves their browser**. Not by us, not on a server.
  We cannot read it afterwards, and neither can the page.
* It is stored **under their own account**, with a rule naming only them, until
  they add somebody.
* **Nobody can send until they grant an agent**, and removing the grant — or the
  row — ends it. The credential never moves while they do that.

### If they report an error

| what they saw | what happened |
|---|---|
| "The consent screen was dismissed, so nothing was connected." | they closed Google's screen; start again from the page |
| "This callback did not come from a connection started in this tab." | the page was reached from an old link or another tab; start again from the page itself |
| "Google refused this authorisation code…" | the code was already used or has expired — it is single-use and lives minutes; start again |
| "Google returned no refresh token for this consent." | the account had granted this app before. Remove it at `myaccount.google.com/permissions`, then connect again |
| "This deployment has no Google client configured", or "…no Google OAuth client configured" | the site is missing its half of the Google app — the first message comes from the page, the second from the exchange behind it. Nothing the owner can do; report it |

### Then ask to be granted

The page stores the row under the profile **`gmail`**, with an empty policy (see
below), readable by the owner alone. To let you send, they open the **secrets
page**, find the row `gmail` under `connectors.outlayer.testnet/gmail` (or
`…near/gmail`), and add your **payer account** under Access — optionally with an
expiry, so the grant lapses on its own. Then you name
`{"account_id": "<their account>", "profile": "gmail"}`.

Your payer account is the account the payment key belongs to, not any name you
act under. Ask like this:

> To let me send mail as you: connect your account at
> https://app.outlayer.ai/connect/gmail — one Google consent for sending only,
> then one transaction from your wallet; the credential is encrypted in your own
> browser and stays yours. After that, add `<your payer account>` under Access on
> the secrets row named `gmail`, and I can send. I never see the credential
> itself: it is opened inside the enclave, and I only get what an operation
> answers.

### Later: the same page looks after the connection

When the owner opens the page again it says *Gmail is connected*, since when,
and who may use it. Three things they can do there, and what each costs them:

* **Show current policy (one transaction).** The policy is sealed together
  with the credential and only the keystore enclave can open it, so the page
  cannot read it back. The one door into the enclave is running the connector,
  and on chain a run is a transaction: it attaches 0.1 NEAR, keeps the run's
  cost — about 0.0013 NEAR — and returns the rest. The connector answers with
  the policy sealed to a key the page has just made and never sends anywhere,
  so the chain records only ciphertext. If the owner asks why reading a
  setting needs a transaction, that is the answer.
* **Save policy: sign, then store.** A signature from their wallet (the
  keystore re-seals the row with the new policy merged in — nothing on chain
  yet), then one transaction. Two wallet prompts, in that order, both from
  their own clicks.
* **Reconnect Google account** — after `credential_expired`, or for a
  different mailbox. A new consent, then the same signature and transaction;
  the policy they have stays as it is.

An owner who brought their own Google OAuth app stores three values instead of
one and grants them the same way; nothing changes for you.

`X-Use-Owner-Secret: 1` is an older arrangement, where the row sits under your
own wallet rather than the owner's. It still works, and it is read only when the
body names no `secrets_ref` — so a body that names one always wins.

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
            "max_attachment_kb": null, "subject_prefix": null},
 "sent_today": 0,
 "next": "`send` with `to`, `subject` and `body`"}
```

`sent_today` counts this wallet's messages through this connector today, in UTC
days.

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

**A refused send costs exactly what a delivered one costs.** The fee is charged
before the run, so a message rejected for a malformed address, an unpermitted
recipient or a dead credential still spends $0.011 — measured, not estimated.
Check `status` first, and read which refusals below are terminal before retrying
any of them. On a trial key every call that was accepted is one of your ten, the
free `status` included — a loop on a refusal that cannot clear spends the trial on
nothing.

How much you may send is the owner's to decide, through `max_per_day` in their
policy: a send refused before it leaves gives its place back, so only mail that
actually left is counted there, in UTC calendar days. The platform adds no quota
for a caller who pays. The connector itself carries one technical ceiling against
a runaway loop — **500 sends in a rolling day per calling wallet** — answered as
`operation_limit_reached` with `retry_after_seconds`. An attempt that ceiling
refuses still counts toward it: wait, do not retry into it.

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
| `` `…` is not a bare email address `` | an entry in `to` or `cc` has a display name, angle brackets, a comma, a second `@`, or characters an address cannot hold | fix the address |
| `` `to` is required `` | no recipient | fix the request |
| `` `reply_pubkey` must be a secp256k1 public key `` | not 33 or 65 bytes of hex; refused before Google is asked | fix the key |
| `` `reply_pubkey` is not a point on secp256k1 `` | the bytes are the right length and not a public key | generate a fresh keypair |
| `an attachment is not base64` | `data` did not decode | fix the attachment |
| `Gmail refused …: HTTP …` | anything else Google said, in its own words | judge it by what Google said |

An operation name this connector does not sell is refused by the platform before
the run, with the list: `Unknown operation "read" for this connector. Known
operations: send, status.` Nothing runs, so there is no fee and no compute to pay, and on a trial key it is
not one of your ten.
