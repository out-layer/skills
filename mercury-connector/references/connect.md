# Connecting the owner's Mercury account

> Part of the `mercury-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/mercury-connector/`.

The owner connects once, at **<https://app.outlayer.ai/connect/mercury>**. You
cannot do it for them — it needs a token from their Mercury settings and their
wallet signature — so your job is to send them there **and tell them what
happens before they paste anything**. A wrong token scope means a new token,
not a setting, so the scope is the thing to say first.

## What they need first

* The NEAR wallet that will own the credential, connected on the dashboard,
  with a little NEAR in it: the last step is a transaction and pays for storage.
* **The right network** — the page writes to whichever the dashboard is
  switched to. Ask them to connect on the network your payment key belongs to.
* **A Mercury API token**, created at Mercury → Settings → API Tokens →
  *Custom*. Its scope cannot be edited afterwards:
  * *Read + Send Money with Approval* — every payment you make waits for a
    person in Mercury's app. The usual choice, and the safe first one. An
    owner who chose it keeps it: never suggest a token without approval to
    get a payment through.
  * *Read + Send Money* — payments go out directly, inside the policy. Mercury
    then requires an IP allowlist on the token, and the addresses to allow are
    OutLayer's enclave nodes, not the owner's: the connector names the address
    to add the first time a payment is refused with `ipNotWhitelisted`.
  * *Read* only — accounts, payees, the ledger and invoices, nothing else.

## What they will see, in order

1. **A page that explains the scopes, then one field: the token.** They paste
   it and press *Continue with this token*. The token stays in that browser tab
   — nothing is sent to us — and the page asks Mercury, from their browser,
   which accounts it reaches.
2. **A deliberate stop. Nothing is stored yet.** The page says so in those
   words, lists the accounts the token reaches, and shows the policy form:
   most per payment, budget per 30 days, payees, rails, account, the two
   switches (new payees, invoicing), and which operations at all. An empty
   policy is **read-only**; both amounts are needed before any payment runs.
   With one account the page pins it; with several, payments are refused until
   they name one.
3. **One button, *Finish: store the encrypted credential on the contract*.**
   Their wallet opens only when they press it. The token and the policy are
   sealed in their browser to a key that exists only inside the keystore
   enclave, and stored under their account with a rule naming them alone.
4. **Mercury connected**, and a link to grant an agent. If their wallet is
   closed or refuses, they land back on step 2: one more click, no new paste.

## What it means, in their words

* A token alone moves nothing. Until the policy names a budget, you can only
  read.
* The token is encrypted before it leaves their browser. We cannot read it
  afterwards, and neither can you: the connector opens it inside the enclave.
* Nobody can use it until they grant an agent, and removing the grant — or the
  row, or the token in Mercury — ends it at once.
* Payments you queue are approved in Mercury's app by a **different Mercury
  user** from the one who created the token, and only if an **approval rule**
  names that approver for the amount. A request no rule covers exists in the
  API and appears to nobody. Say this before the first payment, not after.
* **Mercury deletes a token unused for 45 days.** Your `status` call is a use.
  If you hold this connection, call `status` at least every few weeks.

## Then ask to be granted

The row is stored under the profile **`mercury`**, readable by the owner alone.
To let you act, they open the secrets page,
`https://app.outlayer.ai/secrets?project=connectors.outlayer.near/mercury&profile=mercury&access=1`
(on testnet, `connectors.outlayer.testnet/mercury`), and add your **payer
account** under Access — optionally with an expiry. Then you name
`{"account_id": "<their account>", "profile": "mercury"}` in `secrets_ref`.

Your payer account is the 64-character account of the wallet that owns your
payment key, not any name you act under; how to read it and how a grant is
asked for are in <https://skills.outlayer.ai/outlayer-connectors/references/credentials.md>
(*Asking an owner to let you read their credential*). Ask in the words
`SKILL.md` gives under *Where the credential comes from*.
