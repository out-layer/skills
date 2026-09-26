# Encryption keys: symmetric keys your module seals data with

> Part of the `building-outlayer-apps` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/building-outlayer-apps/`.

A WASI P2 module declares encryption keys in its manifest and encrypts,
decrypts and authenticates with them through the `outlayer:encryption-keys`
host interface. Any project can. The keys are derived and issued exactly like
signing keys ([signing-keys.md](signing-keys.md)); with the raw storage
functions they make records only the module can open.

## When to use it

- Keep records in storage that the storage's operator cannot read — "Sealed
  storage" below.
- Hand data out sealed — a token, a cursor, a state blob — that only a later
  run of the same project and caller can open.
- Name records by a keyed hash (`mac`) so that their names are hidden too.

**Never hand back a plaintext to whoever asks.** With `caller: "signer"`, any
contract the signer transacts with can start a run under the signer's key with
input of its own choosing, and an on-chain answer is public. Decide from what
the module has checked who may read what it opens.

## The model

- The module never sees a key. It names one by `path`; the host encrypts,
  decrypts or authenticates and hands back the result.
- The keystore derives each key inside the TEE, for that one run, from how the
  code is run and the caller — never from anything the module says. The key
  lives only in that run's memory.
- A key is 32 bytes (256-bit). Symmetric 256-bit keys are considered adequate
  against quantum attacks.
- `bind`, `caller` and `vault` follow the signing keys' rules exactly — the
  tables in [signing-keys.md](signing-keys.md), "The model". A `project` key
  follows the project's on-chain uuid: every version opens what an earlier
  version sealed. A `wasm` key follows the exact build: a new build cannot open
  what the old one sealed. A GitHub-sourced run is never issued keys.
- The keystore derives
  `HMAC-SHA256(master, "encryption-key:v1:{project|wasm}:{project_uuid|wasm_sha256}:{caller}:{account_id}:{path}")`,
  `{caller}` being `signer` or `predecessor`.
- `path` is an input of the derivation. **Renaming a path loses the key, and
  with it everything the key sealed.** Pick paths once.
- A namespace of its own: an encryption key and a signing key declared at the
  same `path` are two unrelated secrets.

## 1. manifest.json

```json
{
  "encryption_keys": [
    {"path": "notes"}
  ]
}
```

| Field | Allowed | Meaning |
|---|---|---|
| `path` | `[a-z0-9][a-z0-9_-]{0,31}`, unique | the key's name and an input of its derivation |
| `bind` | `project` (default) \| `wasm` | as for a signing key |
| `caller` | `signer` (default) \| `predecessor` | as for a signing key |
| `vault` | a NEAR account id | `project` keys only, as for a signing key |

**No `type`**: an encryption key has none, and a `type` member is refused as an
unknown field. At most 3 encryption keys, counted apart from signing keys (a
manifest may declare 3 of each). Any other unknown field is refused too; so is a
`bind` or `caller` value outside its list.

**A `predecessor` key stores in the predecessor's cell.** A module that seals
records under a `caller: "predecessor"` key declares
`"storage_account": "predecessor"` in the same manifest, so the key and the
storage cell belong to the same account. With the default `signer` cell,
records sealed for a relaying contract land in the cell of whichever account
signed each transaction, and a call signed by another account finds none of
them. Over HTTPS both are the payment key's owner. Whose cell:
[wasi-tutorial.md](wasi-tutorial.md), "Whose storage".

## 2. The host interface

Copy `worker/wit/deps/encryption-keys.wit` from `https://github.com/out-layer/outlayer`
into your crate as `wit/deps/encryption-keys.wit` — or this equivalent:

