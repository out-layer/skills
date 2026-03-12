# Cross-Chain Patterns — Complete Workflow Examples

All examples use `$API_KEY` as the wallet API key and `https://api.outlayer.fastnear.com` as base URL.

## Pattern 1: Swap wNEAR to USDT (Same Chain)

Most common pattern — swap within NEAR ecosystem.

```bash
# 1. Check wNEAR balance
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near&token=wrap.near"
# Response: {"balance": "5000000000000000000000000", "token": "wrap.near", ...}
# → 5 wNEAR available

# 2. Check NEAR balance for gas
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near"
# Ensure at least 0.01 NEAR for gas

# 3. Get quote (optional — preview rate without executing)
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap/quote"
# Response: {"amount_out": "3150000", "min_amount_out": "3118500", ...}
# → 1 wNEAR ≈ 3.15 USDT

# 4. Execute swap (1 wNEAR → USDT, min 3.0 USDT)
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000","min_amount_out":"3000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap"
# Response: {"request_id": "...", "status": "success", "amount_out": "3150000"}

# 5. Verify USDT arrived
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near&token=usdt.tether-token.near"
```

## Pattern 2: Swap wNEAR to ETH (Cross-Chain)

ETH is represented as `nep141:eth.omft.near` on NEAR. After swap, ETH sits in your wallet's NEAR account as a bridged asset.

```bash
# 1. Check quote for 10 wNEAR → ETH
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:eth.omft.near","amount_in":"10000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap/quote"
# Response: {"amount_out": "6420000000000000", ...}
# → 10 wNEAR ≈ 0.00642 ETH

# 2. Execute swap
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:eth.omft.near","amount_in":"10000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap"
```

## Pattern 3: Convert ETH to NEAR for Gas

Agent received ETH but needs NEAR to pay for gas.

```bash
# 1. Check bridged ETH balance on NEAR
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?chain=near&token=eth.omft.near"

# 2. Swap ETH → wNEAR (0.01 ETH)
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:eth.omft.near","token_out":"nep141:wrap.near","amount_in":"10000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap"

# 3. Unwrap wNEAR to native NEAR (for gas)
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"receiver_id":"wrap.near","method_name":"near_withdraw","args":{"amount":"1000000000000000000000000"},"deposit":"1"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/call"
```

## Pattern 4: Check Rate and Swap Only If Favorable

Agent monitors rate and swaps when price is good.

```bash
# 1. Get current rate
QUOTE=$(curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap/quote")

AMOUNT_OUT=$(echo $QUOTE | jq -r '.amount_out')
echo "1 wNEAR = $(echo "scale=2; $AMOUNT_OUT / 1000000" | bc) USDT"

# 2. Only swap if rate is above threshold (e.g. 3.0 USDT per wNEAR)
if [ "$AMOUNT_OUT" -ge 3000000 ]; then
  curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{\"token_in\":\"nep141:wrap.near\",\"token_out\":\"nep141:usdt.tether-token.near\",\"amount_in\":\"1000000000000000000000000\",\"min_amount_out\":\"3000000\"}" \
    "https://api.outlayer.fastnear.com/wallet/v1/intents/swap"
fi
```

## Pattern 5: Move Tokens to Another NEAR Account via Intents

Deposit into intents → withdraw to another account. Useful when receiver doesn't have storage registered on the token contract.

```bash
# 1. Deposit wNEAR into intents balance
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token":"wrap.near","amount":"1000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/deposit"

# 2. Check intents balance
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.fastnear.com/wallet/v1/balance?token=wrap.near&source=intents"

# 3. Withdraw to receiver
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"to":"receiver.near","amount":"1000000000000000000000000","token":"wrap.near","chain":"near"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/withdraw"
```

## Pattern 6: Multi-Step — Swap and Send

Agent swaps tokens then sends the result to a user.

```bash
# 1. Swap wNEAR → USDT
SWAP=$(curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"5000000000000000000000000"}' \
  "https://api.outlayer.fastnear.com/wallet/v1/intents/swap")

AMOUNT_OUT=$(echo $SWAP | jq -r '.amount_out')

# 2. Send USDT to user via ft_transfer
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"receiver_id\":\"usdt.tether-token.near\",\"method_name\":\"ft_transfer\",\"args\":{\"receiver_id\":\"user.near\",\"amount\":\"$AMOUNT_OUT\"},\"gas\":\"30000000000000\",\"deposit\":\"1\"}" \
  "https://api.outlayer.fastnear.com/wallet/v1/call"
```

**Note:** The receiver (`user.near`) must have storage registered on `usdt.tether-token.near`. If not, register storage first with a `storage_deposit` call.
