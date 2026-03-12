# WASM Environment Variables

Environment variables available to WASI modules during OutLayer execution.

## Safe Access Pattern

```rust
// CORRECT - won't panic
let value = std::env::var("VAR_NAME").ok();
let value = std::env::var("VAR_NAME").unwrap_or_default();
let value = std::env::var("VAR_NAME").unwrap_or("fallback".to_string());

// WRONG - may panic
let value = std::env::var("VAR_NAME").unwrap();
```

## Always Available

| Variable | Values | Description |
|----------|--------|-------------|
| `OUTLAYER_EXECUTION_TYPE` | `"NEAR"` / `"HTTPS"` | Execution mode |
| `NEAR_NETWORK_ID` | `"testnet"` / `"mainnet"` | Network |
| `NEAR_SENDER_ID` | Account ID | Caller's account |
| `NEAR_USER_ACCOUNT_ID` | Account ID | Same as sender |
| `NEAR_MAX_INSTRUCTIONS` | Number | Max WASM instructions |
| `NEAR_MAX_MEMORY_MB` | Number | Max memory (MB) |
| `NEAR_MAX_EXECUTION_SECONDS` | Number | Max time (seconds) |

## Project Variables (Only via Project)

| Variable | Example | Description |
|----------|---------|-------------|
| `OUTLAYER_PROJECT_ID` | `owner/name` | Full project ID |
| `OUTLAYER_PROJECT_OWNER` | `alice.near` | Owner account |
| `OUTLAYER_PROJECT_NAME` | `my-app` | Project name |
| `OUTLAYER_PROJECT_UUID` | UUID | Internal ID |

Not set when running via GitHub URL directly.

## Payment Variables

| Variable | NEAR Mode | HTTPS Mode |
|----------|-----------|------------|
| `NEAR_PAYMENT_YOCTO` | Attached NEAR | `"0"` |
| `ATTACHED_USD` | USD from contract | `"0"` |
| `USD_PAYMENT` | `"0"` | X-Attached-Deposit |

```rust
// Parse payment (1_000_000 = $1.00)
let usd_payment: u64 = std::env::var("USD_PAYMENT")
    .unwrap_or_default()
    .parse()
    .unwrap_or(0);
```

## Blockchain Context (NEAR Mode Only)

| Variable | Description |
|----------|-------------|
| `NEAR_CONTRACT_ID` | OutLayer contract |
| `NEAR_BLOCK_HEIGHT` | Block number |
| `NEAR_BLOCK_TIMESTAMP` | Timestamp (nanoseconds) |
| `NEAR_RECEIPT_ID` | Receipt ID |
| `NEAR_TRANSACTION_HASH` | Transaction hash |
| `NEAR_SIGNER_PUBLIC_KEY` | Signer's public key |
| `NEAR_PREDECESSOR_ID` | Who called the contract |
| `NEAR_GAS_BURNT` | Gas consumed |
| `NEAR_REQUEST_ID` | Execution request ID (u64) |

In HTTPS mode these are empty strings `""`.

```rust
let block_height: Option<u64> = std::env::var("NEAR_BLOCK_HEIGHT")
    .ok()
    .filter(|s| !s.is_empty())
    .and_then(|s| s.parse().ok());
```

## HTTPS-Specific

| Variable | NEAR Mode | HTTPS Mode |
|----------|-----------|------------|
| `OUTLAYER_CALL_ID` | `""` | Call UUID |

## Conditional Variables

| Variable | When Set | Value |
|----------|----------|-------|
| `WALLET_ID` | If wallet_id in request header | Wallet public key (e.g. `ed25519:...`) |
| `NEAR_RPC_PROXY_AVAILABLE` | WASI P2 only | `"1"` when RPC proxy is available |

## User Secrets

Your encrypted secrets are available by name:

```rust
let api_key = std::env::var("MY_API_KEY").ok();
```

## Complete Example

```rust
use std::env;

fn main() {
    // Detect mode
    let exec_type = env::var("OUTLAYER_EXECUTION_TYPE").unwrap_or_default();
    let is_https = exec_type == "HTTPS";

    // Get user
    let sender = env::var("NEAR_SENDER_ID").unwrap_or_default();

    // Get network suffix
    let network = env::var("NEAR_NETWORK_ID").unwrap_or_default();
    let suffix = if network == "testnet" { ".testnet" } else { ".near" };

    // Get project info (optional)
    let project = env::var("OUTLAYER_PROJECT_ID").ok();

    // Get payment based on mode
    let payment = if is_https {
        env::var("USD_PAYMENT").unwrap_or_default()
    } else {
        env::var("NEAR_PAYMENT_YOCTO").unwrap_or_default()
    };

    println!("Mode: {}", exec_type);
    println!("Sender: {}", sender);
    println!("Payment: {}", payment);
}
```

## Recommended: OutLayer SDK

For WASI P2, prefer the SDK over raw env vars:

```rust
use outlayer::env;

// Type-safe, returns Option<String>
let signer = env::signer_account_id();
```
