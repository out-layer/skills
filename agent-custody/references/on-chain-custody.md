# On-chain custody: a wallet contract under two signatures

> Part of the `agent-custody` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/agent-custody/`.

With on-chain custody your main balance lies in a **wallet contract**: a NEAR
account that executes a request only under two signatures, yours and one from
OutLayer's enclave. The enclave signs only what your owner's policy allows.
You hold an Ed25519 key of your own for your signature.

Your OutLayer wallet (the `wk_` one) stays. It is your **working account**: it
relays every move of the wallet contract and pays the gas, and it is where you
do everything the wallet contract does not.

Keep **0.5 NEAR** on the working account. It is not spent: it stays yours,
for your own use. The numbers:

- A relay is sent only while the working account holds at least **0.3 NEAR**.
  The node checks that it could pay the relay's 300 Tgas at ten times today's
  gas price (0.0001 NEAR per Tgas). The 0.3 is checked, not taken.
- A relay spends about **0.0004 NEAR** for a transfer and at most **0.03 NEAR**
  for a call that uses all its gas.
- The check moves with the gas price. 0.5 NEAR passes it up to a price 1.6
  times today's, and pays for some 500 transfers on the way; if the price goes
  higher, a relay answers `402 wallet_underfunded` and you ask for more.

Ask your owner for 0.5 NEAR on the working account when the setup is done.
Read its balance (`GET /wallet/v1/balance?chain=near` with your `wk_`) before
a run of moves; under 0.35 NEAR, ask once for a top-up back to 0.5. A relay
the account cannot cover answers `402 wallet_underfunded` with the balance and
the cost.

| | OutLayer wallet (working account) | Wallet contract |
|---|---|---|
| You authenticate with | `Authorization: Bearer wk_…` | a signature of your own key on each request |
| Who signs a move | the enclave, within the policy | you and the enclave; the contract checks both |
| Cost of a move | the operation's own | one NEAR transaction per move; your working account pays its gas |
| Operations | everything in this skill | `transfer`, `call`, `intents_transfer`, `withdraw`, `swap`, `cross_chain_withdraw` |

## When your owner would choose it

On-chain custody is the owner's decision and the owner's setup; do not start
it unasked. It fits when the owner wants the chain itself to require two
signatures for anything to leave your main balance, so that the policy engine
cannot move those funds by itself, and wants to be able to leave and sign for
both sides. It costs a NEAR transaction and gas per move, a key you keep, a
setup the owner completes, and a narrower set of operations.

An agent that needs every operation, no key of its own and no transaction per
operation uses its OutLayer wallet alone. Say both sides when the owner asks.

Requirements:

- **Your wallet has an owner.** `GET /wallet/v1/address?chain=near` shows
  `exit_owner`. Without it every route here answers `400 bad_request`
  ("On-chain custody is for a wallet with an owner"); the owner registers
  first — `register-and-auth.md`, "A wallet whose owner can leave with its
  keys".
- **The owner stores a policy.** The enclave signs for a wallet contract only
  under a policy the owner account stored; until then every operation answers
  `403 policy_denied`.
- **Operations inside NEAR Intents are mainnet only**: `intents_transfer`,
  `withdraw`, `swap`, `cross_chain_withdraw`. On testnet a wallet contract does
  `transfer` and `call`.

## 1. Open a setup and give the owner the link

With `@outlayer/sdk`:

```ts
import { openSetup, collectSetup } from '@outlayer/sdk';

const options = { apiKey: process.env.OUTLAYER_API_KEY! }; // your wk_
const setup = await openSetup(options);
// setup.url       → https://app.outlayer.ai/wallet/custody#setup=<token>
// setup.expiresAt → the link works for 24 hours
// setup.key       → your one-time key: keep it in memory until step 2 returns
```

Without the SDK: make a one-time X25519 key pair, keep the private half, and
send the public half (the Python helper is in section 6).

```bash
curl -s -X POST -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"recipient_public_key":"<your one-time X25519 public key, 64 lowercase hex>"}' \
  "https://api.outlayer.ai/wallet/v1/contract/setup"
