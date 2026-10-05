# Connecting the owner's GitHub account

> Part of the `github-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/github-connector/`.

The owner connects once, at **<https://app.outlayer.ai/connect/github>**. You
cannot do it for them — it needs their GitHub authorization and their wallet
signature — so your job is to send them there **and tell them what happens
before they click**.

## What they need first

* The NEAR wallet that will own the credential, connected on the dashboard.
* A little NEAR in it: the last step is a transaction and pays for storage.
* **The right network** — the page writes to whichever the dashboard is on.
* A GitHub account, and the repositories they are willing to lend.

## What they will see, in order

1. **Authorize on GitHub.** The button takes them to GitHub and brings them
   straight back. The screen lists only the account-level permission (Gists).
   **This surprises people** — say beforehand that repositories are chosen
   separately, in step 2, and that this screen does not mention them. Someone
   who authorized the app before sees no screen at all and is back at once.
2. **Back on our page: who, and which repositories.** The page shows the GitHub
   name everything will appear under, and the repositories the app reaches. A
   link takes them to GitHub to **choose repositories**; when they save, GitHub
   brings them back and the list on our page has changed. Tell them to pick the
   few they mean and no more: this is the fence, and the strongest one in the
   system. They can return to it later from the same page.
3. **Nothing is saved yet.** The page says so in those words. The credential is
   in that browser tab and nowhere else — closing it means starting over.
4. **The policy.** They choose which actions, repositories, branches and paths,
   and how many writes a day. The page proposes a careful start: reading,
   issues and reviews in the repositories they picked. Without a policy you can
   only call `status`.
5. **One wallet transaction.** It stores the credential, encrypted, in their own
   record. Until they approve it, nothing exists.

## What it means, in their words

* The credential is sealed to a hardware enclave. You, the agent, never receive
  it, and neither OutLayer's operators nor anyone reading the chain can open it.
* Everything you do appears under **their** name, with a note that an app did
  it. Say this plainly — it is the part people are surprised by afterwards.
* They can stop it in two ways, either alone enough: delete the stored record,
  or remove the app at GitHub → Settings → Applications.
* Four things stay out of reach whatever the policy says: the `.github/`
  directory, workflow files, repository settings, and any repository they did
  not pick.

## If they report an error

| what they say | what it is |
|---|---|
| "GitHub only asked about gists" | expected — repositories are chosen separately, and the page shows which it reaches |
| "I changed repositories and the page flickered through GitHub again" | right — coming back from GitHub's page, ours re-checks who they are; it needs no click |
| "it says the organization needs approval" | they are not an owner of that organization; an owner has to approve the install |
| "the wallet did nothing" | the transaction was refused or closed; the page keeps what it has, they press the button again |
| "I connected but you say no repositories" | the app was installed on an account with none selected — `add_repositories` from `status` is the link |

## Then ask to be granted

Storing the credential does not hand it to you. The row is stored under the
profile **`github`**, readable by the owner alone; they add your **payer
account** under Access on the secrets page,
`https://app.outlayer.ai/secrets?project=connectors.outlayer.near/github&profile=github&access=1`
(on testnet, `connectors.outlayer.testnet/github`) — optionally with an
expiry, so the grant lapses on its own. Then you name
`{"account_id": "<their account>", "profile": "github"}` in `secrets_ref`.

Your payer account is the 64-character account of the wallet that owns your
payment key, not any name you act under; how to read it and how a grant is
asked for are in <https://skills.outlayer.ai/outlayer-connectors/references/credentials.md>
(*Asking an owner to let you read their credential*). Ask in the words
`SKILL.md` gives under *Where the credential comes from*.
