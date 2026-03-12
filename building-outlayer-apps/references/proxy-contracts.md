# Proxy Contracts for OutLayer

NEAR smart contracts that call OutLayer for off-chain computation.

## Architecture

```
User → Your Contract → OutLayer Contract → Worker → Callback → Your Contract
```

## Setup

### Cargo.toml

```toml
[dependencies]
near-sdk = { version = "5.9.0", features = ["legacy"] }
schemars = "0.8"
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[lib]
crate-type = ["cdylib"]

[profile.release]
codegen-units = 1
opt-level = "s"
lto = true
```

### rust-toolchain.toml

```toml
[toolchain]
channel = "1.85.0"
```

## OutLayer Contract Interface

```rust
use near_sdk::{ext_contract, AccountId, Gas, NearToken};

// Use env var in production!
const OUTLAYER_CONTRACT_ID: &str = "outlayer.near";

#[ext_contract(ext_outlayer)]
trait OutLayer {
    fn request_execution(
        &mut self,
        source: serde_json::Value,
        resource_limits: Option<serde_json::Value>,
        input_data: Option<String>,
        secrets_ref: Option<serde_json::Value>,
        response_format: Option<String>,
        payer_account_id: Option<AccountId>,
        params: Option<serde_json::Value>,
    );
}
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `source` | JSON | GitHub repo, Project ID, or WASM URL |
| `resource_limits` | Option\<JSON\> | Memory, instructions, time limits |
| `input_data` | Option\<String\> | JSON input for WASM |
| `secrets_ref` | Option\<JSON\> | `{ "profile": "...", "account_id": "..." }` |
| `response_format` | Option\<String\> | `"Text"` (default), `"Json"`, or `"Bytes"` |
| `payer_account_id` | Option | Who gets refund on failure |
| `params` | Option\<JSON\> | `force_rebuild`, `compile_only`, `store_on_fastfs` |

## Source Formats

### Project (most common)

```rust
let source = serde_json::json!({
    "Project": {
        "project_id": "alice.near/my-app",
        "version_key": null
    }
});
```

### GitHub

```rust
let source = serde_json::json!({
    "GitHub": {
        "repo": "https://github.com/owner/repo",
        "commit": "HEAD"
    }
});
```

### WASM URL

```rust
let source = serde_json::json!({
    "WasmUrl": {
        "url": "https://alice.near.fastfs.io/outlayer.near/abc.wasm",
        "hash": "abc123..."
    }
});
```

## Complete Example: Coin Flip

```rust
use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
use near_sdk::{env, near_bindgen, AccountId, Gas, NearToken, Promise, PromiseError};

const OUTLAYER_CONTRACT_ID: &str = "outlayer.near";
const MIN_DEPOSIT: NearToken = NearToken::from_millinear(10);
const CALLBACK_GAS: Gas = Gas::from_tgas(5);

#[ext_contract(ext_outlayer)]
trait OutLayer {
    fn request_execution(
        &mut self,
        source: serde_json::Value,
        resource_limits: Option<serde_json::Value>,
        input_data: Option<String>,
        secrets_ref: Option<serde_json::Value>,
        response_format: Option<String>,
        payer_account_id: Option<AccountId>,
        params: Option<serde_json::Value>,
    );
}

#[ext_contract(ext_self)]
trait SelfCallback {
    fn on_flip_result(&mut self, player: AccountId) -> String;
}

#[near_bindgen]
#[derive(BorshDeserialize, BorshSerialize, Default)]
pub struct CoinFlip {
    wins: u64,
    losses: u64,
}