```wit
package outlayer:encryption-keys@0.1.0;

interface api {
    /// Seal plaintext under the declared key at path, bound to aad.
    /// 0x01 || nonce (24 bytes) || ciphertext || tag (16 bytes); at most 262144 bytes of plaintext and of aad.
    encrypt: func(path: string, vault: option<string>, plaintext: list<u8>, aad: list<u8>) -> result<list<u8>, string>;

    /// Open what encrypt sealed under the same path, vault and aad.
    /// Every failure to open is err("decryption failed").
    decrypt: func(path: string, vault: option<string>, ciphertext: list<u8>, aad: list<u8>) -> result<list<u8>, string>;

    /// HMAC-SHA256 of data (32 bytes) under a subkey of the declared key; deterministic.
    mac: func(path: string, vault: option<string>, data: list<u8>) -> result<list<u8>, string>;
}

world encryption-keys-host {
    import api;
}
```

| Function | `Ok` | Notes |
|---|---|---|
| `encrypt(path, vault, plaintext, aad)` | `0x01 ‖ nonce (24) ‖ ciphertext ‖ tag (16)` — 41 bytes longer than the plaintext | a fresh random nonce each call: two calls never return the same bytes |
| `decrypt(path, vault, ciphertext, aad)` | the plaintext | every failure to open — unknown marker, truncated or tampered bytes, another key, another `aad` — is exactly `Err("decryption failed")` |
| `mac(path, vault, data)` | HMAC-SHA256, 32 bytes | under a subkey used for nothing else; deterministic across runs |

- The first byte is the format marker. Format `0x01` is XChaCha20-Poly1305; the
  algorithm is the platform's choice, and a later format would get another
  marker over the same key.
- `vault` is the key's declared vault exactly: `None` for a key declared without
  one, `Some("<vault>")` for one declared with it. Any other combination, an
  undeclared `path`, or an input over the limit is an `Err` with the reason,
  never a trap.
- Limits: 262144 bytes (256 KiB) of plaintext, of `aad`, of `mac` data; a
  ciphertext may be 41 bytes longer.

## 3. Sealed storage

The raw storage functions in `near:storage` store bytes as given, in the run's
storage cell (per account, per project, like `set`/`get`), with no
keystore on the path. The operator can read a raw record's key name and bytes —
so seal first:

| Part | Use | Why |
|---|---|---|
| storage key | hex of `mac(path, vault, name)` | the operator sees storage keys; the same name always maps to the same tag |
| value | `encrypt(path, vault, value, aad = name)` | a ciphertext copied onto another record fails to open |
| reads, writes | `set-raw`, `get-raw`, `set-if-absent-raw`, `set-if-equals-raw` | the value is already sealed |
| compare-and-swap | `set-if-equals-raw(key, expected, new)` | compares the stored ciphertext bytes: pass the ciphertext you read |

Raw storage rules:

- One key holds one record in one mode. `get` on a raw record, `get-raw` on an
  encrypted one, and a write in the other mode are errors. No write converts a
  record: delete it first.
- `has`, `delete`, `list-keys` work on both modes; `increment`/`decrement` only
  on encrypted records.
- `get-raw` answers an empty value for no record. A ciphertext is never empty,
  so for sealed records empty means absent.

The Rust SDK provides helpers for this pattern. The module below uses the host
functions directly.

## 4. Cargo.toml

```toml
[package]
name = "sealed-notes"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "sealed-notes"
path = "src/main.rs"

[dependencies]
wit-bindgen = "0.36"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
hex = "0.4"

[profile.release]
opt-level = "z"
lto = true
strip = true
```

## 5. wit/world.wit

The world imports both interfaces. Put `encryption-keys.wit` (section 2) and
`worker/wit/deps/storage.wit` from the same repo in `wit/deps/`.

```wit
package my:sealed-notes;

world guest {
    import outlayer:encryption-keys/api@0.1.0;
    import near:storage/api@0.1.0;
}
```

## 6. src/main.rs

Notes per caller under the key `notes`: `put` and `append` write; `get` reads,
over HTTPS only, where the caller is the payment key's owner.

