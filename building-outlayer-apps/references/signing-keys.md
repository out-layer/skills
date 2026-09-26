# Signing keys: ed25519 and secp256k1 keys your module signs with

> Part of the `building-outlayer-apps` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/building-outlayer-apps/`.

A WASI P2 module declares ed25519 or secp256k1 keys in its manifest and signs
with them through the `outlayer:signing-keys` host interface. Any project can. This file
does not cover signing with the custody wallet's keys (EVM, Solana, NEP-413 over
the wallet API) — that is `https://skills.outlayer.ai/agent-custody/SKILL.md`.

## When to use it

- Sign what the module returns — a record, a result, a receipt — so anyone can
  check it against a published public key without trusting the transport.
- Give each caller a stable ed25519 identity per project — a NEAR implicit
  account that can sign NEP-413 messages (section 8).
- Sign for EVM with a secp256k1 key — an EVM address, signatures `ecrecover`
  accepts (section 9).
- Let anyone check once that a public key is this project's, derived in the
  TEE (section 10).

**Do not hold money on a signing key.** An ed25519 key can sign NEAR
transactions for its implicit account and Solana ones for the same public key; a
secp256k1 key signs EVM transactions for its address. Funds sent there are
controlled only by this code, outside every wallet policy. Money goes through
the custody wallet.

**Never sign caller-supplied bytes or digests verbatim.** A signature over bytes
the caller chose is a signature over whatever those bytes are — a transaction
from the key's account, an authorization, a message the account never meant.
A secp256k1 key signs a 32-byte digest as it is, so a caller-chosen digest is
the hash of any EVM transaction, EIP-712 permit or `personal_sign` message the
caller likes. Sign only messages the module composes itself, from fields it has
parsed and checked, under a fixed prefix or structure of its own, and compute
the digest in the module; refuse an input that asks for a signature over raw
bytes or a digest.

**A caller-chosen NEP-413 `message` and `recipient` is a login.** The NEP-413
tag keeps the bytes from being a transaction, but a signature over a message and
recipient the caller picked logs in, as the key's account, to whatever site the
caller names. Fix them in the module.

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
| `type` | `ed25519` \| `secp256k1` | the key's algorithm (section 2) and an input of its derivation (`signing-key:v1:{type}:{project\|wasm}:…`); a path is declared once whatever its type |
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

## 2. wit/signing-keys.wit and the key types

```wit
package outlayer:signing-keys@0.1.0;

interface api {
    /// A NEP-413 signature in the shape a NEAR wallet's `signMessage` answers.
    record nep413-signature {
        /// The key's NEAR implicit account: its 32-byte public key, lowercase hex.
        account-id: string,
        /// `ed25519:` followed by the base58 of the 32-byte public key.
        public-key: string,
        /// The 64-byte ed25519 signature, standard base64 with padding.
        signature: string,
    }

    /// ed25519: the 32-byte public key.
    /// secp256k1: 64 bytes, x ‖ y — the uncompressed SEC1 point without its 0x04 prefix.
    public-key: func(path: string, vault: option<string>) -> result<list<u8>, string>;

    /// ed25519: RFC 8032 over the raw message bytes, at most 65536; 64 bytes out.
    /// secp256k1: exactly a 32-byte prehash, signed as it is; 65 bytes out, r ‖ s ‖ v.
    sign: func(path: string, vault: option<string>, message: list<u8>) -> result<list<u8>, string>;

    /// NEP-413 (NEAR signMessage) with an ed25519 key; the host builds the signed bytes.
    sign-nep413: func(path: string, vault: option<string>, message: string, recipient: string, nonce: list<u8>, callback-url: option<string>) -> result<nep413-signature, string>;
}

world signing-keys-host {
    import api;
}
```

`vault` names the key's declared vault exactly: `None` for a key declared
without one, `Some("<vault>")` for a key declared with that vault. Any other
combination is an `Err`.

| `type` | `public-key` | `sign` input | `sign` output | `sign-nep413` |
|---|---|---|---|---|
| `ed25519` | 32 bytes; in hex, a NEAR implicit account (also a Solana address) | the raw message, at most 65536 bytes — no prehash, no prefix | 64 bytes, RFC 8032 | yes |
| `secp256k1` | 64 bytes `x ‖ y` — uncompressed SEC1 without `0x04`, NEAR's `secp256k1:` format; EVM address = last 20 bytes of keccak256 of these 64 | exactly a 32-byte prehash, signed as it is; any other length is `Err` | 65 bytes `r ‖ s ‖ v`: RFC 6979, big-endian `r`/`s`, low-s, `v` 0 or 1 (EVM: `v + 27`) | `Err` |

A secp256k1 key whose derived secret scalar is zero or not below the group
order (probability about 2^-128) is not a key: the run is refused.

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