# → {"token":"<64 hex>","expires_at":"2026-11-27T12:00:00Z"}
# The link is https://app.outlayer.ai/wallet/custody#setup=<token>
```

Tell the owner what the link does, with the link:

> "To keep my main balance in a wallet contract that moves nothing without two
> signatures, mine and one from OutLayer's enclave given only within your
> policy, open this link and connect as `{owner account}`:
> `https://app.outlayer.ai/wallet/custody#setup={token}`
> You will sign one message that becomes my key and send a little NEAR for
> gas; the page creates my account (by default a new one with no key; a
> sub-account of yours or your own account are the other options). The link
> works for 24 hours. Then set my policy: I can act only under a policy you
> stored."

Rules:

- **The link is a credential for 24 hours**, and ends when the owner has
  finished. Whoever finishes it first names your wallet contract: a new
  `0s…` account, a sub-account of the owner's, or the owner's own account.
  Give it to the owner and to nobody else: send it to the owner directly,
  never print it to a log, a shared chat, an issue or a status message, and
  do not keep it after the owner has finished. If the owner says the page told
  them the setup was already finished, and they did not finish it, open a
  new setup at once and use nothing from the one you collected.
- **Opening a setup again ends the earlier link** and discards a key that was
  left and not collected. Open again only when the link expired or was lost.
- The account has no access key in the end, whichever the owner picks
  (except their own account, which keeps their keys): nothing moves without
  both signatures, and the owner alone acts on it only through the exit.

## 2. Collect your account and your key

```ts
const collected = await collectSetup(options, setup.key);
if (collected === null) {
  // the owner has not finished: ask again later
} else {
  // the wallet contract's account, your AgentKey, its 32-byte seed, the enclave's public key
  const { account, key, seed, teePublicKey } = collected;
}
```

`collectSetup` opens the sealed key with your one-time key and throws when the
key it opened is not the agent's key in the contract's pair.

Without the SDK:

```bash
curl -s -H "Authorization: Bearer $API_KEY" "https://api.outlayer.ai/wallet/v1/contract/setup"
# not finished → {"wallet_id":"…","done":false}
# finished     → {"wallet_id":"…","done":true,"account_id":"agent.alice.near",
#                 "agent_public_key":"<64 hex>","sealed_agent_key":"<base64>"}
```

Open `sealed_agent_key` with the private half of your one-time key
(`open_sealed` in section 6) and check that the public key of the 32-byte seed
you get equals `agent_public_key`. If it does not, do not use the key.
`404 request_not_found` means this wallet has opened no setup.

`account_id` is your address for your main balance: give it to whoever funds
you. Funds sent to it move only under both signatures.

### Keep the key

- **The key is your own secret.** Store it as you store your `wk_`. Never put
  it in chat, in a log or in a request. No API route takes it.
- `collectSetup` returns the key's 32-byte `seed` beside the `AgentKey`. Store
  the seed in your secret storage; `AgentKey.fromSeed(seed)` builds the same
  key after a restart. The sealed key opens with your one-time key alone, so
  collect it once and keep the seed.
- **The owner can derive the key again.** It comes from one signature of the
  owner's own key, and the owner's wallet makes the same signature on request.
  A lost key is not lost funds: tell the owner, and open a setup again.
- If your key may have leaked, tell the owner at once. The owner freezes the
  wallet, sets up another agent on another account and moves the assets
  there. The key of one wallet is always the same key.

## 3. Ask for an operation

Every operation carries an `id` of your own: 1 to 64 letters, digits, `-` and
`_`. **The id is your idempotency key.** Asking again under the same id
continues the same operation; the same id with another content is refused
with `409 conflict`. Make the id before the first request and keep it until
the operation ends.

```ts
import { WalletContract } from '@outlayer/sdk';

const contract = new WalletContract({ account, key, teePublicKey });
// For testnet add: baseUrl: 'https://testnet-api.outlayer.ai'

const op = { kind: 'transfer', to: 'bob.near', amount: '1000000000000000000000000' } as const; // 1 NEAR
const state = await contract.run('pay-1', op);
```

`run` asks, checks the returned request, signs your half and relays. `ask`,
`relay` and `get` are its steps, for when you drive them yourself.

