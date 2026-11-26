# Credentials: the owner's row, and one under your own wallet

> Part of the `outlayer-connectors` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/outlayer-connectors/`.

A connector that acts on somebody's account — a mailbox, a bank, a code host —
needs a credential. It reaches the connector from one of two rows, and you
never see either value: the connector opens it inside the enclave.

| the row | stored by | how the call names it |
|---|---|---|
| **the owner's row** — the usual arrangement | the owner, under THEIR account, with your wallet in its access rule | `secrets_ref: {"account_id": "<owner>", "profile": "<profile>"}` |
| **a row under your own wallet** | a human, for your wallet's account | `X-Use-Owner-Secret: 1` and no `secrets_ref` |

`hyperliquid` and `polymarket` take neither: their row is the owner's policy,
attached for you (`SKILL.md`, "The call").

## Asking an owner to let you read their credential

The owner stores the credential once under their own account and names your
wallet as a reader. You then name their row in `secrets_ref`.

**They cannot guess which account to name, and you must tell them.** Naming the
wrong one is refused in words identical to the secret not existing at all, so a
vague request costs a round trip at best and a wrong diagnosis at worst.

**Step 1 — read your own account.** It is the 64-character account of the wallet
that will PAY, i.e. the one that owns the `X-Payment-Key` you will send:

```
GET https://api.outlayer.ai/wallet/v1/address?chain=near
Authorization: Bearer <that wallet's wk_>
→ { "address": "0baa071c…56a1", "wallet_id": "…" }
```

It is the `address`. Not the `wallet_id`, which is a UUID and names nothing on
chain. Not a bound name like `alice.near`, which is the identity you ACT as and
never the one a grant names. Not another wallet you also hold — if you have
several, the payer is the one that matters.

**Step 2 — ask in a sentence a person can evaluate.** An identifier on its own
is not a request:

> To send that mail I need to read your Gmail credential. I never see its value —
> the connector opens it inside the enclave. Please grant read access to my
> wallet account `0baa071c…56a1` on the secret you stored for project
> `connectors.outlayer.near/gmail`, profile `gmail`.

**Step 3 — call, naming their row:**

```json
{"input": {"operation": "status"}, "secrets_ref": {"account_id": "owner.near", "profile": "gmail"}}
```

`profile` is a label the owner chose when storing the row. It is not derived
from anything and cannot be guessed; each connector's skill names the
conventional one, and if a call is refused it is worth asking which they used.

**A grant issued seconds ago can still be refused.** The condition is read from
the chain, and a refusal immediately after the owner says "done" proves nothing.
Wait a minute, repeat the free `status`, and only then conclude they named the
wrong account. Both cases say `Access denied by access condition` in the same
words.

## A credential a connector reads from your own wallet

A credential **yours to use but not yours to hold** — an API token for the
service a connector talks to — can be stored under YOUR wallet's account,
sealed to the keystore. You never see the value, and neither does the browser
page that stores it: it is encrypted before it leaves.

**Ask for it per call with `X-Use-Owner-Secret: 1`** (`true` works too). Without
the header nothing is fetched. With it, the call reads the row stored under
your wallet's account for that connector. It takes effect only when all of
these hold:

* the project is a curated connector (`connectors.outlayer.near/<connector>`).
  On a project that is not a connector the header does nothing — name the row
  in `secrets_ref` there;
* the call sends no `secrets_ref` — a named row wins;
* the `X-Payment-Key` is a key your custody wallet owns.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-Payment-Key: $PAYMENT_KEY" -H "X-Use-Owner-Secret: 1" \
  -d '{"input":{"operation":"status"}}' \
  "https://api.outlayer.ai/call/connectors.outlayer.near/<connector>"
```

**You cannot store it yourself.** Your wallet has no NEAR to pay for the write,
and the key that authorises it never leaves the TEE — so the coordinator
prepares the transaction and a **human sends and pays for it**. Say what you
need, why, and where:

> The <service> connector needs your <service> API token to <the task you were
> asked to do>, stored for my wallet. Store it at https://app.outlayer.ai/secrets,
> in "Secret for an agent", for project `connectors.outlayer.near/<connector>`.
> It is encrypted in your browser and I never see it. Your NEAR wallet sends one
> transaction with 0.1 NEAR for storage; the excess comes back.

On that section they paste your `wk_` (or pick it, if that browser already
saved it), enter the project, put the credential in the Secret box as JSON
under the variable names the connector's skill gives, and press "Store for
agent". Storing again for the same project replaces the value.

Which route you get is the owner's choice, not yours. A leased account
(`hos_lease`) has only the owner's row: storing under your wallet needs that
wallet's `wk_`, and the human holding the lease does not have it.

**Say what you are asking for and why.** "I need your SendGrid key to send the
mail you asked for" is a sentence a person can refuse. A bare link is not.
