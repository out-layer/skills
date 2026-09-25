# Signing keys: ed25519 keys your module signs with

> Part of the `building-outlayer-apps` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/building-outlayer-apps/`.

A WASI P2 module declares ed25519 keys in its manifest and signs with them
through the `outlayer:signing-keys` host interface. Any project can. This file
does not cover signing with the custody wallet's keys (EVM, Solana, NEP-413 over
the wallet API) — that is `https://skills.outlayer.ai/agent-custody/SKILL.md`.

## When to use it

- Sign what the module returns — a record, a result, a receipt — so anyone can
  check it against a published public key without trusting the transport.
- Give each caller a stable ed25519 identity per project — a NEAR implicit
  account that can sign NEP-413 messages (section 8).

**Do not hold money on a signing key.** The key can sign NEAR transactions for
its implicit account, and Solana ones for the same public key, so funds sent
there are controlled only by this code, outside every wallet policy. Money goes
through the custody wallet. EVM is not supported: it needs secp256k1.

**Never sign caller-supplied bytes or digests verbatim.** A signature over bytes
the caller chose is a signature over whatever those bytes are — a transaction
from the implicit account, an authorization, a message the account never meant.
Sign only messages the module composes itself, from fields it has parsed and
checked, under a fixed prefix or structure of its own; refuse an input that
asks for a signature over raw bytes.

## The model

- The module never sees a key. It names one by `path` and gets a public key or a
  signature back.
- The keystore derives each key inside the TEE, for that one run, from how the
  code is run and the **caller**. The master never leaves the keystore; the
  derived key lives only in that run's memory.
- The caller is one account of the run, chosen per key with `caller`. The
  platform sets both accounts from the job; the code and the input cannot.
  Another caller always gets another key, and a signer key and a predecessor
  key for one account are two keys. A run with no caller account is refused.
  - `signer` (default): `NEAR_USER_ACCOUNT_ID` — the transaction's signer on
    chain, the payment key's owner over HTTPS. Any contract the signer ever
    transacts with can start a run under the signer's key with input of its
    own — an `ft_transfer_call`, a DAO proposal, a wallet contract's callback
    all execute as the signer — so never treat the input as the signer's
    intent.
  - `predecessor`: `NEAR_PREDECESSOR_ID` — the account that called the
    contract: the DAO or wallet contract when one relayed the call, the signer
    when none did, the signer over HTTPS. On a payment through
    `ft_transfer_call` it binds to the token contract. A run with no
    predecessor is refused before it starts.

Keys are issued strictly by how the code is run:

| `bind` | Issued only to | The key belongs to | New code version | The same key for |
|---|---|---|---|---|
| `project` (default) | a run through a project whose version is a wasm URL version | the project's on-chain uuid + the chosen caller | keeps the key | that caller, running any version of that project |
| `wasm` | a direct run from a wasm URL, with no project | the code's sha256 + the chosen caller | gets new keys | that caller, running that exact binary directly |

There is no other `bind` value, and no repository binding.

- A GitHub-sourced run is never issued signing keys — a project version built
  from a repo, or a repo run directly. Publish a wasm URL instead.
- One key whose `bind` or `caller` does not match how the code is run refuses
  the whole run before it starts. The worker reads the run off the job the
  coordinator gave it, never off the module, and sends the job's
  `user_account_id`, `predecessor_id`, `executed_wasm_sha256` and `project_id`;
  a `project_id` makes it a project run, none a direct run. The keystore takes
  those fields on the trust of the worker's TEE attestation, as it does for
  secrets, checks every `bind` and `caller` against them, and for `project`
  also checks on chain that the running code's sha256 is a wasm URL version of
  that project and that the project exists with the owner its id names. A
  direct GitHub build is refused by the worker alone: the keystore sees only
  the hash of the bytes.
- One run never holds both kinds. The manifest is inside the wasm, so declare
  the one `bind` that matches how this module will be run: `project` for a
  project, `wasm` for a direct run.
- `project`: the key follows the project's on-chain uuid, never its
  `owner/name` id. Whoever publishes new versions of the project decides what
  they sign with the same key, and a transferred project keeps its keys — the
  id changes, the uuid stays. A project deleted and created again under the
  same name is another project with another uuid, so other keys. Another
  project gets another key.
- `wasm`: anyone who runs the exact binary directly gets keys for their own
  callers. So never decide WHAT to sign from secrets, environment variables or
  configuration — whoever runs the binary controls those, and a user lured into
  calling someone else's run of the same code would sign under that runner's
  configuration. Decide what to sign from the input and the code.
- `path` is an input of the derivation: the same path is the same key, another
  path is another key. Renaming a path loses the key, any address made from its
  public key, and every signature checked against it. Pick paths once.

