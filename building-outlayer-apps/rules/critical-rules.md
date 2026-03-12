# Critical Rules for OutLayer Development

Read these rules before starting any OutLayer project. They prevent the most common mistakes.

## 1. Environment Variables in .env

**ALWAYS** put configurable parameters in `.env` files, not hardcoded in code:

### Frontend (.env.local)

```bash
# Network configuration
NEXT_PUBLIC_NETWORK_ID=mainnet
NEXT_PUBLIC_OUTLAYER_CONTRACT=outlayer.near
NEXT_PUBLIC_OUTLAYER_API_URL=https://api.outlayer.fastnear.com

# Project identification
NEXT_PUBLIC_PROJECT_OWNER=your-account.near
NEXT_PUBLIC_PROJECT_NAME=your-project

# RPC endpoints
NEXT_PUBLIC_NEAR_RPC_URL=https://rpc.mainnet.fastnear.com
NEXT_PUBLIC_FASTNEAR_API_URL=https://api.fastnear.com

# Optional: for testnet development
# NEXT_PUBLIC_NETWORK_ID=testnet
# NEXT_PUBLIC_OUTLAYER_CONTRACT=outlayer.testnet
# NEXT_PUBLIC_NEAR_RPC_URL=https://rpc.testnet.fastnear.com
# NEXT_PUBLIC_FASTNEAR_API_URL=https://test.api.fastnear.com
```

### Usage in TypeScript

```typescript
// CORRECT: Use environment variables
const NETWORK_ID = process.env.NEXT_PUBLIC_NETWORK_ID || 'mainnet';
const OUTLAYER_CONTRACT = process.env.NEXT_PUBLIC_OUTLAYER_CONTRACT || 'outlayer.near';
const API_URL = process.env.NEXT_PUBLIC_OUTLAYER_API_URL || 'https://api.outlayer.fastnear.com';

// WRONG: Hardcoded values
const OUTLAYER_CONTRACT = 'outlayer.near';  // Don't do this!
```

### Why .env?

1. **Easy switching** between testnet/mainnet
2. **No code changes** for different deployments
3. **Secrets stay out** of version control (.gitignore)
4. **Clear configuration** in one place

---

## 2. Build Targets (NEVER confuse these!)

| What | Target | Build Command |
|------|--------|---------------|
| WASI Module | `wasm32-wasip1` / `wasm32-wasip2` | `cargo build --target wasm32-wasip1 --release` |
| NEAR Contract | `wasm32-unknown-unknown` | `cargo near build` |

```bash
# WASI Module
cargo build --target wasm32-wasip1 --release  # or wasip2

# NEAR Contract (NEVER use raw cargo build!)
cargo near build
```

---

## 3. NEAR Contract Requirements

```toml
# rust-toolchain.toml (REQUIRED in contract directory!)
[toolchain]
channel = "1.85.0"
```

```toml
# Cargo.toml
[dependencies]
near-sdk = { version = "5.9.0", features = ["legacy"] }
schemars = "0.8"  # Required for ABI
```

```rust
// All public types need JsonSchema
use schemars::JsonSchema;

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct MyType {
    #[schemars(with = "String")]  // Required for AccountId!
    pub owner: AccountId,
}
```

---

## 4. WASI Tested Dependencies

Copy from working examples, don't use `cargo add`:

```toml
# WASI P1/P2 - TESTED VERSIONS
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# WASI P2 only
wasi-http-client = "0.2"
outlayer = "0.1"

# For embedded contracts
borsh = { version = "1.5", features = ["derive"] }
base64 = "0.21"
ed25519-dalek = "2.1"
```

---

## 5. Always Flush stdout

```rust
// WRONG - output may be empty
print!("{}", serde_json::to_string(&output)?);

// CORRECT
print!("{}", serde_json::to_string(&output)?);
io::stdout().flush()?;  // MUST flush!
```

---

## 6. Frontend: actionCreators Required

```typescript
import { actionCreators } from '@near-js/transactions';

// WRONG - will fail with "Enum key (type) not found"
actions: [{
  type: 'FunctionCall',
  params: { methodName: 'my_method', ... }
}]

// CORRECT
actions: [actionCreators.functionCall('my_method', args, gas, deposit)]
```

---

## 7. One Wallet Call Per User Click

```typescript
// WRONG - second popup will be BLOCKED
async function bad() {
  await wallet.signMessage({...});  // OK
  await wallet.signMessage({...});  // BLOCKED!
}

// CORRECT - cache signatures, one call per click
async function good() {
  const cached = getCache();
  if (cached) return cached;
  return await wallet.signMessage({...});
}
```

---

## 8. OutLayer Response Wrapper

OutLayer returns wrapped format:

```json
{ "success": true, "result": {...}, "error": null }
```

Handle it in callbacks:

```rust
#[derive(Deserialize)]
pub struct OutLayerResponse {
    pub success: bool,
    pub result: serde_json::Value,
    pub error: Option<String>,
}

// Parse result field separately
let data: MyType = serde_json::from_value(response.result)?;
```

---

## 9. Embedded Contracts

```toml
# Contract Cargo.toml
[package]
edition = "2018"  # Must be 2018, not 2021!

[lib]
crate-type = ["cdylib"]

[profile.release]
opt-level = "s"  # "s" for contracts, not "z"
```

Build with:
```bash
cargo near build non-reproducible-wasm
```

---

## 10. Common Mistakes Summary

| Mistake | Fix |
|---------|-----|
| Hardcoded URLs | Use `.env` files |
| Wrong build target | P1/P2 for WASI, `cargo near` for contracts |
| Missing `rust-toolchain.toml` | Add with `channel = "1.85.0"` |
| Missing `stdout().flush()` | Always flush after print |
| Raw action objects | Use `actionCreators` |
| Multiple wallet popups | One call per user click |
| `edition = "2021"` in contract | Use `edition = "2018"` |
| `opt-level = "z"` in contract | Use `opt-level = "s"` |
