---
name: agent-custody
description: Multi-chain custody wallet for AI agents with cross-chain swaps and payment checks via NEAR Intents. Register a gasless wallet, swap tokens across 20+ chains, send/receive on NEAR, Ethereum, Bitcoin, Solana, and more. Use when an agent needs crypto operations - transfers, swaps, payment checks, contract calls, or cross-chain movements.
metadata:
  api:
    base_url: https://api.outlayer.fastnear.com
    version: v1
    auth: Bearer token
---

# OutLayer Agent Custody Wallet

Multi-chain custody wallet for AI agents. Supports NEAR transfers, smart contract calls, and cross-chain swaps via NEAR Intents protocol - no gas tokens needed on destination chains.

## When to Use This Skill

| You need... | Action |
|-------------|--------|
| A crypto wallet for your agent | Register via `POST /register` - includes 100 free WASI calls |
| Run a WASI module for free | Use `POST /call/{owner}/{project}` with `Authorization: Bearer wk_...` (trial quota — primary `/register` wallets only) |
| Check remaining free calls | Use `GET /trial/status` |
| Upgrade to paid execution | Use `POST /wallet/v1/create-payment-key` (USDC or NEAR) |
| Send NEAR to someone | Use `POST /wallet/v1/transfer` with `chain: "near"` |
| Send FT tokens (USDT, wNEAR) to someone | Use `POST /wallet/v1/call` with `ft_transfer` (see FT transfer section) |
| Swap tokens (e.g. wNEAR to USDT) | Use `POST /wallet/v1/intents/swap` - gasless swap via 1Click. Tokens must be in intents balance first |
| Preview swap rate before committing | Use `POST /wallet/v1/intents/swap/quote` - read-only, no gas spent |
| List available tokens for swaps | Use `GET /wallet/v1/tokens` - returns ~200 tokens across 20+ chains |
| Withdraw native NEAR (gasless) | Use `POST /wallet/v1/intents/withdraw` with `chain: "near"` and `token: "near"` (default). Unwraps your wNEAR → native NEAR; receiver needs **no** storage. Recipient account must already exist (or be a 64-char implicit account) |
| Send tokens cross-chain (gasless) | Use `POST /wallet/v1/intents/withdraw` with `chain` param - gasless. For NEAR delivering wNEAR (`token: "nep141:wrap.near"`): receiver must have storage (use `/storage-deposit` first). For Solana: use `chain: "solana"` |
| Register token storage | Use `POST /wallet/v1/storage-deposit` - needed before withdrawing to accounts without storage |
| Move FT from wallet into Intents | Use `POST /wallet/v1/intents/deposit` - on-chain, needs gas |
| Call a NEAR smart contract | Use `POST /wallet/v1/call` - on-chain, needs gas |
| Check your balance | Use `GET /wallet/v1/balance?chain=near` or `&token=usdt.tether-token.near` |
| Check intents deposit balance | Use `GET /wallet/v1/balance?token=wrap.near&source=intents` |
| Get your address on any chain | Use `GET /wallet/v1/address?chain=ethereum` |
| Delete the wallet | Use `POST /wallet/v1/delete` - deletes on-chain account, sends NEAR to beneficiary. Wallet must have NEAR balance |
| Ask user to fund your wallet | Generate a fund link (see below) or share your NEAR address |
| Pay another agent (write a check) | `POST /wallet/v1/payment-check/create` - get `check_key` to send |
| Pay multiple agents at once | `POST /wallet/v1/payment-check/batch-create` - up to 10 checks |
| Receive payment from another agent | `POST /wallet/v1/payment-check/claim` with the `check_key` you received |
| Claim only part of a check | `POST /wallet/v1/payment-check/claim` with `amount` param |
| See if your check was cashed | `GET /wallet/v1/payment-check/status?check_id={id}` |
| Take back an unclaimed check | `POST /wallet/v1/payment-check/reclaim` (supports partial via `amount`) |
| Check a check's balance by key | `POST /wallet/v1/payment-check/peek` with `check_key` |
| Deposit from another chain (Solana, Ethereum, etc.) | `POST /wallet/v1/deposit-intent` with `source_asset` (defuse asset id from `GET /wallet/v1/tokens`) - get a deposit address, user sends tokens, 1Click bridges to intents |
| Check cross-chain deposit status | `GET /wallet/v1/deposit-status?id={intent_id}` - poll until `success` |
| Withdraw to another chain | `POST /wallet/v1/intents/withdraw` with `chain` param (e.g. `"solana"`, `"ethereum"`) - gasless |
| List cross-chain deposits | `GET /wallet/v1/deposits` |
| Move funds into the private (confidential) shard | `POST /wallet/v1/confidential/deposit` with `{ token, amount }` — SHIELD from public intents balance; **publicly links your wallet on chain** (entry reveal) |
| Move funds back from private to public | `POST /wallet/v1/confidential/unshield` with `{ token, amount }` — reverse SHIELD (exit reveal) |
| Fund private balance **without** linking your wallet | `POST /wallet/v1/confidential/deposit-intent` with `{ source_asset, amount }` → returns a bridge address on the source chain; send funds there. Your NEAR wallet never touches the public chain |
| Withdraw private balance to an external chain (no link) | `POST /wallet/v1/confidential/withdraw` with `{ chain, to, amount, token }` — gasless; your wallet stays off the public chain. **`chain="near"` is rejected (400)** — use unshield instead |
| Preview a confidential withdraw | `POST /wallet/v1/confidential/withdraw/dry-run` — same body, no commit |
| Private transfer to another wallet's private balance | `POST /wallet/v1/confidential/transfer` with `{ to, amount, token }` — no public-chain trace |
| Swap tokens privately | `POST /wallet/v1/confidential/swap` with `{ token_in, token_out, amount_in, min_amount_out? }` — distinct assets, no public-chain trace |
| Preview a confidential swap | `POST /wallet/v1/confidential/swap/quote` |
| Read your private (confidential) balance | `GET /wallet/v1/confidential/balance?token={defuse_id}` or omit `token` for all |
| Authenticate to an external service | `POST /wallet/v1/sign-message` - NEP-413 signed message for login/auth |
| Let the user set spending limits | Share the `handoff_url` from registration |
| Create wallets for users (no per-user keys) | Use deterministic registration: `POST /register` with NEAR signature fields |
| Authenticate with NEAR key (no stored secrets) | Use `Bearer near:<base64url>` header instead of `Bearer wk_...` |
| Use your OWN per-customer master (no shared TEE) | Tell the user to deploy a sovereign vault — see "Sovereign Vaults" section |
| Create sub-agent (custody wallet) | `PUT /wallet/v1/api-key` with Bearer auth + `{seed, key_hash}` — see "Create Sub-Agents" section |
| Create sub-agent (external NEAR key) | Derive `wk_` key, sign with your NEAR key, register hash via `PUT /wallet/v1/api-key` |
| Revoke a sub-agent's key | `DELETE /wallet/v1/api-key/{key_hash}` (last key protected) |

## Configuration

- **API Base URL**: `https://api.outlayer.fastnear.com`
- **Dashboard**: `https://outlayer.fastnear.com`
- **Network**: mainnet

## Gas Model

Every wallet operation falls into one of three categories:

| Category | Who pays gas | NEAR on wallet needed? | Endpoints |
|----------|-------------|----------------------|-----------|
| **On-chain** | Agent's wallet | Yes (~0.001 NEAR/tx) | `/call`, `/transfer`, `/delete`, `/intents/deposit`, `/intents/ft-withdraw`, `/storage-deposit` |
| **Gasless** | Solver relay | No | `/intents/withdraw`, `/intents/swap`, `/payment-check/*` |
| **Cross-chain** | 1Click solver | No | `/deposit-intent`, `/intents/withdraw` (chain: solana/ethereum/etc.) |
| **Confidential** | 1Click solver (settles on private shard `intents.far`) | No | `/confidential/deposit`, `/confidential/unshield`, `/confidential/withdraw`, `/confidential/transfer`, `/confidential/swap`, `/confidential/deposit-intent` — see "Confidential Intents" section |
| **Read / no tx** | Nobody | No | `/balance`, `/address`, `/tokens`, `/requests`, `/sign-message`, `/deposit-status`, `/deposits`, `/confidential/balance` |

**On-chain** - wallet signs a NEAR transaction and broadcasts it. The wallet's implicit account must hold NEAR for gas.

**Gasless** - wallet signs a NEP-413 message (off-chain). The solver relay executes the intent and pays gas. Works even with zero NEAR balance.

### `/intents/withdraw` vs `/intents/ft-withdraw`

Same result, different execution:
- `/intents/withdraw` - **gasless**. Signs NEP-413 intent, solver relay executes. Use this by default.
  - **For `chain=near`, the `token` field picks what the recipient gets:** omitted / `near` / `native` (default) delivers **native NEAR** — intents.near unwraps your wNEAR (`native_withdraw` intent), and the receiver needs **no** storage. `nep141:wrap.near` (or any `nep141:<token>`) delivers that NEP-141 instead, and the receiver **must** have storage registered (use `/storage-deposit` first).
  - **Native-NEAR caveat:** the recipient account must already exist (or be a 64-char implicit account). Withdrawing native NEAR to a non-existent named account is rejected up front (the unwrapped wNEAR would otherwise be burned).
