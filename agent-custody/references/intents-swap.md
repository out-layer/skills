# Swap tokens (NEAR Intents)

> Part of the `agent-custody` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/agent-custody/`.

> These routes act on your OutLayer wallet, the account whose key is in the enclave. If your main balance lies in a wallet contract (on-chain custody), it does not move through them: see `on-chain-custody.md`. A swap asked for there returns its result, and any refund, to the wallet contract's balance inside NEAR Intents.

## Cross-Chain Swaps (NEAR Intents)

Swap tokens across 20+ blockchains using NEAR Intents protocol. All swaps are atomic - either both sides complete or nothing happens.

### Swap workflow

**1. Find token IDs:**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.ai/wallet/v1/tokens"
```
Response includes `defuse_asset_id` for each token. `token_in` is the asset's id on intents.near — `nep141:…`, `nep245:…`, or its NEAR-side 1Click id `1cs_v1:near:nep141:…` (the same balance); a `1cs_v1:` id on another chain is a delivery, not a balance, and is refused as a source (`400 unsupported_token`). `token_out` takes any `nep141:`, `nep245:` or `1cs_v1:` id the catalog lists, sent to 1Click as given — for a `1cs_v1:<chain>:…` destination 1Click decides which id lands on intents.near (ZEC bought as `1cs_v1:sol:spl:…` arrives as `nep141:zec.omft.near`).

> ⚠️ **`symbol` is NOT unique — never resolve a token by symbol.** The same
> display symbol appears once per chain (e.g. "USDC" returns ~17 entries:
> `nep141:17208628…` native NEAR USDC, `nep141:eth-0xa0b8…omft.near` Ethereum
> USDC, `nep141:base-0x833…omft.near` Base USDC, plus arb/sol/avax/pol/op/…).
> A naive `symbol === "USDC"` lookup grabs the first match (usually the
> Ethereum-bridged one) and you deposit/withdraw against the WRONG chain's
> asset — funds end up stuck or lost. Always select the entry by its exact
> `defuse_asset_id`, choosing the one whose `chains` array contains your target
> chain. See [token-reference.md](token-reference.md) for the
> chain-disambiguated list of common assets.

**2. Check intents balance (tokens must be in intents):**
```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.outlayer.ai/wallet/v1/balance?token=wrap.near&source=intents"
```

If tokens are on the NEAR account (not in intents), deposit them first:
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token":"wrap.near","amount":"1000000000000000000000000"}' \
  "https://api.outlayer.ai/wallet/v1/intents/deposit"
```

**3. Preview swap rate (optional, no gas):**
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000"}' \
  "https://api.outlayer.ai/wallet/v1/intents/swap/quote"
```
Response: `{"amount_in": "1000000000000000000000000", "amount_out": "3150000", "min_amount_out": "3118500", "amount_in_usd": "…", "amount_out_usd": "…", "withdraw_fee": "0", "refund_fee": "0", "time_estimate_seconds": 30}` — 1Click's own figures. `amount_out` is its estimate, `min_amount_out` what it guarantees (1% under); the swap delivers between the two.

**4. Execute swap (gasless):**
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:wrap.near","token_out":"nep141:usdt.tether-token.near","amount_in":"1000000000000000000000000","min_amount_out":"3000000"}' \
  "https://api.outlayer.ai/wallet/v1/intents/swap"
