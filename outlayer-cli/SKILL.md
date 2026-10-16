---
name: outlayer-cli
description: Deploy, run, and manage OutLayer WASI agents from the command line. Use when building, deploying, or operating OutLayer agents - project scaffolding, publishing and deploying .wasm builds, HTTPS and on-chain execution, secrets management, payment keys, FastFS uploads, version control, and earnings.
metadata:
  install: "curl -fsSL https://raw.githubusercontent.com/out-layer/outlayer-cli/main/install.sh | sh"
  config: ~/.outlayer/
  project_config: outlayer.toml
---

# OutLayer CLI

Command-line tool for deploying, running, and managing WASI agents on OutLayer (verifiable off-chain compute on NEAR).

## Quick Start

```bash
# Install (macOS / Linux)
curl -fsSL https://raw.githubusercontent.com/out-layer/outlayer-cli/main/install.sh | sh
# Or via cargo: cargo install outlayer-cli

# Login with NEAR private key (prompts for Account ID + ed25519 private key)
outlayer login              # mainnet
outlayer login testnet      # testnet

# Or login with Agent Custody wallet key (for AI agents)
outlayer login --wallet-key wk_...

# Create, build, publish, deploy
outlayer create my-agent
cd my-agent
# edit src/main.rs
./build.sh
outlayer upload out/my-agent.wasm             # prints SHA256 and the FastFS URL
outlayer deploy my-agent <FastFS URL>

# Create payment key for HTTPS calls
outlayer keys create

# Run
outlayer run alice.near/my-agent '{"command": "hello"}'
```

## Authentication

Two login modes: **NEAR private key** (direct signing) or **wallet API key** (custody signing via coordinator).

```bash
# Login with NEAR private key (default - prompts for Account ID + private key)
outlayer login              # mainnet
outlayer login testnet      # testnet

# Login with custody wallet API key (for agents using OutLayer Agent Custody)
outlayer login --wallet-key wk_15807dbda492636df5280629d7617c3ea80f915ba960389b621e420ca275e545
outlayer login testnet --wallet-key wk_...

outlayer whoami             # show current account, network, public key, auth type
outlayer logout             # delete stored credentials
```

Credentials: `~/.outlayer/{network}/credentials.json` + OS keychain (macOS Keychain / Linux Secret Service).
Active network: `~/.outlayer/default-network` (auto-detected if not set).

### Auth Types

| auth_type | How it works | Use case |
|-----------|-------------|----------|
| `near_key` | Signs transactions locally with ed25519 private key | Humans, scripts with full access key |
| `wallet_key` | Routes signing through coordinator `POST /wallet/v1/call` | AI agents using Agent Custody wallets |

When logged in with `--wallet-key`, all commands that need transaction signing (deploy, run, keys, secrets, earnings, versions) use the coordinator wallet API instead of local signing. Upload (FastFS) requires `near_key` auth for now.

The CLI is a CONVENIENCE, never a prerequisite: everything it does is an HTTP
call you can make yourself. The network argument is the same axis as the API
host — credentials are kept per network in `~/.outlayer/{network}/credentials.json`,
and a testnet `wk_` is a testnet wallet. It is not a separate "platform" setting
layered over a mainnet wallet.

Login with `--wallet-key` calls `/wallet/v1/sign-message` to derive the account ID and public key, then stores the wallet key in `~/.outlayer/{network}/credentials.json` with `auth_type: "wallet_key"`.

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

Not supported with `wallet_key`:

| Command | Reason |
|---------|--------|
| Limit orders | HTTP API (and SDK) only, like payment checks — no CLI command and no WASI host function until a user asks for one. Use `POST /wallet/v1/limit-orders` |
| `outlayer upload` (FastFS) | Uses raw Borsh-encoded transaction args - `/wallet/v1/call` only accepts JSON. Use `outlayer login` with a NEAR private key for uploads. |

`whoami` output includes `Auth: near_key` or `Auth: wallet_key`.

## Project Scaffolding

```bash
outlayer create my-agent                      # basic template (stdin/stdout WASI)
outlayer create my-agent --template contract   # with OutLayer SDK (VRF, storage, RPC)
outlayer create my-agent --dir /custom/path    # custom directory
```