## 1. manifest.json

```json
{
  "signing_keys": [
    {"path": "records", "type": "ed25519"}
  ]
}
```

| Field | Allowed | Meaning |
|---|---|---|
| `path` | `[a-z0-9][a-z0-9_-]{0,31}`, unique | the key's name |
| `type` | `ed25519` | the only type |
| `bind` | `project` (default) \| `wasm` | see the table above |
| `caller` | `signer` (default) \| `predecessor` | which account of the run the key belongs to; see "The model" |
| `vault` | a NEAR account id | `project` keys only: derive from that vault's master instead of the default one |

At most 3 keys. An unknown field is refused, not ignored; so is a `type`, `bind`
or `caller` value outside its list.

`vault`: the vault must be a direct sub-account of the project's owner
(`vault.alice.near` for `alice.near/my-signer`) and its contract's `parent` must
be that owner. A vault not named directly under the owner is refused on the
names alone, before any chain read. A missing or unavailable vault refuses the
run — never a fallback to the default master. `vault` with `bind: "wasm"` is refused. Vaults themselves:
`https://skills.outlayer.ai/agent-custody/SKILL.md`.

## 2. wit/signing-keys.wit

```wit
package outlayer:signing-keys@0.1.0;

interface api {
    /// ed25519: the 32-byte public key.
    public-key: func(path: string, vault: option<string>) -> result<list<u8>, string>;

    /// ed25519 (RFC 8032) over the raw message bytes: no prehash, no prefix.
    /// 64-byte signature. At most 65536 bytes of message; sign a digest to cover more.
    sign: func(path: string, vault: option<string>, message: list<u8>) -> result<list<u8>, string>;
}

world signing-keys-host {
    import api;
}
```

`vault` names the key's declared vault exactly: `None` for a key declared
without one, `Some("<vault>")` for a key declared with that vault. Any other
combination is an `Err`.

## 3. Cargo.toml

```toml
[package]
name = "my-signer"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "my-signer"
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

The `outlayer` SDK crate can sit beside it for storage and env; keep the
generated bindings in their own module, as below, so the two `outlayer` names
never meet.

## 4. src/main.rs

```rust
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

// Bindings for `outlayer:signing-keys`, generated from wit/signing-keys.wit.
mod signing_keys_host {
    wit_bindgen::generate!({
        world: "signing-keys-host",
        path: "wit",
    });
}
use signing_keys_host::outlayer::signing_keys::api as signing_keys;

// The manifest, in the `outlayer.manifest` custom section: covered by the wasm's sha256.
#[used]
#[link_section = "outlayer.manifest"]
static OUTLAYER_MANIFEST: [u8; include_bytes!("../manifest.json").len()] =
    *include_bytes!("../manifest.json");

#[derive(Deserialize)]
struct Input {
    record: String,
}

#[derive(Serialize)]
struct Output {
    public_key: String, // hex, 32 bytes
    signature: String,  // hex, 64 bytes
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut raw = String::new();
    io::stdin().read_to_string(&mut raw)?;
    let input: Input = serde_json::from_str(&raw)?;

    // `None`: "records" is declared without a vault. Both calls return
    // Result<_, String>: an undeclared path, a vault that is not the declared
    // one, or a message over 64 KiB is an Err, never a trap.
    let public_key = signing_keys::public_key("records", None)?;
    let signature = signing_keys::sign("records", None, input.record.as_bytes())?;

    let out = Output {
        public_key: hex::encode(public_key),
        signature: hex::encode(signature),
    };
    print!("{}", serde_json::to_string(&out)?);
    io::stdout().flush()?;
    Ok(())
}
```

## 5. Build and check

```bash
cargo build --target wasm32-wasip2 --release
W=target/wasm32-wasip2/release/my-signer.wasm
wasm-tools component wit $W | grep 'import outlayer:signing-keys/api'   # the import
wasm-tools print $W | grep -c 'outlayer.manifest'                       # must be at least 1
```

`wasmtime` alone cannot run it: the host functions exist only on an OutLayer
worker. Build for `wasm32-wasip2`; a `wasm32-wasip1` module that declares keys is
refused.

## 6. Upload, then run it the way its `bind` says

Both kinds start from a wasm URL; a GitHub-sourced run is never issued signing keys.

```bash
outlayer upload target/wasm32-wasip2/release/my-signer.wasm   # prints the FastFS URL
```

**`bind: "project"`** (the manifest above): deploy the URL as a project version,
then call the project.

```bash
outlayer deploy my-signer <fastfs_url>