```rust
use serde::Deserialize;
use serde_json::{json, Value};
use std::io::{self, Read, Write};

// Bindings for `outlayer:encryption-keys` and `near:storage`, generated from
// wit/world.wit and the two interfaces in wit/deps/.
mod host {
    wit_bindgen::generate!({
        world: "guest",
        path: "wit",
        generate_all, // the interfaces live in packages under wit/deps/
    });
}
use host::near::storage::api as storage;
use host::outlayer::encryption_keys::api as encryption_keys;

// The manifest, in the `outlayer.manifest` custom section: covered by the wasm's sha256.
#[used]
#[link_section = "outlayer.manifest"]
static OUTLAYER_MANIFEST: [u8; include_bytes!("../manifest.json").len()] =
    *include_bytes!("../manifest.json");

/// The declared encryption key. Declared without a vault, so every call passes `None`.
const KEY: &str = "notes";

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case")]
enum Input {
    Put { name: String, text: String },
    Append { name: String, text: String },
    Get { name: String },
}

/// A storage function answers its error as a string, empty on success.
fn ok(error: String) -> Result<(), String> {
    if error.is_empty() { Ok(()) } else { Err(error) }
}

/// Where a note is stored: `n/` + hex of the MAC of its name. The storage
/// operator sees this key, never the name.
fn storage_key(name: &str) -> Result<String, String> {
    let tag = encryption_keys::mac(KEY, None, name.as_bytes())?;
    Ok(format!("n/{}", hex::encode(tag)))
}

/// Seal a note bound to its name: a ciphertext copied onto another note's key
/// fails to open instead of being read as that note.
fn seal(name: &str, text: &str) -> Result<Vec<u8>, String> {
    encryption_keys::encrypt(KEY, None, text.as_bytes(), name.as_bytes())
}

fn open(name: &str, sealed: &[u8]) -> Result<String, String> {
    let plain = encryption_keys::decrypt(KEY, None, sealed, name.as_bytes())?;
    String::from_utf8(plain).map_err(|_| "the note is not UTF-8".to_string())
}

/// The stored ciphertext, or `None`. A ciphertext is never empty, so an empty
/// value is no record.
fn load(key: &str) -> Result<Option<Vec<u8>>, String> {
    let (sealed, error) = storage::get_raw(key);
    ok(error)?;
    Ok((!sealed.is_empty()).then_some(sealed))
}

fn put(name: &str, text: &str) -> Result<(), String> {
    ok(storage::set_raw(&storage_key(name)?, &seal(name, text)?))
}

/// Read-modify-write under compare-and-swap. The swap compares the stored
/// ciphertext bytes: another run's write between our read and our swap
/// changes them, and this attempt starts over.
fn append(name: &str, text: &str) -> Result<(), String> {
    let key = storage_key(name)?;
    for _ in 0..5 {
        match load(&key)? {
            None => {
                let (inserted, error) = storage::set_if_absent_raw(&key, &seal(name, text)?);
                ok(error)?;
                if inserted {
                    return Ok(());
                }
            }
            Some(current) => {
                let updated = open(name, &current)? + text;
                let (swapped, _stored_now, error) =
                    storage::set_if_equals_raw(&key, &current, &seal(name, &updated)?);
                ok(error)?;
                if swapped {
                    return Ok(());
                }
            }
        }
    }
    Err("the note kept changing; try again".to_string())
}

/// A note is handed back only over HTTPS, to the payment key's owner. On chain
/// the output is public, and any contract the signer transacts with can start
/// a run under the signer's key.
fn get(name: &str) -> Result<Value, String> {
    if std::env::var("OUTLAYER_EXECUTION_TYPE").as_deref() != Ok("HTTPS") {
        return Err("notes are read over HTTPS only".to_string());
    }
    let text = match load(&storage_key(name)?)? {
        Some(sealed) => Some(open(name, &sealed)?),
        None => None,
    };
    Ok(json!({ "name": name, "text": text }))
}

fn run() -> Result<Value, String> {
    let mut raw = String::new();
    io::stdin().read_to_string(&mut raw).map_err(|e| e.to_string())?;
    match serde_json::from_str::<Input>(&raw).map_err(|e| e.to_string())? {
        Input::Put { name, text } => put(&name, &text).map(|()| json!({ "stored": name })),
        Input::Append { name, text } => append(&name, &text).map(|()| json!({ "stored": name })),
        Input::Get { name } => get(&name),
    }
}

fn main() {
    let answer = run().unwrap_or_else(|error| json!({ "error": error }));
    print!("{answer}");
    io::stdout().flush().expect("stdout");
}
```

