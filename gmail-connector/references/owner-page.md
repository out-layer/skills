# The owner's page, after the account is connected

> Part of the `gmail-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/gmail-connector/`.

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