- `/intents/ft-withdraw` - **on-chain**. Calls `ft_withdraw` on `intents.near`. Needs NEAR for gas. NEP-141 only (no native NEAR).

### `/storage-deposit` - register token storage

Before withdrawing tokens to an account, that account must have storage registered on the token contract. Use this endpoint to register storage.

```bash
curl -X POST -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"token":"wrap.near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/storage-deposit"
```

Idempotent - returns `already_registered: true` if storage already exists. Optional `account_id` field to register storage for a different account (default = wallet's own address). Costs ~0.00125 NEAR.

---

## 1. Register Wallet

Call the registration endpoint. No auth required.

```bash
curl -s -X POST https://api.outlayer.fastnear.com/register
```

Response:
```json
{
  "api_key": "wk_15807dbda492636df5280629d7617c3ea80f915ba960389b621e420ca275e545",
  "wallet_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "near_account_id": "36842e2f73d0b7b2f2af6e0d94a7a997398c2c09d9cf09ca3fa23b5426fccf88",
  "handoff_url": "https://outlayer.fastnear.com/wallet?key=wk_...",
  "trial": {
    "calls_remaining": 100,
    "expires_at": "2026-04-10T00:00:00Z",
    "limits": { "max_instructions": 100000000, "max_execution_seconds": 30, "max_memory_mb": 64 }
  }
}
```

**Save `api_key` securely** - it is shown only once. All subsequent requests require it.

**Important:** Persist the `api_key` to a file or session state immediately after registration. If you lose the key, recovery depends on the user having set a policy (see Key Recovery below).

The `near_account_id` is the NEAR implicit account (hex public key). Cross-chain transfers (Ethereum, Bitcoin, Solana, etc.) are handled via NEAR Intents - no gas tokens needed on other chains.

### Deterministic Wallets (NEAR Signature Auth)

For servers, bots, and agents **that have their own NEAR private key**: register deterministic wallets with zero per-user key storage. The wallet_id is derived from `(account_id, seed, vault_or_none)` — same inputs always produce the same wallet, and different vault scopes legitimately mint independent sub-wallets.

**Seed format:** `[a-zA-Z0-9._-]`, 1-256 characters. No NUL byte, no `:`, no whitespace, no Unicode. SHA-256 hex strings (typical seed source) fit naturally.

**Requires:** Access to a NEAR ed25519 private key (in env, in a file, etc.). This is NOT the custody wallet key — it's the integrator's own NEAR account key.

**Use cases:** Telegram bots (one NEAR key in env, thousands of user wallets), web apps with OAuth login, parent agents creating sub-agents.

**Custody wallets** (created via `POST /register` with a `wk_` key) don't need NEAR signatures for sub-agents. Use `PUT /wallet/v1/api-key` with your Bearer token — see "Create Sub-Agents" section below.

#### Signature format (IMPORTANT)

All signatures in deterministic wallet endpoints are **raw ed25519 signatures**, NOT NEP-413.

- Sign the **raw message string bytes** with your NEAR ed25519 private key
- Encode the 64-byte signature as **base58** (no prefix)
- `POST /wallet/v1/sign-message` returns NEP-413 signatures — these are a **different format** and will NOT work here
- `pubkey` field uses the `ed25519:` prefix: `"ed25519:<base58_public_key>"`
- `signature` field has NO prefix: just the base58-encoded 64-byte signature

```python
# Python example (nacl library)
from nacl.signing import SigningKey
import base58

key = SigningKey(secret_key_bytes)  # 32 bytes
message = "register:user-42:1712000000"
sig = key.sign(message.encode()).signature  # 64 bytes
signature_b58 = base58.b58encode(sig).decode()  # no prefix
pubkey = f"ed25519:{base58.b58encode(key.verify_key.encode()).decode()}"
```

#### Register a deterministic wallet

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{
    "account_id": "my-bot.near",
    "seed": "user-42",
    "pubkey": "ed25519:<base58_public_key>",
    "message": "register:user-42:1712000000",
    "signature": "<base58_signature_no_prefix>"
  }' \
  "https://api.outlayer.fastnear.com/register"
```

Signed message format: `"register:<seed>:<unix_timestamp>"`. Timestamp window: **±5 minutes**.

Response:
```json
{
  "wallet_id": "uuid-string",
  "near_account_id": "hex64-implicit-account",
  "trial": { "calls_remaining": 100, "expires_at": "...", "limits": {...} }
}
```

No `api_key` in response — not needed. Idempotent: calling again returns the same wallet.

#### Authenticate with Bearer near:

All wallet endpoints accept `Bearer near:<base64url>` instead of `Bearer wk_...`:

```bash
# Build token: base64url-encode a JSON object with signature
TOKEN=$(echo -n '{"account_id":"my-bot.near","seed":"user-42","pubkey":"ed25519:...","timestamp":1712000000,"signature":"<base58_no_prefix>"}' | base64url)

curl -s -H "Authorization: Bearer near:${TOKEN}" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near"
```

The signed message for Bearer auth is `"auth:<seed>:<timestamp>"` (±30 second window).

#### Register delegate key for sub-agents

Parent agent (with NEAR key) derives a `wk_` key and registers its SHA-256 hash. Sub-agent uses simple `Bearer wk_...` — no crypto needed.

```bash
# Parent: derive key = "wk_" + hex(HMAC-SHA256(near_private_key, "sub-task:0"))
# Parent: compute key_hash = SHA256(key)

curl -s -X PUT -H "Content-Type: application/json" \
  -d '{
    "account_id": "parent-agent.near",
    "seed": "sub-task",
    "key_hash": "sha256hex64chars...",
    "pubkey": "ed25519:<base58>",
    "message": "api-key:sub-task:1712000000",
    "signature": "<base58_no_prefix>"
  }' \
  "https://api.outlayer.fastnear.com/wallet/v1/api-key"
```

Signed message format: `"api-key:<seed>:<unix_timestamp>"`. Timestamp window: **±5 minutes**.

Response: `{"wallet_id": "...", "near_account_id": "..."}`

Creates wallet if it doesn't exist. Idempotent.

#### Revoke delegate key

```bash
curl -s -X DELETE -H "Authorization: Bearer near:${TOKEN}" \
  "https://api.outlayer.fastnear.com/wallet/v1/api-key/${KEY_HASH}"
```

Returns 409 Conflict if it's the last active key for the wallet.

#### Key rotation

No endpoint needed. Add a new key to your NEAR account, start signing with it. Remove old key — access revoked within 60 seconds (cache TTL). Wallet identity is tied to `(account_id, seed, vault_or_none)`, not to which key signs.

## Sovereign Vaults — Per-Customer Master Keys

> **TL;DR for the agent**: a vault is just an on-chain account that holds the *master secret* for a customer. Once the user has deployed one, you call **`POST /register`** with `{"vault_id": "<vault_addr>"}` and get back a `wk_...` API key — use it exactly like any other custody wallet. You can call this **N times** to get N independent wallets under the same vault (just like default-master `/register` can be called N times). **Don't** use "Create Sub-Agents" for this; that's a different flow for splitting one wk_ into deterministic child keys.

### What a vault is, in one paragraph

By default every custody wallet's keys derive from OutLayer's shared TEE master. A **sovereign vault** replaces that shared master with a per-customer one derived via NEAR's MPC network — recoverable by the customer if OutLayer ever shuts down. The vault is just a small on-chain contract that anchors a per-customer master in keystore-TEE memory; it does **not** issue API keys itself. API keys are always minted through `/register`, with or without a vault binding. The architecture is symmetric:

| | Default master | Per-vault master |
|---|---|---|
| Wallets per master | ∞ | ∞ |
| How to mint | `POST /register` | `POST /register {"vault_id": "..."}` |
| Each wallet | own `wk_`, own `wallet_id`, own derived address | same, plus `vault_id` in DB |
| Recovery if OutLayer stops | none | 7-day DAO cessation OR 24h-30d unilateral exit |

### Step 1 — User deploys the vault (off your hands)

The agent **cannot** deploy a vault — it requires an on-chain transaction signed by the user's NEAR account. When the user asks how, point them to either:

- **Dashboard**: <https://outlayer.fastnear.com/vault>
- **CLI**: `outlayer vault init` (after `outlayer login`)

Either flow ends with the vault registered on chain (`is_vault_verified == true` on keystore-DAO). The vault account id (e.g. `vault.alice.near`, name is user-chosen) is what you'll pass to `/register`.

### Step 2 — Mint custody wallets under the vault

```bash
curl -s -X POST "https://api.outlayer.fastnear.com/register" \
  -H "Content-Type: application/json" \
  -d '{"vault_id": "vault.alice.near"}'
