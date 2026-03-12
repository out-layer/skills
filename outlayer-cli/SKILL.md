---
name: outlayer-cli
description: Deploy, run, and manage OutLayer WASI agents from the command line. Use when building, deploying, or operating OutLayer agents — project scaffolding, GitHub/WASM deploys, HTTPS and on-chain execution, secrets management, payment keys, FastFS uploads, version control, and earnings.
metadata:
  install: cargo install --git https://github.com/out-layer/outlayer-cli
  config: ~/.outlayer/
  project_config: outlayer.toml
---

# OutLayer CLI

Command-line tool for deploying, running, and managing WASI agents on OutLayer (verifiable off-chain compute on NEAR).

## Quick Start

```bash
# Install
cargo install --git https://github.com/out-layer/outlayer-cli

# Login (prompts for Account ID + ed25519 private key)
outlayer login              # mainnet
outlayer login testnet      # testnet

# Create + deploy
outlayer create my-agent
cd my-agent
# edit src/main.rs, push to GitHub
outlayer deploy my-agent

# Create payment key for HTTPS calls
outlayer keys create

# Run
outlayer run alice.near/my-agent '{"command": "hello"}'
```

## Authentication

```bash
outlayer login              # mainnet (default) — prompts for Account ID + private key
outlayer login testnet      # testnet
outlayer whoami             # show current account, network, public key
outlayer logout             # delete stored credentials
```

Credentials: `~/.outlayer/{network}/credentials.json` + OS keychain (macOS Keychain / Linux Secret Service).
Active network: `~/.outlayer/default-network` (auto-detected if not set).

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
source = "github"

[run]
payment_key_nonce = 1
```

## Deploy

```bash
outlayer deploy my-agent                        # from current git repo (origin remote + HEAD commit)
outlayer deploy my-agent <wasm-url>             # from WASM URL (FastFS, etc.)
outlayer deploy my-agent --no-activate          # deploy without activating
```

GitHub deploy reads `origin` remote URL and current HEAD commit from the local git repo. The WASM is compiled on OutLayer workers from source.

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

# Run from GitHub (on-chain only)
outlayer run --github github.com/user/repo '{"command": "hello"}'
outlayer run --github github.com/user/repo --commit abc123 '{"input": 1}'

# Run from WASM URL (on-chain only)
outlayer run --wasm https://alice.near.fastfs.io/outlayer.near/abc.wasm '{"cmd": "hi"}'
outlayer run --wasm https://example.com/file.wasm --hash abc123... '{}'
```

### HTTPS mode

When a payment key is configured, `outlayer run` sends:

```
POST https://api.outlayer.fastnear.com/call/{owner}/{project}
X-Payment-Key: owner:nonce:secret
Content-Type: application/json

{"input": ..., "async": false}
```

### On-chain mode

Calls `request_execution` on `outlayer.near` contract via NEAR transaction. Used when no payment key is available, or when `--github`/`--wasm` flags are used.

## Secrets

Encrypted client-side with TEE public key. Decrypted only inside TEE during execution. Values are **JSON objects** (not KEY=val pairs).

```bash
# Set (overwrites all existing secrets for this accessor)
outlayer secrets set '{"API_KEY":"sk-...","DB_URL":"postgres://..."}'

# Accessor types (which agent can read these secrets)
outlayer secrets set '{"KEY":"val"}' --project alice.near/my-agent
outlayer secrets set '{"KEY":"val"}' --repo github.com/user/repo --branch main
outlayer secrets set '{"KEY":"val"}' --wasm-hash abc123...

# Named profile
outlayer secrets set '{"KEY":"val"}' --profile production

# Generate protected secrets in TEE (values never visible, even to owner)
outlayer secrets set --generate PROTECTED_MASTER_KEY:hex32
outlayer secrets set '{"API_KEY":"sk-..."}' --generate PROTECTED_DB:hex64   # mixed

# Generation types: hex16, hex32, hex64, ed25519, ed25519_seed, password, password:N

# Access control
outlayer secrets set '{"KEY":"val"}' --access allow-all                     # default
outlayer secrets set '{"KEY":"val"}' --access whitelist:alice.near,bob.near

# Update (merge — preserves existing keys, preserves all PROTECTED_* variables)
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
outlayer keys delete <nonce>           # delete key (refunds storage deposit)
```

Key format: `owner:nonce:secret` (e.g., `alice.near:1:a1b2c3d4e5f6...`).

**Key cannot be recovered after creation** — save it immediately.

## Payment Checks (Agent-to-Agent)

Trustless agent-to-agent payments via ephemeral intents accounts.

```bash
# Create a check for 1 USDC with memo and 24h expiry
outlayer checks create 17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1 1000000 \
  --memo "Payment for task" --expires-in 86400
# → check_id: pc_..., check_key: ed25519:... (save and send to recipient!)

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
```

Token is the plain NEAR contract ID (e.g. USDC: `17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1`). Amount is in smallest denomination (USDC: 6 decimals, so `1000000` = 1 USDC).

Claimed funds land in the recipient's **intents balance**. Use `/intents/withdraw` to move them.

## Upload (FastFS)

Upload files to on-chain storage (NEAR FastFS) via NEAR transactions.

```bash
outlayer upload ./target/wasm32-wasip2/release/my-agent.wasm
# → https://alice.near.fastfs.io/outlayer.near/abcdef.wasm

outlayer upload <file> --receiver <account>    # custom receiver (default: outlayer.near)
outlayer upload <file> --mime-type <type>      # override MIME type
```

Files >1MB are automatically chunked into multiple transactions.

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
git init && git add -A && git commit -m "init"
git remote add origin git@github.com:user/my-agent.git && git push
outlayer deploy my-agent
outlayer keys create                    # save the key!
outlayer run alice.near/my-agent '{"test": true}'
```

### Deploy from pre-built WASM

```bash
outlayer upload ./my-agent.wasm
# copy the FastFS URL
outlayer deploy my-agent https://alice.near.fastfs.io/outlayer.near/abc.wasm
```

### Add secrets to existing agent

```bash
outlayer secrets set '{"OPENAI_KEY":"sk-...","DB_URL":"postgres://..."}' \
  --project alice.near/my-agent
# later, add more without overwriting:
outlayer secrets update '{"NEW_SECRET":"value"}' --project alice.near/my-agent
```

### Switch active version

```bash
outlayer versions                       # see available versions
outlayer versions activate abc123       # switch to specific version
```
