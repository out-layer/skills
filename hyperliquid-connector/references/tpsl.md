# Stop-loss and take-profit (trigger orders)

> Part of the `hyperliquid-connector` skill. Read `SKILL.md` first. When fetched over HTTP the base is `https://skills.outlayer.ai/hyperliquid-connector/`.

Hyperliquid holds a trigger order and fires it on the **mark price** the
moment it is crossed — between your checks, while you are not running. Place
the stop right after a position opens; a stop you plan to place at the next
check does nothing during a fast move. Every trigger order is reduce-only: it
closes, it never opens.

The rules below are Hyperliquid's documentation and its SDKs, as the connector
sends them. On a funded account they are not yet "seen": where a behaviour
is not observed, this file says so and tells you the step that is safe
either way.

## Three shapes, one operation

| you want | send to `order` |
|---|---|
| a stop (or target) on a position you hold | `"grouping": "positionTpsl"` and `"tp"` and/or `"sl"` — no `side`, no `size` |
| to open a position with its stop and target in one call | the entry as usual, plus `"grouping": "normalTpsl"` and `"tp"` and/or `"sl"` |
| one trigger order with a side and size you choose | `"kind": "trigger"`, `"side"` (the **closing** side: `sell` closes a long), `"size"`, `"trigger_px"`, `"tpsl"` |

```json
{"operation": "order", "coin": "ETH", "grouping": "positionTpsl",
 "sl": {"trigger_px": "2400"}, "tp": {"trigger_px": "2900"}}
```

```json
{"operation": "order", "coin": "ETH", "side": "buy", "size": "0.004", "kind": "market",
 "grouping": "normalTpsl", "sl": {"trigger_px": "2400"}, "tp": {"trigger_px": "2900"}}
```

```json
{"operation": "order", "coin": "ETH", "side": "sell", "size": "0.004",
 "kind": "trigger", "trigger_px": "2400", "tpsl": "sl"}
```

A `tp`/`sl` leg is `{trigger_px, is_market?, price?, size?, cloid?}`; the
same three fields sit at the top level for `kind: trigger` (`tpsl` is `tp` or
`sl` there).

| field | meaning |
|---|---|
| `trigger_px` | the mark price that fires it; price rules apply (5 significant figures, the market's decimals) |
| `is_market` | `true` (default): once fired it fills at market, within the venue's 10% slippage tolerance. `false`: once fired it rests as a limit at `price` |
| `price` | only with `is_market: false` — the limit. A limit at the trigger may rest unfilled after a gap; one further away fills more surely. For a stop that must close, keep the default |
| `size` | `positionTpsl` only. Absent: the **whole position at the moment it fires**, even if you added to it since. Given: that size, fixed — it does not follow the position |
| `cloid` | your own id, `0x` + 32 hex; cancel by it |

Side of the trigger: a long's stop is **below** the mark and its target
above; a short's the reverse. The venue judges the trigger price and refuses
one it finds invalid with its own sentence (`Hyperliquid rejected …`); the
connector does not judge it first.

## What the venue does with them

* **TP and SL placed together**: the one that fills cancels the other.
* **`normalTpsl`**: the TP/SL take the entry's size. They are placed when the
  entry fills fully; an entry cancelled unfilled — or partly filled and then
  cancelled — takes them with it. After a `normalTpsl` whose entry did not
  fill fully, read `orders`: if you hold a position and no trigger order
  rests for it, place a `positionTpsl`.
* **Liquidation** cancels the account's orders.
* **You closed the position yourself**: cancel its TP/SL — `orders`, then
  `cancel` each trigger order's `oid` on that coin. Whether the venue removes
  them on its own when the position reaches zero is not observed, and a
  reduce-only stop left behind closes the next position you open on the
  wrong side.
* **Moving a stop**: place the new one first, then cancel the old `oid` — the
  position is never without one.
* **The $10 minimum order** (`SKILL.md`, "Trading") applies to closes; whether
  it refuses a TP/SL at placement is not observed. Keep positions large
  enough that a full close is ≥ $10.

## Reading the answer and `orders`

The answer to `order` lists every order of the action in `orders[]`, each
with `role` (`entry`, `tp`, `sl`), `side`, `price`, `size`, `trigger_px`,
`is_market`, `counted_usd` and the venue's own `status`. A status that is
not `{"error": …}` is placed; note its `oid` when it carries one. A
`positionTpsl` leg sent for the whole position shows `size: "0"` and
`whole_position: true`. **`warnings`** names an order the venue refused while
the rest was placed — the position lacks the stop you asked for: place it
again as a `positionTpsl`. When the venue refuses every order the call is
`success: false`, `Hyperliquid rejected …`.

On `{"operation": "orders"}` a trigger order carries `isTrigger: true`,
`triggerPx`, `triggerCondition`, `isPositionTpsl`, `reduceOnly`, `oid`,
`side` (`B` buy, `A` sell).

## Policy and cost

TP/SL and every reduce-only order are refused by none of the owner's caps —
`max_order_usd`, `max_daily_volume_usd`, `max_leverage`, the leverage record —
and need none of them in the policy: closing stays possible whatever the
owner set. `coins` still applies. Each counts toward the day's volume at the
higher of its trigger and limit plus 10% (a whole-position leg at the
position's size when placed), so an entry with a TP and an SL
counts three times, though at most one exit fills; leave room in
`max_daily_volume_usd` for it.

A grouped action is one `order` call: $0.01 for the entry and both legs.
