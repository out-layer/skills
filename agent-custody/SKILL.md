---
name: agent-custody
description: Multi-chain custody wallet for AI agents with cross-chain swaps via NEAR Intents. Register a gasless wallet, swap tokens across 20+ chains, send/receive on NEAR, Ethereum, Bitcoin, Solana, and more. Use when an agent needs crypto operations — transfers, swaps, contract calls, or cross-chain movements.
metadata:
  api:
    base_url: https://api.outlayer.fastnear.com
    version: v1
    auth: Bearer token
---

# OutLayer Agent Custody Wallet

Multi-chain custody wallet for AI agents. Supports NEAR transfers, smart contract calls, and cross-chain swaps via NEAR Intents protocol — no gas tokens needed on destination chains.

## When to Use This Skill

| You need... | Action |
|-------------|--------|
| A crypto wallet for your agent | Register via `POST /register` — includes 100 free WASI calls |
| Run a WASI module for free | Use `POST /call/{owner}/{project}` with `Authorization: Bearer wk_...` (trial quota) |
| Check remaining free calls | Use `GET /trial/status` |
| Upgrade to paid execution | Use `POST /wallet/v1/create-payment-key` (USDC or NEAR) |
| Send NEAR to someone | Use `POST /wallet/v1/transfer` with `chain: "near"` |
| Send FT tokens (USDT, wNEAR) to someone | Use `POST /wallet/v1/call` with `ft_transfer` (see FT transfer section) |
| Swap tokens (e.g. wNEAR to USDT) | Use `POST /wallet/v1/intents/swap` — atomic swap via 1Click API |
| Preview swap rate before committing | Use `POST /wallet/v1/intents/swap/quote` — read-only, no gas spent |
| List available tokens for swaps | Use `GET /wallet/v1/tokens` — returns ~200 tokens across 20+ chains |
| Send tokens cross-chain (gasless) | Use `POST /wallet/v1/intents/withdraw` — no gas tokens needed on destination chain |
| Deposit tokens into Intents balance | Use `POST /wallet/v1/intents/deposit` — for manual intents operations |
| Call a NEAR smart contract | Use `POST /wallet/v1/call` — requires NEAR balance for gas |
| Check your balance | Use `GET /wallet/v1/balance?chain=near` or `&token=usdt.tether-token.near` |
| Check intents deposit balance | Use `GET /wallet/v1/balance?token=wrap.near&source=intents` |
| Get your address on any chain | Use `GET /wallet/v1/address?chain=ethereum` |
| Delete the wallet | Use `POST /wallet/v1/delete` — deletes on-chain account, sends NEAR to beneficiary |
| Ask user to fund your wallet | Generate a fund link (see below) or share your NEAR address |
| Let the user set spending limits | Share the `handoff_url` from registration |

## Configuration

- **API Base URL**: `https://api.outlayer.fastnear.com`
- **Dashboard**: `https://outlayer.fastnear.com`
- **Network**: mainnet

---

## 1. Register Wallet

Call the registration endpoint. No auth required.

```bash
curl -s -X POST https://api.outlayer.fastnear.com/register
```

Response:
```json
{
  "api_key": "wk_15807dbda492636df5280629d7617c3ea80f915ba960389b621e420ca275e545",
  "near_account_id": "36842e2f73d0b7b2f2af6e0d94a7a997398c2c09d9cf09ca3fa23b5426fccf88",
  "handoff_url": "https://outlayer.fastnear.com/wallet?key=wk_...",
  "trial": {
    "calls_remaining": 100,
    "expires_at": "2026-04-10T00:00:00Z",
    "limits": { "max_instructions": 100000000, "max_execution_seconds": 30, "max_memory_mb": 64 }
  }
}
```

**Save `api_key` securely** — it is shown only once. All subsequent requests require it.

**Important:** Persist the `api_key` to a file or session state immediately after registration. If you lose the key, recovery depends on the user having set a policy (see Key Recovery below).

