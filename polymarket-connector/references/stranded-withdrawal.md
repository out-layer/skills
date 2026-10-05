# A withdrawal stranded under the bridge's floor

> Part of the `polymarket-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/polymarket-connector/`.

**When this applies.** `withdraw_status` stays at `bridging` and
`https://bridge.polymarket.com/status/<bridge_out>` is empty: what was sent to
the withdraw address is under the bridge's $2 floor and waits there. It is not
refused, not returned, and not listed by `/status`. Seen with $1.43.

**Join its route** with a second withdrawal that names the first:

```json
{"operation": "withdraw_start", "amount": "0.67", "resume": "<its id>"}
```

`amount` is decimal USDC, not minimal units. The bridge judges the address as
a whole (seen: 1.43 + 0.67 → one transfer of 2.10, `COMPLETED`), so the
original amount goes home. The route is good for three days from the original
call.

**Join with the minimum that clears the floor.** A too-small join is refused
with the sentence "send at least N". Anything above the original quote does
not reach intents: the 1Click leg swaps only its original quote and refunds
the rest as native USDC to the wallet's own Polygon address
(`GET /wallet/v1/address?chain=polygon`). Seen: 0.663 parked there for 0.67
joined. The joined amount always ends up this way: it is the price of the
rescue, not a side effect.

**Bringing the parked USDC home** is outside this connector, three steps:

1. A 1Click deposit intent for it:
   `POST /wallet/v1/intents/deposit/cross-chain {"chain":"polygon","token":"USDC","amount":"<units>"}`
   (`amount` here is minimal units, 6 decimals) — see
   [`agent-custody`](https://skills.outlayer.ai/agent-custody/references/cross-chain.md).
2. About 0.05 POL on that Polygon address for gas. Ask the owner: "To bring
   back the $<x> the Polymarket bridge refunded to my Polygon address, I need
   about 0.05 POL there for gas: <address>."
3. An ERC-20 `transfer` of the USDC from that address to the intent's deposit
   address, signed through `POST /wallet/v1/evm/sign-transaction` and
   broadcast by you — see
   [`agent-custody`](https://skills.outlayer.ai/agent-custody/references/signing-evm-solana.md).
