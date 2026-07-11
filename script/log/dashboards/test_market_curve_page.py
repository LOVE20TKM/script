from pathlib import Path
import re
import unittest


HTML = (Path(__file__).parent / "market-curve" / "index.html").read_text(encoding="utf-8")


class MarketCurvePageTest(unittest.TestCase):
    def test_combined_chart_controls_and_render_contract_exist(self) -> None:
        self.assertNotIn('id="tokenSelect"', HTML)
        self.assertIn('id="metricToggle"', HTML)
        self.assertIn('data-metric="market_cap"', HTML)
        self.assertIn('data-metric="close"', HTML)
        self.assertIn("visibleTokens", HTML)
        self.assertIn("renderCombinedChart", HTML)

    def test_initial_load_and_url_do_not_select_tokens(self) -> None:
        self.assertIn("fetchData();", HTML)
        self.assertNotIn('params.has("tokens")', HTML)
        self.assertNotIn('next.set("tokens"', HTML)
        self.assertNotIn('api.searchParams.set("tokens"', HTML)

    def test_metric_rendering_keeps_guides_and_zero_values(self) -> None:
        self.assertIn("wireChartGuides", HTML)
        self.assertIn('data-token', HTML)
        self.assertIn("market_cap", HTML)
        self.assertIn("close", HTML)
        self.assertRegex(HTML, re.compile(r"Number\.isFinite\(value\) \|\| value < 0"))

    def test_empty_state_distinguishes_drawable_series_from_hidden_series(self) -> None:
        self.assertIn("const drawableItems = items.filter(isDrawable);", HTML)
        self.assertIn('drawableItems.length ? "请选择至少一个图例" : "暂无可展示数据"', HTML)


if __name__ == "__main__":
    unittest.main()
