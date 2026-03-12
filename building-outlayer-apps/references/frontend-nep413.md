# NEP-413 Sign Message Authentication

For operations needing cryptographic proof of account ownership without blockchain transactions.

**Use cases:**
- Invite system authentication
- Off-chain access control
- API authentication
- Proving account ownership

## Frontend: Sign with Caching

### Signature Type

```typescript
interface SignedData {
  signature: string;   // base64 encoded
  public_key: string;  // ed25519:xxx format
  timestamp_ms: number;
  nonce: string;       // base64 encoded 32-byte nonce
}
```

### Sign Message Function

```typescript
import type { WalletSelector } from '@near-wallet-selector/core';

let selector: WalletSelector | null = null;

// Cache to avoid repeated popups (50 min, signatures expire at 60 min)
const signatureCache: Map<string, SignedData> = new Map();
const CACHE_DURATION_MS = 50 * 60 * 1000;

function getCachedSignature(accountId: string): SignedData | null {
  const cached = signatureCache.get(accountId);
  if (!cached) return null;

  const age = Date.now() - cached.timestamp_ms;
  if (age > CACHE_DURATION_MS) {
    signatureCache.delete(accountId);
    return null;
  }
  return cached;
}

export async function signMessage(accountId: string): Promise<SignedData | null> {
  // Check cache first
  const cached = getCachedSignature(accountId);
  if (cached) {
    console.log('Using cached signature');
    return cached;
  }

  if (!selector) return null;

  const wallet = await selector.wallet();
  if (!wallet.signMessage) {
    console.error('Wallet does not support signMessage');
    return null;
  }

  const timestamp_ms = Date.now();
  const message = `your-app:${accountId}:${timestamp_ms}`;

  // Generate 32-byte nonce (required by NEP-413)
  const nonceBytes = new Uint8Array(32);
  crypto.getRandomValues(nonceBytes);
  const nonce = Buffer.from(nonceBytes);

  try {
    const result = await wallet.signMessage({
      message,
      recipient: 'your-app',
      nonce,
    });

    if (!result) return null;

    // Handle signature format
    let signatureBase64: string;
    const sig = result.signature as unknown;
    if (typeof sig === 'string') {
      signatureBase64 = sig;
    } else if (sig instanceof Uint8Array) {
      signatureBase64 = btoa(String.fromCharCode(...sig));
    } else if (Array.isArray(sig)) {
      signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(sig)));
    } else {
      return null;
    }

    const nonceBase64 = btoa(String.fromCharCode(...nonceBytes));

    const signedData: SignedData = {
      signature: signatureBase64,
      public_key: result.publicKey,
      timestamp_ms,
      nonce: nonceBase64,
    };

    // Cache for future calls
    signatureCache.set(accountId, signedData);

    return signedData;
  } catch (e) {
    console.error('Signing failed:', e);
    return null;
  }
}

// Clear cache on logout
export function clearSignatureCache(): void {
  signatureCache.clear();
}
```

### Authenticated API Call

```typescript
export async function authenticatedApiCall(
  accountId: string,
  endpoint: string,
  body: Record<string, any>
): Promise<Response> {
  const signed = await signMessage(accountId);
  if (!signed) throw new Error('Failed to sign request');

  return fetch(`https://your-api.com/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      account_id: accountId,
      signature: signed.signature,
      public_key: signed.public_key,
      timestamp_ms: signed.timestamp_ms,
      nonce: signed.nonce,
      ...body,
    }),
  });
}
```

## Backend: Verify Signature (Rust)

### Dependencies

```toml
[dependencies]
ed25519-dalek = { version = "2.1", features = ["rand_core"] }
bs58 = "0.5"
borsh = { version = "1.5", features = ["derive"] }
sha2 = "0.10"
base64 = "0.21"
reqwest = { version = "0.11", features = ["json"] }
chrono = "0.4"
serde = { version = "1.0", features = ["derive"] }
```

### NEP-413 Verification

```rust
use ed25519_dalek::{Signature, VerifyingKey, Verifier};
use sha2::{Sha256, Digest};
use borsh::BorshSerialize;

#[derive(BorshSerialize)]
struct Nep413Payload {
    message: String,
    nonce: [u8; 32],
    recipient: String,
    callback_url: Option<String>,
}

const NEP413_TAG: u32 = 2147484061; // 2^31 + 413

#[derive(serde::Deserialize)]
pub struct SignedRequest {
    pub account_id: String,
    pub signature: String,
    pub public_key: String,
    pub timestamp_ms: u64,
    pub nonce: String,
}