Templates are Rust + wasm32-wasip2. Both generate: `Cargo.toml`, `src/main.rs`, `build.sh`, `.gitignore`, `outlayer.toml`.

### outlayer.toml

Created by `outlayer create`, used by deploy/run/secrets/versions:

```toml
[project]
name = "my-agent"
owner = "alice.near"

[build]
target = "wasm32-wasip2"
source = "wasm_url"

[run]
payment_key_nonce = 1
```

## Deploy

```bash
outlayer deploy my-agent <wasm-url>             # create the project or add a version, and activate it
outlayer deploy my-agent <wasm-url> --no-activate   # add the version without activating
outlayer deploy my-agent <wasm-url> --hash <sha256> # name the hash (omitted: the CLI downloads the file and computes it)
```

A version is a published `.wasm`, named by its sha256: what a caller runs and pays for cannot
change under that version afterwards. Build it yourself (`./build.sh` in a scaffold, or
`cargo build --target wasm32-wasip2 --release`), publish it with `outlayer upload`, then deploy
the URL. The worker refuses a file whose bytes do not match the hash. Any `https://` URL works; FastFS is the default. For a reproducible build (same pinned
Docker image, same hash on every machine) use `scripts/build_github_wasm.sh --dir ./my-agent
--target wasm32-wasip2` from the OutLayer repository (`https://github.com/out-layer/outlayer`).

## Run (Execute Agent)

Two modes: **HTTPS** (if payment key available) or **on-chain** (fallback via NEAR transaction).

```bash
# Basic
outlayer run alice.near/my-agent '{"command": "hello"}'
outlayer run alice.near/my-agent --input request.json        # input from file

# Options
outlayer run alice.near/my-agent '{}' --async                # async execution (HTTPS only)
outlayer run alice.near/my-agent '{}' --deposit 0.01         # attached deposit (USD)
outlayer run alice.near/my-agent '{}' --compute-limit 1000000000  # custom compute limit
outlayer run alice.near/my-agent '{}' --version abc123       # specific version

# Attach secrets
outlayer run alice.near/my-agent '{}' --secrets-profile default --secrets-account alice.near

# Run from WASM URL (on-chain only)
outlayer run --wasm https://main.fastfs.io/alice.near/outlayer.near/abc.wasm '{"cmd": "hi"}'
outlayer run --wasm https://example.com/file.wasm --hash abc123... '{}'
```

### HTTPS mode

When a payment key is configured, `outlayer run` sends:

```
POST https://api.outlayer.ai/call/{owner}/{project}
X-Payment-Key: owner:nonce:secret
Content-Type: application/json

{"input": ..., "async": false}
```

### On-chain mode

Calls `request_execution` on `outlayer.near` contract via NEAR transaction. Used when no payment key is available, or when `--wasm` is used.

## Secrets

Encrypted client-side with TEE public key. Decrypted only inside TEE during execution. Values are **JSON objects** (not KEY=val pairs).

```bash
# Set (overwrites all existing secrets for this accessor)
outlayer secrets set '{"API_KEY":"sk-...","DB_URL":"postgres://..."}'

# Accessor types (which agent can read these secrets)
outlayer secrets set '{"KEY":"val"}' --project alice.near/my-agent
outlayer secrets set '{"KEY":"val"}' --wasm-hash abc123...   # the row a direct `run --wasm` reads
# Rows bound to a repository are listed and can only be deleted; set/update/access refuse --repo
outlayer secrets delete --repo github.com/user/repo --branch main

# Named profile
outlayer secrets set '{"KEY":"val"}' --profile production

# Generate protected secrets in TEE (values never visible, even to owner)
outlayer secrets set --generate PROTECTED_MASTER_KEY:hex32
outlayer secrets set '{"API_KEY":"sk-..."}' --generate PROTECTED_DB:hex64   # mixed

# Generation types: hex16, hex32, hex64, ed25519, ed25519_seed, password, password:N

# Access control
outlayer secrets set '{"KEY":"val"}' --access allow-all                     # everyone who names it
outlayer secrets set '{"KEY":"val"}' --access whitelist:alice.near,bob.near
# Without --access: a row that exists keeps its condition; a new project row admits only you;
# a new hash row admits everyone.

# Update (merge - preserves existing keys, preserves all PROTECTED_* variables)
outlayer secrets update '{"NEW_KEY":"val"}' --project alice.near/my-agent
outlayer secrets update --generate PROTECTED_NEW:ed25519

# List / delete
outlayer secrets list
outlayer secrets delete --project alice.near/my-agent
outlayer secrets delete --profile production
```

