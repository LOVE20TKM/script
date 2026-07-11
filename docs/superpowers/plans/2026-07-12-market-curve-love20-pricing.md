# Market Curve LOVE20 Pricing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 market-curve 对任意计价代币都通过 LOVE20 交易对间接计算其它代币价格，并移除首屏串行 meta 请求以缩短加载时间。

**Architecture:** 服务端将目标代币/LOVE20 candles 与 LOVE20/quote bridge candles 按时间合并后相乘；`quote=LOVE20` 使用目标代币/LOVE20 的直接结果，任何存在的目标代币/quote 直连交易对都不参与计算。页面直接请求完整 payload；服务端在一次请求内只聚合一次 LOVE20/quote bridge candles。

**Tech Stack:** Python `unittest`、SQLite、原生 HTML/CSS/JavaScript、SVG。

---

## File Map

- Modify: `script/log/dashboards/price_curve_runtime.py` — 增加 pair candle 复用、间接 candle 合并，并调整 token series 路由。
- Modify: `script/log/dashboards/test_price_curve_runtime.py` — 覆盖间接计算、时间延续、直接 quote 忽略和 `quote=LOVE20`。
- Modify: `script/log/dashboards/market-curve/index.html` — 初次直接请求完整数据，移除 `meta=1` 分支。
- Modify: `script/log/dashboards/test_market_curve_page.py` — 覆盖页面不再发 meta 请求的契约。

## Task 1: Add failing backend behavior tests

**Files:**
- Modify: `script/log/dashboards/test_price_curve_runtime.py`

- [ ] **Step 1: Test indirect candle multiplication and carry-forward values**

Add this test to `PriceCurveRuntimeTest`:

```python
    def test_indirect_candles_use_latest_values_at_each_timestamp(self) -> None:
        target_candles = [
            {"time": 100, "close_block": 10, "close": 2.0, "count": 1},
            {"time": 300, "close_block": 30, "close": 3.0, "count": 1},
        ]
        bridge_candles = [
            {"time": 100, "close_block": 11, "close": 4.0, "count": 1},
            {"time": 200, "close_block": 20, "close": 5.0, "count": 1},
        ]

        candles = price_curve_runtime.build_indirect_candles(target_candles, bridge_candles)

        self.assertEqual([candle["time"] for candle in candles], [100, 200, 300])
        self.assertEqual([candle["close"] for candle in candles], [8.0, 10.0, 15.0])
        self.assertEqual([candle["close_block"] for candle in candles], [11, 20, 30])
```

- [ ] **Step 2: Test the real token-series route and ignore a direct quote pair**

Add an in-memory SQLite fixture with `blocks`, `events`, `v_contract`, and `v_pair_created`. Register `ALPHA`, `LOVE20`, and `TUSDT`; add these pairs and Sync events:

```python
        target_pair = "0xtargetpair"
        bridge_pair = "0xbridgepair"
        direct_pair = "0xdirectpair"
        conn.executemany(
            "INSERT INTO v_pair_created(pair, token0, token1, block_number) VALUES (?, ?, ?, ?)",
            [
                (target_pair, "0xlove", "0xalpha", 10),
                (bridge_pair, "0xtusdt", "0xlove", 10),
                (direct_pair, "0xtusdt", "0xalpha", 10),
            ],
        )
        conn.execute("INSERT INTO blocks(block_number, timestamp) VALUES (?, ?)", (10, 1000))
        insert_event(conn, "", "Sync", 10, target_pair, {"reserve0": 1000, "reserve1": 100})
        insert_event(conn, "", "Sync", 10, bridge_pair, {"reserve0": 300, "reserve1": 100})
        insert_event(conn, "", "Sync", 10, direct_pair, {"reserve0": 99900, "reserve1": 100})
```

Call `query_token_series` with ALPHA and TUSDT, then assert the first close is `30.0` and the returned pair is `target_pair`, proving the direct 999 TUSDT price is ignored. Call the same fixture with quote LOVE20 and assert the first close is `10.0`, proving quote LOVE20 uses the direct target/LOVE20 path.

- [ ] **Step 3: Test bridge candle reuse**

Import `patch` from `unittest.mock`, call `query_price_curve_data` with the fixture and `token_symbols=["ALPHA"]`, and wrap `query_pair_candles`:

```python
        with patch.object(
            price_curve_runtime,
            "query_pair_candles",
            wraps=price_curve_runtime.query_pair_candles,
        ) as loader:
            price_curve_runtime.query_price_curve_data(
                conn,
                token_symbols=["ALPHA"],
                quote_symbol="TUSDT",
                interval="1d",
                days=30,
            )

        bridge_calls = [
            call for call in loader.call_args_list
            if call.args[1]["pair"] == bridge_pair
        ]
        self.assertEqual(len(bridge_calls), 1)
```