Amounts are strings in the smallest unit (yoctoNEAR for NEAR, 24 decimals; the
token's own for a token). A token is its id inside NEAR Intents,
`nep141:<account>`. This list is exhaustive:

| `kind` | Fields | What it does |
|---|---|---|
| `transfer` | `to`, `amount` | Sends NEAR from the wallet contract |
| `call` | `to`, `method`, `args_base64`, `gas`, `deposit` | A function call from the wallet contract; `gas` at most `250000000000000` |
| `intents_transfer` | `to`, `amount`, `token` | A token to another account's balance inside NEAR Intents |
| `withdraw` | `to`, `amount`, `token` | A NEP-141 token out of NEAR Intents to the NEAR account `to` |
| `swap` | `token_in`, `amount_in`, `token_out`, `min_out` | A swap through 1Click; the output arrives in the wallet contract's balance inside NEAR Intents |
| `cross_chain_withdraw` | `to`, `amount`, `token`, `chain` | A withdrawal to the address `to` on another chain through 1Click |

A `call` to a NEAR Intents contract, to the keystore DAO contract or to the
OutLayer contract, and a call of a method whose name starts with `w_execute_`,
are refused: use the
kinds above for NEAR Intents.

### Statuses, and what to do in each

This set is exhaustive.

| `status` | Meaning | Do |
|---|---|---|
| `pending_approval` | The policy asks for approvers; `approval_id` names the vote | Tell the owner what waits and why, with `https://app.outlayer.ai/wallet/approvals/{approval_id}`. **An approval starts nothing**: after they voted, ask again under the same id with the same operation |
| `awaiting_signature` | Prepared: `message` is the wallet contract's request and `tee_half` the enclave's signature over it. Usage is counted | Check that `message` is your operation (below), sign your half, relay. `run` does it |
| `relayed` | The transaction `tx_hash` was sent; its outcome is not recorded | Read the operation with `get(id)`; the read settles it |
| `success` | The request executed on chain. For `swap` and `cross_chain_withdraw` it says the input reached 1Click; read again for `route_status` | Done |
| `failed` | The chain refused; `result` carries its failure | Read the failure. The same thing again is a new operation under a new id |
| `closed` | Ended with nothing sent, for `reason`: the vote was rejected or expired, an approval was not used within its 24 hours, a prepared request was not relayed within ten minutes, its transaction never reached the chain in that time, or the node refused it three times | Read `reason`. Start a new operation under a new id |

- The vote lives 24 hours, and an approval is good within them only: ask
  again under the same id before they end, or the operation is closed. Do not
  poll the operation in a tight loop while it waits: asking again is how you
  learn the vote ended.
- **Relay within ten minutes.** A prepared request that is not relayed within ten
  minutes is `closed`, and what it counted stays counted.
- Nothing is retried on your behalf. A failed or closed operation is over.
- **After a restart, read what is under way**: `GET /wallet/contract/v1/operations` (signed like the rest, empty body) lists your operations that are not over. Continue each by its status.
- The owner's webhook, when the policy names one, receives `operation_updated` on each change of status.

### Why you sign last, and what you check

The enclave returns a request it built and its half over that request. With
your half added, the wallet contract executes it. Your half must therefore
exist only for a request that is the operation you asked for. **Never sign a
`message` you have not checked.** A refused or waiting operation has no half
of yours anywhere, and that is the property.

`WalletContract.run` and `relay` do the check (`messageIsFor`) and throw a
`CustodyError` without signing when it fails. They verify the enclave's half
against `teePublicKey` (required in the options; from
`GET /wallet/v1/contract/key`) and sign one request under an id. Driving it
yourself, verify the enclave's half too, and check all of:

| Kind | `message` must be |
|---|---|
| every kind | `signer_id` is your wallet contract's account, and `promise.receiver_id` is not |
| `transfer` | `receiver_id` is `to`; the action is `transfer` with your `amount` |
| `call` | `receiver_id` is `to`; `function_name`, `deposit`, `gas` are yours; `args` are your `args_base64` |
| `intents_transfer` | `receiver_id` is `intents.near`; `function_name` is `mt_transfer`, `deposit` is `1`; the JSON in `args` is exactly `receiver_id` = `to`, `token_id` = `token`, `amount` = `amount` |
| `withdraw` | `receiver_id` is `intents.near`; `function_name` is `ft_withdraw`, `deposit` is `1`; the JSON in `args` is exactly `token` = your token without `nep141:`, `receiver_id` = `to`, `amount` = `amount` |
| `swap`, `cross_chain_withdraw` | `receiver_id` is `intents.near`; `function_name` is `mt_transfer`, `deposit` is `1`; the JSON in `args` has exactly `receiver_id`, `token_id`, `amount`, with your input token and amount, and a `receiver_id` that is not your account. That address is 1Click's deposit address: you cannot derive it, so read `quote` for what the route gives |

If the check fails, do not sign, do not relay, and tell the owner: the API
returned a request you did not ask for.

## 4. Swaps and withdrawals to another chain

- The state carries `quote`: `amount_in`, `amount_out`, `min_amount_out`,
  `deadline`, `time_estimate`. A swap whose quote guarantees less than your
  `min_out` is refused with `400 below_min_amount_out` and nothing is counted.
- **The result of a swap returns to the wallet contract**: the output arrives
  in its balance inside NEAR Intents, and so does a refund.
- The quote waits ten minutes for your input. Relay at once; an input that
  arrives later is returned by 1Click to the wallet contract.
- `success` means the input reached 1Click's deposit address. Read the
  operation again: `route_status` is 1Click's own status of the route.

## 5. The working account

Do from your OutLayer wallet, with your `wk_`, everything a wallet contract
does not: a confidential balance (`confidential.md`), a limit order
(`limit-orders.md`), a venue's trading account (the Hyperliquid and Polymarket
connector skills), payment checks, message and transaction signing. Asking the
wallet contract for one of these answers `400 bad_request`.