curl -X POST "https://api.outlayer.ai/call/alice.near/my-signer" \
  -H "Content-Type: application/json" \
  -H "X-Payment-Key: $PAYMENT_KEY" \
  -d '{"input": {"record": "order #1"}}'
```

The key is bound to the payment key's owner (`caller: "signer"`, the default).
The same owner calling any later version of `alice.near/my-signer` gets the
same `public_key`.

**`bind: "wasm"`** (every key in the manifest declares it): run the URL directly,
with no project. This is an on-chain run; the key is bound to the transaction's
signer.

```bash
outlayer run --wasm <fastfs_url> '{"record": "order #1"}'
```

CLI details: `https://skills.outlayer.ai/outlayer-cli/SKILL.md`.

## 7. Verify a signature anywhere

```python
from nacl.signing import VerifyKey   # pip install pynacl
VerifyKey(bytes.fromhex(public_key)).verify(b"order #1", bytes.fromhex(signature))  # raises on a bad signature
```

## 8. NEP-413: sign as the key's NEAR account

`sign` takes raw bytes, so a module can make a NEP-413 (NEAR `signMessage`)
signature with a signing key:

1. Build `borsh(u32 little-endian 2^31 + 413)` followed by
   `borsh(Payload { message, nonce: [u8; 32], recipient, callback_url: Option })`,
   fields in that order.
2. Take the sha256 of those bytes.
3. `sign` the 32-byte hash.

The key's NEAR implicit account is `accountId` = the lowercase hex of the
32-byte public key. It is a real NEAR account and needs no registration, so a
NEP-413 verifier checks the signature against that account like any wallet's.
In NEAR's key format the public key is `ed25519:` + base58 of the same 32 bytes.

```rust
// Cargo.toml adds: borsh = { version = "1", features = ["derive"] }, sha2 = "0.10"

/// NEP-413's prefix, borsh-serialized as a little-endian u32 before the payload.
const NEP413_TAG: u32 = (1 << 31) + 413;

/// Field order is part of the format: borsh encodes in declaration order.
#[derive(borsh::BorshSerialize)]
struct Nep413Payload {
    message: String,
    nonce: [u8; 32], // the verifier's: it picks it and refuses one it has seen
    recipient: String,
    callback_url: Option<String>,
}

fn nep413_hash(payload: &Nep413Payload) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut bytes = borsh::to_vec(&NEP413_TAG).expect("a u32 serializes");
    bytes.extend(borsh::to_vec(payload).expect("the payload serializes"));
    Sha256::digest(&bytes).into()
}

fn sign_nep413(path: &str, payload: &Nep413Payload) -> Result<(String, Vec<u8>), String> {
    let signature = signing_keys::sign(path, None, &nep413_hash(payload))?;
    let account_id = hex::encode(signing_keys::public_key(path, None)?); // the implicit account
    Ok((account_id, signature))
}
```

The full version, answering in a NEAR wallet's `signMessage` shape (`accountId`,
`publicKey`, base64 `signature`), with a Python verifier, is the
signing-key-probe example in the OutLayer repo: `wasi-examples/signing-key-probe/`,
`sign_nep413` in `src/main.rs` and its README.

## Refused before the code runs

| Cause | What clears it |
|---|---|
| a `wasm32-wasip1` build declares keys | build for `wasm32-wasip2` |
| more than 3 keys, a bad or repeated `path`, an unknown field, a `type` other than `ed25519`, a `bind` other than `project`/`wasm`, a `caller` other than `signer`/`predecessor` | fix `manifest.json`, publish a new version |
| keys declared on a GitHub-sourced run (a project version from a repo, or a repo run directly), when the manifest reaches the worker | publish the code as a wasm URL |
| a `project` key on a run with no project | run it through its project |
| a `wasm` key on a run through a project | run the wasm URL directly, or declare the key `project` |
| a `predecessor` key on a run that carries no predecessor | call through a contract, or declare the key `signer` |
| a project run whose running code is not a wasm URL version of that project, or whose project does not exist or is not owned by the account its id names | deploy the wasm URL as a version of that project |
| `vault` on a `wasm` key; a vault not named directly under the project's owner (refused by name, before any chain read), not the owner's, or not available | fix the manifest, or the vault |
| a run with no caller account (the worker's placeholder for a missing account is refused by name) | call with a payment key, or on chain |
| a worker or keystore without signing-key support | none from your side |

Inside a run, `public-key` and `sign` answer `Err(String)` for an undeclared
`path`, a `vault` argument that is not the key's declared vault, or a message
over 65536 bytes; a module that imports the interface and declares no key gets
`Err` for every path. A GitHub-sourced module whose manifest does not reach the
worker runs, and every call answers `Err`.
