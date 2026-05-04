import sqlite3
import unittest
import json

import tusdt_flow_runtime


GROW_USER = "0x1111111111111111111111111111111111111111"
LIVELY_USER = "0x2222222222222222222222222222222222222222"
PAIR = "0x3333333333333333333333333333333333333333"
E18 = 10**18


def make_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE transactions (tx_hash TEXT PRIMARY KEY, "from" TEXT);
        CREATE TABLE events (
            log_round INTEGER,
            tx_hash TEXT,
            contract_name TEXT,
            event_name TEXT,
            decoded_data TEXT
        );

        CREATE TABLE v_love20_tusdt_swap (
            log_round INTEGER, user TEXT, "to" TEXT, tusdt_in_amount REAL, tusdt_out_amount REAL
        );
        CREATE TABLE v_life20_tusdt_swap (
            log_round INTEGER, user TEXT, "to" TEXT, tusdt_in_amount REAL, tusdt_out_amount REAL
        );
        CREATE TABLE v_grow20_tusdt_swap (
            log_round INTEGER, user TEXT, "to" TEXT, tusdt_in_amount REAL, tusdt_out_amount REAL
        );
        CREATE TABLE v_lively_tusdt_swap (
            log_round INTEGER, user TEXT, "to" TEXT, tusdt_in_amount REAL, tusdt_out_amount REAL
        );

        CREATE TABLE v_liquidity_tusdt_love20 (
            log_round INTEGER, user TEXT, amount_sign INTEGER, tusdt_amount REAL
        );
        CREATE TABLE v_liquidity_tusdt_life20 (
            log_round INTEGER, user TEXT, amount_sign INTEGER, tusdt_amount REAL
        );
        CREATE TABLE v_liquidity_tusdt_grow20 (
            log_round INTEGER, user TEXT, amount_sign INTEGER, tusdt_amount REAL
        );
        CREATE TABLE v_liquidity_tusdt_lively (
            log_round INTEGER, user TEXT, amount_sign INTEGER, tusdt_amount REAL
        );
        CREATE TABLE v_tusdt_crosschain (
            log_round INTEGER, user TEXT, amount_sign INTEGER, tusdt_amount REAL
        );
        """
    )
    insert_tx(conn, "0xgrow20swap", GROW_USER)
    insert_tx(conn, "0xgrow20lp", GROW_USER)
    insert_tx(conn, "0xlivelyswap", LIVELY_USER)
    insert_tx(conn, "0xlivelylp", LIVELY_USER)

    insert_event(
        conn,
        tx_hash="0xgrow20swap",
        contract_name="grow20TusdtPair",
        event_name="Swap",
        payload={"amount0In": 0, "amount0Out": 0, "amount1In": 0, "amount1Out": 5 * E18, "to": PAIR},
    )
    insert_event(
        conn,
        tx_hash="0xgrow20lp",
        contract_name="grow20TusdtPair",
        event_name="Mint",
        payload={"amount0": 100 * E18, "amount1": 3 * E18},
    )
    insert_event(
        conn,
        tx_hash="0xlivelyswap",
        contract_name="livelyTusdtPair",
        event_name="Swap",
        payload={"amount0In": 7 * E18, "amount0Out": 0, "amount1In": 0, "amount1Out": 0, "to": PAIR},
    )
    insert_event(
        conn,
        tx_hash="0xlivelylp",
        contract_name="livelyTusdtPair",
        event_name="Burn",
        payload={"amount0": 2 * E18, "amount1": 100 * E18},
    )
    return conn


def insert_tx(conn: sqlite3.Connection, tx_hash: str, tx_from: str) -> None:
    conn.execute("INSERT INTO transactions(tx_hash, \"from\") VALUES (?, ?)", (tx_hash, tx_from))


def insert_event(conn: sqlite3.Connection, *, tx_hash: str, contract_name: str, event_name: str, payload: dict) -> None:
    conn.execute(
        "INSERT INTO events(log_round, tx_hash, contract_name, event_name, decoded_data) VALUES (10, ?, ?, ?, ?)",
        (tx_hash, contract_name, event_name, json.dumps(payload)),
    )


class TusdtFlowRuntimeTest(unittest.TestCase):
    def test_grow20_and_lively_tusdt_flows_are_returned(self) -> None:
        conn = make_conn()
        conn.execute(
            "INSERT INTO v_grow20_tusdt_swap(log_round, user, tusdt_in_amount, tusdt_out_amount) VALUES (10, ?, 0, 5)",
            (GROW_USER,),
        )
        conn.execute(
            "INSERT INTO v_liquidity_tusdt_grow20(log_round, user, amount_sign, tusdt_amount) VALUES (10, ?, 1, 3)",
            (GROW_USER,),
        )
        conn.execute(
            "INSERT INTO v_lively_tusdt_swap(log_round, user, tusdt_in_amount, tusdt_out_amount) VALUES (10, ?, 7, 0)",
            (LIVELY_USER,),
        )
        conn.execute(
            "INSERT INTO v_liquidity_tusdt_lively(log_round, user, amount_sign, tusdt_amount) VALUES (10, ?, -1, 2)",
            (LIVELY_USER,),
        )

        data = tusdt_flow_runtime.query_tusdt_flow_data(
            conn,
            recent_rounds=1,
            mode="round",
            selected_round=None,
            sort_by="net_inflow",
        )

        selected = data["selected_summary"]
        self.assertEqual(selected["grow20_swap_tusdt_flow"], -5)
        self.assertEqual(selected["grow20_lp_tusdt_flow"], 3)
        self.assertEqual(selected["lively_swap_tusdt_flow"], 7)
        self.assertEqual(selected["lively_lp_tusdt_flow"], -2)
        self.assertEqual(selected["net_swap_tusdt_flow"], 2)
        self.assertEqual(selected["net_lp_tusdt_flow"], 1)
        self.assertEqual(selected["net_inflow_tusdt"], 3)

        detail_by_address = {row["address"]: row for row in data["detail"]["rows"]}
        self.assertEqual(detail_by_address[GROW_USER]["grow20_swap_tusdt_flow"], -5)
        self.assertEqual(detail_by_address[GROW_USER]["grow20_lp_tusdt_flow"], 3)
        self.assertEqual(detail_by_address[LIVELY_USER]["lively_swap_tusdt_flow"], 7)
        self.assertEqual(detail_by_address[LIVELY_USER]["lively_lp_tusdt_flow"], -2)


if __name__ == "__main__":
    unittest.main()