```
Response: `{"request_id": "uuid", "status": "success", "amount_out": "3150000", "intent_hash": "..."}`

**Prerequisite:** tokens must be in intents balance. Use `/intents/deposit` to move from NEAR account, or receive via payment check (funds arrive in intents directly).

**Result stays in intents balance.** Use `/intents/withdraw` to move tokens out.

### Sizing a swap: exact input, a floor, or exact output

A swap body carries exactly one size. Any field the body does not need is refused (`400 bad_request` naming it).

| You know | Send | What happens |
|---|---|---|
| How much to sell | `amount_in` | That amount goes in; you receive what the quote gives |
| How much to sell, and the least you accept | `amount_in` + `min_amount_out` | The swap takes a FRESH quote and compares your floor to that quote's `min_amount_out` (the guarantee), before anything is signed. Under it: `400 below_min_amount_out`, body carries `quoted_min_amount_out`, nothing moved |
| How much you must receive | `amount_out` + `max_amount_in` (no `amount_in`, no `min_amount_out`) | You receive exactly `amount_out`. The swap sends the fresh quote's `amount_in` (it includes 1Click's 1% buffer) and 1Click returns the part it did not use to your intents balance afterwards. If the quote needs more than `max_amount_in`: `400 above_max_amount_in`, body carries `quoted_amount_in`, nothing moved |

Rules that decide whether the call goes through:

- **Leave the market room.** The swap never reuses your preview; it quotes again. A floor set exactly at a preview's `min_amount_out`, or a ceiling exactly at its `amount_in`, is refused whenever the fresh quote is one unit worse. Set the floor under the previewed `min_amount_out`, and the ceiling over the previewed `amount_in`, by the move you accept (0.5–1% is typical).
- **Never set the floor from `amount_out`.** That is the estimate; the guarantee is 1% lower, so such a floor is always refused.
- **`max_amount_in` is what your policy sees.** Per-transaction and daily limits, and approvers on a multisig wallet, judge `max_amount_in`, the balance must cover all of it (not only the quoted `amount_in`), and the daily limit is charged that figure — the returned input is not given back to it. Keep the ceiling tight, and never above the balance.
- The quote endpoint takes the same body. With a floor or ceiling in it, a quote that does not meet it answers `200` with `"reason": "below_min_amount_out"` or `"above_max_amount_in"` and the figures — the refusal the swap would give.

```bash
# Receive exactly 0.1 wNEAR, spend at most 0.30 USDC
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"token_in":"nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1","token_out":"nep141:wrap.near","amount_out":"100000000000000000000000","max_amount_in":"300000"}' \
  "https://api.outlayer.ai/wallet/v1/intents/swap"
```

The request's `result.quote` is the quote the swap ran with (`amount_in`, `min_amount_in`, `amount_out`, `min_amount_out`, `swap_type`, and `max_amount_in` on an exact output); `result.refunded_amount` appears once 1Click reports what it returned.

> **Reading `amount_out` correctly — the realized fill. SAME RULE for `/intents/swap` AND `/confidential/swap`:**
>
> `amount_out` is the **actual delivered amount ONLY when `status == "success"`**. At every earlier stage it is an **estimate, not the fill**:
> - `/intents/swap/quote` and `/confidential/swap/quote` → price preview only.
> - **Public** `/intents/swap` blocks to settlement, so its response usually already carries `status:"success"` + the realized `amount_out`. If it returns `processing` (settlement outlasted the call's wait; `amount_out` is then the quote), poll its `poll_url` (`GET /wallet/v1/requests/{request_id}`) and read `result.amount_out` from the `success` row. The swap runs to its outcome even if your client disconnects — give the call at least 100 s, and if your client gives up first, do not submit a new swap: re-send with the same `X-Idempotency-Key` and poll the id the duplicate answer names.
> - **Confidential** `/confidential/swap` returns `status:"pending_deposit"` with **NO `amount_out`** in the submit response — this is **timing, NOT privacy**. It settles `pending_deposit → processing → success` (slower than public); the realized `amount_out` appears in `result.amount_out` **only at `success`**. The actual delivered amount *is* returned — confidential does **not** hide it. A short poll window (e.g. 90s / 30×3s) can expire before `success` — keep polling, do not give up and record the quote.
>
> **Never** record a position / qty / PnL from a quote or a submit-time estimate, and **never** fall back to a snapshot- or price-derived qty — both drift from the real fill. The only correct source is **`result.amount_out` read at `status == "success"`**, for both public and confidential swaps.

### Common swap pairs

| Pair | token_in | token_out |
|------|----------|-----------|
| wNEAR to USDT | `nep141:wrap.near` | `nep141:usdt.tether-token.near` |
| USDT to wNEAR | `nep141:usdt.tether-token.near` | `nep141:wrap.near` |
| wNEAR to USDC | `nep141:wrap.near` | `nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1` |
| wNEAR to ETH | `nep141:wrap.near` | `nep141:eth.omft.near` |
| wNEAR to BTC | `nep141:wrap.near` | `nep141:btc.omft.near` |
