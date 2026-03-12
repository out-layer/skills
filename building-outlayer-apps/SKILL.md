---
name: building-outlayer-apps
description: Build verifiable off-chain applications on NEAR OutLayer platform. Covers WASI module development in Rust, frontend integration with wallet-selector, Payment Keys, and NEP-413 authentication. Use when creating WASI containers, integrating with NEAR wallets, or building OutLayer-powered applications.
---

# Building OutLayer Apps

OutLayer is a verifiable off-chain computation platform for NEAR. Your code runs in TEE (Trusted Execution Environment) with:
- **WASI modules** (Rust) for backend logic
- **Frontend** (TypeScript/React) for user interaction
- **NEAR integration** for payments and authentication

## Quick Start: What Are You Building?

| Task | Technology | Reference |
|------|------------|-----------|
| Backend computation (no HTTP) | WASI P1 | [wasi-tutorial.md](references/wasi-tutorial.md) |
| Backend with HTTP requests | WASI P2 | [wasi-tutorial.md](references/wasi-tutorial.md) |
| NEAR contract calling OutLayer | Proxy contract | [proxy-contracts.md](references/proxy-contracts.md) |
| Frontend wallet connection | wallet-selector | [frontend-wallet.md](references/frontend-wallet.md) |
| No-popup API calls | Payment Keys | [frontend-payment-keys.md](references/frontend-payment-keys.md) |
| Off-chain authentication | NEP-413 signing | [frontend-nep413.md](references/frontend-nep413.md) |
| Available env vars in WASM | Environment | [wasi-env-vars.md](references/wasi-env-vars.md) |

**CRITICAL**: Read [rules/critical-rules.md](rules/critical-rules.md) before starting!

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│    Frontend     │────▶│  OutLayer API    │────▶│  WASI Module    │
│  (React/Next)   │     │  (Coordinator)   │     │  (Rust/WASM)    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                        │                       │
        ▼                        ▼                       ▼
   wallet-selector         PostgreSQL              TEE Worker
   Payment Keys            Redis                   wasmtime
   NEP-413 signing         WASM cache              outlayer SDK
```

## WASI Module Development (Backend)

### Choose Your Target

| Feature | WASI P1 | WASI P2 |
|---------|---------|---------|
| Target | `wasm32-wasip1` | `wasm32-wasip2` |
| HTTP requests | No | Yes |
| Binary size | ~100-200KB | ~500KB-1MB |
| Use case | Simple computation | HTTP APIs, complex I/O |

**Rule**: Use P1 unless you need HTTP.

### Minimal WASI P1 Example

```rust
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

#[derive(Deserialize)]
struct Input { value: i32 }

#[derive(Serialize)]
struct Output { result: i32 }

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let data: Input = serde_json::from_str(&input)?;

    let output = Output { result: data.value * 2 };

    print!("{}", serde_json::to_string(&output)?);
    io::stdout().flush()?;  // MUST flush!
    Ok(())
}
```

```bash
# Build
cargo build --target wasm32-wasip1 --release

# Test
echo '{"value":21}' | wasmtime target/wasm32-wasip1/release/my-app.wasm
```

**Full tutorial**: [references/wasi-tutorial.md](references/wasi-tutorial.md)

## Frontend Integration

### Three Ways to Call OutLayer

| Method | Popup | Speed | Max Payload | Use Case |
|--------|-------|-------|-------------|----------|
| Blockchain TX | Yes | Slower | ~1.5MB | Default, most secure |
| Payment Key | No | Fast | 10MB | Frequent operations |
| NEP-413 Sign | Once | Fast | N/A | Off-chain auth |

### Quick Wallet Setup

```typescript
import { setupWalletSelector } from '@near-wallet-selector/core';
import { setupMyNearWallet } from '@near-wallet-selector/my-near-wallet';
import { actionCreators } from '@near-js/transactions';

const selector = await setupWalletSelector({
  network: process.env.NEXT_PUBLIC_NETWORK_ID || 'mainnet',
  modules: [setupMyNearWallet()],
});

// IMPORTANT: Use actionCreators, not raw objects!
const action = actionCreators.functionCall(
  'request_execution',
  {
    source: { Project: { project_id: 'owner.near/project', version_key: null } },
    input_data: JSON.stringify({ action: 'process' }),
    resource_limits: { max_instructions: 2000000000, max_memory_mb: 512, max_execution_seconds: 120 },
    response_format: 'Json',
  },
  BigInt('300000000000000'),
  BigInt('100000000000000000000000')
);

const wallet = await selector.wallet();
await wallet.signAndSendTransaction({
  receiverId: process.env.NEXT_PUBLIC_OUTLAYER_CONTRACT,
  actions: [action],
});
```

**Full guides**:
- [Wallet integration](references/frontend-wallet.md)
- [Payment Keys](references/frontend-payment-keys.md)
- [NEP-413 signing](references/frontend-nep413.md)

## OutLayer SDK (WASI P2)

```rust
use outlayer::{env, storage};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let signer = env::signer_account_id()
        .ok_or("Must be called via NEAR transaction or Payment Key")?;

    storage::set_worker("key", b"value")?;
    let data = storage::get_worker("key")?;

    let network = std::env::var("NEAR_NETWORK_ID").unwrap_or("mainnet".to_string());
    Ok(())
}
```

## Project Structure

### Full Stack App
```
my-app/
├── .env.local              # Environment variables (URLs, keys)
├── wasi-module/
│   ├── Cargo.toml
│   └── src/main.rs
└── web-ui/
    ├── package.json
    ├── .env.local          # Frontend env vars
    └── src/
```

### With Embedded NEAR Contract
```
my-app/
├── Cargo.toml              # Workspace
├── src/main.rs             # WASI entry
├── my-contract/
│   ├── Cargo.toml          # edition = "2018"!
│   ├── rust-toolchain.toml # channel = "1.85.0"
│   └── src/lib.rs
└── build.sh
```

## Deployment

### Via Blockchain
```bash
near call $OUTLAYER_CONTRACT request_execution '{
  "source": { "Project": { "project_id": "you.near/app" } },
  "input_data": "{\"action\":\"test\"}",
  "resource_limits": { "max_instructions": 2000000000, "max_memory_mb": 512 }
}' --accountId you.near --deposit 0.1
```

### Via HTTPS API
```bash
curl -X POST "$OUTLAYER_API_URL/call/owner.near/project" \
  -H "Content-Type: application/json" \
  -H "X-Payment-Key: $PAYMENT_KEY" \
  -d '{"input": {"action": "test"}}'
```

## Reference Files

| File | Content |
|------|---------|
| [wasi-tutorial.md](references/wasi-tutorial.md) | WASI P1/P2 development, I/O, SDK, pitfalls |
| [wasi-env-vars.md](references/wasi-env-vars.md) | All environment variables available in WASM |
| [proxy-contracts.md](references/proxy-contracts.md) | NEAR contracts calling OutLayer |
| [frontend-wallet.md](references/frontend-wallet.md) | Wallet-selector setup, transaction handling |
| [frontend-payment-keys.md](references/frontend-payment-keys.md) | Payment Keys for no-popup API calls |
| [frontend-nep413.md](references/frontend-nep413.md) | NEP-413 signing for authentication |
| [critical-rules.md](rules/critical-rules.md) | Must-read rules to avoid common errors |
