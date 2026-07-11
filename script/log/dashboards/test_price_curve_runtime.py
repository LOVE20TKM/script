import json
import sqlite3
import unittest

import price_curve_runtime


class PriceCurveRuntimeTest(unittest.TestCase):
    def test_query_price_curve_data_defaults_to_all_non_quote_tokens(self) -> None:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        conn.executescript(
            """
            CREATE TABLE blocks (block_number INTEGER, timestamp INTEGER);
            CREATE TABLE events (
                contract_name TEXT,
                event_name TEXT,
                block_number INTEGER,
                address TEXT,
                decoded_data TEXT
            );
            CREATE TABLE v_contract (address TEXT, contract_name TEXT);
            CREATE TABLE v_pair_created (
                pair TEXT,
                token0 TEXT,
                token1 TEXT,
                block_number INTEGER
            );
            """
        )
        conn.executemany(
            "INSERT INTO v_contract(address, contract_name) VALUES (?, ?)",
            [
                ("0xtkm20", "TKM20"),
                ("0xtusdt", "TUSDT"),
            ],
        )
        token_address = "0xabc0000000000000000000000000000000000000"
        insert_event(conn, "launch", "LaunchEnd", 1, "0xlaunch", {"tokenAddress": token_address})
        insert_event(conn, "ALPHA", "Transfer", 2, token_address, {"value": 1})
        conn.execute("INSERT INTO blocks(block_number, timestamp) VALUES (?, ?)", (2, 1000))

        data = price_curve_runtime.query_price_curve_data(
            conn,
            token_symbols=[],
            quote_symbol="TUSDT",
            interval="1d",
            days=30,
        )

        self.assertEqual(data["selected_tokens"], ["TKM20", "ALPHA"])

    def test_default_selected_tokens_returns_all_non_quote_tokens(self) -> None:
        tokens = [
            {"symbol": "TKM20", "address": "0xtkm20", "decimals": 18},
            {"symbol": "TUSDT", "address": "0xtusdt", "decimals": 18},
            {"symbol": "LOVE20", "address": "0xlove20", "decimals": 18},
        ]
        quote = tokens[1]

        selected = price_curve_runtime.default_selected_tokens(tokens, quote)

        self.assertEqual(selected, [tokens[0], tokens[2]])

    def test_token_symbols_fall_back_to_event_contract_name(self) -> None:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        conn.executescript(
            """
            CREATE TABLE events (
                contract_name TEXT,
                event_name TEXT,
                block_number INTEGER,
                address TEXT,
                decoded_data TEXT
            );
            CREATE TABLE v_contract (address TEXT, contract_name TEXT);
            """
        )
        token_address = "0xabc0000000000000000000000000000000000000"
        insert_event(conn, "launch", "LaunchEnd", 1, "0xlaunch", {"tokenAddress": token_address})
        insert_event(conn, "FRIEND", "Transfer", 2, token_address, {"value": 1})
        insert_event(conn, "FRIEND", "TokenMint", 3, token_address, {"amount": 1})

        tokens = price_curve_runtime.query_price_curve_tokens(conn)

        self.assertIn({"symbol": "FRIEND", "address": token_address, "decimals": 18}, tokens)

    def test_sync_rows_can_be_loaded_by_pair_address(self) -> None:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        conn.executescript(
            """
            CREATE TABLE blocks (block_number INTEGER, timestamp INTEGER);
            CREATE TABLE events (
                block_number INTEGER,
                log_index INTEGER,
                address TEXT,
                event_name TEXT,
                decoded_data TEXT
            );
            """
        )
        pair_address = "0xabc0000000000000000000000000000000000000"
        conn.execute("INSERT INTO blocks(block_number, timestamp) VALUES (10, 1000)")
        conn.execute(
            "INSERT INTO events(block_number, log_index, address, event_name, decoded_data) VALUES (?, ?, ?, ?, ?)",
            (10, 1, pair_address, "Sync", json.dumps({"reserve0": 10 * 10**18, "reserve1": 20 * 10**18})),
        )

        rows = price_curve_runtime.query_sync_rows_by_address(conn, pair_address, 1, 20)

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["block_number"], 10)
        self.assertEqual(rows[0]["reserve0"], 10 * 10**18)

    def test_market_cap_uses_cumulative_supply_at_close_block(self) -> None:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        conn.execute(
            """
            CREATE TABLE events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                contract_name TEXT,
                event_name TEXT,
                block_number INTEGER,
                address TEXT,
                decoded_data TEXT
            )
            """
        )
        token_address = "0xabc0000000000000000000000000000000000000"
        insert_event(conn, "ABC", "TokenMint", 10, token_address, {"amount": 1000 * 10**18})
        insert_event(conn, "ABC", "TokenBurn", 20, token_address, {"amount": 100 * 10**18})

        candles = [
            {"close_block": 15, "close": 2.0},
            {"close_block": 25, "close": 3.0},
        ]
        price_curve_runtime.add_market_caps(conn, {"symbol": "ABC", "address": "0xother00000000000000000000000000000000000"}, candles)

        self.assertEqual(candles[0]["supply"], 1000)
        self.assertEqual(candles[0]["market_cap"], 2000)
        self.assertEqual(candles[1]["supply"], 900)
        self.assertEqual(candles[1]["market_cap"], 2700)

    def test_market_cap_can_use_address_for_unnamed_token(self) -> None:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        conn.execute(
            """
            CREATE TABLE events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                contract_name TEXT,
                event_name TEXT,
                block_number INTEGER,
                address TEXT,
                decoded_data TEXT
            )
            """
        )
        token_address = "0xabc0000000000000000000000000000000000000"
        insert_event(conn, "", "TokenMint", 10, token_address, {"amount": 1000 * 10**18})

        candles = [{"close_block": 15, "close": 2.0}]
        price_curve_runtime.add_market_caps(conn, {"symbol": token_address, "address": token_address}, candles)

        self.assertEqual(candles[0]["supply"], 1000)
        self.assertEqual(candles[0]["market_cap"], 2000)


def insert_event(
    conn: sqlite3.Connection,
    contract_name: str,
    event_name: str,
    block_number: int,
    address: str,
    payload: dict,
) -> None:
    conn.execute(
        "INSERT INTO events(contract_name, event_name, block_number, address, decoded_data) VALUES (?, ?, ?, ?, ?)",
        (contract_name, event_name, block_number, address, json.dumps(payload)),
    )


if __name__ == "__main__":
    unittest.main()
