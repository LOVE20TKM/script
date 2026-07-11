# Market Curve Combined Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 market-curve 改为默认展示全部非计价代币的共享组合曲线，并支持图例显隐与市值/币价切换。

**Architecture:** 服务端仅在未指定 `tokens` 时把默认系列扩大为全部非计价代币，保留显式筛选兼容性。前端继续使用现有单页和原生 SVG，不引入依赖；数据请求返回完整 series，浏览器本地维护可见代币和当前指标，并在同一坐标系中绘制多条折线。

**Tech Stack:** Python `unittest`、SQLite 查询运行时、原生 HTML/CSS/JavaScript、SVG。

---

## File Map

- Modify: `script/log/dashboards/price_curve_runtime.py` — 调整无 `tokens` 参数时的默认系列选择。
- Modify: `script/log/dashboards/test_price_curve_runtime.py` — 覆盖全部非计价代币默认选择。
- Modify: `script/log/dashboards/market-curve/index.html` — 移除代币下拉框，实现组合 SVG、图例显隐和指标切换。
- Create: `script/log/dashboards/test_market_curve_page.py` — 用原生 `unittest` 检查页面结构契约，避免代币下拉列表和双面板渲染回归。

## Task 1: Lock the server-side default selection

**Files:**
- Modify: `script/log/dashboards/test_price_curve_runtime.py`
- Modify: `script/log/dashboards/price_curve_runtime.py:59,203`

- [ ] **Step 1: Write the failing test**

Add this test to `PriceCurveRuntimeTest`:

```python
    def test_default_selection_returns_all_non_quote_tokens(self) -> None:
        tokens = [
            {"symbol": "TKM20", "address": "0x1", "decimals": 18},
            {"symbol": "TUSDT", "address": "0x2", "decimals": 18},
            {"symbol": "LOVE20", "address": "0x3", "decimals": 18},
            {"symbol": "LIFE20", "address": "0x4", "decimals": 18},
        ]

        selected = price_curve_runtime.default_selected_tokens(tokens, tokens[1])

        self.assertEqual(
            [token["symbol"] for token in selected],
            ["TKM20", "LOVE20", "LIFE20"],
        )
```

- [ ] **Step 2: Run the focused test and verify it fails for the missing behavior**

Run:

```bash
python3 -m unittest script/log/dashboards/test_price_curve_runtime.py -v
```

Expected: the new test fails because the current helper still requires a database connection and only returns the old limited default selection.

- [ ] **Step 3: Implement the smallest server change**

Change the data query call from `default_selected_tokens(conn, tokens, quote)` to `default_selected_tokens(tokens, quote)`, and replace the helper with:

```python
def default_selected_tokens(tokens: list[dict], quote: dict) -> list[dict]:
    quote_symbol = quote["symbol"].upper()
    return [token for token in tokens if token["symbol"].upper() != quote_symbol]
```

Explicit `token_symbols` filtering remains unchanged, so callers that send `tokens=...` keep their current behavior.

- [ ] **Step 4: Run the focused test, then the existing dashboard tests**

Run:

```bash
python3 -m unittest script/log/dashboards/test_price_curve_runtime.py -v
python3 -m unittest discover -s script/log/dashboards -p 'test_*.py' -v
```

Expected: the focused test and all existing tests pass.

## Task 2: Add a page-level regression contract

**Files:**
- Create: `script/log/dashboards/test_market_curve_page.py`

- [ ] **Step 1: Write the failing page contract tests**

Create a test that reads the actual page and asserts the requested visible structure:

```python
from pathlib import Path
import unittest


PAGE = Path(__file__).parent / "market-curve" / "index.html"


class MarketCurvePageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.html = PAGE.read_text(encoding="utf-8")

    def test_page_uses_combined_metric_controls_without_token_dropdown(self) -> None:
        self.assertNotIn('id="tokenSelect"', self.html)
        self.assertIn('id="metricToggle"', self.html)
        self.assertIn('data-metric="market_cap"', self.html)
        self.assertIn('data-metric="close"', self.html)

    def test_page_has_local_visibility_state_and_combined_series_renderer(self) -> None:
        self.assertIn("visibleTokens", self.html)
        self.assertIn("renderCombinedChart", self.html)
        self.assertIn("series.map", self.html)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the page contract and verify it fails before the UI change**

Run:

```bash
python3 -m unittest script/log/dashboards/test_market_curve_page.py -v
```

Expected: both tests fail because the current page contains `tokenSelect`, has no metric toggle, and renders one panel per series without `visibleTokens` or `renderCombinedChart`.

## Task 3: Replace the per-token UI with the combined chart

**Files:**
- Modify: `script/log/dashboards/market-curve/index.html`

- [ ] **Step 1: Replace the control markup and chart styling**

Remove the `tokenSelect` field. Keep quote, days, interval, and refresh controls. Add a segmented metric control:

```html
<div class="field metric-field">
  <span class="field-label">指标</span>
  <div id="metricToggle" class="segmented" role="group" aria-label="图表指标">
    <button type="button" class="metric-button active" data-metric="market_cap" aria-pressed="true">市值</button>
    <button type="button" class="metric-button" data-metric="close" aria-pressed="false">币价</button>
  </div>
