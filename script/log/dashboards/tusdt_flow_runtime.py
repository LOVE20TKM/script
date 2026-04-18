#!/usr/bin/env python3
import sqlite3
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
TUSDT_FLOW_DIR = BASE_DIR / "tusdt-flow"
SUMMARY_SQL = (TUSDT_FLOW_DIR / "summary_query.sql").read_text(encoding="utf-8")
DETAIL_SQL = (TUSDT_FLOW_DIR / "detail_query.sql").read_text(encoding="utf-8")
DEFAULT_TUSDT_FLOW_RECENT_ROUNDS = 15
MAX_TUSDT_FLOW_RECENT_ROUNDS = 240
TUSDT_FLOW_MODES = {"round", "cumulative"}
TUSDT_FLOW_SORT_OPTIONS = {"net_inflow", "crosschain_net"}
SUMMARY_NUMERIC_FIELDS = (
    "chain_inflow_tusdt",
    "chain_outflow_tusdt",
    "net_inflow_tusdt",
    "swap_in_tusdt",
    "swap_out_tusdt",
    "net_swap_tusdt_flow",
    "lp_in_tusdt",
    "lp_out_tusdt",
    "net_lp_tusdt_flow",
    "love20_swap_tusdt_flow",
    "life20_swap_tusdt_flow",
    "love20_lp_tusdt_flow",
    "life20_lp_tusdt_flow",
    "tusdt_crosschain_in_tusdt",
    "tusdt_crosschain_out_tusdt",
    "tusdt_crosschain_net_tusdt_flow",
)


def parse_tusdt_flow_recent_rounds(value: str) -> int:
    if not value:
        return DEFAULT_TUSDT_FLOW_RECENT_ROUNDS
    parsed = int(value)
    if parsed <= 0:
        raise ValueError("invalid recent_rounds")
    return min(parsed, MAX_TUSDT_FLOW_RECENT_ROUNDS)


def parse_tusdt_flow_mode(value: str) -> str:
    if not value:
        return "round"
    mode = value.strip().lower()
    if mode not in TUSDT_FLOW_MODES:
        raise ValueError("invalid mode")
    return mode


def parse_tusdt_flow_sort_by(value: str) -> str:
    if not value:
        return "net_inflow"
    sort_by = value.strip().lower()
    if sort_by not in TUSDT_FLOW_SORT_OPTIONS:
        raise ValueError("invalid sort_by")
    return sort_by


def parse_tusdt_flow_selected_round(value: str) -> int | None:
    if not value:
        return None
    parsed = int(value)
    if parsed < 0:
        raise ValueError("invalid selected_round")
    return parsed


def to_float(value) -> float:
    if value is None:
        return 0.0
    return float(value)


def round_six(value: float) -> float:
    return round(float(value), 6)


def query_tusdt_flow_data(
    conn: sqlite3.Connection,
    *,
    recent_rounds: int,
    mode: str,
    selected_round: int | None,
    sort_by: str,
) -> dict:
    raw_summary_rows = [dict(row) for row in conn.execute(SUMMARY_SQL, (recent_rounds,)).fetchall()]
    summary_rows = build_display_summary_rows(raw_summary_rows, mode)
    raw_rounds = [int(row["log_round"]) for row in raw_summary_rows]
    available_rounds = [int(row["log_round"]) for row in summary_rows]
    resolved_selected_round = resolve_selected_round(available_rounds, selected_round)
    min_round = raw_rounds[0] if raw_rounds else None
    max_round = raw_rounds[-1] if raw_rounds else None
    detail_from_round, detail_to_round = resolve_detail_bounds(
        summary_rows,
        mode,
        resolved_selected_round,
        min_round=min_round,
        max_round=max_round,
    )
    detail_rows = []
    if detail_from_round is not None and detail_to_round is not None:
        detail_rows = [dict(row) for row in conn.execute(DETAIL_SQL, (detail_from_round, detail_to_round)).fetchall()]
        detail_rows = sort_detail_rows(detail_rows, sort_by)

    selected_summary = None
    if resolved_selected_round is not None:
        selected_summary = next((row for row in summary_rows if int(row["log_round"]) == resolved_selected_round), None)

    window_totals = build_window_totals(raw_summary_rows)

    return {
        "mode": mode,
        "mode_label": "按轮次" if mode == "round" else "累计",
        "sort_by": sort_by,
        "sort_label": "链内净流量：流出 → 流入" if sort_by == "net_inflow" else "跨链净流量：流出 → 流入",
        "recent_rounds": recent_rounds,
        "window": {
            "min_round": min_round,
            "max_round": max_round,
            "round_count": len(summary_rows),
            "detail_from_round": detail_from_round,
            "detail_to_round": detail_to_round,
            "detail_scope_label": build_detail_scope_label(mode, detail_from_round, detail_to_round),
        },
        "selected_round": resolved_selected_round,
        "selected_summary": selected_summary,
        "summary": {
            "rows": summary_rows,
            "window_totals": window_totals,
        },
        "detail": {
            "rows": detail_rows,
            "row_count": len(detail_rows),
        },
    }