The `near_account_id` is the NEAR implicit account (hex public key). Cross-chain transfers (Ethereum, Bitcoin, Solana, etc.) are handled via NEAR Intents — no gas tokens needed on other chains.

## 2. Free Trial: Run WASI Without Payment

Every registered wallet gets **100 free WASI execution calls** (30-day expiry).

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"input": "hello"}' \
  "https://api.outlayer.fastnear.com/call/{owner}/{project}"
```

**Trial limits:** 100 calls, 30-day expiry, 10 req/min, 3s cooldown, 30s execution, 100M instructions, 64MB RAM.

**Check remaining quota:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/trial/status"
```

When quota is exhausted (HTTP 402), upgrade to a payment key (see below).

## 3. Request Funding from User

NEAR balance is needed for on-chain operations (`/call`, `/intents/swap`, `/transfer`). Cross-chain operations via Intents (`/intents/withdraw`) are gasless.

**Fund link format:**
```
https://outlayer.fastnear.com/wallet/fund?to={near_account_id}&amount={amount}&token={token}&msg={message}
```

| Param | Required | Description |
|-------|----------|-------------|
| `to` | yes | Agent's NEAR account (the `near_account_id` from registration) |
| `amount` | yes | Human-readable amount (e.g. `1` for 1 NEAR, `10` for 10 USDT) |
| `token` | no | `near` (default) or FT contract ID (e.g. `usdt.tether-token.near`) |
| `msg` | no | Message to display to the user (URL-encoded) |

The page automatically handles FT storage deposits.

## 4. Request Policy from User (Optional)

A policy defines spending limits, address whitelists, and multisig rules.

**Available policy types:** spending limits, address whitelist/blacklist, allowed tokens, transaction types, time restrictions, rate limits, multisig approval, authorized API keys, webhooks.

**Message to user:**
> Please configure a security policy for your wallet:
> https://outlayer.fastnear.com/wallet?key={api_key}

## Key Recovery

If you lost your wallet API key and the user previously set a policy, the key is saved in their browser.

**Message to user:**
> I lost access to your wallet API key. Please go to: https://outlayer.fastnear.com/wallet/manage
> Find your wallet, click **show** next to the API Key, then copy and paste it here.
> The key looks like: `wk_15807d...e545`

After receiving the key, verify: `GET /wallet/v1/balance?chain=near` with the key.

If recovery is not possible (no policy set, browser data cleared), register a new wallet with `POST /register`.

## 5. Upgrade to Paid (Payment Key)

When trial quota runs out, create a payment key. Wallet must have USDC or NEAR balance.

### Option A: Pay with USDC
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"initial_deposit_usdc": "2.00"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/create-payment-key"
```

### Option B: Pay with NEAR
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"initial_deposit_near": "1.0"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/create-payment-key"
```

Response includes `payment_key` — save securely. Use via `X-Payment-Key` header for paid WASI calls.

---

## Wallet Operations

### Check balance
```bash
# Native NEAR
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near"

# FT token (e.g. USDT)
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near&token=usdt.tether-token.near"

# Intents deposit balance (tokens in intents.near)
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?token=wrap.near&source=intents"
```

Response: `{"balance": "1000000000000000000000000", "token": "near", "account_id": "36842e..."}`

### Get address (for other chains)
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/address?chain=ethereum"
```
Supported chains: `near`, `ethereum`, `solana`, `bitcoin`, etc.

### Transfer NEAR
**Before calling:** check NEAR balance covers transfer amount + gas (~0.001 NEAR).

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"chain":"near","receiver_id":"bob.near","amount":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/transfer"
```

### Transfer FT tokens (USDT, wNEAR, etc.)

Use the generic contract call endpoint with `ft_transfer`. Requires 1 yoctoNEAR deposit. Receiver must have storage registered on the token contract.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"receiver_id":"usdt.tether-token.near","method_name":"ft_transfer","args":{"receiver_id":"bob.near","amount":"1000000"},"gas":"30000000000000","deposit":"1"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/call"
```

### Call a contract
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"receiver_id":"wrap.near","method_name":"near_deposit","args":{},"deposit":"10000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/call"
```

