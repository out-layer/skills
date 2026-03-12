# Payment Keys for Better UX

Payment Keys allow HTTPS API calls instead of blockchain transactions:
- No transaction popups
- Faster response times
- Larger payloads (10MB vs ~1.5MB)
- Pre-paid execution

## Payment Key Format

`owner:nonce:secret`

Example: `alice.near:1:a1b2c3d4e5f6...`

Users create Payment Keys at the OutLayer Dashboard.

## Environment Variables

```bash
# .env.local
NEXT_PUBLIC_OUTLAYER_API_URL=https://api.outlayer.fastnear.com
NEXT_PUBLIC_PROJECT_OWNER=your-account.near
NEXT_PUBLIC_PROJECT_NAME=your-project
```

## Implementation

### Configuration

```typescript
interface PaymentKeyConfig {
  enabled: boolean;
  key: string | null;
  owner: string | null;
}

let paymentKeyConfig: PaymentKeyConfig = {
  enabled: false,
  key: null,
  owner: null
};

function parsePaymentKey(key: string): { owner: string; nonce: string; secret: string } | null {
  const parts = key.split(':');
  if (parts.length < 3) return null;
  return {
    owner: parts[0],
    nonce: parts[1],
    secret: parts.slice(2).join(':')
  };
}

export function setPaymentKey(key: string | null): boolean {
  if (key === null) {
    paymentKeyConfig = { enabled: false, key: null, owner: null };
    localStorage.removeItem('payment-key');
    return true;
  }

  const parsed = parsePaymentKey(key);
  if (!parsed) return false;

  paymentKeyConfig = { enabled: true, key, owner: parsed.owner };
  localStorage.setItem('payment-key', key);
  return true;
}

export function loadPaymentKey(): void {
  const saved = localStorage.getItem('payment-key');
  if (saved) setPaymentKey(saved);
}

export function getPaymentKeyOwner(): string | null {
  return paymentKeyConfig.owner;
}

export function isPaymentKeyEnabled(): boolean {
  return paymentKeyConfig.enabled;
}
```

### HTTPS API Call

```typescript
const API_URL = process.env.NEXT_PUBLIC_OUTLAYER_API_URL || 'https://api.outlayer.fastnear.com';
const PROJECT_OWNER = process.env.NEXT_PUBLIC_PROJECT_OWNER;
const PROJECT_NAME = process.env.NEXT_PUBLIC_PROJECT_NAME;

async function callOutLayerHttps(
  action: string,
  params: Record<string, any>
): Promise<any> {
  if (!paymentKeyConfig.key) {
    throw new Error('Payment key not configured');
  }

  const url = `${API_URL}/call/${PROJECT_OWNER}/${PROJECT_NAME}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Payment-Key': paymentKeyConfig.key,
    },
    body: JSON.stringify({
      input: { action, ...params },
      resource_limits: {
        max_instructions: 2000000000,
        max_memory_mb: 512,
        max_execution_seconds: 120,
      },
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(error);
  }

  const result = await response.json();
  if (result.status === 'failed') {
    throw new Error(result.error || 'Execution failed');
  }

  return JSON.parse(result.output);
}
```

### Unified Call Function

```typescript
export async function callOutLayer(
  action: string,
  params: Record<string, any>
): Promise<any> {
  if (paymentKeyConfig.enabled) {
    return callOutLayerHttps(action, params);
  }
  return callOutLayerTransaction(action, params);
}
```

## UI: Payment Key Toggle

```tsx
import { useState, useEffect } from 'react';

function PaymentKeySettings() {
  const [enabled, setEnabled] = useState(false);
  const [keyInput, setKeyInput] = useState('');
  const [owner, setOwner] = useState<string | null>(null);

  useEffect(() => {
    loadPaymentKey();
    setEnabled(isPaymentKeyEnabled());
    setOwner(getPaymentKeyOwner());
  }, []);

  function handleSave() {
    if (setPaymentKey(keyInput)) {
      setEnabled(true);
      setOwner(getPaymentKeyOwner());
      setKeyInput('');
    } else {
      alert('Invalid payment key format');
    }
  }

  function handleClear() {
    setPaymentKey(null);
    setEnabled(false);
    setOwner(null);
  }

  return (
    <div>
      <h3>Payment Key</h3>

      {owner ? (
        <div>
          <p>Active: {owner}</p>
          <button onClick={handleClear}>Remove Key</button>
        </div>
      ) : (
        <div>
          <input
            type="password"
            placeholder="alice.near:1:secret..."
            value={keyInput}
            onChange={e => setKeyInput(e.target.value)}
          />
          <button onClick={handleSave}>Save Key</button>
        </div>
      )}

      <label>
        <input
          type="checkbox"
          checked={enabled}
          onChange={e => {
            if (e.target.checked && !owner) {
              alert('Add a payment key first');
              return;
            }
            paymentKeyConfig.enabled = e.target.checked;
            setEnabled(e.target.checked);
          }}
          disabled={!owner}
        />
        Use Payment Key (faster, no popups)
      </label>
    </div>
  );
}
```

## When to Use

| Use Case | Method |
|----------|--------|
| First-time user | Blockchain TX |
| Frequent operations | Payment Key |
| Large data transfer | Payment Key |
| Maximum security | Blockchain TX |

## Notes

- Payment Keys require pre-paid balance
- Create keys at OutLayer Dashboard
- Keys can be revoked anytime
- Owner account is visible to WASI via `NEAR_SENDER_ID`
