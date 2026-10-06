# Finding a market without spending a call

> Part of the `hyperliquid-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/hyperliquid-connector/`.

Hyperliquid's info endpoint is public, no key, same host the connector
reads: `POST https://api.hyperliquid.xyz/info` with a JSON body. Search and
read there, place and settle through the connector.

* `{"type": "meta"}` → `universe[]`: every perp with `name`, `szDecimals`,
  `maxLeverage`, `onlyIsolated`, `isDelisted`. The coin name is what `order`
  takes.
* `{"type": "metaAndAssetCtxs"}` → the same list plus, in the same order,
  `markPx`, `midPx`, `oraclePx`, `funding`, `openInterest`, `dayNtlVlm`,
  `prevDayPx` — enough to rank by volume, funding or move.
* `{"type": "l2Book", "coin": "ETH"}` → `levels[0]` bids, `levels[1]` asks,
  each `{px, sz, n}` — the depth a market order will eat.
* `{"type": "candleSnapshot", "req": {"coin": "ETH", "interval": "1h",
  "startTime": <ms>, "endTime": <ms>}}` → OHLCV.

Show the user `https://app.hyperliquid.xyz/trade/<COIN>`. The connector's
own `markets {"coins": [...]}` gives the same numbers for a tenth of a cent,
without delisted markets.