Response: `{"request_id": "uuid", "status": "success", "tx_hash": "...", "result": ...}`

### Delete wallet
**WARNING:** FT tokens and Intents balances are lost. Transfer all assets first.

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"beneficiary":"receiver.near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/delete"
```

---

## Cross-Chain Swaps (NEAR Intents)

Swap tokens across 20+ blockchains using NEAR Intents protocol. All swaps are atomic — either both sides complete or nothing happens.

### Token ID Format (CRITICAL)

| Endpoint | Format | Example |
|----------|--------|---------|
| `/intents/swap` and `/intents/swap/quote` | Defuse asset ID with prefix | `nep141:wrap.near` |
| `/intents/deposit` | Plain NEAR contract ID | `wrap.near` |
| `/intents/withdraw` | Plain NEAR contract ID | `wrap.near` |
| `/balance` (wallet) | Plain NEAR contract ID | `wrap.near` |
| `/balance?source=intents` | Either format (auto-prefixed) | `wrap.near` or `nep141:wrap.near` |

**Rule:** Swap uses `nep141:` prefix. Everything else uses plain contract ID.

### Swap workflow

**1. Find token IDs:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/tokens"
```
Response includes `defuse_asset_id` for each token — use this in swap calls.

**2. Check input balance:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near&token=wrap.near"
```

**3. Preview swap rate (optional, no gas):**
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap/quote"
```
Response: `{"amount_out": "3150000", "min_amount_out": "3118500", "deadline": "...", "time_estimate_seconds": 30}`

**4. Execute swap:**
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000","min_amount_out":"3000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap"
```
Response: `{"request_id": "uuid", "status": "success", "amount_out": "3150000", "intent_hash": "..."}`

The swap handles everything internally — quote, storage registration, intents deposit, solver transfer, settlement. **No prerequisites needed.**

`min_amount_out` is optional — omit for a market order. Set to protect against slippage.

### Common swap pairs

| Pair | token_in | token_out |
|------|----------|-----------|
| wNEAR to USDT | `nep141:wrap.near` | `nep141:usdt.tether-token.near` |
| USDT to wNEAR | `nep141:usdt.tether-token.near` | `nep141:wrap.near` |
| wNEAR to USDC | `nep141:wrap.near` | `nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1` |
| wNEAR to ETH | `nep141:wrap.near` | `nep141:eth.omft.near` |
| wNEAR to BTC | `nep141:wrap.near` | `nep141:btc.omft.near` |

### Cross-chain transfer (deposit + withdraw)

For moving tokens to another chain without swapping:

```bash
# 1. Deposit tokens into intents balance
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token":"wrap.near","amount":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/deposit"

# 2. Withdraw to destination
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"to":"receiver.near","amount":"1000000000000000000000000","token":"wrap.near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/withdraw"
```

### Dry-run (check without executing)
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"to":"receiver.near","amount":"1000000000000000000000000","token":"wrap.near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/withdraw/dry-run"
```

### Supported chains

NEAR, Ethereum, Bitcoin, Solana, Arbitrum, Base, Polygon, Optimism, Avalanche, BSC, TON, Aptos, Sui, StarkNet, Tron, Stellar, Dogecoin, XRP, Zcash, Litecoin, Bitcoin Cash, Berachain, Aleo, Cardano, Dash.

Use `GET /wallet/v1/tokens` for the full current list.

---

## Quick Reference