Default accessor: `--project` auto-resolved from `outlayer.toml` if present.

**IMPORTANT**: `secrets set` overwrites ALL secrets for the accessor. Use `secrets update` to merge with existing.

## Payment Keys

Required for HTTPS API execution. Each key has a nonce and a USDC balance.

```bash
outlayer keys create                   # create new key → prints key string (save it!)
outlayer keys list                     # list keys with balances
outlayer keys balance <nonce>          # check specific key balance
outlayer keys topup <nonce> <amount>   # top up with NEAR (auto-swaps to USDC on mainnet)
outlayer keys delete <nonce>           # delete key: storage deposit refunded, remaining balance forfeited; its nonce is not freed
```

Key format: `owner:nonce:secret` (e.g., `alice.near:1:a1b2c3d4e5f6...`).

**Key cannot be recovered after creation** - save it immediately. The one
exception is a custody wallet's nonce-0 key (its trial, or a sponsor code's
subscription): it is derived, and read again on request.

```bash
outlayer redeem spn_... --api-key wk_...   # sponsor code → subscription on the wallet's nonce-0 key; stdout = the key
outlayer keys trial-key --api-key wk_...   # print the wallet's nonce-0 key again
```

Both take the wallet key from `--api-key`, then `OUTLAYER_WALLET_KEY`. A code
that cannot be redeemed answers `sponsor_code_invalid` whatever the reason —
ask whoever gave it; `sponsor_cannot_top_up` means the key already holds more.
An older nonce-0 key issued at random (`payment_key_not_recoverable`) redeems
with `--payment-key owner:0:key`; stdout is then the derived key that replaces it.

## Payment Checks (Agent-to-Agent)

Trustless agent-to-agent payments via ephemeral intents accounts. Requires a wallet API key (`wk_...`) - pass via `--api-key` flag or `OUTLAYER_WALLET_KEY` env var.

```bash
# Set wallet API key (from POST /register)
export OUTLAYER_WALLET_KEY=wk_15807dbda492636df5280629d7617c3ea80f915ba960389b621e420ca275e545

# Create a check for 1 USDC with memo and 24h expiry
outlayer checks create 17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1 1000000 \
  --memo "Payment for task" --expires-in 86400
# → check_id: pc_..., check_key: ed25519:... (save and send to recipient!)

# Or pass key inline:
outlayer checks --api-key wk_... create <token> <amount>

# Batch create from JSON file
outlayer checks batch-create --file checks.json

# Claim a check (full)
outlayer checks claim ed25519:5Kd3NBU...

# Partial claim (take part of the check)
outlayer checks claim ed25519:5Kd3NBU... --amount 500000

# Reclaim unclaimed funds (full)
outlayer checks reclaim pc_a1b2c3d4e5f6

# Partial reclaim
outlayer checks reclaim pc_a1b2c3d4e5f6 --amount 300000

# Check status
outlayer checks status pc_a1b2c3d4e5f6

# List checks (with optional filters)
outlayer checks list
outlayer checks list --status unclaimed --limit 50

# Peek at check balance before claiming
outlayer checks peek ed25519:5Kd3NBU...

# Sign a message (NEP-413) for external service auth
outlayer checks sign-message "Login to example.com" example.com
outlayer checks sign-message "Login to example.com" example.com --nonce "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# → account_id, public_key, signature, nonce
```

Token is the plain NEAR contract ID (e.g. USDC: `17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1`). Amount is in smallest denomination (USDC: 6 decimals, so `1000000` = 1 USDC).

