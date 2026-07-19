import json
import sqlite3
import unittest
from unittest.mock import patch

import price_curve_runtime


class PriceCurveRuntimeTest(unittest.TestCase):
    def test_parse_days_supports_one_year(self) -> None:
        self.assertEqual(price_curve_runtime.parse_days("365"), 365)

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

    def test_token_series_uses_love20_bridge_instead_of_direct_quote_pair(self) -> None:
        conn = make_bridge_connection()

        data = price_curve_runtime.query_price_curve_data(
            conn,
            token_symbols=["ALPHA"],
            quote_symbol="TUSDT",
            interval="1d",
            days=30,
        )
        series = data["series"][0]

        self.assertEqual(series["candles"][0]["close"], 30.0)
        self.assertEqual(series["pair"]["pair"], "0xtargetpair")

        love20_data = price_curve_runtime.query_price_curve_data(
            conn,
            token_symbols=["ALPHA"],
            quote_symbol="LOVE20",
            interval="1d",
            days=30,
        )
        love20_series = love20_data["series"][0]

        self.assertEqual(love20_series["candles"][0]["close"], 10.0)

    def test_quote_bridge_candles_are_loaded_once_per_request(self) -> None:
        conn = make_bridge_connection()

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
            if call.args[1]["pair"] == "0xbridgepair"
        ]
        self.assertEqual(len(bridge_calls), 1)

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
        launched_tokens = {
            "ALPHA": "0xabc0000000000000000000000000000000000000",
            "BETA": "0xdef0000000000000000000000000000000000000",
            "GAMMA": "0x1230000000000000000000000000000000000000",
        }
        for block_number, (symbol, token_address) in enumerate(launched_tokens.items(), start=1):
            insert_event(conn, "launch", "LaunchEnd", block_number, "0xlaunch", {"tokenAddress": token_address})
            insert_event(conn, symbol, "Transfer", block_number, token_address, {"value": 1})
        conn.execute("INSERT INTO blocks(block_number, timestamp) VALUES (?, ?)", (10, 1000))

        data = price_curve_runtime.query_price_curve_data(
            conn,
            token_symbols=[],
            quote_symbol="TUSDT",
            interval="1d",
            days=30,
        )

        self.assertEqual(data["selected_tokens"], ["TKM20", "ALPHA", "BETA", "GAMMA"])
        self.assertEqual([item["token"]["symbol"] for item in data["series"]], data["selected_tokens"])
        self.assertEqual(data["from_timestamp"], 1000 - 30 * 86400)
        self.assertEqual(data["to_timestamp"], 1000)

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

    def test_market_cap_uses_weth_deposit_and_withdrawal_supply_events(self) -> None:
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
        insert_event(conn, "TKM20", "Deposit", 10, token_address, {"wad": 1000 * 10**18})
        insert_event(conn, "TKM20", "Withdrawal", 20, token_address, {"wad": 100 * 10**18})

        candles = [
            {"close_block": 15, "close": 2.0},
            {"close_block": 25, "close": 3.0},
        ]
        price_curve_runtime.add_market_caps(conn, {"symbol": "TKM20", "address": token_address}, candles)

        self.assertEqual(candles[0]["supply"], 1000)
        self.assertEqual(candles[0]["market_cap"], 2000)
        self.assertEqual(candles[1]["supply"], 900)
        self.assertEqual(candles[1]["market_cap"], 2700)


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


def make_bridge_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE blocks (block_number INTEGER, timestamp INTEGER);
        CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            contract_name TEXT,
            event_name TEXT,
            block_number INTEGER,
            log_index INTEGER,
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
        [("0xtusdt", "TUSDT"), ("0xlove", "LOVE20"), ("0xalpha", "ALPHA")],
    )
    insert_event(conn, "launch", "LaunchEnd", 1, "0xlaunch", {"tokenAddress": "0xlove"})
    insert_event(conn, "LOVE20", "Transfer", 2, "0xlove", {"value": 1})
    insert_event(conn, "launch", "LaunchEnd", 3, "0xlaunch", {"tokenAddress": "0xalpha"})
    insert_event(conn, "ALPHA", "Transfer", 4, "0xalpha", {"value": 1})
    conn.execute("INSERT INTO blocks(block_number, timestamp) VALUES (?, ?)", (10, 1000))
    conn.executemany(
        "INSERT INTO v_pair_created(pair, token0, token1, block_number) VALUES (?, ?, ?, ?)",
        [
            ("0xtargetpair", "0xlove", "0xalpha", 10),
            ("0xbridgepair", "0xtusdt", "0xlove", 10),
            ("0xdirectpair", "0xtusdt", "0xalpha", 10),
        ],
    )
    insert_event(conn, "", "Sync", 10, "0xtargetpair", {"reserve0": 1000, "reserve1": 100})
    insert_event(conn, "", "Sync", 10, "0xbridgepair", {"reserve0": 300, "reserve1": 100})
    insert_event(conn, "", "Sync", 10, "0xdirectpair", {"reserve0": 99900, "reserve1": 100})
    return conn


if __name__ == "__main__":
    unittest.main()
