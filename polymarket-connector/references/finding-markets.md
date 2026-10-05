# Finding markets without spending a call

> Part of the `polymarket-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/polymarket-connector/`.

Public data needs no call: `https://gamma-api.polymarket.com/markets` carries
`bestBid`, `bestAsk`, `spread`, `liquidityNum`, `orderMinSize`, `endDate`,
`sportsMarketType`. For a sports market `endDate` is the game's start, not
its resolution: it keeps accepting orders through the game and resolves
hours later. Crypto up/down markets are the fastest and carry the highest
fee. An order you may want to cancel later belongs on a market that is
neither.

Polymarket's public APIs need no key, and a keyword search is cheaper there
than through the connector. The pattern: search and read at Polymarket, place
and settle through the connector.

* Search: `GET https://gamma-api.polymarket.com/public-search?q=<words>&limit_per_type=5`
  → `events[]`, each with `title`, `slug` and `markets[]` carrying
  `question`, `conditionId`, `bestBid`, `bestAsk`. One event can hold many
  markets (dates, thresholds): pick the market, not the event.
* One event in full: `GET https://gamma-api.polymarket.com/events?slug=<slug>`
  → `markets[]` with `conditionId`, `clobTokenIds` and `outcomes` (both are
  JSON **strings** — parse them; the n-th token is the n-th outcome),
  `outcomePrices`, `bestBid`, `bestAsk`, `orderMinSize`,
  `orderPriceMinTickSize`, `negRisk`, `endDate`, `feesEnabled`.
* The live book for a token: `GET https://clob.polymarket.com/book?token_id=<token_id>`
  → `bids[]`, `asks[]` with `price` and `size`; sort them yourself.
* Show the user `https://polymarket.com/event/<slug>` — the same page the
  search found.

Then `order` names the `token_id`. The connector's own `markets {"query"}`
/ `markets {"market"}` give the same facts for a tenth of a cent when a call
is simpler than an HTTP fetch.
