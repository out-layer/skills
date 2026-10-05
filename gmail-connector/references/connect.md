# Connecting the owner's Gmail account

> Part of the `gmail-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/gmail-connector/`.

The mailbox owner connects their account once, at
**<https://app.outlayer.ai/connect/gmail>**. You cannot do it for them — it needs
their Google consent and their wallet signature — so your job is to send them
there **and tell them what will happen before they click anything**. Someone who
does not know what the page does stops at Google's warning screen, or at the
wallet, and reports that it is broken.

## What they need first

* The NEAR wallet they want to own the credential, connected on the dashboard.
* A little NEAR in it: the last step is a transaction, and it pays for the
  storage it uses.
* **The right network.** The page writes to whichever network the dashboard is
  switched to — the Testnet / Mainnet toggle at the top; switching disconnects
  the wallet and asks them to reconnect. Ask them to connect on the network your
  payment key belongs to, or the credential lands where this connector cannot see
  it.

## What they will see, in order

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

## What it means, in their words

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

## If they report an error

| what they saw | what happened |
|---|---|
| "The consent screen was dismissed, so nothing was connected." | they closed Google's screen; start again from the page |
| "This callback did not come from a connection started in this tab." | the page was reached from an old link or another tab; start again from the page itself |
| "Google refused this authorisation code…" | the code was already used or has expired — it is single-use and lives minutes; start again |
| "Google returned no refresh token for this consent." | the account had granted this app before. Remove it at `myaccount.google.com/permissions`, then connect again |
| "This deployment has no Google client configured", or "…no Google OAuth client configured" | the site is missing its half of the Google app — the first message comes from the page, the second from the exchange behind it. Nothing the owner can do; report it |

## Then ask to be granted

The page stores the row under the profile **`gmail`**, with an empty policy,
readable by the owner alone. To let you send, they open the secrets page at
`https://app.outlayer.ai/secrets?project=connectors.outlayer.near/gmail&profile=gmail&access=1`
(on testnet, `connectors.outlayer.testnet/gmail`) and add your **payer
account** under Access — optionally with an expiry, so the grant lapses on its
own. Then you name `{"account_id": "<their account>", "profile": "gmail"}`.

Your payer account is the 64-character account of the wallet that owns your
payment key, not any name you act under; how to read it and how a grant is
asked for are in
<https://skills.outlayer.ai/outlayer-connectors/references/credentials.md>
(*Asking an owner to let you read their credential*). Ask in the words `SKILL.md` gives under
*Where the credential comes from*.

## Later: the same page looks after the connection

The owner reads their policy, saves a new one and reconnects there. What each
costs them, and why reading a setting takes a transaction:
[`owner-page.md`](owner-page.md).

An owner who brought their own Google OAuth app stores three values instead of
one — `GMAIL_REFRESH_TOKEN` with `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` — and
grants them the same way; nothing changes for you.