| You need | Do |
|---|---|
| Funds on the working account | An operation of the wallet contract to your wallet's own NEAR `address`: `transfer` for NEAR, `intents_transfer` for a token inside NEAR Intents |
| To return them | An ordinary operation of the working account to the wallet contract's account: `POST /wallet/v1/transfer` for NEAR, `POST /wallet/v1/intents/transfer` for a token |
| Gas | Keep NEAR on the working account: it pays for every relay. Ask the owner to fund it before it runs out (`funding-and-payment-keys.md`) |

Take out what the work needs and return the rest when it is done. What lies on
the working account is under the enclave's key within the policy, as for any
OutLayer wallet; what lies in the wallet contract is under two signatures.

**Limits are one set.** The policy's limits count your working account and
your wallet contract together. Usage is counted when a request is prepared
(`awaiting_signature`) and is not given back: not when you never relay it, and
not when it fails on chain. Ask only for what you will execute.

## 6. Without the SDK: the raw HTTP shape

The operation routes take **no** `Authorization` header. Each request carries
four headers:

| Header | Value |
|---|---|
| `x-agent-account` | your wallet contract's account |
| `x-agent-timestamp` | Unix seconds; accepted within 120 s of the server's clock |
| `x-agent-nonce` | 16 random bytes in lowercase hex; each request is taken once |
| `x-agent-signature` | 64 bytes in lowercase hex: your key's Ed25519 signature |

The signature is over the ASCII text `OUTLAYER_AGENT_REQUEST/V1` followed by
the Borsh encoding of: the account (string), the method in capitals (string),
the path as sent (string), the SHA-256 of the body as sent (32 bytes; of the
empty string for a `GET`), the timestamp (`u64`), the nonce (16 bytes). A Borsh
string is its length as a little-endian `u32`, then its bytes. A signature
covers one method, one path and one body: sign every request anew, with a new
nonce, and send the body byte for byte as you signed it.

| Route | Signed over | Body |
|---|---|---|
| `POST /wallet/contract/v1/operations` | `POST`, that path, the body | `{"id":"pay-1","op":{"kind":"transfer","to":"bob.near","amount":"1000000000000000000000000"}}` |
| `POST /wallet/contract/v1/operations/{id}/relay` | `POST`, that path, the body | `{"agent_half":"<128 hex>"}` |
| `GET /wallet/contract/v1/operations/{id}` | `GET`, that path, the empty string | none |

Your half is your key's signature over the bytes
`NEAR_WALLET_TWO_KEY/V1/AGENT` followed by the request's 32-byte hash,
`SHA3-256("NEAR_WALLET_CONTRACT/V1" ‖ borsh(message))`.

Python, with the `cryptography` package:

```python
import base64, hashlib, os, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

RAW = (serialization.Encoding.Raw, serialization.PublicFormat.Raw)

# --- setup: the one-time key, and opening what the owner left -----------------
def one_time_key():
    private = X25519PrivateKey.generate()
    return private, private.public_key().public_bytes(*RAW).hex()   # send the hex

def open_sealed(private, sealed_base64, wallet_id):
    sealed = base64.b64decode(sealed_base64)
    assert sealed[0] == 2 and len(sealed) == 81, "not a sealed agent key"
    ephemeral, ciphertext = sealed[1:33], sealed[33:]
    mine = private.public_key().public_bytes(*RAW)
    shared = private.exchange(X25519PublicKey.from_public_bytes(ephemeral))
    key = HKDF(hashes.SHA256(), 32, salt=None,
               info=b"outlayer:encryption-keys:v1:seal:kdf" + ephemeral + mine).derive(shared)
    aad = f"outlayer:wallet-contract:agent-key:{wallet_id}".encode()
    return AESGCM(key).decrypt(bytes(12), ciphertext, aad)          # the 32-byte seed

def agent_key(seed):
    key = Ed25519PrivateKey.from_private_bytes(seed)
    return key, key.public_key().public_bytes(*RAW).hex()           # compare with agent_public_key

# --- a signed request ----------------------------------------------------------
def bstr(s):                      # Borsh string / bytes: u32 LE length, then the bytes
    b = s if isinstance(s, bytes) else s.encode()
    return len(b).to_bytes(4, "little") + b

def request_bytes(account, method, path, body, timestamp, nonce):
    return (b"OUTLAYER_AGENT_REQUEST/V1" + bstr(account) + bstr(method) + bstr(path)
            + hashlib.sha256(body.encode()).digest()
            + timestamp.to_bytes(8, "little") + nonce)

def signed_headers(key, account, method, path, body=""):
    timestamp, nonce = int(time.time()), os.urandom(16)
    signature = key.sign(request_bytes(account, method, path, body, timestamp, nonce))
    return {"x-agent-account": account, "x-agent-timestamp": str(timestamp),
            "x-agent-nonce": nonce.hex(), "x-agent-signature": signature.hex()}

# --- the agent's half ----------------------------------------------------------
def message_hash(m):              # SHA3-256("NEAR_WALLET_CONTRACT/V1" ‖ borsh(message))
    a = m["promise"]["action"]
    if a["action"] == "transfer":
        action = b"\x03" + int(a["amount"]).to_bytes(16, "little")
    else:
        action = (b"\x02" + bstr(a["function_name"]) + bstr(base64.b64decode(a["args"]))
                  + int(a["deposit"]).to_bytes(16, "little") + int(a["gas"]).to_bytes(8, "little")
                  + bytes(8))
    borsh = (b"\x00" + bstr(m["chain_id"]) + bstr(m["signer_id"])
             + m["nonce"].to_bytes(4, "little") + int(m["created_at_ns"]).to_bytes(8, "little")
             + (600).to_bytes(4, "little") + bytes(4) + (1).to_bytes(4, "little")
             + bstr(m["promise"]["receiver_id"]) + b"\x00" + (1).to_bytes(4, "little") + action)
    return hashlib.sha3_256(b"NEAR_WALLET_CONTRACT/V1" + borsh).digest()

def agent_half(key, message):     # call ONLY after checking the message is your operation
    return key.sign(b"NEAR_WALLET_TWO_KEY/V1/AGENT" + message_hash(message)).hex()
```

One operation, start to end:

```python
import json, requests
BASE, PATH = "https://api.outlayer.ai", "/wallet/contract/v1/operations"

body = json.dumps({"id": "pay-1", "op": {"kind": "transfer", "to": "bob.near",
                                         "amount": "1000000000000000000000000"}})
state = requests.post(BASE + PATH, data=body, headers={
    **signed_headers(key, account, "POST", PATH, body), "content-type": "application/json"}).json()

if state.get("status") == "awaiting_signature":
    message = state["message"]
    # CHECK the message is the operation above (section 3) before the next line.
    relay_path = f"{PATH}/pay-1/relay"
    relay_body = json.dumps({"agent_half": agent_half(key, message)})
    state = requests.post(BASE + relay_path, data=relay_body, headers={
        **signed_headers(key, account, "POST", relay_path, relay_body),
        "content-type": "application/json"}).json()

# Later, or after `relayed`:
get_path = f"{PATH}/pay-1"
state = requests.get(BASE + get_path, headers=signed_headers(key, account, "GET", get_path)).json()
```