```

Response is the standard `/register` shape — `api_key`, `wallet_id`, `near_account_id`, trial quota. The `near_account_id` derives from the per-vault master (not OutLayer's shared master), and `GET /wallet/v1/address` responses for this key include `"vault_id"`. Call this endpoint multiple times to get **independent wallets under the same vault** — each has its own `wallet_id`, `wk_`, and address (different `wallet_id` salt on the same per-vault master).

### Step 3 — Use the wk_ normally

Set `Authorization: Bearer wk_...` on every wallet endpoint as usual. No `X-Customer-Vault` header is needed (the coordinator binds the vault from the DB row, not from a request header — a spoofed header is silently ignored).

### Cross-vault and vault-vs-default isolation

A single user can mix vault-bound and default-master wallets:

- A wallet minted under `vault_id=A` only sees `vault_id=A` in its derived state. Its derived address has zero correlation with any wallet under `vault_id=B` or with the default master.
- A wallet minted via `POST /register` with NO `vault_id` stays on the default master forever; its `GET /address` response omits `vault_id`.
- Two `wk_`s from different vaults can be used concurrently from the same client — the coordinator routes each based on its own DB binding.

### What this is NOT

- **Not "Create Sub-Agents"** — that flow (further below) splits a single parent `wk_` into deterministic child keys using `PUT /wallet/v1/api-key`. Sub-agent wallets do inherit the parent's vault binding, but the use case is "delegate a slice of an existing wallet with reproducible IDs", not "get a fresh wallet under a vault". Sub-agents also don't get a trial quota (only primary `/register` wallets do).
- **Not deterministic registration** — the `POST /register` with NEAR-signature fields (`account_id`, `seed`, `pubkey`, `message`, `signature`) does **not** accept `vault_id`. Only the random-wallet path of `/register` supports the vault binding.

### Same parent, multiple vaults

Under the current schema each `(account_id, seed, vault_id)` tuple maps to a **distinct wallet_id**. A parent that runs both a custody vault and a treasury vault can use the same `seed` for both:

- `PUT /wallet/v1/api-key {seed: "user-42", vault_id: "vault.custody.parent.near", ...}` → wk_A under custody vault
- `PUT /wallet/v1/api-key {seed: "user-42", vault_id: "vault.treasury.parent.near", ...}` → wk_B under treasury vault (DIFFERENT wallet_id, DIFFERENT on-chain address)

Both succeed (no rebind refusal). The two sub-wallets are cryptographically isolated — funds at one are inaccessible from the other.

## Create Sub-Agents

### From a custody wallet (Bearer wk_...)

Pass your `Bearer wk_...` header to `PUT /wallet/v1/api-key` — no NEAR signatures or crypto needed. The coordinator derives a sub-wallet from your wallet_id + seed.

```python
import hashlib, requests

API = "https://api.outlayer.fastnear.com"
PARENT_KEY = "wk_..."  # parent's custody wallet key
HEADERS = {"Authorization": f"Bearer {PARENT_KEY}", "Content-Type": "application/json"}

# 1. Choose a seed for the sub-agent (deterministic — same seed = same wallet)
seed = "sub-agent-task-42"

# 2. Derive a wk_ key for the sub-agent
sub_key = f"wk_{hashlib.sha256(f'{seed}:0:{PARENT_KEY}'.encode()).hexdigest()}"
key_hash = hashlib.sha256(sub_key.encode()).hexdigest()

# 3. Register the key hash (Bearer auth — no NEAR signatures needed)
#    Creates sub-wallet if needed, idempotent
resp = requests.put(f"{API}/wallet/v1/api-key",
    headers=HEADERS,
    json={"seed": seed, "key_hash": key_hash},
).json()
print(f"Sub-agent wallet: {resp['near_account_id']}")

# 4. Hand the key to the sub-agent — it uses simple Bearer auth
sub_agent_headers = {"Authorization": f"Bearer {sub_key}"}
balance = requests.get(f"{API}/wallet/v1/balance?chain=near",
    headers=sub_agent_headers).json()
```

Same `(parent_wallet_id, seed, vault_scope)` always produces the same sub-wallet — call again to re-derive the key without storage. Different vault scopes under the same `(parent_wallet_id, seed)` mint **independent sub-wallets** with their own addresses (this is intentional — each scope is its own identity).

**Sub-agents do not get trial quota.** Trial is reserved for primary `/register` wallets. A sub-agent calling `/call/{owner}/{project}` without `X-Payment-Key` will see `TrialQuotaExhausted`. To run WASI from a sub-agent, attach a payment key.

No `sign-message`, no NEAR signatures, no crypto libraries. Just derive a key, register its hash, hand it to the sub-agent.

### From an external NEAR account

If you have your own NEAR private key (bot, server), sign directly without `sign-message`:

```python
# Sign "api-key:<seed>:<timestamp>" with your NEAR ed25519 key
# See "Deterministic Wallets" section for details
```

### Simple alternative (no parent→child link)

If you don't need deterministic wallet IDs, just register independent wallets:

```bash
curl -s -X POST https://api.outlayer.fastnear.com/register
# Give the new api_key to the sub-agent — independent wallet, no link to parent
```

---

## 2. Free Trial: Run WASI Without Payment

Trial is granted to **primary wallets only** — those minted via `POST /register` (random or deterministic). Sub-agents created via `PUT /wallet/v1/api-key` and stateless `Bearer near:` callers do **not** receive a trial quota; they must use `X-Payment-Key` (paid path) or be granted a primary wallet's `wk_` to access trial.

A primary wallet gets **100 free WASI execution calls** (30-day expiry).

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"input": "hello"}' \
  "https://api.outlayer.fastnear.com/call/{owner}/{project}"
```

**Trial limits:** 100 calls, 30-day expiry, 10 req/min, 3s cooldown, 30s execution, 100M instructions, 64MB RAM.

**Check remaining quota:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/trial/status"
```

When quota is exhausted (HTTP 402), upgrade to a payment key (see below).

## 3. Request Funding from User

NEAR balance is needed for on-chain operations (`/call`, `/transfer`). Intents balance is needed for swaps, payment checks, and cross-chain withdrawals (all gasless).

**Fund link format:**
```
https://outlayer.fastnear.com/wallet/fund?to={near_account_id}&amount={amount}&token={token}&msg={message}&dest=intents
```

| Param | Required | Description |
|-------|----------|-------------|
| `to` | yes | Agent's NEAR account (the `near_account_id` from registration) |
| `amount` | yes | Human-readable amount (e.g. `1` for 1 NEAR, `10` for 10 USDT) |
| `token` | no | `near` (default) or FT contract ID (e.g. `usdt.tether-token.near`) |
| `msg` | no | Message to display to the user (URL-encoded) |
| `dest` | no | `intents` - deposit directly to agent's Intents balance (FT tokens only) |

When `dest=intents`, the user's tokens go directly to the agent's Intents balance via `ft_transfer_call` to `intents.near`. This is the preferred option when the agent needs funds for swaps, payment checks, or cross-chain withdrawals - no extra deposit step needed.

The page includes a toggle so the user can switch between direct transfer and Intents deposit. The page automatically handles FT storage deposits.

**Example - request 10 USDC to Intents balance:**
```
https://outlayer.fastnear.com/wallet/fund?to={near_account_id}&amount=10&token=17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1&msg=Fund+my+trading+balance&dest=intents
```

## 4. Request Policy from User (Optional)

A policy defines spending limits, address whitelists, and multisig rules.

**Available policy types:** spending limits, address whitelist/blacklist, allowed tokens, transaction types, time restrictions, rate limits, multisig approval, authorized API keys, webhooks.

**Message to user:**
> Please configure a security policy for your wallet:
> https://outlayer.fastnear.com/wallet?key={api_key}

## Key Recovery

If you lost your wallet API key and the user previously set a policy, the key is saved in their browser.

**Message to user:**
> I lost access to your wallet API key. Please go to: https://outlayer.fastnear.com/wallet/manage
> Find your wallet, click **show** next to the API Key, then copy and paste it here.
> The key looks like: `wk_15807d...e545`

After receiving the key, verify: `GET /wallet/v1/balance?chain=near` with the key.

If recovery is not possible (no policy set, browser data cleared), register a new wallet with `POST /register`.

## 5. Upgrade to Paid (Payment Key)

When trial quota runs out, create a payment key. Wallet must have USDC or NEAR balance.

### Option A: Pay with USDC
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"initial_deposit_usdc": "2.00"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/create-payment-key"
```

### Option B: Pay with NEAR
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"initial_deposit_near": "1.0"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/create-payment-key"
```

Response includes `payment_key` - save securely. Use via `X-Payment-Key` header for paid WASI calls.

---

## Wallet Operations

### Check balance
```bash
# Native NEAR (for gas: /call, /transfer)
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near"

# FT token balance on wallet (e.g. USDT)
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near&token=usdt.tether-token.near"

# Intents balance (for swaps, payment checks, cross-chain withdrawals)
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?token=wrap.near&source=intents"

