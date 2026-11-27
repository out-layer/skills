# Tokenized stocks and vault yield (Ondo, Earn)

> Part of the `agent-custody` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/agent-custody/`.

Hold a tokenized stock or ETF (Ondo), or a yield vault position (1Click Earn),
on the wallet's public or confidential intents balance. Both are ordinary
tokens reached by a swap: there is no stock or yield endpoint. This file does
not cover the issuers or the vault protocols themselves: OutLayer and 1Click do
not run them, set their yield, or guarantee principal.

## What they are

| Kind | What the token is | Where it lives | Find the ids |
|---|---|---|---|
| Ondo stock / ETF | Ondo's token tracking one stock, ETF or portfolio (`TSLAon`, `NVDAon`, `SPYon`, `GLDon`, …; also `USDY`, `USDon`) | BNB Chain: `chains: ["bsc"]`, ids `nep141:bnb-0x….omdep.near`, **18 decimals** | `GET /wallet/v1/tokens`, entries on `bsc` whose `symbol` ends in `on`, plus `USDY` |
| Earn receipt token | A vault's shares; holding it is the position | The vault's chain (`base`, `eth`, `sol`) | The table in `token-reference.md`, then confirm in `GET /wallet/v1/tokens` |

Pick a token by its exact `defuse_asset_id`, never by its symbol.

## Rules that hold on every path

- **Every step is its own call, checked by the wallet policy on its own.**
  Nothing chains them for you: you call each step, read its answer, then call
  the next. The policy can allow one step and refuse another (a swap allowed, a
  withdrawal to BSC refused).
- **Every instrument has a minimum size in each direction.** Below it the quote
  answers `400 no_liquidity`. Minimums run from under $1 to over $10 and move
  with liquidity, and the exit minimum is not the entry minimum. **Before entering, quote the entry AND the exit for the same size**
  (`/swap/quote` both ways). Never enter a position smaller than its exit
  minimum: it cannot be sold back. A partial exit must also clear the exit
  minimum.
- **A round trip pays two spreads.** Read `amount_in_usd` against
  `amount_out_usd` on each quote. Tell the user the cost before entering.
- **No yield figure comes from this API.** There is no APY, share price or
  position value endpoint. The position's value is its balance times the price
  of a fresh quote back to USDC.

## Confidential path (the position is hidden on the confidential balance)

Endpoints and bodies: `confidential.md`. USDC on NEAR is
`nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1`
(6 decimals).

Enter:

1. `POST /wallet/v1/confidential/shield` `{ token: <USDC>, amount }`: USDC from
   the public intents balance into the confidential one. Poll
   `GET /wallet/v1/requests/{request_id}` to `success`.
2. `POST /wallet/v1/confidential/swap/quote` `{ token_in: <USDC>, token_out: <stock or receipt id>, amount_in }`,
   and the exit quote the other way (rule above).
3. `POST /wallet/v1/confidential/swap` with the same body, plus `min_amount_out`
   from the quote. Poll to `success`; the fill is `result.amount_out`.
4. `GET /wallet/v1/confidential/balance?token=<stock or receipt id>`.

Exit:

1. `POST /wallet/v1/confidential/swap` `{ token_in: <stock or receipt id>, token_out: <USDC>, amount_in }`. Poll to `success`.
2. `POST /wallet/v1/confidential/unshield` `{ token: <USDC>, amount }` back to
   the public intents balance, or `POST /wallet/v1/confidential/withdraw` to
   another chain.

To take the token itself out instead of selling it, use
`/confidential/withdraw` with its home chain: `chain: "bsc"` and a `0x`
address for an Ondo token.

Shield and unshield put the wallet on the public chain; see the privacy model
in `confidential.md` before promising the user that the position is unlinkable.

## Public path

Endpoints and bodies: `intents-swap.md`, `intents-withdraw.md`.

1. `POST /wallet/v1/intents/swap/quote` `{ token_in: <USDC>, token_out: <stock or receipt id>, amount_in }`, and the exit quote back.
2. `POST /wallet/v1/intents/swap` with the same body and `min_amount_out`.
3. Exit: `POST /wallet/v1/intents/swap` back to USDC, or
   `POST /wallet/v1/intents/withdraw` with the token's home chain (`chain: "bsc"`
   and a `0x` address for an Ondo token; pass `"async": true` and poll).

## What to tell the user

Before the first buy: "This buys `<symbol>`, a token issued by `<Ondo / the
vault's protocol>`, not by OutLayer. Entering and leaving costs about
`<entry + exit spread from the quotes>`; the smallest position that can be sold
back is about `<exit minimum>`. Its yield, if any, is set by the issuer, and
nothing here guarantees the principal."