The answer of all three routes has the same shape: `id`, `status`,
`request_hash` always; `approval_id` while `pending_approval`; `message` and
`tee_half` while `awaiting_signature`; `tx_hash` from `relayed` on; `result`
on `success` and `failed`; `reason` on `closed`; `quote` and `route_status`
for a route through 1Click. `request_hash` is the hash of your operation, what
approvers sign; it is not the hash of `message`.

## 7. Refusals

A refusal of `POST …/operations` creates no operation under the id. With the
SDK a refusal is a `CustodyError` with `code` and `status`; one with neither
is the client's own check, and nothing was signed.

| HTTP | `error` | Retry? | Do |
|---|---|---|---|
| 400 | `bad_request` | no | Fix the request: a header, the body, the `id`, or a kind a wallet contract does not do (use the working account). Also: the wallet has no owner |
| 400 | `below_min_amount_out` | later, or with a lower `min_out` | The quote guarantees less than `min_out`; the body carries `min_amount_out` and `quoted_min_amount_out`. Nothing was counted |
| 400 | `upstream_rejected`, `no_liquidity`, `unsupported_token`, `unsupported_chain` | no | What 1Click answered to the quote. Change the route |
| 401 | `invalid_signature` | after fixing | The request is not signed by the key in your wallet contract's pair, the timestamp is outside 120 s, or the account is no wallet's wallet contract. On `relay`: `agent_half` is not your signature over this operation's request. Check the clock, the account, the signed bytes |
| 403 | `policy_denied` | no | The policy refuses it, or the wallet has no policy stored by its owner; `message` says why. Tell the owner; do not split the operation or send it another way |
| 403 | `wallet_frozen` | no | The owner froze the wallet. Tell the owner |
| 403 | `wallet_contract_refused` | no | The enclave does not serve the account as your wallet contract: its build is not an approved one, it has an extension, signatures are switched off, or its pair is not this wallet's; `message` says which. Tell the owner |
| 404 | `request_not_found` | no | No operation under this id (`GET`, `relay`), or no setup was opened (`GET /wallet/v1/contract/setup`) |
| 409 | `conflict` | yes | The nonce was taken: sign again with a new nonce. Or the `id` was used for another content: take a new id |
| 409 | `wallet_busy` | yes, later | Another operation is using this wallet; one runs at a time |
| 409 | `conflict` (votes) | later | 20 operations already wait for the approvers. Wait for a vote to end |
| 400 | `insufficient_balance` | after funding | A swap or a withdrawal to another chain sends more than the wallet contract holds inside NEAR Intents |
| 429 | `rate_limited` | later | Too many quotes for this wallet |
| 429 | `operation_limit_reached` | after `Retry-After` | The wallet's counted ceiling on operations is reached |

## 8. Running a program as your wallet contract's account

By default a program you call runs under your wallet's own name: the guest
sees `NEAR_SENDER_ID` = your wallet's NEAR account. Ask for the wallet
contract's account per call:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-Payment-Key: $PAYMENT_KEY" \
  -d '{"input":{"operation":"status"}, "use_bound_identity": true}' \
  "https://api.outlayer.ai/call/<owner>/<project>"
```

- The guest's `NEAR_SENDER_ID` is your wallet contract's account. Billing does
  not follow the name: `NEAR_USER_ACCOUNT_ID` stays the account that paid.
- The wallet is taken from the payment key you sent. Before the program is
  given the name, the enclave confirms from the chain that your wallet is the
  wallet of that wallet contract; a job that fails this is refused, never run
  under your own name instead.
- `request_execution` on chain takes the same flag in `params`
  (`{"use_bound_identity": true}`). There the wallet is matched by the caller
  of the transaction, so send it from your wallet with `POST /wallet/v1/call`.
- `409 no_bound_identity` on `/call`, before anything is priced or charged:
  `terminal: true` — the payment key names no wallet; `terminal: false` — the
  wallet has no wallet contract. Drop the flag, or finish the setup above.
- **The flag changes a name.** It gives the program no signature of the wallet
  contract; a move out of it is an operation of section 3.