- [ ] **Step 4: Run the backend tests and verify RED**

Run:

```bash
python3 -m unittest script/log/dashboards/test_price_curve_runtime.py -v
```

Expected: the new tests fail because `build_indirect_candles` does not exist and `query_token_series` still reads a direct token/quote pair.

## Task 2: Implement the backend pricing bridge

**Files:**
- Modify: `script/log/dashboards/price_curve_runtime.py:38-197`

- [ ] **Step 1: Add a single pair-candle loader**

Extract Sync-row selection from `query_token_series` into:

```python
def query_pair_candles(
    conn: sqlite3.Connection,
    pair: dict,
    target: dict,
    quote: dict,
    from_block: int | None,
    to_block: int | None,
    interval_seconds: int,
) -> list[dict]:
    if pair["pair_contract_name"]:
        rows = query_sync_rows_by_contract(conn, pair["pair_contract_name"], from_block, to_block)
    else:
        rows = query_sync_rows_by_address(conn, pair["pair"], from_block, to_block)
    return build_candles(rows, pair, target, quote, interval_seconds)
```

- [ ] **Step 2: Add time-aligned indirect candles**

Implement the tested helper with one forward cursor per input list. At each sorted union timestamp, advance both cursors through candles whose `time` is not later than the timestamp; emit only when both current candles exist:

```python
def build_indirect_candles(target_candles: list[dict], bridge_candles: list[dict]) -> list[dict]:
    times = sorted({candle["time"] for candle in target_candles} | {candle["time"] for candle in bridge_candles})
    target_index = bridge_index = 0
    target_current = bridge_current = None
    candles = []
    for timestamp in times:
        while target_index < len(target_candles) and target_candles[target_index]["time"] <= timestamp:
            target_current = target_candles[target_index]
            target_index += 1
        while bridge_index < len(bridge_candles) and bridge_candles[bridge_index]["time"] <= timestamp:
            bridge_current = bridge_candles[bridge_index]
            bridge_index += 1
        if not target_current or not bridge_current:
            continue
        price = target_current["close"] * bridge_current["close"]
        candles.append({
            "time": timestamp,
            "time_label": iso_from_timestamp(timestamp),
            "close_block": max(target_current["close_block"], bridge_current["close_block"]),
            "open": price,
            "high": price,
            "low": price,
            "close": price,
            "count": target_current.get("count", 1) + bridge_current.get("count", 1),
        })
    return candles
```

- [ ] **Step 3: Resolve and reuse the quote bridge once per request**

In `query_price_curve_data`, resolve LOVE20 once. When quote is not LOVE20, find LOVE20/quote once and call `query_pair_candles` once. Pass that pair and candle list into each `query_token_series` call; do not find or query the bridge pair inside every token loop. If the bridge is absent, non-LOVE20 series return `LOVE20/计价代币交易对不存在` and never fall back to direct token/quote pairs.

- [ ] **Step 4: Route token series through the bridge**

Use this decision order inside `query_token_series`:

```python
if token["symbol"].upper() == quote["symbol"].upper():
    return {"token": token, "pair": None, "candles": [], "message": "不能和计价代币相同"}
if token["symbol"].upper() == "LOVE20":
    pair = quote_bridge_pair
    candles = quote_bridge_candles
elif quote["symbol"].upper() == "LOVE20":
    pair = find_pair(conn, token["address"], quote["address"])
    candles = query_pair_candles(conn, pair, token, quote, from_block, to_block, interval_seconds) if pair else []
else:
    pair = find_pair(conn, token["address"], love20["address"])
    target_candles = query_pair_candles(conn, pair, token, love20, from_block, to_block, interval_seconds) if pair else []
    candles = build_indirect_candles(target_candles, quote_bridge_candles or [])
```

Return the target/LOVE20 pair for indirect series, preserve `add_market_caps(conn, token, candles)`, and return clear messages when the required pair or candles are missing.

- [ ] **Step 5: Run backend tests and the full dashboard suite**

Run:

```bash
python3 -m unittest script/log/dashboards/test_price_curve_runtime.py -v
python3 -m unittest discover -s script/log/dashboards -p 'test_*.py' -v
```

Expected: indirect, direct LOVE20 quote, direct-pair-ignore, and all existing tests pass.

## Task 3: Add the failing frontend performance contract