#[near_bindgen]
impl CoinFlip {
    #[payable]
    pub fn flip(&mut self) -> Promise {
        let deposit = env::attached_deposit();
        assert!(deposit >= MIN_DEPOSIT, "Minimum deposit is 0.01 NEAR");

        let player = env::predecessor_account_id();

        let source = serde_json::json!({
            "Project": { "project_id": "owner.near/random-wasm" }
        });

        let resource_limits = serde_json::json!({
            "max_memory_mb": 64,
            "max_instructions": 1_000_000_000u64,
            "max_execution_seconds": 30
        });

        let input_data = serde_json::json!({ "action": "flip" }).to_string();

        let remaining_gas = env::prepaid_gas().saturating_sub(CALLBACK_GAS);

        ext_outlayer::ext(OUTLAYER_CONTRACT_ID.parse().unwrap())
            .with_attached_deposit(deposit)
            .with_static_gas(remaining_gas)
            .with_unused_gas_weight(1)
            .request_execution(
                source,
                Some(resource_limits),
                Some(input_data),
                None,
                Some("Text".into()),
                Some(player.clone()),
                None,
            )
            .then(
                ext_self::ext(env::current_account_id())
                    .with_static_gas(CALLBACK_GAS)
                    .on_flip_result(player)
            )
    }

    #[private]
    pub fn on_flip_result(
        &mut self,
        player: AccountId,
        #[callback_result] result: Result<Option<String>, PromiseError>,
    ) -> String {
        match result {
            Ok(Some(output)) => {
                if output.contains("heads") {
                    self.wins += 1;
                    format!("{} won! {}", player, output)
                } else {
                    self.losses += 1;
                    format!("{} lost! {}", player, output)
                }
            }
            Ok(None) => "No result".to_string(),
            Err(_) => "Execution failed".to_string(),
        }
    }
}
```

## Parsing JSON Results

OutLayer wraps JSON responses:

```rust
#[derive(Deserialize)]
struct OutLayerResponse<T> {
    success: bool,
    output: Option<T>,
    error: Option<String>,
}

#[private]
pub fn on_result(
    &mut self,
    #[callback_result] result: Result<Option<String>, PromiseError>,
) {
    let Ok(Some(raw)) = result else { return; };

    let response: OutLayerResponse<MyData> = match serde_json::from_str(&raw) {
        Ok(r) => r,
        Err(e) => {
            env::log_str(&format!("Parse error: {}", e));
            return;
        }
    };

    if !response.success {
        env::log_str(&format!("WASM error: {:?}", response.error));
        return;
    }

    if let Some(data) = response.output {
        // Use data
    }
}
```

## Using Secrets

```rust
let secrets_ref = serde_json::json!({
    "profile": "default",
    "account_id": env::current_account_id(),
});

ext_outlayer::ext(...)
    .request_execution(
        source,
        Some(resource_limits),
        Some(input_data),
        Some(secrets_ref),  // <- pass secrets
        Some("Json".into()),
        Some(player),
        None,
    )
```

WASM accesses via env vars:
```rust
let api_key = std::env::var("API_KEY").ok();
```

## Gas Management

```rust
const CALLBACK_GAS: Gas = Gas::from_tgas(5);

// Give remaining gas to OutLayer
let remaining_gas = env::prepaid_gas()
    .saturating_sub(CALLBACK_GAS)
    .saturating_sub(Gas::from_tgas(5));

ext_outlayer::ext(...)
    .with_static_gas(remaining_gas)
    .with_unused_gas_weight(1)  // Important!
    .request_execution(...)
```

`with_unused_gas_weight(1)` gives unused gas to OutLayer call.

## Deposit Requirements

Minimum: **0.01 NEAR**

```rust
const MIN_DEPOSIT: NearToken = NearToken::from_millinear(10);

#[payable]
pub fn my_method(&mut self) -> Promise {
    let deposit = env::attached_deposit();
    assert!(deposit >= MIN_DEPOSIT, "Minimum 0.01 NEAR");
    // ...
}
```

Unused deposit refunded to `payer_account_id`.

## Callback Result Types

```rust
#[callback_result] result: Result<Option<String>, PromiseError>
```

| Result | Meaning |
|--------|---------|
| `Ok(Some(output))` | Success |
| `Ok(None)` | Success, no output |
| `Err(PromiseError)` | Failed |

## Build & Deploy

```bash
cargo near build

near deploy your-contract.testnet ./target/near/your_contract.wasm

near call your-contract.testnet flip '{}' \
    --accountId alice.testnet \
    --deposit 0.1 \
    --gas 100000000000000
```

## Project Structure

```
my-proxy/
├── Cargo.toml
├── rust-toolchain.toml
└── src/
    └── lib.rs
```
