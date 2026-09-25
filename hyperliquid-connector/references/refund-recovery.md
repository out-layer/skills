# Recovering a 1Click refund on HyperCore

> Part of the `hyperliquid-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/hyperliquid-connector/`.

**When this applies.** A `withdraw_start` to `intents` or `confidential` sent
its spot transfer, and 1Click then failed the route and refunded. A refund
from HyperCore goes back on HyperCore — not to your trading account, but to
the wallet's OWN EVM address, a key the connector cannot sign with. The signs:
`withdraw_status` stays `bridging` past its `expires_at` while the intents (or
confidential) balance has not risen, and the wallet's address holds spot USDC.
Nothing is lost: that account is the wallet's. Not yet seen live.

Moving it back is a HyperCore spot transfer signed by the wallet's own key. It
costs no gas: HyperCore takes a signature and an HTTP POST.

1. **The address.** `GET /wallet/v1/address?chain=ethereum` → `address`. The
   wallet's EVM address is the same on HyperCore.
2. **What is there.** `POST https://api.hyperliquid.xyz/info`
   `{"type": "spotClearinghouseState", "user": "<address>"}` → the `balances`
   entry with `"coin": "USDC"`, its `total`.
3. **The fee.** `POST https://api.hyperliquid.xyz/info`
   `{"type": "preTransferCheck", "user": "<address>", "source": "<address>"}`
   → `fee`: `"1.0"` for an account's first outbound transfer, then `"0.0"`.
   Send `total − fee`, as a plain decimal string (`"12.35"`).
4. **Where to.** Your trading account — `addresses.trading` from
   `{"operation": "status"}`. The money is the connector's again, and a normal
   `withdraw_start` takes it on.
5. **Sign** this EIP-712 object with the wallet's own key (no `sub_path`,
   `"chain": "arbitrum"`) — the request shape is in
   <https://skills.outlayer.ai/agent-custody/references/signing-evm-solana.md>.
   `time` is now in milliseconds, and the same number is the nonce below.

   ```json
   {
     "domain": {"name": "HyperliquidSignTransaction", "version": "1",
                "chainId": 42161,
                "verifyingContract": "0x0000000000000000000000000000000000000000"},
     "types": {
       "EIP712Domain": [{"name": "name", "type": "string"}, {"name": "version", "type": "string"},
                        {"name": "chainId", "type": "uint256"}, {"name": "verifyingContract", "type": "address"}],
       "HyperliquidTransaction:SpotSend": [
         {"name": "hyperliquidChain", "type": "string"}, {"name": "destination", "type": "string"},
         {"name": "token", "type": "string"}, {"name": "amount", "type": "string"},
         {"name": "time", "type": "uint64"}]
     },
     "primaryType": "HyperliquidTransaction:SpotSend",
     "message": {"hyperliquidChain": "Mainnet", "destination": "<trading, lowercase>",
                 "token": "USDC:0x6d1e7cde53ba9467b783cb7c530ce054",
                 "amount": "12.35", "time": 1790261829555}
   }
   ```

6. **Send.** Split the 65-byte signature into `r` (bytes 0–31), `s` (32–63)
   and `v` (the last byte, 27 or 28; add 27 to a 0 or 1), then
   `POST https://api.hyperliquid.xyz/exchange`:

   ```json
   {"action": {"type": "spotSend", "hyperliquidChain": "Mainnet", "signatureChainId": "0xa4b1",
               "destination": "<trading>", "token": "USDC:0x6d1e7cde53ba9467b783cb7c530ce054",
               "amount": "12.35", "time": 1790261829555},
    "nonce": 1790261829555,
    "signature": {"r": "0x…", "s": "0x…", "v": 27},
    "vaultAddress": null}
   ```

   `{"status": "ok"}` means it went; `{"status": "err", …}` means nothing
   moved. `{"operation": "status"}` then shows the USDC on your spot.

The `token` is USDC's HyperCore token id (`spotMeta`, `USDC:<tokenId>`); the
`destination` and every field must be exactly as signed, or the signature
recovers to a different account and the venue refuses it.