**Files:**
- Modify: `script/log/dashboards/test_market_curve_page.py`

- [ ] **Step 1: Add the no-meta assertions**

Add:

```python
    def test_initial_load_requests_full_data_without_meta_round_trip(self) -> None:
        self.assertNotIn("meta=1", HTML)
        self.assertNotIn("fetchData(true)", HTML)
        self.assertIn("fetchData();", HTML)
```

- [ ] **Step 2: Run the page test and verify RED**

Run:

```bash
python3 -m unittest script/log/dashboards/test_market_curve_page.py -v
```

Expected: this test fails because the current page still performs `fetchData(true)` and adds `meta=1` before fetching full data.

## Task 4: Remove the serial meta request

**Files:**
- Modify: `script/log/dashboards/market-curve/index.html:199-242,455`

- [ ] **Step 1: Make fetchData always request full data**

Remove the `metaOnly` argument, the `meta` query parameter, and the second fetch branch. Keep the existing control disabling and error recovery:

```javascript
async function fetchData() {
  statusValue.textContent = "查询中...";
  quoteSelect.disabled = true;
  daysInput.disabled = true;
  intervalSelect.disabled = true;
  refreshButton.disabled = true;
  const api = new URL(API_URL, location.origin);
  api.searchParams.set("network", state.network);
  api.searchParams.set("quote", state.quote);
  api.searchParams.set("days", state.days);
  api.searchParams.set("interval", state.interval);
  try {
    const response = await fetch(api.toString(), { cache: "no-store" });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "读取失败");
    state.payload = payload;
    render(payload);
    statusValue.textContent = "已更新";
  } catch (error) {
    statusValue.textContent = error.message || "读取失败";
  } finally {
    quoteSelect.disabled = false;
    daysInput.disabled = false;
    intervalSelect.disabled = false;
    refreshButton.disabled = false;
  }
}
```

- [ ] **Step 2: Simplify render and initial load**

Make `render(payload)` always populate quote options, set `state.series` and `state.quote` from the full response, sync the URL, and call `renderCombinedChart`. Remove the meta-only branch and replace the final `fetchData(true)` with `fetchData()`.

- [ ] **Step 3: Run page, full Python, and JS syntax checks**

Run:

```bash
python3 -m unittest script/log/dashboards/test_market_curve_page.py -v
python3 -m unittest discover -s script/log/dashboards -p 'test_*.py' -v
node --check <(sed -n '/<script>/,/<\/script>/p' script/log/dashboards/market-curve/index.html | sed '1d;$d')
```

Expected: the no-meta contract and all existing tests pass.

## Task 5: Verify performance and end-to-end behavior

**Files:**
- Verify: `script/log/dashboards/price_curve_runtime.py`
- Verify: `script/log/dashboards/market-curve/index.html`

- [ ] **Step 1: Verify all quote modes through the real SQLite database**

Run:

```bash
python3 - <<'PY'
import sqlite3
import sys
sys.path.insert(0, "script/log/dashboards")
from price_curve_runtime import query_price_curve_data

conn = sqlite3.connect("script/log/db/thinkium70001_public/events.db")
conn.row_factory = sqlite3.Row
for quote in ("TUSDT", "LOVE20", "TKM20"):
    data = query_price_curve_data(conn, token_symbols=[], quote_symbol=quote, interval="1d", days=30)
    print(quote, len(data["series"]), data["selected_tokens"])
    assert data["quote"]["symbol"] == quote
conn.close()
PY
```

Expected: all three quote modes return series without raising and non-LOVE20 tokens use the bridge path.

- [ ] **Step 2: Verify the page makes one initial API request**

Start a dashboard server on an unused local port, open `/dashboards/market-curve/`, and inspect its request log. The initial load must contain one `GET /api/dashboards/market-curve?...` without `meta=1`, followed by no second request caused solely by initialization.

- [ ] **Step 3: Verify visible chart behavior**

Confirm TUSDT and LOVE20 quote modes show the indirect prices, metric switching does not issue a request, changing quote/days/interval issues one request after the control is enabled, and legend toggling only redraws the selected series.

- [ ] **Step 4: Verify final state and commit**

Run:

```bash
git diff --check
git status --short --untracked-files=all
git diff --stat
git add script/log/dashboards/price_curve_runtime.py \
  script/log/dashboards/test_price_curve_runtime.py \
  script/log/dashboards/market-curve/index.html \
  script/log/dashboards/test_market_curve_page.py
git commit -m "feat: 使用 LOVE20 桥接计算市价"
```

Expected: only the four implementation files are committed; design and plan documents remain separate documentation commits.
