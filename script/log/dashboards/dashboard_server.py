#!/usr/bin/env python3
import argparse
import json
import sqlite3
import threading
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from timeline_runtime import TIMELINE_INDEX_DEFINITIONS, load_contract_map, now_iso, query_activity_rows_by_account
from tusdt_flow_runtime import (
    parse_tusdt_flow_mode,
    parse_tusdt_flow_recent_rounds,
    parse_tusdt_flow_selected_round,
    parse_tusdt_flow_sort_by,
    query_tusdt_flow_data,
)


DASHBOARDS_DIR = Path(__file__).resolve().parent
LOG_DIR = DASHBOARDS_DIR.parent
MINT_DIR = DASHBOARDS_DIR / "mint-addresses-by-log-round"
DEFAULT_NETWORK = "thinkium70001_public"
DEFAULT_TIMELINE_LIMIT = 100
MAX_TIMELINE_LIMIT = 500
MINT_SOURCE_QUERY_SQL = (MINT_DIR / "source_query.sql").read_text(encoding="utf-8")
MINT_SOURCE_SUMMARY_SQL = (MINT_DIR / "source_summary.sql").read_text(encoding="utf-8")
_ENSURED_DB_MTIMES: dict[str, float] = {}
_ENSURE_LOCK = threading.Lock()


def iso_from_timestamp(value: float) -> str:
    return datetime.fromtimestamp(value, timezone.utc).replace(microsecond=0).isoformat()


def resolve_db_path(network: str | None = None, *, db_path: str | None = None) -> Path:
    if db_path:
        path = Path(db_path).expanduser().resolve()
    else:
        chosen_network = network or DEFAULT_NETWORK
        path = (LOG_DIR / "db" / chosen_network / "events.db").resolve()
    if not path.exists():
        raise FileNotFoundError(f"events.db not found: {path}")
    return path


def ensure_events_db_indexes(db_path: Path) -> None:
    resolved = db_path.expanduser().resolve()
    db_mtime = resolved.stat().st_mtime

    with _ENSURE_LOCK:
        if _ENSURED_DB_MTIMES.get(str(resolved)) == db_mtime:
            return

        conn = sqlite3.connect(resolved, timeout=60.0)
        try:
            for _, sql in TIMELINE_INDEX_DEFINITIONS:
                conn.execute(sql)
            conn.commit()
        finally:
            conn.close()

        _ENSURED_DB_MTIMES[str(resolved)] = db_mtime


def mint_payload(network: str, db_path: Path) -> dict:
    db_mtime = db_path.stat().st_mtime

    conn = sqlite3.connect(db_path, timeout=60.0)
    conn.row_factory = sqlite3.Row
    try:
        rows = [dict(row) for row in conn.execute(MINT_SOURCE_QUERY_SQL).fetchall()]
        summary_row = conn.execute(MINT_SOURCE_SUMMARY_SQL).fetchone()
        history_summary = dict(summary_row) if summary_row else {
            "history_gov_unique_address_count": 0,
            "history_action_unique_address_count": 0,
            "history_total_unique_address_count": 0,
        }
    finally:
        conn.close()

    payload = {
        "network": network,
        "source_db": str(db_path),
        "db_mtime": iso_from_timestamp(db_mtime),
        "updated_at": now_iso(),
        "data": {
            "rows": rows,
            "history_summary": history_summary,
        },
    }
    return payload


def timeline_payload(network: str, db_path: Path, address: str | None, *, limit: int, cursor: dict | None) -> dict:
    normalized_address = (address or "").strip().lower()
    db_mtime = db_path.stat().st_mtime

    conn = sqlite3.connect(db_path, timeout=60.0)
    conn.row_factory = sqlite3.Row
    try:
        result = {
            "rows": [],
            "has_more": False,
            "next_cursor": None,
            "page_size": limit,
        }
        if normalized_address:
            contract_map = load_contract_map(conn)
            result = query_activity_rows_by_account(conn, contract_map, normalized_address, limit=limit, cursor=cursor)
    finally:
        conn.close()

    payload = {
        "network": network,
        "source_db": str(db_path),
        "db_mtime": iso_from_timestamp(db_mtime),
        "updated_at": now_iso(),
        "data": {
            "address": normalized_address,
            "rows": result["rows"],
            "page_size": result["page_size"],
            "has_more": result["has_more"],
            "next_cursor": result["next_cursor"],
        },
    }
    return payload