pub fn verify_signature(signed: &SignedRequest) -> Result<(), String> {
    // 1. Check timestamp (1 hour window)
    let now_ms = chrono::Utc::now().timestamp_millis() as u64;
    let one_hour_ms = 60 * 60 * 1000;

    if signed.timestamp_ms > now_ms + one_hour_ms {
        return Err("Timestamp in future".to_string());
    }
    if now_ms > signed.timestamp_ms + one_hour_ms {
        return Err("Signature expired".to_string());
    }

    // 2. Parse public key (ed25519:base58...)
    let pubkey_parts: Vec<&str> = signed.public_key.split(':').collect();
    if pubkey_parts.len() != 2 || pubkey_parts[0] != "ed25519" {
        return Err("Invalid public key format".to_string());
    }

    let pubkey_bytes = bs58::decode(pubkey_parts[1])
        .into_vec()
        .map_err(|e| format!("Decode public key: {}", e))?;

    // 3. Decode signature and nonce (base64)
    use base64::Engine;
    let b64 = base64::engine::general_purpose::STANDARD;

    let sig_bytes = b64.decode(&signed.signature)
        .map_err(|e| format!("Decode signature: {}", e))?;

    let nonce_bytes = b64.decode(&signed.nonce)
        .map_err(|e| format!("Decode nonce: {}", e))?;

    let nonce_array: [u8; 32] = nonce_bytes.try_into()
        .map_err(|_| "Invalid nonce length")?;

    // 4. Reconstruct message (must match frontend)
    let message = format!(
        "your-app:{}:{}",
        signed.account_id, signed.timestamp_ms
    );

    // 5. Build NEP-413 payload
    let payload = Nep413Payload {
        message,
        nonce: nonce_array,
        recipient: "your-app".to_string(),
        callback_url: None,
    };

    // 6. Serialize with Borsh
    let payload_bytes = borsh::to_vec(&payload)
        .map_err(|e| format!("Serialize: {}", e))?;

    // 7. Hash: SHA256(NEP413_TAG || Borsh(payload))
    let mut to_hash = Vec::with_capacity(4 + payload_bytes.len());
    to_hash.extend_from_slice(&NEP413_TAG.to_le_bytes());
    to_hash.extend_from_slice(&payload_bytes);
    let hash = Sha256::digest(&to_hash);

    // 8. Verify
    let verifying_key = VerifyingKey::from_bytes(
        &pubkey_bytes.try_into().map_err(|_| "Invalid key length")?
    ).map_err(|e| format!("Invalid public key: {}", e))?;

    let signature = Signature::from_bytes(
        &sig_bytes.try_into().map_err(|_| "Invalid signature length")?
    );

    verifying_key
        .verify(&hash, &signature)
        .map_err(|_| "Signature verification failed")?;

    Ok(())
}
```

### Verify Key Ownership

```rust
#[derive(serde::Deserialize)]
struct FastNearResponse {
    account_ids: Vec<String>,
}

pub async fn verify_key_ownership(
    public_key: &str,
    account_id: &str,
) -> Result<(), String> {
    let key = public_key.strip_prefix("ed25519:").unwrap_or(public_key);

    let fastnear_url = if account_id.ends_with(".testnet") {
        "https://test.api.fastnear.com"
    } else {
        "https://api.fastnear.com"
    };

    let url = format!("{}/v1/public_key/{}", fastnear_url, key);

    let response = reqwest::get(&url).await
        .map_err(|e| format!("FastNEAR request: {}", e))?;

    if response.status() == 404 {
        return Err("Public key not found".to_string());
    }

    let data: FastNearResponse = response.json().await
        .map_err(|e| format!("Parse response: {}", e))?;

    if data.account_ids.contains(&account_id.to_string()) {
        Ok(())
    } else {
        Err(format!("Key does not belong to {}", account_id))
    }
}

// Full verification
pub async fn verify_request(signed: &SignedRequest) -> Result<(), String> {
    verify_signature(signed)?;
    verify_key_ownership(&signed.public_key, &signed.account_id).await?;
    Ok(())
}
```

## Best Practices

1. **Cache on frontend** - Avoid repeated popups
2. **Timestamp in message** - Replay protection
3. **50-60 min expiry** - Good balance
4. **Generic message** - One signature for multiple ops
5. **Clear on logout** - Security hygiene

```typescript
export async function signOut(): Promise<void> {
  clearSignatureCache();
  await wallet.signOut();
}
```

## Summary

| Step | Frontend | Backend |
|------|----------|---------|
| 1 | Sign message with wallet | Verify signature |
| 2 | Send with request | Verify key ownership |
| 3 | Cache signature | Check timestamp |
