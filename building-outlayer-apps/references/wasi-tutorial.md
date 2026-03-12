# WASI Development Tutorial

## WASI P1 vs P2

| Feature | WASI P1 | WASI P2 |
|---------|---------|---------|
| Target | `wasm32-wasip1` | `wasm32-wasip2` |
| HTTP requests | No | Yes |
| Binary size | ~100-200KB | ~500KB-1MB |
| Use case | Simple computation | HTTP APIs |

**Rule**: Use P1 unless you need HTTP.

## Quick Start: WASI P1

### Cargo.toml

```toml
[package]
name = "my-app"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "my-app"
path = "src/main.rs"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[profile.release]
opt-level = "z"
lto = true
strip = true
```

### src/main.rs

```rust
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

#[derive(Deserialize)]
struct Input { name: String }

#[derive(Serialize)]
struct Output { greeting: String }

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Read from stdin
    let mut input_string = String::new();
    io::stdin().read_to_string(&mut input_string)?;
    let input: Input = serde_json::from_str(&input_string)?;

    // Process
    let output = Output {
        greeting: format!("Hello, {}!", input.name),
    };

    // Write to stdout and FLUSH
    print!("{}", serde_json::to_string(&output)?);
    io::stdout().flush()?;

    Ok(())
}
```

### Build & Test

```bash
rustup target add wasm32-wasip1
cargo build --target wasm32-wasip1 --release

echo '{"name":"World"}' | wasmtime target/wasm32-wasip1/release/my-app.wasm
# Output: {"greeting":"Hello, World!"}
```

## Quick Start: WASI P2 (with HTTP)

### Cargo.toml

```toml
[package]
name = "my-http-app"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "my-http-app"
path = "src/main.rs"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
wasi-http-client = "0.2"

[profile.release]
opt-level = "z"
lto = true
strip = true
```

### src/main.rs

```rust
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};
use wasi_http_client::{Client, Request, Method};

#[derive(Deserialize)]
struct Input { url: String }

#[derive(Serialize)]
struct Output { status: u16, body: String }

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut input_string = String::new();
    io::stdin().read_to_string(&mut input_string)?;
    let input: Input = serde_json::from_str(&input_string)?;

    // HTTP request
    let client = Client::new();
    let request = Request::new(Method::Get, &input.url);
    let response = client.send(request)?;

    let output = Output {
        status: response.status(),
        body: String::from_utf8_lossy(response.body()).to_string(),
    };

    print!("{}", serde_json::to_string(&output)?);
    io::stdout().flush()?;

    Ok(())
}
```

### Build

```bash
rustup target add wasm32-wasip2
cargo build --target wasm32-wasip2 --release
```

## OutLayer SDK

For WASI P2, use the `outlayer` crate:

```toml
[dependencies]
outlayer = "0.1"
```

### `outlayer::env` — Execution Context

```rust
use outlayer::env;

// Caller identity
let signer = env::signer_account_id();          // Option<String> — NEAR account or payment key owner
let predecessor = env::predecessor_account_id(); // Option<String> — contract that called OutLayer

// Input/output (alternative to raw stdin/stdout)
let input: MyInput = env::input_json()?.unwrap();  // Deserialize stdin as JSON
env::output_json(&my_output)?;                      // Serialize to stdout + flush

// Raw I/O
let raw_bytes: Vec<u8> = env::input();
let input_str: Option<String> = env::input_string();
env::output(b"raw bytes");
env::output_string("text");

// Environment variables (includes secrets)
let api_key: Option<String> = env::var("MY_API_KEY");
let has_key: bool = env::has_var("MY_API_KEY");

// Blockchain context
let tx_hash = env::transaction_hash();   // Option<String>
let req_id = env::request_id();          // Option<String>
```

`signer_account_id()` returns:
- `Some(account)` via blockchain transaction
- `Some(owner)` via HTTPS with Payment Key
- `None` via HTTPS without auth

### `outlayer::storage` — Persistent Encrypted Storage

