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

    def test_tokens_use_unique_address_keys_and_symbol_labels(self) -> None:
        self.assertRegex(
            HTML,
            re.compile(
                r'function tokenKey\(item\) \{\s+'
                r'return String\(item\?\.token\?\.address \|\| item\?\.token\?\.symbol \|\| ""\);\s+'
                r'\}'
            ),
        )
        self.assertIn('const symbol = String(item?.token?.symbol || item?.token?.address || "");', HTML)
        self.assertIn("guidePoints.push({ token: key", HTML)

    def test_controls_fetch_on_change_without_duplicate_while_loading(self) -> None:
        for control, assignment in (
            ("quoteSelect", "state.quote = quoteSelect.value;"),
            ("daysInput", 'state.days = daysInput.value || "30";'),
            ("intervalSelect", "state.interval = intervalSelect.value;"),
        ):
            self.assertRegex(
                HTML,
                re.compile(
                    rf'{control}\.addEventListener\("change", \(\) => \{{\s*'
                    rf'{re.escape(assignment)}\s*'
                    r'if \(!refreshButton\.disabled\) fetchData\(\);\s*\}\);'
                ),
            )
        self.assertIn('refreshButton.addEventListener("click"', HTML)
        self.assertEqual(HTML.count("if (!refreshButton.disabled) fetchData();"), 3)

    def test_guide_uses_two_dimensional_nearest_point_and_polyline_token(self) -> None:
        self.assertRegex(
            HTML,
            re.compile(
                r'Math\.hypot\(item\.x - cursor\.x, item\.y - cursor\.y\)'
                r' < Math\.hypot\(best\.x - cursor\.x, best\.y - cursor\.y\)'
            ),
        )
        self.assertRegex(
            HTML,
            re.compile(r'<polyline[^>]*data-token="\$\{escapeHtml\(key\)\}"'),
        )


if __name__ == "__main__":
    unittest.main()
