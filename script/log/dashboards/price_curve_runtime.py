#!/usr/bin/env python3
import sqlite3
from datetime import datetime, timezone


DEFAULT_PRICE_CURVE_DAYS = 30
MAX_PRICE_CURVE_DAYS = 365
PRICE_CURVE_INTERVALS = {
    "1h": 3600,
    "4h": 14400,
    "1d": 86400,
}
BASE_TOKENS = {"TKM20", "TUSDT"}


def parse_interval(value: str) -> str:
    if not value:
        return "1d"
    interval = value.strip().lower()
    if interval not in PRICE_CURVE_INTERVALS:
        raise ValueError("invalid interval")
    return interval


def parse_days(value: str) -> int:
    if not value:
        return DEFAULT_PRICE_CURVE_DAYS
    parsed = int(value)
    if parsed <= 0:
        raise ValueError("invalid days")
    return min(parsed, MAX_PRICE_CURVE_DAYS)


def parse_token_symbols(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def query_price_curve_data(
    conn: sqlite3.Connection,
    *,
    token_symbols: list[str],
    quote_symbol: str,
    interval: str,
    days: int,
) -> dict:
    tokens = query_price_curve_tokens(conn)
    token_by_symbol = {token["symbol"].upper(): token for token in tokens}
    token_by_address = {token["address"].lower(): token for token in tokens}
    quote = token_by_symbol.get((quote_symbol or "TUSDT").upper())
    if not quote:
        raise ValueError("quote token not found")

    selected = []
    for symbol in token_symbols:
        token = token_by_symbol.get(symbol.upper()) or token_by_address.get(symbol.lower())
        if token:
            selected.append(token)
    if not selected:
        selected = default_selected_tokens(tokens, quote)

    latest_timestamp = conn.execute("SELECT max(timestamp) FROM blocks WHERE timestamp > 0").fetchone()[0]
    if not latest_timestamp:
        return {
            "tokens": tokens,
            "quote": quote,
            "selected_tokens": [token["symbol"] for token in selected],
            "series": [],
        }

    interval_seconds = PRICE_CURVE_INTERVALS[interval]
    from_timestamp = int(latest_timestamp) - days * 86400
    from_block, to_block = query_block_range(conn, from_timestamp, int(latest_timestamp))
    love20 = next((token for token in tokens if token["symbol"].upper() == "LOVE20"), None)
    quote_bridge_pair = None
    quote_bridge_candles = None
    if love20 and quote["symbol"].upper() != "LOVE20":
        quote_bridge_pair = find_pair(conn, love20["address"], quote["address"])
        if quote_bridge_pair:
            quote_bridge_candles = query_pair_candles(
                conn,
                quote_bridge_pair,
                love20,
                quote,
                from_block,
                to_block,
                interval_seconds,
            )

    series = [
        query_token_series(
            conn,
            token,
            quote,
            from_timestamp,
            int(latest_timestamp),
            from_block,
            to_block,
            interval_seconds,
            love20=love20,
            quote_bridge_pair=quote_bridge_pair,
            quote_bridge_candles=quote_bridge_candles,
        )
        for token in selected
    ]

    return {
        "tokens": tokens,
        "quote": quote,
        "selected_tokens": [token["symbol"] for token in selected],
        "interval": interval,
        "days": days,
        "from_timestamp": from_timestamp,
        "to_timestamp": int(latest_timestamp),
        "from_time": iso_from_timestamp(from_timestamp),
        "to_time": iso_from_timestamp(int(latest_timestamp)),
        "series": series,
    }


def query_price_curve_meta(conn: sqlite3.Connection, *, quote_symbol: str, days: int, interval: str) -> dict:
    tokens = query_price_curve_tokens(conn)
    token_by_symbol = {token["symbol"].upper(): token for token in tokens}
    quote = token_by_symbol.get((quote_symbol or "TUSDT").upper())
    if not quote:
        raise ValueError("quote token not found")

    return {
        "tokens": tokens,
        "quote": quote,
        "selected_tokens": [],
        "interval": interval,
        "days": days,
        "series": [],
    }


def query_price_curve_tokens(conn: sqlite3.Connection) -> list[dict]:
    base_rows = conn.execute(
        """
        SELECT contract_name AS symbol, address
        FROM v_contract
        WHERE contract_name IN ('TKM20', 'TUSDT')
        """
    ).fetchall()
    base_by_symbol = {row["symbol"]: row["address"] for row in base_rows}

    launched_rows = conn.execute(
        """
        SELECT DISTINCT lower(json_extract(decoded_data, '$.tokenAddress')) AS address
        FROM events
        WHERE contract_name = 'launch'
          AND event_name = 'LaunchEnd'
        """
    ).fetchall()
    launched = sorted({row["address"] for row in launched_rows if row["address"]})

    launched_symbols = {}
    if launched:
        rows = conn.execute(
            """
            SELECT lower(address) AS address, contract_name AS symbol
            FROM v_contract
            WHERE lower(address) IN ({placeholders})
            """.format(placeholders=",".join("?" for _ in launched)),
            tuple(launched),
        ).fetchall()
        launched_symbols = {row["address"]: row["symbol"] for row in rows}
        rows = conn.execute(
            """
            SELECT lower(address) AS address, contract_name AS symbol, COUNT(*) AS event_count
            FROM events
            WHERE lower(address) IN ({placeholders})
              AND contract_name IS NOT NULL
              AND contract_name != ''
              AND contract_name NOT LIKE '0x%'
            GROUP BY lower(address), contract_name
            ORDER BY event_count DESC
            """.format(placeholders=",".join("?" for _ in launched)),
            tuple(launched),
        ).fetchall()
        for row in rows:
            launched_symbols.setdefault(row["address"], row["symbol"])

    seen = set()
    tokens = []
    for symbol in ("TKM20", "TUSDT"):
        address = base_by_symbol.get(symbol)
        if address and address.lower() not in seen:
            seen.add(address.lower())
            tokens.append({"symbol": symbol, "address": address, "decimals": 18})

    launched_tokens = [(launched_symbols.get(address) or address, address) for address in launched]
    for symbol, address in sorted(launched_tokens, key=lambda item: (item[0].startswith("0x"), item[0].upper())):
        if not address or address.lower() in seen:
            continue
        seen.add(address.lower())
        tokens.append({"symbol": symbol, "address": address, "decimals": 18})
    return tokens


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
        candles.append(
            {
                "time": timestamp,
                "time_label": iso_from_timestamp(timestamp),
                "close_block": max(target_current["close_block"], bridge_current["close_block"]),
                "open": price,
                "high": price,
                "low": price,
                "close": price,
                "count": target_current.get("count", 1) + bridge_current.get("count", 1),
            }
        )
    return candles


def query_token_series(
    conn: sqlite3.Connection,
    token: dict,
    quote: dict,
    from_timestamp: int,
    to_timestamp: int,
    from_block: int | None,
    to_block: int | None,
    interval_seconds: int,
    *,
    love20: dict | None = None,
    quote_bridge_pair: dict | None = None,
    quote_bridge_candles: list[dict] | None = None,
) -> dict:
    if token["symbol"].upper() == quote["symbol"].upper():
        return {"token": token, "pair": None, "candles": [], "message": "不能和计价代币相同"}

    if token["symbol"].upper() == "LOVE20":
        pair = quote_bridge_pair or find_pair(conn, token["address"], quote["address"])
        if not pair:
            return {"token": token, "pair": None, "candles": [], "message": "LOVE20/计价代币交易对不存在"}
        candles = quote_bridge_candles
        if candles is None:
            candles = query_pair_candles(conn, pair, token, quote, from_block, to_block, interval_seconds)
    elif quote["symbol"].upper() == "LOVE20":
        pair = find_pair(conn, token["address"], quote["address"])
        if not pair:
            return {"token": token, "pair": None, "candles": [], "message": "交易对不存在"}
        candles = query_pair_candles(conn, pair, token, quote, from_block, to_block, interval_seconds)
    else:
        if not love20:
            return {"token": token, "pair": None, "candles": [], "message": "LOVE20代币不存在"}
        if quote_bridge_pair is None:
            quote_bridge_pair = find_pair(conn, love20["address"], quote["address"])
        if not quote_bridge_pair:
            return {"token": token, "pair": None, "candles": [], "message": "LOVE20/计价代币交易对不存在"}
        if quote_bridge_candles is None:
            quote_bridge_candles = query_pair_candles(
                conn,
                quote_bridge_pair,
                love20,
                quote,
                from_block,
                to_block,
                interval_seconds,
            )
        pair = find_pair(conn, token["address"], love20["address"])
        if not pair:
            return {"token": token, "pair": None, "candles": [], "message": "交易对不存在"}
        target_candles = query_pair_candles(
            conn,
            pair,
            token,
            love20,
            from_block,
            to_block,
            interval_seconds,
        )
        candles = build_indirect_candles(target_candles, quote_bridge_candles)

    add_market_caps(conn, token, candles)
    return {"token": token, "pair": pair, "candles": candles}


def query_block_range(conn: sqlite3.Connection, from_timestamp: int, to_timestamp: int) -> tuple[int | None, int | None]:
    row = conn.execute(
        "SELECT min(block_number) AS from_block, max(block_number) AS to_block FROM blocks WHERE timestamp BETWEEN ? AND ?",
        (from_timestamp, to_timestamp),
    ).fetchone()
    return (row["from_block"], row["to_block"]) if row else (None, None)


def default_selected_tokens(tokens: list[dict], quote: dict) -> list[dict]:
    return [token for token in tokens if token["symbol"].upper() != quote["symbol"].upper()]


def find_pair(conn: sqlite3.Connection, token_address: str, quote_address: str) -> dict | None:
    row = conn.execute(
        """
        SELECT
          pc.pair,
          pc.token0,
          c0.contract_name AS token0_symbol,
          pc.token1,
          c1.contract_name AS token1_symbol,
          pair_contract.contract_name AS pair_contract_name,
          COALESCE(pair_contract.contract_name, pc.pair) AS pair_name
        FROM v_pair_created pc
        LEFT JOIN v_contract c0 ON lower(c0.address) = lower(pc.token0)
        LEFT JOIN v_contract c1 ON lower(c1.address) = lower(pc.token1)
        LEFT JOIN v_contract pair_contract ON lower(pair_contract.address) = lower(pc.pair)
        WHERE (
            lower(pc.token0) = lower(?) AND lower(pc.token1) = lower(?)
          ) OR (
            lower(pc.token0) = lower(?) AND lower(pc.token1) = lower(?)
          )
        ORDER BY pc.block_number DESC
        LIMIT 1
        """,
        (token_address, quote_address, quote_address, token_address),
    ).fetchone()
    if not row:
        return None
    return dict(row)


def query_sync_rows_by_contract(
    conn: sqlite3.Connection,
    pair_contract_name: str,
    from_block: int | None,
    to_block: int | None,
) -> list[sqlite3.Row]:
    if from_block is None or to_block is None:
        return []
    return conn.execute(
        """
        SELECT
          e.block_number,
          b.timestamp,
          CAST(json_extract(e.decoded_data, '$.reserve0') AS REAL) AS reserve0,
          CAST(json_extract(e.decoded_data, '$.reserve1') AS REAL) AS reserve1
        FROM events e
        JOIN blocks b ON b.block_number = e.block_number
        WHERE e.contract_name = ?
          AND e.event_name = 'Sync'
          AND e.block_number BETWEEN ? AND ?
        ORDER BY e.block_number, e.log_index
        """,
        (pair_contract_name, from_block, to_block),
    ).fetchall()


def query_sync_rows_by_address(
    conn: sqlite3.Connection,
    pair_address: str,
    from_block: int | None,
    to_block: int | None,
) -> list[sqlite3.Row]:
    if from_block is None or to_block is None:
        return []
    return conn.execute(
        """
        SELECT
          e.block_number,
          b.timestamp,
          CAST(json_extract(e.decoded_data, '$.reserve0') AS REAL) AS reserve0,
          CAST(json_extract(e.decoded_data, '$.reserve1') AS REAL) AS reserve1
        FROM events e
        JOIN blocks b ON b.block_number = e.block_number
        WHERE lower(e.address) = lower(?)
          AND e.event_name = 'Sync'
          AND e.block_number BETWEEN ? AND ?
        ORDER BY e.block_number, e.log_index
        """,
        (pair_address, from_block, to_block),
    ).fetchall()


def build_candles(rows: list[sqlite3.Row], pair: dict, token: dict, quote: dict, interval_seconds: int) -> list[dict]:
    buckets: dict[int, dict] = {}
    token0_is_target = pair["token0"].lower() == token["address"].lower()

    for row in rows:
        reserve0 = float(row["reserve0"] or 0)
        reserve1 = float(row["reserve1"] or 0)
        if reserve0 <= 0 or reserve1 <= 0:
            continue

        target_reserve = reserve0 if token0_is_target else reserve1
        quote_reserve = reserve1 if token0_is_target else reserve0
        if target_reserve <= 0 or quote_reserve <= 0:
            continue

        price = quote_reserve / target_reserve
        if price <= 0:
            continue

        timestamp = int(row["timestamp"])
        bucket = timestamp - (timestamp % interval_seconds)
        candle = buckets.get(bucket)
        if not candle:
            buckets[bucket] = {
                "time": bucket,
                "time_label": iso_from_timestamp(bucket),
                "close_block": int(row["block_number"]),
                "open": price,
                "high": price,
                "low": price,
                "close": price,
                "count": 1,
            }
            continue

        candle["high"] = max(candle["high"], price)
        candle["low"] = min(candle["low"], price)
        candle["close"] = price
        candle["close_block"] = int(row["block_number"])
        candle["count"] += 1

    return [buckets[key] for key in sorted(buckets)]


def add_market_caps(conn: sqlite3.Connection, token: dict, candles: list[dict]) -> None:
    if not candles:
        return

    max_block = max(candle["close_block"] for candle in candles)
    is_weth_supply = token["symbol"].upper() == "TKM20"
    supply_events = ("Deposit", "Withdrawal") if is_weth_supply else ("TokenMint", "TokenBurn")
    amount_field = "wad" if is_weth_supply else "amount"
    if token["symbol"].startswith("0x"):
        rows = conn.execute(
            f"""
            SELECT
              block_number,
              event_name,
              CAST(json_extract(decoded_data, '$.{amount_field}') AS REAL) AS amount
            FROM events
            WHERE lower(address) = lower(?)
              AND event_name IN (?, ?)
              AND block_number <= ?
            ORDER BY block_number, id
            """,
            (token["address"], *supply_events, max_block),
        ).fetchall()
    else:
        rows = conn.execute(
            f"""
            SELECT
              block_number,
              event_name,
              CAST(json_extract(decoded_data, '$.{amount_field}') AS REAL) AS amount
            FROM events
            WHERE contract_name = ?
              AND event_name IN (?, ?)
              AND block_number <= ?
            ORDER BY block_number, id
            """,
            (token["symbol"], *supply_events, max_block),
        ).fetchall()

    supply = 0.0
    row_index = 0
    for candle in candles:
        while row_index < len(rows) and int(rows[row_index]["block_number"]) <= candle["close_block"]:
            amount = float(rows[row_index]["amount"] or 0) / 1e18
            if rows[row_index]["event_name"] in ("TokenMint", "Deposit"):
                supply += amount
            else:
                supply -= amount
            row_index += 1

        candle["supply"] = max(supply, 0.0)
        candle["market_cap"] = candle["close"] * candle["supply"]


def iso_from_timestamp(value: int) -> str:
    return datetime.fromtimestamp(value, timezone.utc).replace(microsecond=0).isoformat()
