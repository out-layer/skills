# Frontend: Wallet Selector Integration

## Setup

### Environment Variables (.env.local)

```bash
NEXT_PUBLIC_NETWORK_ID=mainnet
NEXT_PUBLIC_OUTLAYER_CONTRACT=outlayer.near
NEXT_PUBLIC_PROJECT_OWNER=your-account.near
NEXT_PUBLIC_PROJECT_NAME=your-project
```

### Dependencies (package.json)

```json
{
  "dependencies": {
    "@near-wallet-selector/core": "^8.9.0",
    "@near-wallet-selector/modal-ui": "^8.9.0",
    "@near-wallet-selector/my-near-wallet": "^8.9.0",
    "@near-wallet-selector/here-wallet": "^8.9.0",
    "@near-wallet-selector/meteor-wallet": "^8.9.0",
    "@near-js/transactions": "^1.2.0"
  }
}
```

### Initialize Wallet Selector

```typescript
import { setupWalletSelector } from '@near-wallet-selector/core';
import { setupModal } from '@near-wallet-selector/modal-ui';
import { setupMyNearWallet } from '@near-wallet-selector/my-near-wallet';
import { setupHereWallet } from '@near-wallet-selector/here-wallet';
import { setupMeteorWallet } from '@near-wallet-selector/meteor-wallet';
import { setupIntearWallet } from '@near-wallet-selector/intear-wallet';
import type { WalletSelector } from '@near-wallet-selector/core';

const NETWORK_ID = process.env.NEXT_PUBLIC_NETWORK_ID || 'mainnet';
const OUTLAYER_CONTRACT = process.env.NEXT_PUBLIC_OUTLAYER_CONTRACT || 'outlayer.near';

let selector: WalletSelector | null = null;
let modal: ReturnType<typeof setupModal> | null = null;

export async function initWalletSelector(): Promise<WalletSelector> {
  if (selector) return selector;

  selector = await setupWalletSelector({
    network: NETWORK_ID as 'mainnet' | 'testnet',
    modules: [
      setupMyNearWallet(),
      setupHereWallet(),
      setupMeteorWallet(),
      setupIntearWallet(),
    ],
  });

  // Omit contractId to prevent function call access key creation
  modal = setupModal(selector, {});

  return selector;
}

export function showModal() {
  modal?.show();
}
```

## Call OutLayer

### CRITICAL: Use actionCreators

```typescript
import { actionCreators } from '@near-js/transactions';

// WRONG - will fail with "Enum key (type) not found"
actions: [{
  type: 'FunctionCall',
  params: { methodName: 'request_execution', ... }
}]

// CORRECT
const action = actionCreators.functionCall(
  'request_execution',
  args,
  BigInt(gas),
  BigInt(deposit)
);
```

### Complete Call Function

```typescript
export async function callOutLayer(
  action: string,
  params: Record<string, any>
): Promise<any> {
  if (!selector) throw new Error('Wallet not initialized');

  const wallet = await selector.wallet();
  const accounts = selector.store.getState().accounts;
  if (accounts.length === 0) throw new Error('Not connected');

  const PROJECT_OWNER = process.env.NEXT_PUBLIC_PROJECT_OWNER;
  const PROJECT_NAME = process.env.NEXT_PUBLIC_PROJECT_NAME;

  const inputData = JSON.stringify({ action, ...params });

  const functionCallAction = actionCreators.functionCall(
    'request_execution',
    {
      source: {
        Project: {
          project_id: `${PROJECT_OWNER}/${PROJECT_NAME}`,
          version_key: null,
        },
      },
      input_data: inputData,
      resource_limits: {
        max_instructions: 2000000000,
        max_memory_mb: 512,
        max_execution_seconds: 120,
      },
      response_format: 'Json',
    },
    BigInt('300000000000000'),       // 300 TGas
    BigInt('100000000000000000000000') // 0.1 NEAR
  );

  const result = await wallet.signAndSendTransaction({
    receiverId: OUTLAYER_CONTRACT,
    actions: [functionCallAction],
  });

  return parseTransactionResult(result);
}

function parseTransactionResult(result: any): any {
  let successValue: string | null = null;

  if (result?.receipts_outcome) {
    for (const receipt of result.receipts_outcome) {
      if (receipt?.outcome?.status?.SuccessValue) {
        successValue = receipt.outcome.status.SuccessValue;
        break;
      }
    }
  }

  if (!successValue) {
    throw new Error('No result from OutLayer execution');
  }

  const decoded = atob(successValue);
  const response = JSON.parse(decoded);

  if (!response.success) {
    throw new Error(response.error || 'Unknown error');
  }

  return response;
}
```

## CRITICAL: One Wallet Call Per Click

Browsers block multiple consecutive popups:

```typescript
// WRONG - second popup WILL BE BLOCKED
async function bad() {
  await wallet.signMessage({...});  // First popup OK
  await wallet.signMessage({...});  // BLOCKED!
}

// CORRECT - one call per user action
async function handleClick() {
  await wallet.signAndSendTransaction({...});
}
```

## UI Pattern

```tsx
function MyApp() {
  const [result, setResult] = useState(null);

  // Each button = one wallet call
  async function handleProcess() {
    const res = await callOutLayer('process', { data: 'test' });
    setResult(res);
  }

  async function handleSave() {
    await callOutLayer('save', { value: 'data' });
  }

  return (
    <div>
      <button onClick={handleProcess}>Process</button>
      <button onClick={handleSave}>Save</button>
      {result && <pre>{JSON.stringify(result, null, 2)}</pre>}
    </div>
  );
}
```

## Get Current Account

```typescript
export function getCurrentAccount(): string | null {
  if (!selector) return null;
  const accounts = selector.store.getState().accounts;
  return accounts.length > 0 ? accounts[0].accountId : null;
}
```

## Sign Out

```typescript
export async function signOut(): Promise<void> {
  if (!selector) return;
  const wallet = await selector.wallet();
  await wallet.signOut();
}
```