Claimed funds land in the recipient's **intents balance**. Use `/intents/withdraw` (gasless) to move them to a NEAR account. Note: the receiver must have storage registered on the token contract first - use `/storage-deposit` if needed.

## Upload (FastFS)

Upload files to on-chain storage (NEAR FastFS) via NEAR transactions.

```bash
outlayer upload ./target/wasm32-wasip2/release/my-agent.wasm
# → https://main.fastfs.io/alice.near/outlayer.near/abcdef.wasm

outlayer upload <file> --receiver <account>    # custom receiver (default: network contract - outlayer.near mainnet / outlayer.testnet testnet)
outlayer upload <file> --mime-type <type>      # override MIME type
```

Files >1MB are automatically chunked into multiple transactions.

**Important:** Upload transactions will show "Exceeded the prepaid gas" - this is expected and by design. Gas is intentionally set to 1 to minimize costs. No contract execution is needed - the NEAR indexer picks up file data from the transaction arguments regardless of execution status. The file will be available at its FastFS URL after indexing, which takes 1–2 minutes. Chunked uploads (files >1MB) may take longer since all chunks must be indexed before the file is assembled.

## Versions

```bash
outlayer versions                     # list project versions (requires outlayer.toml)
outlayer versions activate <key>      # switch active version
outlayer versions remove <key>        # remove a version
```

## Earnings

```bash
outlayer earnings                              # view blockchain + HTTPS earnings
outlayer earnings withdraw                     # withdraw blockchain earnings
outlayer earnings history                      # view earnings history
outlayer earnings history --source blockchain  # filter by source
outlayer earnings history --limit 50           # custom limit
```

## Logs

```bash
outlayer logs                  # execution history for default payment key
outlayer logs --nonce 2        # history for specific key
outlayer logs --limit 50       # custom limit (default: 20)
```

## Other Commands

```bash
outlayer projects [account]    # list projects for account (default: logged-in user)
outlayer status [call_id]      # project info or poll async call status
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OUTLAYER_HOME` | Config directory (default: `~/.outlayer`) |
| `OUTLAYER_NETWORK` | Override network: `mainnet` or `testnet` |
| `PAYMENT_KEY` | Payment key for `outlayer run` (format: `owner:nonce:secret`) |
| `OUTLAYER_WALLET_KEY` | Wallet API key for `outlayer checks`, `redeem` and `keys trial-key` (format: `wk_...`) |

## Global Flags

```bash
outlayer --verbose ...         # verbose output (all commands)
```

## Typical Workflows

### New agent from scratch

```bash
outlayer login
outlayer create my-agent --template contract
cd my-agent
# write your agent in src/main.rs
./build.sh
outlayer upload out/my-agent.wasm
outlayer deploy my-agent <FastFS URL printed by upload>
outlayer keys create                    # save the key!
outlayer run alice.near/my-agent '{"test": true}'
```

### Deploy from pre-built WASM

```bash
outlayer upload ./my-agent.wasm
# copy the FastFS URL
outlayer deploy my-agent https://main.fastfs.io/alice.near/outlayer.near/abc.wasm
```

### Add secrets to existing agent

```bash
outlayer secrets set '{"OPENAI_KEY":"sk-...","DB_URL":"postgres://..."}' \
  --project alice.near/my-agent
# later, add more without overwriting:
outlayer secrets update '{"NEW_SECRET":"value"}' --project alice.near/my-agent
```

### Agent with custody wallet

```bash
# Agent registers a custody wallet via API
# POST https://api.outlayer.ai/register → gets wk_...

# Login with the wallet key
outlayer login --wallet-key wk_15807dbda...

# All commands work transparently - signing goes through coordinator
outlayer upload out/my-agent.wasm
outlayer deploy my-agent <FastFS URL printed by upload>
outlayer run alice.near/my-agent '{"test": true}'
outlayer secrets set '{"API_KEY":"sk-..."}' --project alice.near/my-agent
outlayer keys create
```

### Switch active version

```bash
outlayer versions                       # see available versions
outlayer versions activate abc123       # switch to specific version
```