def tusdt_flow_payload(
    network: str,
    db_path: Path,
    *,
    recent_rounds: int,
    mode: str,
    selected_round: int | None,
    sort_by: str,
) -> dict:
    db_mtime = db_path.stat().st_mtime

    conn = sqlite3.connect(db_path, timeout=60.0)
    conn.row_factory = sqlite3.Row
    try:
        data = query_tusdt_flow_data(
            conn,
            recent_rounds=recent_rounds,
            mode=mode,
            selected_round=selected_round,
            sort_by=sort_by,
        )
    finally:
        conn.close()

    payload = {
        "network": network,
        "source_db": str(db_path),
        "db_mtime": iso_from_timestamp(db_mtime),
        "updated_at": now_iso(),
        "data": data,
    }
    return payload


class DashboardRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, directory: str | None = None, **kwargs):
        super().__init__(*args, directory=directory or str(LOG_DIR), **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/"):
            self.handle_api(parsed)
            return
        super().do_GET()

    def handle_api(self, parsed) -> None:
        try:
            params = parse_qs(parsed.query)
            network = params.get("network", [self.server.default_network])[0]  # type: ignore[attr-defined]
            db_path = resolve_db_path(network)
            ensure_events_db_indexes(db_path)

            if parsed.path == "/api/dashboards/mint-addresses-by-log-round":
                payload = mint_payload(network, db_path)
                self.respond_json(200, payload)
                return

            if parsed.path == "/api/dashboards/wallet-activity-timeline":
                address = params.get("address", [""])[0].strip().lower()
                if address and not is_address(address):
                    self.respond_json(400, {"error": "invalid address"})
                    return
                limit = parse_limit(params.get("limit", [""])[0])
                cursor = parse_timeline_cursor(params)
                payload = timeline_payload(network, db_path, address, limit=limit, cursor=cursor)
                self.respond_json(200, payload)
                return

            if parsed.path == "/api/dashboards/tusdt-flow":
                recent_rounds = parse_tusdt_flow_recent_rounds(params.get("recent_rounds", [""])[0])
                mode = parse_tusdt_flow_mode(params.get("mode", [""])[0])
                selected_round = parse_tusdt_flow_selected_round(params.get("selected_round", [""])[0])
                sort_by = parse_tusdt_flow_sort_by(params.get("sort_by", [""])[0])
                payload = tusdt_flow_payload(
                    network,
                    db_path,
                    recent_rounds=recent_rounds,
                    mode=mode,
                    selected_round=selected_round,
                    sort_by=sort_by,
                )
                self.respond_json(200, payload)
                return

            self.respond_json(404, {"error": "not found"})
        except FileNotFoundError as error:
            self.respond_json(404, {"error": str(error)})
        except ValueError as error:
            self.respond_json(400, {"error": str(error)})
        except Exception as error:  # noqa: BLE001
            self.respond_json(500, {"error": str(error)})

    def respond_json(self, status_code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def is_address(value: str) -> bool:
    return len(value) == 42 and value.startswith("0x") and all(ch in "0123456789abcdef" for ch in value[2:])


def parse_limit(value: str) -> int:
    if not value:
        return DEFAULT_TIMELINE_LIMIT
    parsed = int(value)
    if parsed <= 0:
        raise ValueError("invalid limit")
    return min(parsed, MAX_TIMELINE_LIMIT)


def parse_timeline_cursor(params: dict[str, list[str]]) -> dict | None:
    block_value = params.get("before_block_number", [""])[0]
    tx_index_value = params.get("before_tx_index", [""])[0]
    tx_hash_value = params.get("before_tx_hash", [""])[0].strip().lower()
    provided = [bool(block_value), bool(tx_index_value), bool(tx_hash_value)]
    if not any(provided):
        return None
    if not all(provided):
        raise ValueError("invalid timeline cursor")
    if not tx_hash_value.startswith("0x"):
        raise ValueError("invalid timeline cursor")
    return {
        "block_number": int(block_value),
        "tx_index": int(tx_index_value),
        "tx_hash": tx_hash_value,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve LOVE20 dashboards and dynamic dashboard APIs.")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind")
    parser.add_argument("--network", default=DEFAULT_NETWORK, help="Default network label")
    parser.add_argument("--db-path", help="Explicit events.db path for ensure-indexes mode")
    parser.add_argument(
        "--ensure-indexes-only",
        action="store_true",
        help="Only ensure dashboard indexes, then exit",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.ensure_indexes_only:
        db_path = resolve_db_path(args.network, db_path=args.db_path)
        ensure_events_db_indexes(db_path)
        print(f"Dashboard indexes ready: {db_path}")
        return

    ensure_events_db_indexes(resolve_db_path(args.network))

    httpd = ThreadingHTTPServer((args.host, args.port), lambda *handler_args, **handler_kwargs: DashboardRequestHandler(*handler_args, directory=str(LOG_DIR), **handler_kwargs))
    httpd.default_network = args.network  # type: ignore[attr-defined]
    print(f"Serving dashboards at http://{args.host}:{args.port}/dashboards/")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