`sign-nep413(path, vault, message, recipient, nonce, callback-url)` signs with
an **ed25519** key. The host builds the bytes: `sha256(borsh(2^31 + 413) ‖
borsh(payload))`, payload `{message: string, nonce: [u8; 32], recipient: string,
callback_url: option<string>}` in that order, signed with ed25519. The answer
has a NEAR wallet's `signMessage` shape:

| `nep413-signature` field | Value |
|---|---|
| `account-id` | lowercase hex of the 32-byte public key (64 chars): the key's NEAR implicit account |
| `public-key` | `ed25519:` + base58 of the 32 bytes |
| `signature` | 64-byte ed25519 signature, standard base64 with padding |

`Err` for: a key that is not ed25519, a `nonce` that is not exactly 32 bytes, a
`message` over 65536 bytes, a `recipient` or `callback-url` over 2048 bytes. The
nonce is the verifier's: it chooses it and refuses one it has seen.

The implicit account needs no registration: the signature verifies against
`hex(public key)`. A verifier that also looks the key up among the account's
access keys over RPC finds it only once the implicit account has been funded;
checking `account-id == hex(public key)` holds regardless.

A module that proves its key — it fixes `message` and `recipient`, the verifier
chooses only the nonce (same `Cargo.toml` as section 3; manifest
`{"signing_keys": [{"path": "identity", "type": "ed25519"}]}`):

```rust
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

// Bindings and the manifest section exactly as in the minimal module above.
mod signing_keys_host {
    wit_bindgen::generate!({
        world: "signing-keys-host",
        path: "wit",
    });
}
use signing_keys_host::outlayer::signing_keys::api as signing_keys;

#[used]
#[link_section = "outlayer.manifest"]
static OUTLAYER_MANIFEST: [u8; include_bytes!("../manifest.json").len()] =
    *include_bytes!("../manifest.json");

// The module fixes what it signs; the verifier chooses only the nonce.
const MESSAGE: &str = "my-signer key proof";
const RECIPIENT: &str = "my-signer";

#[derive(Deserialize)]
struct Input {
    nonce_hex: String, // 32 bytes, chosen by the verifier
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Output {
    account_id: String, // hex of the public key: the NEAR implicit account
    public_key: String, // "ed25519:" + base58
    signature: String,  // base64
    message: &'static str,
    recipient: &'static str,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut raw = String::new();
    io::stdin().read_to_string(&mut raw)?;
    let input: Input = serde_json::from_str(&raw)?;
    let nonce = hex::decode(&input.nonce_hex)?;

    // The host builds the NEP-413 bytes, hashes and signs them. An Err: a key
    // that is not ed25519, a nonce that is not 32 bytes, an oversized field.
    let signed = signing_keys::sign_nep413("identity", None, MESSAGE, RECIPIENT, &nonce, None)?;

    let out = Output {
        account_id: signed.account_id,
        public_key: signed.public_key,
        signature: signed.signature,
        message: MESSAGE,
        recipient: RECIPIENT,
    };
    print!("{}", serde_json::to_string(&out)?);
    io::stdout().flush()?;
    Ok(())
}
```

Verify the answer anywhere:

```python
import base64, hashlib, struct
import base58                          # pip install base58 pynacl
from nacl.signing import VerifyKey

def borsh_string(s): return struct.pack('<I', len(s)) + s

def check_key_proof(answer, nonce):    # nonce: the 32 bytes you sent
    public_key = base58.b58decode(answer["publicKey"].removeprefix("ed25519:"))
    assert answer["accountId"] == public_key.hex()          # the implicit account IS the key
    payload = (borsh_string(b"my-signer key proof") + nonce
               + borsh_string(b"my-signer") + b"\x00")      # callback_url: None
    digest = hashlib.sha256(struct.pack('<I', 2**31 + 413) + payload).digest()
    VerifyKey(public_key).verify(digest, base64.b64decode(answer["signature"]))  # raises if bad
    return answer["accountId"]
```

The same signature built in the guest from `sign`, for when the payload must be
seen, is `sign_nep413` in the OutLayer repo's
`wasi-examples/signing-key-probe/src/main.rs`, with a Python verifier in its README.

## 9. EVM with a secp256k1 key

Manifest: `{"signing_keys": [{"path": "evm", "type": "secp256k1"}]}`. The module
hashes what it signs; never pass `sign` a digest from the input.

```rust
// Cargo.toml adds: sha3 = "0.10"
use sha3::{Digest, Keccak256};

/// The key's EVM address: the last 20 bytes of keccak256 of the 64-byte x ‖ y.
fn evm_address(path: &str) -> Result<String, String> {
    let public_key = signing_keys::public_key(path, None)?; // 64 bytes for a secp256k1 key
    Ok(format!("0x{}", hex::encode(&Keccak256::digest(&public_key)[12..])))
}

/// EIP-191 `personal_sign` over a message this module composed itself.
fn personal_sign(path: &str, message: &str) -> Result<String, String> {
    let mut hasher = Keccak256::new();
    hasher.update(format!("\x19Ethereum Signed Message:\n{}", message.len()));
    hasher.update(message);
    let prehash: [u8; 32] = hasher.finalize().into();
    let mut signature = signing_keys::sign(path, None, &prehash)?; // r ‖ s ‖ v, v ∈ {0, 1}
    signature[64] += 27; // EVM wants v + 27
    Ok(format!("0x{}", hex::encode(signature)))
}
```