def build_display_summary_rows(raw_rows: list[dict], mode: str) -> list[dict]:
    if mode == "round":
        return [normalize_summary_row(row) for row in raw_rows]

    return build_cumulative_summary_rows(raw_rows)


def normalize_summary_row(row: dict) -> dict:
    normalized = {
        "log_round": int(row["log_round"]),
        "log_round_label": str(row.get("log_round_label") or row["log_round"]),
    }
    for field in SUMMARY_NUMERIC_FIELDS:
        normalized[field] = round_six(to_float(row.get(field)))
    return normalized


def build_window_totals(raw_rows: list[dict]) -> dict:
    totals = {field: 0.0 for field in SUMMARY_NUMERIC_FIELDS}
    for row in raw_rows:
        for field in SUMMARY_NUMERIC_FIELDS:
            totals[field] += to_float(row.get(field))
    return {field: round_six(value) for field, value in totals.items()}


def build_cumulative_summary_rows(raw_rows: list[dict]) -> list[dict]:
    if not raw_rows:
        return []

    min_round = int(raw_rows[0]["log_round"])
    max_round = int(raw_rows[-1]["log_round"])
    cumulative = {
        "log_round": max_round,
        "log_round_label": build_cumulative_round_label(min_round, max_round),
    }
    for field in SUMMARY_NUMERIC_FIELDS:
        cumulative[field] = round_six(sum(to_float(row.get(field)) for row in raw_rows))
    return [cumulative]


def build_cumulative_round_label(min_round: int, max_round: int) -> str:
    if min_round == max_round:
        return f"{max_round} 累计"
    return f"{min_round}-{max_round} 累计"


def resolve_selected_round(available_rounds: list[int], requested: int | None) -> int | None:
    if not available_rounds:
        return None
    if requested in available_rounds:
        return requested
    return available_rounds[-1]


def resolve_detail_bounds(
    summary_rows: list[dict],
    mode: str,
    selected_round: int | None,
    *,
    min_round: int | None,
    max_round: int | None,
) -> tuple[int | None, int | None]:
    if not summary_rows:
        return None, None
    if mode == "round":
        if selected_round is None:
            return None, None
        return selected_round, selected_round
    return min_round, max_round


def build_detail_scope_label(mode: str, detail_from_round: int | None, detail_to_round: int | None) -> str:
    if detail_from_round is None or detail_to_round is None:
        return "暂无可查看轮次"
    if mode == "round":
        return f"log_round {detail_to_round}"
    return f"log_round {detail_from_round} 至 {detail_to_round} 累计"


def sort_detail_rows(rows: list[dict], sort_by: str) -> list[dict]:
    numeric_field = "net_inflow_tusdt" if sort_by == "net_inflow" else "tusdt_crosschain_net_tusdt_flow"

    def sort_key(row: dict) -> tuple[float, str]:
        return (to_float(row.get(numeric_field)), row.get("address", ""))

    normalized: list[dict] = []
    for row in rows:
        normalized_row = {"address": row["address"]}
        for key, value in row.items():
            if key == "address":
                continue
            normalized_row[key] = round_six(to_float(value))
        normalized.append(normalized_row)
    return sorted(normalized, key=sort_key)