```rust
use outlayer::storage;

// Worker-private storage (only your project can read/write)
storage::set_worker("key", b"value")?;
let data: Option<Vec<u8>> = storage::get_worker("key")?;

// Public storage (readable by other projects)
storage::set("key", b"value")?;
let data: Option<Vec<u8>> = storage::get("key")?;

// Convenience wrappers
storage::set_string("key", "text")?;
let text: Option<String> = storage::get_string("key")?;
storage::set_json("key", &my_struct)?;
let obj: Option<MyStruct> = storage::get_json("key")?;

// Key management
let exists: bool = storage::has("key");
let deleted: bool = storage::delete("key");
let keys: Vec<String> = storage::list_keys("prefix:")?;

// Atomic operations
let new_val: i64 = storage::increment("counter", 1)?;
let new_val: i64 = storage::decrement("counter", 1)?;

// Conditional write (CAS)
storage::set_if_absent("key", b"value")?;
storage::set_if_equals("key", b"old", b"new")?;

// Cross-project reads
let data = storage::get_worker_from_project("key", Some("project-uuid"))?;
let data = storage::get_by_version("key", "wasm-hash")?;

// Cleanup
storage::clear_all()?;
storage::clear_version("wasm-hash")?;
```

### `outlayer::vrf` — Verifiable Random Function

```rust
use outlayer::vrf;

// Generate verifiable randomness (includes proof)
let vrf_output = vrf::random()?;
// Returns bytes that can be verified on-chain
```

### Complete Example

```rust
use outlayer::{env, storage};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Input { action: String, data: Option<String> }

#[derive(Serialize)]
struct Output { success: bool, account: String, result: String }

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let account = env::signer_account_id()
        .ok_or("Authentication required")?;

    let input: Input = env::input_json()?.ok_or("Missing input")?;

    let result = match input.action.as_str() {
        "save" => {
            let key = format!("user:{}", account);
            storage::set_worker(&key, input.data.unwrap_or_default().as_bytes())?;
            "Data saved".to_string()
        }
        "load" => {
            let key = format!("user:{}", account);
            storage::get_worker(&key)?
                .map(|d| String::from_utf8_lossy(&d).to_string())
                .unwrap_or_else(|| "No data".to_string())
        }
        _ => "Unknown action".to_string(),
    };

    let output = Output { success: true, account, result };
    env::output_json(&output)?;

    Ok(())
}
```

## Input/Output Requirements

1. **Input**: Read from `stdin` (not args)
2. **Output**: Write to `stdout` (not stderr)
3. **Format**: JSON only
4. **Size**:
   - Blockchain: ≤900 bytes
   - HTTPS: Up to 25MB
5. **MUST flush**: `stdout().flush()`

## Common Pitfalls

### "entry symbol not defined: _initialize"

Use `[[bin]]`, not `[lib]`:

```toml
# CORRECT
[[bin]]
name = "my-app"
path = "src/main.rs"

# WRONG
[lib]
crate-type = ["cdylib"]
```

### Empty output

Forgot to flush:

```rust
print!("{}", output);
io::stdout().flush()?;  // Add this!
```

### "Failed to instantiate WASM module"

Wrong target. Use `wasm32-wasip1` or `wasm32-wasip2`, not `wasm32-unknown-unknown`.

### Version errors

Don't use `cargo add` or `cargo update`. Copy Cargo.toml from working examples.

## Embedded NEAR Contracts

For WASI apps that deploy contracts:

### Structure

```
your-wasi-app/
├── Cargo.toml              # Workspace
├── src/main.rs             # WASI entry
└── your-contract/
    ├── Cargo.toml          # edition = "2018"!
    ├── rust-toolchain.toml # channel = "1.85.0"
    └── src/lib.rs
```

### Contract Cargo.toml

```toml
[package]
name = "your-contract"
version = "0.1.0"
edition = "2018"  # Must be 2018!

[lib]
crate-type = ["cdylib"]

[dependencies]
near-sdk = { version = "5.9.0", features = ["legacy", "unit-testing"] }

[profile.release]
codegen-units = 1
opt-level = "s"  # "s" for contracts
lto = true
panic = "abort"
```

### Build

```bash
cd your-contract
cargo near build non-reproducible-wasm
```

### Load in WASI

```rust
const CONTRACT_WASM: &[u8] = include_bytes!(
    "../your-contract/res/local/your_contract.wasm"
);
```