</div>
```

Add compact legend and shared-chart styles for `.chart-panel`, `.legend`, `.legend-button`, `.legend-swatch`, `.legend-button.is-hidden`, `.legend-button.is-disabled`, `.segmented`, and `.metric-button`. Use fixed SVG dimensions via `viewBox` and `width: 100%` so chart layout does not shift.

- [ ] **Step 2: Add state and load all default series**

Replace the token selection state with:

```javascript
const state = {
  network: params.get("network") || "thinkium70001_public",
  quote: params.get("quote") || "TUSDT",
  days: params.get("days") || "30",
  interval: params.get("interval") || "1d",
  metric: "market_cap",
  visibleTokens: new Set(),
  payload: null,
};
```

After a successful `meta=1` response, populate quote options and immediately call `fetchData()` with no `tokens` query parameter. After a normal response, initialize `visibleTokens` from every returned series with candles, then call `renderSeries`. URL sync writes only `network`, `quote`, `days`, and `interval`.

- [ ] **Step 3: Render one legend and one shared SVG**

Replace `renderSeries` and the single-series `lineChartSvg` implementation with these responsibilities:

```javascript
function renderSeries(series, quote) {
  const drawable = series.filter((item) => item.candles?.length);
  const metric = METRICS[state.metric];
  const latest = drawable.map((item) => ({
    symbol: item.token.symbol,
    value: item.candles.at(-1)?.[state.metric],
  }));
  const latestText = latest.map((item) => `${item.symbol}: ${formatMetric(item.value)} ${quote.symbol}`).join(" · ");
  seriesRoot.innerHTML = `<section class="panel chart-panel">
    <div class="chart-head">
      <div>
        <div class="title">${metric.title}曲线</div>
        <div class="subtle">单位：${quote.symbol}</div>
      </div>
      <div class="subtle">${latestText || "暂无可展示数据"}</div>
    </div>
    <div class="legend">${renderLegend(series)}</div>
    ${renderCombinedChart(series, state.metric, metric.title, quote.symbol)}
  </section>`;
  wireLegend(series);
  wireChartGuides();
}
```

`renderCombinedChart` must build the union of candle timestamps across drawable visible series, calculate min/max from the selected metric across visible series, use a stable six-color palette, draw one `<polyline data-token="${escapeHtml(item.token.symbol)}">` per visible drawable series, include selected data points in the existing pointer guide payload, and return an empty state when no series is visible.

`renderLegend` creates a button for each returned series, uses `disabled` and the server `message` for non-drawable series, and marks hidden drawable series with `is-hidden` plus `aria-pressed="false"`. `wireLegend` toggles the symbol in `state.visibleTokens` and re-renders without fetching.

- [ ] **Step 4: Wire metric, quote, range, and interval controls**

Metric buttons update `state.metric`, their active/pressed state, and redraw. Quote, days, and interval trigger a new fetch; after a new response all drawable series become visible again. The refresh handler must not require a selected token, and `fetchData` must not add `tokens` to the API URL. Remove the old `tokenSelect` lookup, `renderSelects`, and single-token validation.

- [ ] **Step 5: Run both regression suites**

Run:

```bash
python3 -m unittest script/log/dashboards/test_market_curve_page.py -v
python3 -m unittest discover -s script/log/dashboards -p 'test_*.py' -v
```

Expected: page contract tests pass and all Python tests pass.

## Task 4: Verify the live dashboard

**Files:**
- Verify: `script/log/dashboards/market-curve/index.html`
- Verify: `script/log/dashboards/dashboard_server.py`

- [ ] **Step 1: Start the dashboard server**

Run from `script/log/dashboards`:

```bash
python3 dashboard_server.py --host 127.0.0.1 --port 8000 --network thinkium70001_public
```

Use another free port if `8000` is occupied.

- [ ] **Step 2: Check the API default response**

Run:

```bash
curl -s 'http://127.0.0.1:8000/api/dashboards/market-curve?network=thinkium70001_public&quote=TUSDT&days=30&interval=1d' > /tmp/market-curve.json
python3 - <<'PY'
import json
payload = json.load(open('/tmp/market-curve.json'))
series = payload["data"]["series"]
assert len(series) == len([t for t in payload["data"]["tokens"] if t["symbol"] != payload["data"]["quote"]["symbol"]])
print("default series:", len(series))
PY
```

Expected: the series count equals all known non-quote tokens.

- [ ] **Step 3: Verify browser interactions at desktop and narrow widths**

Open `/dashboards/market-curve/` and verify:

```text
no token dropdown is present
all returned drawable tokens are visible in one shared SVG by default
clicking a legend item hides only its matching polyline and clicking again restores it
市值/币价 changes the title, scale labels, tooltip values, and latest values without an API request
changing quote, days, or interval reloads data and resets drawable tokens visible
desktop and narrow layouts have no control or legend overflow
```

- [ ] **Step 4: Stop the server and inspect the final diff**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Expected: only the two runtime/test files and `market-curve/index.html` are changed by implementation; the already committed design and plan docs are the only documentation changes.

## Task 5: Commit the implementation

- [ ] **Step 1: Commit the verified implementation**

Run:

```bash
git add script/log/dashboards/price_curve_runtime.py \
  script/log/dashboards/test_price_curve_runtime.py \
  script/log/dashboards/test_market_curve_page.py \
  script/log/dashboards/market-curve/index.html
git commit -m "feat: 合并市值曲线看板"
```

Expected: one implementation commit containing only the files listed above.