# Intents balance for USDC
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?token=17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1&source=intents"
```

Response: `{"balance": "1000000000000000000000000", "token": "near", "account_id": "36842e..."}`

**Two balances matter:**
- **Wallet balance** (`chain=near`) - direct FT holdings on the NEAR account. Needed for `ft_transfer`, contract calls.
- **Intents balance** (`source=intents`) - tokens deposited into `intents.near`. Needed for swaps (`/intents/swap`), payment checks, and cross-chain withdrawals (`/intents/withdraw`). Use `POST /wallet/v1/intents/deposit` (on-chain, needs gas) to move tokens from wallet to intents, or request funds with `dest=intents` to skip this step.

### Get address (for other chains)
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/address?chain=ethereum"
```
Supported chains: `near` only. Multi-chain address derivation (ethereum, solana, bitcoin, etc.) is not yet available in wallet v1. For cross-chain operations, use `/deposit-intent` and `/intents/withdraw` with `chain` param instead — these work without a derived address.

### Transfer NEAR
**Before calling:** check NEAR balance covers transfer amount + gas (~0.001 NEAR).

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"chain":"near","to":"bob.near","amount":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/transfer"
```

The recipient field is `to`. (An older `receiver_id` alias is accepted by the
API for backward compatibility but should not be used in new code; sending
both fields in the same body is rejected with a 400.)

### Transfer FT tokens (USDT, wNEAR, etc.)

Use the generic contract call endpoint with `ft_transfer`. Requires 1 yoctoNEAR deposit. Receiver must have storage registered on the token contract.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"receiver_id":"usdt.tether-token.near","method_name":"ft_transfer","args":{"receiver_id":"bob.near","amount":"1000000"},"gas":"30000000000000","deposit":"1"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/call"
```

### Call a contract
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"receiver_id":"wrap.near","method_name":"near_deposit","args":{},"deposit":"10000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/call"
```

Response: `{"request_id": "uuid", "status": "success", "tx_hash": "...", "result": ...}`

### Delete wallet
**WARNING:** FT tokens and Intents balances are lost. Transfer all assets first. Wallet must have NEAR balance (for gas to execute the on-chain delete).

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"beneficiary":"receiver.near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/delete"
```

### Sign a message (NEP-413 - for external auth)