Recover the signer anywhere (`message`, `signature`, `address` from the
module's output):

```python
import coincurve
from Crypto.Hash import keccak         # pip install coincurve pycryptodome

def keccak256(data):
    h = keccak.new(digest_bits=256); h.update(data); return h.digest()

def recover_address(message, signature_hex):
    sig = bytes.fromhex(signature_hex.removeprefix("0x"))
    prehash = keccak256(b"\x19Ethereum Signed Message:\n" + str(len(message.encode())).encode() + message.encode())
    public_key = coincurve.PublicKey.from_signature_and_message(sig[:64] + bytes([sig[64] - 27]), prehash, hasher=None)
    return "0x" + keccak256(public_key.format(compressed=False)[1:])[12:].hex()

assert recover_address(message, signature) == address
```

## 10. Prove a key is the project's

Every run carries an Intel TDX quote whose report data commits to the run's
input, output, build (`wasm_hash`), caller and project. A key the module puts in
its output is attested with it.

1. The module returns its `public-key` in its output — or, for freshness, a
   signature over a verifier-chosen nonce, as the section 8 module does.
2. Get the attestation. An HTTPS `/call` response carries `attestation_url` =
   `/attestations/by-call/{call_id}`, relative to `https://api.outlayer.ai`; it
   answers once the worker has uploaded the quote. On-chain run:
   `/attestations/by-tx/{tx_hash}`.
3. Verify it: Intel-signed quote, approved worker measurements, task hash over
   this input and output. Keep an HTTPS call's request and response — only their
   hashes are stored.

   ```bash
   # An HTTPS call: the response you kept carries call_id, output and attestation_url
   curl -s "https://api.outlayer.ai/attestations/by-call/$CALL_ID"     # the attestation record
   outlayer-verify call "$CALL_ID" --input '{"nonce_hex":"…"}' --output '<the output you received>'

   # An on-chain run
   outlayer-verify tx <near-tx-hash>
   ```

   (`cargo install --git https://github.com/out-layer/outlayer-verify outlayer-verify`)
4. Read the attested fields: `project_id` is the project; the caller —
   `payment_key_owner` over HTTPS, `caller_account_id` on chain — is the account
   the key belongs to; `wasm_hash` is the build that ran. Audit that build: the
   attestation proves what ran, not that it returned the host's key unaltered.
5. From then on, a signature by that key is the project's for that caller,
   checked against the public key alone.

- The attestation names the project by `owner/name`; the key belongs to its
  on-chain uuid. A project deleted and created again under the same name has
  other keys: the proof holds for the project that ran under that name then.
- A `caller: "predecessor"` key belongs to the account that called the
  contract; read it from the requesting transaction. Over HTTPS it is the
  payment key's owner.
- A `bind: "wasm"` key belongs to the build and the caller: the proof is for
  that `wasm_hash`, with no project.

## Refused before the code runs

| Cause | What clears it |
|---|---|
| a `wasm32-wasip1` build declares keys | build for `wasm32-wasip2` |
| more than 3 keys, a bad `path` or one declared twice (under any type), an unknown field, a `type` other than `ed25519`/`secp256k1`, a `bind` other than `project`/`wasm`, a `caller` other than `signer`/`predecessor` | fix `manifest.json`, publish a new version |
| keys declared on a GitHub-sourced run (a project version from a repo, or a repo run directly), when the manifest reaches the worker | publish the code as a wasm URL |
| a `project` key on a run with no project | run it through its project |
| a `wasm` key on a run through a project | run the wasm URL directly, or declare the key `project` |
| a `predecessor` key on a run that carries no predecessor | call through a contract, or declare the key `signer` |
| a project run whose running code is not a wasm URL version of that project, or whose project does not exist or is not owned by the account its id names | deploy the wasm URL as a version of that project |
| `vault` on a `wasm` key; a vault not named directly under the project's owner (refused by name, before any chain read), not the owner's, or not available | fix the manifest, or the vault |
| a run with no caller account (the worker's placeholder for a missing account is refused by name) | call with a payment key, or on chain |
| a `secp256k1` key whose derived scalar is zero or not below the group order (about 2^-128) | declare the key under another `path` |
| a worker or keystore without signing-key support | none from your side |

Inside a run, a call answers `Err(String)` for an undeclared `path` or a `vault`
argument that is not the key's declared vault; `sign` for an ed25519 message
over 65536 bytes or a secp256k1 message that is not exactly 32 bytes;
`sign-nep413` as in section 8. A module that imports the interface and declares
no key gets `Err` for every path. A GitHub-sourced module whose manifest does not reach the
worker runs, and every call answers `Err`.