## 7. Build and check

```bash
cargo build --target wasm32-wasip2 --release
W=target/wasm32-wasip2/release/sealed-notes.wasm
wasm-tools component wit $W | grep -E 'import (outlayer:encryption-keys|near:storage)/api'   # both imports
wasm-tools print $W | grep -c 'outlayer.manifest'                                           # must be at least 1
```

`wasmtime` alone cannot run it: the host functions exist only on an OutLayer
worker. A `wasm32-wasip1` module that declares keys is refused.

## 8. Upload, deploy, call

```bash
outlayer upload target/wasm32-wasip2/release/sealed-notes.wasm   # prints the FastFS URL
outlayer deploy sealed-notes <fastfs_url>

curl -s -X POST "https://api.outlayer.ai/call/alice.near/sealed-notes" \
  -H "Content-Type: application/json" -H "X-Payment-Key: $PAYMENT_KEY" \
  -d '{"input": {"operation": "put", "name": "todo", "text": "buy milk"}}'

curl -s -X POST "https://api.outlayer.ai/call/alice.near/sealed-notes" \
  -H "Content-Type: application/json" -H "X-Payment-Key: $PAYMENT_KEY" \
  -d '{"input": {"operation": "get", "name": "todo"}}'
# "output": {"name":"todo","text":"buy milk"}
```

The same payment-key owner calling any later version of the project reads the
same notes. CLI details: `https://skills.outlayer.ai/outlayer-cli/SKILL.md`.

## Refused before the code runs

Every cause in [signing-keys.md](signing-keys.md), "Refused before the code
runs", except the `type` and `secp256k1` rows:

| Cause | What clears it |
|---|---|
| a `wasm32-wasip1` build declares keys | build for `wasm32-wasip2` |
| more than 3 encryption keys, a bad `path` or one declared twice, an unknown field (`type` included), a `bind` other than `project`/`wasm`, a `caller` other than `signer`/`predecessor` | fix `manifest.json`, publish a new version |
| keys declared on a GitHub-sourced run, when the manifest reaches the worker | publish the code as a wasm URL |
| a `project` key on a run with no project | run it through its project |
| a `wasm` key on a run through a project | run the wasm URL directly, or declare the key `project` |
| a `predecessor` key on a run that carries no predecessor | call through a contract, or declare the key `signer` |
| `storage_account: "predecessor"` on a run that carries no predecessor | call on chain, or over HTTPS with a payment key |
| a `storage_account` other than `signer`/`predecessor` (the manifest is unreadable) | fix `manifest.json`, publish a new version |
| a project run whose running code is not a wasm URL version of that project, or whose project does not exist or is not owned by the account its id names | deploy the wasm URL as a version of that project |
| `vault` on a `wasm` key; a vault not named directly under the project's owner, not the owner's, or not available | fix the manifest, or the vault |
| a run with no caller account | call with a payment key, or on chain |

Inside a run, a call answers `Err(String)` for an undeclared `path`, a `vault`
argument that is not the key's declared vault, an input over the limit, and —
from `decrypt` — any failure to open, always exactly `decryption failed`. A
module that imports the interface and declares no key gets `Err` for every path.