Sign an arbitrary message using the wallet's NEAR private key (NEP-413 standard). Use this to authenticate your agent to external services that verify NEAR signatures.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"message":"Login to example.com at 2026-03-14T12:00:00Z","recipient":"example.com"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/sign-message"
```

Response:

```json
{
  "account_id": "aabbccdd11223344...",
  "public_key": "ed25519:...",
  "signature": "ed25519:...",
  "signature_base64": "base64-encoded-signature",
  "nonce": "base64-encoded-32-bytes"
}
```

**Parameters:**

| Field | Required | Description |
|-------|----------|-------------|
| `message` | Yes | Text to sign (max 10000 bytes) |
| `recipient` | Yes (NEP-413) | Service that will verify (1-128 chars). Ignored for `format: "raw"` |
| `nonce` | No | Base64-encoded 32 bytes. Auto-generated if omitted. Not used for `format: "raw"` |
| `format` | No | `"nep413"` (default) or `"raw"`. Raw signs message bytes directly with ed25519 |

**NEP-413 (default):** The response includes both `signature` (ed25519 base58, NEAR-native format) and `signature_base64` (base64-encoded raw bytes). Use `signature_base64` for HTTP auth headers and JWT.

**Raw (`format: "raw"`):** Signs the raw message bytes with the wallet's ed25519 key — a plain `ed25519.sign(message_bytes)`, no NEP-413 wrapping. Returns `signature` as base58 (no prefix). Use for custom authentication protocols, off-chain proofs, or any integration that needs a plain ed25519 signature from the wallet's key.

```bash
curl -s -X POST -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"message":"any payload to sign","recipient":"_","format":"raw"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/sign-message"
# Response: {"signature": "<base58_no_prefix>", "public_key": "ed25519:...", ...}
```

**Note:** `recipient` is required by the schema but ignored for raw format — pass any non-empty string.

**Verification (external service, NEP-413 only):**

The NEP-413 signature verifier computes:
1. Borsh-serialize: `tag(2147484061) + message + nonce(32 bytes) + recipient + callback_url(None)`
2. SHA-256 hash the serialized payload
3. Verify ed25519 signature against the `public_key`
4. For implicit accounts: `account_id == hex(public_key_bytes)` - no RPC needed

---

## Cross-Chain Swaps (NEAR Intents)

Swap tokens across 20+ blockchains using NEAR Intents protocol. All swaps are atomic - either both sides complete or nothing happens.

### Token ID Format (CRITICAL)

| Endpoint | Format | Example |
|----------|--------|---------|
| `/intents/swap` and `/intents/swap/quote` | Defuse asset ID with prefix | `nep141:wrap.near` |
| `/intents/deposit` | Plain NEAR contract ID | `wrap.near` |
| `/intents/withdraw` | Either format (auto-prefixed); `near`/`native`/omitted = native NEAR | `near` (native), `wrap.near` or `nep141:wrap.near` (wNEAR) |
| `/intents/ft-withdraw` | Plain NEAR contract ID | `wrap.near` |
| `/balance` (wallet) | Plain NEAR contract ID | `wrap.near` |
| `/balance?source=intents` | Either format (auto-prefixed) | `wrap.near` or `nep141:wrap.near` |
| `/payment-check/*` | Plain NEAR contract ID | `17208628f...a1` (USDC) |
| `/deposit-intent` | Defuse asset id (`source_asset`) | `nep141:base-0x833…omft.near` |

**Rule:** Swap uses `nep141:` prefix. Cross-chain deposit takes
`source_asset` (defuse asset id; chain is derived from the prefix). Withdraw
accepts either format. Everything else uses plain contract ID.

### Swap workflow

**1. Find token IDs:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/tokens"
```
Response includes `defuse_asset_id` for each token - use this in swap calls.

**2. Check intents balance (tokens must be in intents):**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?token=wrap.near&source=intents"
```

If tokens are on the NEAR account (not in intents), deposit them first:
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token":"wrap.near","amount":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/deposit"
```

**3. Preview swap rate (optional, no gas):**
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap/quote"
```
Response: `{"amount_out": "3150000", "min_amount_out": "3118500", "deadline": "...", "time_estimate_seconds": 30}`

**4. Execute swap (gasless):**
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000","min_amount_out":"3000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap"
```
Response: `{"request_id": "uuid", "status": "success", "amount_out": "3150000", "intent_hash": "..."}`

**Prerequisite:** tokens must be in intents balance. Use `/intents/deposit` to move from NEAR account, or receive via payment check (funds arrive in intents directly).

**Result stays in intents balance.** Use `/intents/withdraw` to move tokens out.

`min_amount_out` is optional - omit for a market order. Set to protect against slippage.

### Common swap pairs

| Pair | token_in | token_out |
|------|----------|-----------|
| wNEAR to USDT | `nep141:wrap.near` | `nep141:usdt.tether-token.near` |
| USDT to wNEAR | `nep141:usdt.tether-token.near` | `nep141:wrap.near` |
| wNEAR to USDC | `nep141:wrap.near` | `nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1` |
| wNEAR to ETH | `nep141:wrap.near` | `nep141:eth.omft.near` |
| wNEAR to BTC | `nep141:wrap.near` | `nep141:btc.omft.near` |

### Cross-chain transfer (deposit + withdraw)

For moving tokens to another chain without swapping:

```bash
# 1. Deposit tokens into intents balance
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token":"wrap.near","amount":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/deposit"

# 2. Withdraw to destination (gasless - no NEAR needed for gas)
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"to":"receiver.near","amount":"1000000000000000000000000","token":"wrap.near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/withdraw"
```

**Withdraw NATIVE NEAR** (default for `chain=near`) - unwraps your wNEAR and delivers native NEAR; receiver needs no `wrap.near` storage. `amount` is yoctoNEAR (24 decimals; 1 NEAR = `1000000000000000000000000`):

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"to":"receiver.near","amount":"1000000000000000000000000","token":"near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/withdraw"
```

The `/intents/withdraw` endpoint is **gasless** - it uses NEP-413 signed intents via the solver relay. No NEAR balance is required on the wallet's implicit account.

For the on-chain `ft_withdraw` method (requires NEAR for gas on the implicit account), use `/intents/ft-withdraw` instead.

### Dry-run (check without executing)
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"to":"receiver.near","amount":"1000000000000000000000000","token":"wrap.near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/withdraw/dry-run"
```

### Supported chains

NEAR, Ethereum, Bitcoin, Solana, Arbitrum, Base, Polygon, Optimism, Avalanche, BSC, TON, Aptos, Sui, StarkNet, Tron, Stellar, Dogecoin, XRP, Zcash, Litecoin, Bitcoin Cash, Berachain, Aleo, Cardano, Dash.

Use `GET /wallet/v1/tokens` for the full current list.

---

## Cross-Chain Deposit & Withdraw

Deposit tokens from any supported chain (Solana, Ethereum, Base, Arbitrum, etc.) into intents balance, or withdraw from intents to any chain. No gas tokens needed on source/destination chains - 1Click handles execution.

Supported chains: `near`, `solana`, `ethereum`, `base`, `arbitrum`, `bitcoin`, `bsc`, `polygon`, `optimism`, `avalanche`. The returned `deposit_address` is always on the chain that matches the source asset (64-char hex for NEAR, `0x…` for EVM, base58 for Solana, `bc1…`/`1…`/`3…` for Bitcoin).

> **NEAR source? Use `/wallet/v1/intents/deposit` instead.** When the funds
> are already on NEAR (in the agent's wallet), skip this endpoint and call
> `POST /wallet/v1/intents/deposit` (see "Move FT from wallet into Intents"
> in the quick-reference table above). It signs a direct
> `ft_transfer_call(token, receiver=intents.near, amount)` in one
> transaction, ~3 seconds, no 1Click solver hop. `/deposit-intent` still
> accepts a NEAR-source asset for symmetry, but adds a solver hop and
> ~5 seconds for no benefit — and the response carries a `hint` field
> nudging you to `/intents/deposit`.

### Deposit from another chain → intents

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "source_asset": "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near",
    "amount": "1000000"
  }' \
  "https://api.outlayer.fastnear.com/wallet/v1/deposit-intent"
```

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `source_asset` | yes | - | Defuse asset id (e.g. `nep141:eth-…omft.near`) from `GET /wallet/v1/tokens`. The source chain is derived from the prefix; supported prefixes cover `near`, `solana`, `ethereum`, `base`, `arbitrum`, `bitcoin`, `bsc`, `polygon`, `optimism`, `avalanche`. |
| `amount` | yes | - | Amount in minimal units. USDC: 6 decimals (`"1000000"` = 1 USDC). |
| `refund_address` | no | - | Address on the source chain to refund to if the bridge fails. Required for source chains where the keystore cannot derive a wallet-owned address (e.g. Bitcoin) — without it the request fails with HTTP 400. |
| `destination_asset` | no | NEAR USDC | Defuse asset id for destination token. Override to receive wNEAR etc. |

Response:
```json
{
  "intent_id": "uuid",
  "deposit_address": "7szyqKsG3SC4XvrEaF128DHCYEmy7n7SvM4DSoW1e5jZ",
  "amount": "1000000",
  "amount_out": "999998",
  "min_amount_out": "989998",
  "expires_at": "2026-03-26T17:25:45.914Z",
  "estimated_time_secs": 20
}
```

**2. User sends tokens** to `deposit_address` on the source chain.

**3. Poll status:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/deposit-status?id={intent_id}"
```

Status transitions: `pending` → `bridging` → `success`. On `success`, tokens are in intents balance - create payment checks, swap, or withdraw as usual.

| Status | Meaning |
|--------|---------|
| `pending` | Waiting for deposit on source chain |
| `bridging` | 1Click detected deposit, settling to NEAR intents |
| `success` | Tokens in intents balance |
| `failed` | Error or refund |
| `expired` | No deposit before deadline |

**4. List all deposits:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/deposits?limit=20"
```

### Withdraw from intents → another chain

Send tokens from intents balance to any supported chain. Uses `/intents/withdraw` with `chain` param. Gasless - 1Click solver handles execution.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"to": "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU", "token": "nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1", "amount": "1000000", "chain": "solana"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/withdraw"
```

| Param | Required | Description |
|-------|----------|-------------|
| `to` | yes | Destination address on target chain |
| `token` | yes | Intents token (defuse asset ID, e.g. `nep141:17208628f...a1` for USDC) |
| `amount` | yes | Amount in minimal units |
| `chain` | yes | `"solana"`, `"ethereum"`, `"base"`, etc. |

Response: `{"request_id": "uuid", "status": "success"}`

### Cross-chain limitations

- **Minimum deposit/withdraw**: ~$0.10. 1Click returns clear error with exact minimum if too low.
- **Fee**: ~0.2% (shown in `amount_out` / `min_amount_out`).
- **Settlement time**: ~15-30 seconds depending on chain.
- **Deposit address**: unique per intent, valid ~30 min. Each `deposit-intent` call creates a new address. Amount sent must match exactly.
- **Supported tokens**: use `GET /wallet/v1/tokens` to check available tokens per chain.

---

## Confidential Intents

Move balances between your **public** intents shard, the **confidential**
shielded-pool shard, and external chains. Same TEE-mediated signing as the
rest of the wallet — just a different shard.

> **Full developer integration guide**: [`CONFIDENTIAL_INTENTS.md`](https://github.com/out-layer/coordinator/blob/main/docs/CONFIDENTIAL_INTENTS.md)
> — mental model (private shard vs off-chain misconception), endpoint flow,
> two privacy recipes (SHIELD vs cross-chain in/out), curl walkthroughs, error
> codes. Read it once before integrating; the section below is a quick
> reference for an already-familiar caller.

**Availability**: these routes return **HTTP 503** (`confidential_unavailable`)
unless the deployment has confidential intents enabled. Treat 503 as "not
offered here", not an error to retry.

### Endpoints

| Endpoint | Action | Body |
|---|---|---|
| `POST /wallet/v1/confidential/deposit` | **SHIELD**: public intents → confidential | `{ token, amount }` |
| `POST /wallet/v1/confidential/unshield` | confidential → public intents | `{ token, amount }` |
| `POST /wallet/v1/confidential/withdraw` | confidential → external chain | `{ chain, to, amount, token }` |
| `POST /wallet/v1/confidential/withdraw/dry-run` | quote a withdraw | same |
| `POST /wallet/v1/confidential/transfer` | private transfer (confidential → confidential) | `{ to, amount, token }` |
| `POST /wallet/v1/confidential/swap` | confidential swap (distinct assets) | `{ token_in, token_out, amount_in }` |
| `POST /wallet/v1/confidential/swap/quote` | quote a swap | same |
| `POST /wallet/v1/confidential/deposit-intent` | cross-chain DEPOSIT (returns bridge address) | `{ source_asset, amount }` |
| `GET  /wallet/v1/confidential/balance` | read confidential balances | `?token=` (optional) |

The action endpoints are **asynchronous**: they return
`{ request_id, status: "pending_deposit", intent_hash, deposit_address }`. Poll
`GET /wallet/v1/requests/{request_id}` until `status` is `success`, `failed`, or
`refunded`. `chain="near"` on `/confidential/withdraw` is **rejected (400)** —
use `/confidential/unshield` to return funds to your own public balance.

### Conventions (apply to every endpoint below)

- **`Authorization: Bearer wk_…`** on every call (same key as the rest of the
  wallet — no separate confidential key).
- **`X-Idempotency-Key: <uuid>`** is supported on every action endpoint. A
  retry with the same key returns the original `request_id` instead of acting
  twice. Use one per logical user action.
- **Token IDs**: defuse asset id (`nep141:wrap.near`). Plain contract IDs
  (`wrap.near`) are also accepted and auto-prefixed.
- **Amounts**: minimal integer units as a **string**. wNEAR/NEAR 24 decimals
  (`"10000000000000000000000"` = 0.01 NEAR). USDC 6 decimals (`"1000000"` = 1
  USDC). Same convention as the public `/intents/*` endpoints.
- **`request_id` from the action response is the poll key**: keep it,
  `GET /wallet/v1/requests/{request_id}` returns the merged
  `{ status, result }` until terminal. `result.intent_hash` /
  `result.deposit_address` mirror the action response; `result.swap_details`
  appears once the solver settles.
- **No `tx_hash`**: confidential ops don't put your signed intent on the
  public chain (the private shard's settlement isn't a public tx). Track by
  `request_id` and `intent_hash`.

### Method reference (body + response, per endpoint)

`ConfidentialOpResponse` (the shared async-action response):

```json
{ "request_id": "uuid", "status": "pending_deposit", "intent_hash": "...", "deposit_address": "..." }
```

`QuotePreview` (returned by `/withdraw/dry-run` and `/swap/quote`):

```json
{
  "amount_in": "...", "amount_out": "...", "min_amount_out": "...",
  "deadline": "2026-…T…Z", "time_estimate_seconds": 10
}
```

| Endpoint | Body | Response | Notes |
|---|---|---|---|
| `POST /confidential/deposit` | `{ token, amount }` | `ConfidentialOpResponse` | SHIELD — wallet must already hold `token` in its **public** intents balance |
| `POST /confidential/unshield` | `{ token, amount }` | `ConfidentialOpResponse` | Reverse of SHIELD; returns funds to **your own** public intents balance |
| `POST /confidential/withdraw` | `{ chain, to, amount, token }` (all required) | `ConfidentialOpResponse` | `chain="near"` → **400** (use `unshield`). Supported chains same as public intents. The NEAR-side `ft_withdraw` is signed by a 1Click hop — your wallet stays off the public chain |
| `POST /confidential/withdraw/dry-run` | same as `withdraw` | `QuotePreview` | No DB write, no sign/submit. Use to preview spread/eta before the real call |
| `POST /confidential/transfer` | `{ to, amount, token }` (no `chain`) | `ConfidentialOpResponse` | `to` = recipient's `intentsUserId` (their 64-hex NEAR implicit address). NEAR-only context. Recipient must also have confidential intents enabled on their deployment |
| `POST /confidential/swap` | `{ token_in, token_out, amount_in, min_amount_out? }` | `ConfidentialOpResponse` | `token_in != token_out`; `min_amount_out` enforced before signing (rejects 400 if quote below floor) |
| `POST /confidential/swap/quote` | same as `swap` | `QuotePreview` | Read-only; no DB, no sign. Preview the swap rate |
| `POST /confidential/deposit-intent` | `{ source_asset, amount }` **or** `{ chain, token?, amount }` (`token` defaults to `"USDC"`) | `{ intent_id, deposit_address, amount, amount_out, min_amount_out, expires_at?, hint? }` | Quote-only — returns the bridge address on the source chain; you then send funds out-of-band on that chain. **Privacy-preserving path**: your NEAR wallet never touches the public chain |
| `GET /confidential/balance?token=` | query string | `{ balance, token, account_id }` (filtered) or `{ balances: [{ token_id, available }, …], account_id }` (no filter) | Reads `/v0/account/balances` from the private shard. Zero-balance tokens are **omitted** from the unfiltered list |

### More curl examples

```bash
# WITHDRAW 0.5 USDC from confidential to a Solana address (gasless, async)
curl -sX POST $BASE/wallet/v1/confidential/withdraw \
  -H "Authorization: Bearer $WK" -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  -d '{"chain":"solana","to":"<sol-addr>","amount":"500000","token":"nep141:sol-5ce3bf3a31af18be40ba30f721101b4341690186.omft.near"}'
# → {"request_id":"…","status":"pending_deposit","intent_hash":"…","deposit_address":"…"}

# DRY-RUN the same withdraw (preview spread + eta, no commit)
curl -sX POST $BASE/wallet/v1/confidential/withdraw/dry-run \
  -H "Authorization: Bearer $WK" -H "Content-Type: application/json" \
  -d '{"chain":"solana","to":"<sol-addr>","amount":"500000","token":"nep141:sol-…omft.near"}'
# → {"amount_in":"500000","amount_out":"440000","min_amount_out":"435600","time_estimate_seconds":7,...}

# Privacy-preserving FUND path: get a Solana bridge address; send funds on Solana
curl -sX POST $BASE/wallet/v1/confidential/deposit-intent \
  -H "Authorization: Bearer $WK" -H "Content-Type: application/json" \
  -d '{"source_asset":"nep141:sol-5ce3bf3a31af18be40ba30f721101b4341690186.omft.near","amount":"500000"}'
# → {"intent_id":"…","deposit_address":"<Solana addr>","amount":"500000","amount_out":"500000",...}

# Private transfer to another confidential identity (no public-chain trace)
curl -sX POST $BASE/wallet/v1/confidential/transfer \
  -H "Authorization: Bearer $WK" -H "Content-Type: application/json" \
  -d '{"to":"<their 64-hex intentsUserId>","amount":"1000000","token":"nep141:wrap.near"}'

# Confidential swap (distinct assets, min_amount_out floor enforced)
curl -sX POST $BASE/wallet/v1/confidential/swap \
  -H "Authorization: Bearer $WK" -H "Content-Type: application/json" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:17208628f...a1","amount_in":"10000000000000000000000","min_amount_out":"22500000"}'

# Poll any action's progress
curl -s $BASE/wallet/v1/requests/<request_id> -H "Authorization: Bearer $WK"
# → {"status":"success","result":{"intent_hash":"…","deposit_address":"…","swap_details":{...},"oneclick_status":"SUCCESS",...}}

# Read confidential balance for one asset, or all
curl -s "$BASE/wallet/v1/confidential/balance?token=nep141:wrap.near" -H "Authorization: Bearer $WK"
curl -s $BASE/wallet/v1/confidential/balance                          -H "Authorization: Bearer $WK"
```

### Errors

| HTTP | `error` | Meaning |
|---|---|---|
| 503 | `confidential_unavailable` | confidential intents not enabled on this deployment — **don't retry**, route to a different deployment or fall back to public intents |
| 502 | `confidential_jwt_expired` / `keystore_error` | upstream (1Click / keystore) hiccup; the coordinator already retried auth once. Safe to retry |
| 403 | `policy_denied` / `wallet_frozen` | blocked by the wallet's on-chain policy (same engine as `/intents/withdraw`). Don't retry without changing the policy |
| 400 | `bad_request` | bad input — `chain="near"` on withdraw, missing `to`/`token`, `token_in == token_out` on swap, quote `amount_out` below `min_amount_out`, etc. |

### Privacy model — read this before relying on "confidential"

The confidential shard is a separate **private shard** — the `intents.far`
contract, distinct from public `intents.near` — NOT a Tor-like anonymity
network. Confidential balances are **real on-chain state** on that private
shard, not off-chain and not a solver database: it is an auditable smart
contract. The privacy is that the private shard has **no public RPC** — you
cannot read it from public mainnet (`intents.far` resolves as
`UNKNOWN_ACCOUNT` there) — but the operator/Defuse, auditors, or law
enforcement with a warrant **can** read it. Only edges (shield/unshield,
cross-chain in/out) touch the **public** chain, and those carry only **public**
asset ids and **public-side** participants.

**What public chain observers see, by direction** (SHIELD and cross-chain DEPOSIT/WITHDRAW verified against mainnet; UNSHIELD and internal transfer/swap inferred by protocol symmetry, not yet exercised live):

| Direction | Your wallet on chain? | Asset id on chain | Amount on chain | Notes |
|---|---|---|---|---|
| SHIELD (`INTENTS → CONFIDENTIAL`) | **yes** (signer of inner intent) | public `nep141:…` | yes | "entry" reveal: full link wallet ↔ confidential pool |
| UNSHIELD (mirror) | **yes** | public `nep141:…` | yes | "exit-to-public" reveal: same as SHIELD inverted |
| internal CONFIDENTIAL ops (transfer, swap) | **no** | n/a | n/a | settle on the private shard — no **public-chain** trace |
| DEPOSIT `ORIGIN_CHAIN → CONFIDENTIAL` | **no** | public on source chain + NEAR bridge mint | yes | source-chain sender visible on source chain only |
| WITHDRAW `CONFIDENTIAL → DESTINATION_CHAIN` | **no** | public dest-chain token | yes (after bridge fee) | dest-chain receiver visible on dest chain only; the NEAR-side `ft_withdraw` is signed by a 1Click hop |

**What is NOT hidden, ever:**

- **Defuse / 1Click solvers** see plaintext intents pre-execution. They know the
  asset, signer, recipient, amount, and the route. Privacy holds against public
  chain observers, not against the solver layer.
- **`partner_id` mapping**: all per-account JWTs issued under our partner JWT are
  tagged with `partner_id=near-agents-market`. Defuse can enumerate every
  confidential identity we mint under that partner.
- **Source-chain identity**: the externally-funded chain side (Solana sender
  address, EVM `from`, BTC input UTXO) is fully public — no protocol-level hiding.

**Strongest-privacy recipe**: avoid SHIELD/UNSHIELD (they link your wallet
on-chain). Instead fund the confidential balance via cross-chain DEPOSIT
(`/confidential/deposit-intent`), do your work inside the shard (transfer/swap —
settles on the private shard, no public-chain trace), and exit via cross-chain
WITHDRAW. In that flow your NEAR custody address never appears on the public
chain. The only residual attack surface is
**timing/amount correlation** between the source-chain deposit and the
destination-chain delivery — mitigate with jitter and amount splitting.

> Each wallet has one confidential identity — your custody wallet itself. There
> is no separate or unlinkable confidential identity.

---

## Payment Checks (Agent-to-Agent Payments)

Payment checks enable trustless agent-to-agent payments. One agent writes a check (deposits tokens into an ephemeral account), sends the `check_key` to another agent, and the recipient claims the funds. First-to-claim semantics - no double-spend possible.

Check keys are derived in TEE from the custody keystore - deterministic and recoverable. The server never stores raw private keys.

Optional expiration: set `expires_in` when creating a check. After expiry, the recipient cannot claim via our API, and the sender can reclaim the funds.

### How it works

1. **Agent2** (buyer) creates a check for 1 USDC → gets `check_id` + `check_key`
2. **Agent2** sends `check_key` to **Agent1** (seller) via any channel (API, message, etc.)
3. **Agent1** claims the check → 1 USDC lands in Agent1's intents balance
4. **Agent1** does the work, delivers the result

If Agent1 never claims, Agent2 can reclaim the check at any time.

### Create a payment check

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token":"17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1","amount":"1000000","memo":"Payment for song generation","expires_in":86400}' \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/create"
```

| Param | Required | Description |
|-------|----------|-------------|
| `token` | yes | Plain NEAR contract ID (e.g. USDC: `17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1`) |
| `amount` | yes | Amount in smallest denomination (string) |
| `memo` | no | Human-readable memo (max 256 chars) |
| `expires_in` | no | Seconds until expiry (e.g. `86400` for 24h). Omit for no expiry. |

Response:
```json
{
  "request_id": "uuid",
  "status": "success",
  "check_id": "pc_a1b2c3d4e5f6",
  "check_key": "ed25519:5Kd3NBU...base58_private_key",
  "token": "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1",
  "amount": "1000000",
  "memo": "Payment for song generation",
  "created_at": "2026-03-12T10:30:00Z",
  "expires_at": "2026-03-13T10:30:00Z"
}
```

**`check_key` is shown only once** - this is the check itself. Send it to the recipient. The `check_id` is for your own status tracking and reclaims.

If the wallet has insufficient intents balance but enough wallet balance, the API auto-deposits to intents before creating the check.

### Batch create payment checks

Create up to 10 checks in a single request.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"checks":[{"token":"17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1","amount":"500000","memo":"Task 1"},{"token":"17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1","amount":"500000","memo":"Task 2"}]}' \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/batch-create"
```

Response: `{"checks": [<same as single create>, ...]}` - one entry per check, same fields.

### Claim a payment check

Supports **partial claims** - pass `amount` to claim less than the full check. Omit for full claim.

```bash
# Full claim
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RECIPIENT_API_KEY" \
  -d '{"check_key":"ed25519:5Kd3NBU...base58_private_key"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/claim"

# Partial claim (500000 out of 1000000)
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RECIPIENT_API_KEY" \
  -d '{"check_key":"ed25519:5Kd3NBU...base58_private_key","amount":"500000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/claim"
```

| Param | Required | Description |
|-------|----------|-------------|
| `check_key` | yes | The check private key received from sender |
| `amount` | no | Partial claim amount (smallest units). Omit for full balance. |

Response:
```json
{
  "request_id": "uuid",
  "status": "success",
  "token": "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1",
  "amount_claimed": "500000",
  "remaining": "500000",
  "memo": "Payment for song generation",
  "claimed_at": "2026-03-12T10:35:00Z",
  "intent_hash": "abc123..."
}
```

Claimed funds land in the recipient's **intents balance**. Use `/intents/withdraw` to move them to a wallet or another chain. When `remaining > 0`, the check stays active for further claims or reclaim.

### Check status

```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/status?check_id=pc_a1b2c3d4e5f6"
```

Response:
```json
{
  "check_id": "pc_a1b2c3d4e5f6",
  "token": "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1",
  "amount": "1000000",
  "claimed_amount": "500000",
  "reclaimed_amount": "0",
  "memo": "Payment for song generation",
  "status": "partially_claimed",
  "created_at": "2026-03-12T10:30:00Z",
  "expires_at": "2026-03-13T10:30:00Z",
  "claimed_at": "2026-03-12T10:35:00Z",
  "claimed_by": "a1b2c3..."
}
```

| Status | Meaning |
|--------|---------|
| `unclaimed` | Funds waiting - check not yet claimed |
| `partially_claimed` | Recipient claimed part of the check - remaining funds available |
| `claimed` | Recipient claimed the entire check |
| `partially_reclaimed` | Sender reclaimed part - remaining available for claim |
| `reclaimed` | Sender took all remaining funds back |
| `expired` | Unclaimed and past `expires_at` - sender can reclaim |

### List payment checks

```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/list?status=unclaimed&limit=50"
```

Returns `{"checks": [...]}` - all checks created by the authenticated wallet.

### Reclaim a check (full or partial)

Supports **partial reclaims** - pass `amount` to reclaim less than the remaining balance. Omit for full reclaim.

```bash
# Full reclaim
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"check_id":"pc_a1b2c3d4e5f6"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/reclaim"

# Partial reclaim (300000 out of remaining 500000)
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"check_id":"pc_a1b2c3d4e5f6","amount":"300000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/reclaim"
```

| Param | Required | Description |
|-------|----------|-------------|
| `check_id` | yes | The check ID from create response |
| `amount` | no | Partial reclaim amount (smallest units). Omit for full remaining. |

Response:
```json
{
  "request_id": "uuid",
  "status": "success",
  "token": "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1",
  "amount_reclaimed": "300000",
  "remaining": "200000",
  "reclaimed_at": "2026-03-12T12:00:00Z",
  "intent_hash": "def456..."
}
```

Reclaim works anytime the check has remaining balance - before or after expiry. Only the check creator can reclaim. When `remaining > 0`, the check stays active for further claims or reclaims.

### Peek a check (check balance by key)

Check the on-chain balance and status of a check using its key. Requires wallet auth.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"check_key":"ed25519:5Kd3NBU...base58_private_key"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/payment-check/peek"
```

Response:
```json
{
  "token": "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1",
  "balance": "500000",
  "memo": "Payment for song generation",
  "status": "partially_claimed",
  "expires_at": "2026-03-13T10:30:00Z"
}
```

Use this to verify a check has funds before claiming. The `balance` field is the live on-chain balance of the ephemeral account.

### Flow: Both agents in Agent Custody

```
Agent2 (buyer)                    API                        Agent1 (seller)
     |                             |                              |
     |  POST /payment-check/create |                              |
     |  {token, amount, memo}      |                              |
     |---------------------------->|                              |
     |  {check_id, check_key}      |                              |
     |<----------------------------|                              |
     |                             |                              |
     |  ---- sends check_key to Agent1 (any channel) ----------->|
     |                             |                              |
     |                             |  POST /payment-check/claim   |
     |                             |  {check_key}                 |
     |                             |<-----------------------------|
     |                             |  {token, amount}             |
     |                             |----------------------------->|
     |                             |                              |
     |                             |  Funds in Agent1's intents   |
     |                             |  balance - ready to use      |
```

### Flow: External wallet claims

External wallets can claim using the `check_key` as a NEAR Intents Gift private key directly on-chain - no API needed. Our status endpoint detects the claim by checking the ephemeral account balance.

```
Agent2 (buyer, custody)         API                    External Wallet
     |                           |                          |
     |  POST /payment-check/create                          |
     |-------------------------->|                          |
     |  {check_key}              |                          |
     |<--------------------------|                          |
     |                           |                          |
     |  ---- sends check_key (any channel) ---------------->|
     |                           |                          |
     |                           |   Claims on-chain via    |
     |                           |   NEAR Intents SDK       |
     |                           |                          |
     |  GET /payment-check/status|                          |
     |-------------------------->|                          |
     |  {status: "claimed"}      |                          |
     |<--------------------------|                          |
```

**Expiration caveat:** Expiration is enforced by our API. External wallets claiming directly on-chain can bypass expiry. For high-value checks to external wallets, reclaim promptly after expiry.

---

## Quick Reference

| Action | Method | Endpoint | Gas |
|--------|--------|----------|-----|
| Register (random) | POST | `/register` | - |
| Register (deterministic) | POST | `/register` (with NEAR sig body) | - |
| Register delegate key | PUT | `/wallet/v1/api-key` (Bearer or NEAR sig) | - |
| Revoke delegate key | DELETE | `/wallet/v1/api-key/{key_hash}` | - |
| Execute WASI (trial) | POST | `/call/{owner}/{project}` | - |
| Trial status | GET | `/trial/status` | - |
| Create payment key | POST | `/wallet/v1/create-payment-key` | on-chain |
| Get address | GET | `/wallet/v1/address?chain={chain}` | - |
| Get balance | GET | `/wallet/v1/balance?chain={chain}&token={token}` | - |
| Get intents balance | GET | `/wallet/v1/balance?token={token}&source=intents` | - |
| Transfer NEAR | POST | `/wallet/v1/transfer` | on-chain |
| Call contract | POST | `/wallet/v1/call` | on-chain |
| Delete wallet | POST | `/wallet/v1/delete` | on-chain |
| Register token storage | POST | `/wallet/v1/storage-deposit` | on-chain |
| Move FT: wallet → intents.near | POST | `/wallet/v1/intents/deposit` | on-chain |
| Withdraw on-chain (ft_withdraw) | POST | `/wallet/v1/intents/ft-withdraw` | on-chain |
| Withdraw native NEAR / wNEAR / cross-chain (gasless, default) | POST | `/wallet/v1/intents/withdraw` | gasless |
| Dry-run withdrawal | POST | `/wallet/v1/intents/withdraw/dry-run` | - |
| Swap tokens | POST | `/wallet/v1/intents/swap` | gasless |
| Swap quote | POST | `/wallet/v1/intents/swap/quote` | - |
| Deposit from any chain | POST | `/wallet/v1/deposit-intent` | cross-chain |
| Check deposit status | GET | `/wallet/v1/deposit-status?id={id}` | - |
| List deposits | GET | `/wallet/v1/deposits` | - |
| Confidential: SHIELD public→confidential | POST | `/wallet/v1/confidential/deposit` | confidential |
| Confidential: confidential→public | POST | `/wallet/v1/confidential/unshield` | confidential |
| Confidential: withdraw to external chain | POST | `/wallet/v1/confidential/withdraw` | confidential |
| Confidential: dry-run withdraw | POST | `/wallet/v1/confidential/withdraw/dry-run` | - |
| Confidential: private transfer | POST | `/wallet/v1/confidential/transfer` | confidential |
| Confidential: swap inside private shard | POST | `/wallet/v1/confidential/swap` | confidential |
| Confidential: swap quote | POST | `/wallet/v1/confidential/swap/quote` | - |
| Confidential: cross-chain DEPOSIT (bridge address) | POST | `/wallet/v1/confidential/deposit-intent` | confidential |
| Confidential: read balance | GET | `/wallet/v1/confidential/balance?token={token}` | - |
| List tokens | GET | `/wallet/v1/tokens` | - |
| Request status | GET | `/wallet/v1/requests/{request_id}` | - |
| List requests | GET | `/wallet/v1/requests` | - |
| Sign message (NEP-413) | POST | `/wallet/v1/sign-message` | - |
| Audit log | GET | `/wallet/v1/audit?limit=50` | - |
| Create payment check | POST | `/wallet/v1/payment-check/create` | gasless |
| Batch create checks | POST | `/wallet/v1/payment-check/batch-create` | gasless |
| Claim payment check | POST | `/wallet/v1/payment-check/claim` | gasless |
| Check status | GET | `/wallet/v1/payment-check/status?check_id={id}` | - |
| List checks | GET | `/wallet/v1/payment-check/list` | - |
| Reclaim check | POST | `/wallet/v1/payment-check/reclaim` | gasless |
| Peek check balance | POST | `/wallet/v1/payment-check/peek` | - |

**Gas column:** `on-chain` = wallet pays gas (needs NEAR), `gasless` = solver relay pays, `cross-chain` = 1Click bridge (fee ~0.2%), `confidential` = 1Click solver settles on the private shard (no wallet gas, no wallet on the public chain except for SHIELD/UNSHIELD edges), `-` = no transaction.

All endpoints except `/register` and `PUT /wallet/v1/api-key` require `Authorization: Bearer <api_key>` or `Bearer near:<base64url>` header.
Base URL: `https://api.outlayer.fastnear.com`

---

## Token Amounts Reference

| Token | Decimals | 1 unit in smallest denomination |
|-------|----------|---------------------------------|
| NEAR / wNEAR | 24 | `1000000000000000000000000` |
| USDT / USDC | 6 | `1000000` |
| ETH / wETH | 18 | `1000000000000000000` |
| BTC / wBTC | 8 | `100000000` |
| SOL | 9 | `1000000000` |

## Automatic Storage Registration

| Endpoint | What it auto-registers |
|----------|----------------------|
| `/wallet/v1/intents/swap` | Output token storage on your wallet |
| `/wallet/v1/intents/deposit` | Your wallet's storage on `intents.near` |
| Fund link (dashboard) | Your wallet's storage on the token contract |
| `/wallet/v1/payment-check/create` | Auto-deposits to intents if wallet balance sufficient |

**NOT auto-registered:** `/wallet/v1/call` - register storage manually with `storage_deposit` if calling `ft_transfer` to a new receiver.

## Reading Transaction Statuses

| Status | Meaning | Action |
|--------|---------|--------|
| `success` | Completed | Read result fields |
| `failed` | Failed | Check `result` for error details |
| `processing` | In progress | Poll `GET /wallet/v1/requests/{id}` |
| `pending_approval` | Needs multisig | Inform user, provide dashboard link |
| `pending_deposit` | Confidential op accepted by 1Click, waiting for solver settlement | Poll `GET /wallet/v1/requests/{id}` (typical 5–30s) |
| `refunded` | Confidential op failed mid-flight; funds refunded inside the confidential balance | Inspect `result.swap_details.refundReason`; safe to retry |

## Error Handling

| Error | Meaning |
|-------|---------|
| `missing_auth` | No `Authorization: Bearer` header |
| `invalid_api_key` | Key revoked or not found |
| `policy_denied` | Operation blocked by policy rules |
| `wallet_frozen` | Wallet frozen by controller |
| `insufficient_balance` | Not enough funds |
| `unsupported_token` | Token not supported - check `/tokens` |
| `pending_approval` | Needs multisig approval (not an error) |
| `"token_in must use defuse asset format"` | Missing `nep141:` prefix in swap |
| `"1Click swap was refunded"` | Solver couldn't fill - tokens returned to wallet |
| `check_already_claimed` | Payment check was already claimed by recipient |
| `check_not_found` | No check with this ID for the authenticated wallet |
| `invalid_check_key` | Key format invalid or does not correspond to a check |
| `check_empty` | Ephemeral account has zero balance (already claimed on-chain) |
| `check_already_reclaimed` | Check was already reclaimed by sender |
| `check_expired` | Check expired - cannot claim (sender can reclaim) |
| `memo_too_long` | Memo exceeds 256 characters |
| `timestamp_expired` | Signature timestamp outside allowed window (±30s for Bearer, ±5min for register/api-key) |
| `conflict` | Cannot revoke last active API key (409) |
| `"Ambiguous auth"` | PUT /api-key received both Bearer header and signature fields in body — use one or the other |
| `"seed: 1-256 chars required"` | Empty or oversized seed in register or api-key |
| `"seed: only [a-zA-Z0-9._-] allowed"` | Seed contains forbidden characters (NUL, colon, whitespace, Unicode, etc) — use SHA-256 hex or alphanumeric |
| `TrialQuotaExhausted` | Sub-agent or stateless Bearer-near tried `/call` without `X-Payment-Key`; trial is only available on primary `/register` wk_ |

## Guidelines

- **Always check balance before any operation.** Query `/wallet/v1/balance` before swap, transfer, call, or withdraw.
- **Use quote to preview swap rates.** The quote endpoint is free - no gas, no state change.
- **Tokens must be in intents balance before swapping.** Use `/intents/deposit` to move FT from wallet, or request funds with `dest=intents` to skip this step.
- **`min_amount_out` is optional** but recommended for slippage protection.
- **Cross-chain transfers need deposit + withdraw.** Only for moving tokens without swapping.
- **Solana deposits create a temporary address.** Each `deposit-intent` call generates a unique Solana address. Poll `deposit-status` until `success`.
- **Solana withdraw goes through 1Click bridge.** Use `/solana/withdraw` - tokens leave intents balance and arrive on Solana in ~15-20 seconds.
- **Poll for async results.** If status is `processing`, poll `/requests/{id}`.
- Always use `withdraw/dry-run` before real withdrawals.
- **Payment checks** are ideal for agent-to-agent payments - first-to-claim prevents double-spend. Set `expires_in` to protect against unclaimed checks.
- Store the API key as a secret - never log or expose it.
- NEAR amounts are in yoctoNEAR (1 NEAR = 10^24 yoctoNEAR).
- **Never interpolate variables directly into JSON in bash `-d` args.** Characters like `$`, `!`, and quotes break JSON. Build the body with `python3 -c "import json; print(json.dumps({...}))"` or write to a temp file with `cat > /tmp/body.json << 'EOF'`, then use `curl -d @/tmp/body.json`.
- **Long URLs (fund links, handoff links) break in terminal.** When you generate a URL with query params (especially fund links with token contract IDs), open it directly in the browser instead of printing. Use `open "URL"` (macOS) or `xdg-open "URL"` (Linux). Always offer to open rather than risk the user copying a truncated URL that won't work.

## Using OutLayer CLI with Wallet Key

Agents with custody wallets can use the OutLayer CLI directly - no NEAR private key needed. The CLI routes all contract operations through `POST /wallet/v1/call` transparently.

### Login with wallet key

```bash
outlayer login --wallet-key wk_15807dbda492636df5280629d7617c3ea80f915ba960389b621e420ca275e545
outlayer login testnet --wallet-key wk_...
```

This calls `/wallet/v1/sign-message` to derive the account ID and public key, then stores the wallet key in `~/.outlayer/{network}/credentials.json` with `auth_type: "wallet_key"`.

### Supported commands

After wallet-key login, these commands work transparently:

| Command | How it works with wallet_key |
|---------|------------------------------|
| `outlayer deploy` | Routes `add_version`/`create_project` via `/wallet/v1/call` |
| `outlayer run` (on-chain) | Routes `request_execution` via `/wallet/v1/call` |
| `outlayer keys create/topup/delete` | Routes `store_secrets`/`top_up_payment_key_with_near`/`delete_payment_key` via `/wallet/v1/call` |
| `outlayer secrets set/delete` | Routes `store_secrets`/`delete_secrets` via `/wallet/v1/call` |
| `outlayer secrets update` | Signs NEP-413 via `/wallet/v1/sign-message`, then stores via `/wallet/v1/call` |
| `outlayer earnings withdraw` | Routes `withdraw_developer_earnings` via `/wallet/v1/call` |
| `outlayer versions activate/remove` | Routes contract calls via `/wallet/v1/call` |
| `outlayer run` (HTTPS) | Works if payment key is set (signing not needed) |
| `outlayer whoami` | Shows `Auth: wallet_key` |

### Not yet supported

| Command | Reason |
|---------|--------|
| `outlayer upload` (FastFS) | Uses raw Borsh-encoded transaction args - `/wallet/v1/call` only accepts JSON. Use `outlayer login` with a NEAR private key for uploads. |

### Typical agent workflow

```bash
# 1. Agent registers a custody wallet via API
# POST https://api.outlayer.fastnear.com/register → gets wk_...

# 2. Login to CLI with wallet key
outlayer login --wallet-key wk_15807dbda...

# 3. All commands work transparently
outlayer deploy my-agent
outlayer keys create
outlayer run alice.near/my-agent '{"test": true}'
outlayer secrets set '{"API_KEY":"sk-..."}' --project alice.near/my-agent
outlayer earnings
```

## References

- [Token reference](references/token-reference.md) - popular tokens with IDs, decimals, chains
- [Cross-chain patterns](references/cross-chain-patterns.md) - complete workflow examples