| Action | Method | Endpoint |
|--------|--------|----------|
| Register | POST | `/register` |
| Execute WASI (trial) | POST | `/call/{owner}/{project}` |
| Trial status | GET | `/trial/status` |
| Create payment key | POST | `/wallet/v1/create-payment-key` |
| Get address | GET | `/wallet/v1/address?chain={chain}` |
| Get balance | GET | `/wallet/v1/balance?chain={chain}&token={token}` |
| Get intents balance | GET | `/wallet/v1/balance?token={token}&source=intents` |
| Transfer NEAR | POST | `/wallet/v1/transfer` |
| Call contract | POST | `/wallet/v1/call` |
| Swap tokens | POST | `/wallet/v1/intents/swap` |
| Swap quote | POST | `/wallet/v1/intents/swap/quote` |
| Intents deposit | POST | `/wallet/v1/intents/deposit` |
| Withdraw (cross-chain) | POST | `/wallet/v1/intents/withdraw` |
| Dry-run withdrawal | POST | `/wallet/v1/intents/withdraw/dry-run` |
| List tokens | GET | `/wallet/v1/tokens` |
| Request status | GET | `/wallet/v1/requests/{request_id}` |
| List requests | GET | `/wallet/v1/requests` |
| Audit log | GET | `/wallet/v1/audit?limit=50` |
| Delete wallet | POST | `/wallet/v1/delete` |

All endpoints except `/register` require `Authorization: Bearer <api_key>` header.
Base URL: `https://api.outlayer.fastnear.com`

---

## Token Amounts Reference

| Token | Decimals | 1 unit in smallest denomination |
|-------|----------|---------------------------------|
| NEAR / wNEAR | 24 | `1000000000000000000000000` |
| USDT / USDC | 6 | `1000000` |
| ETH / wETH | 18 | `1000000000000000000` |
| BTC / wBTC | 8 | `100000000` |
| SOL | 9 | `1000000000` |

## Automatic Storage Registration

| Endpoint | What it auto-registers |
|----------|----------------------|
| `/wallet/v1/intents/swap` | Output token storage on your wallet |
| `/wallet/v1/intents/deposit` | Your wallet's storage on `intents.near` |
| Fund link (dashboard) | Your wallet's storage on the token contract |

**NOT auto-registered:** `/wallet/v1/call` — register storage manually with `storage_deposit` if calling `ft_transfer` to a new receiver.

## Reading Transaction Statuses

| Status | Meaning | Action |
|--------|---------|--------|
| `success` | Completed | Read result fields |
| `failed` | Failed | Check `result` for error details |
| `processing` | In progress | Poll `GET /wallet/v1/requests/{id}` |
| `pending_approval` | Needs multisig | Inform user, provide dashboard link |

## Error Handling

| Error | Meaning |
|-------|---------|
| `missing_auth` | No `Authorization: Bearer` header |
| `invalid_api_key` | Key revoked or not found |
| `policy_denied` | Operation blocked by policy rules |
| `wallet_frozen` | Wallet frozen by controller |
| `insufficient_balance` | Not enough funds |
| `unsupported_token` | Token not supported — check `/tokens` |
| `pending_approval` | Needs multisig approval (not an error) |
| `"token_in must use defuse asset format"` | Missing `nep141:` prefix in swap |
| `"1Click swap was refunded"` | Solver couldn't fill — tokens returned to wallet |

## Guidelines

- **Always check balance before any operation.** Query `/wallet/v1/balance` before swap, transfer, call, or withdraw.
- **Use quote to preview swap rates.** The quote endpoint is free — no gas, no state change.
- **Swap handles everything.** No need to deposit into intents first.
- **`min_amount_out` is optional** but recommended for slippage protection.
- **Cross-chain transfers need deposit + withdraw.** Only for moving tokens without swapping.
- **Poll for async results.** If status is `processing`, poll `/requests/{id}`.
- Always use `withdraw/dry-run` before real withdrawals.
- Store the API key as a secret — never log or expose it.
- NEAR amounts are in yoctoNEAR (1 NEAR = 10^24 yoctoNEAR).

## References

- [Token reference](references/token-reference.md) — popular tokens with IDs, decimals, chains
- [Cross-chain patterns](references/cross-chain-patterns.md) — complete workflow examples
