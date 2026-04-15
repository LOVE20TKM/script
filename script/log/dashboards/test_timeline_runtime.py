import json
import sqlite3
import unittest

import timeline_runtime


ACCOUNT = "0x1111111111111111111111111111111111111111"
TOKEN = "0x2222222222222222222222222222222222222222"
SPENDER = "0x3333333333333333333333333333333333333333"
COUNTERPARTY = "0x4444444444444444444444444444444444444444"
GROUP_VERIFY = "0x5555555555555555555555555555555555555555"


def make_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            block_number INTEGER,
            block_hash TEXT,
            block_timestamp INTEGER,
            tx_hash TEXT UNIQUE,
            tx_index INTEGER,
            "from" TEXT,
            "to" TEXT,
            status INTEGER,
            value_wei TEXT,
            amount REAL,
            gas INTEGER,
            gas_price INTEGER,
            max_fee_per_gas INTEGER,
            max_priority_fee_per_gas INTEGER,
            type INTEGER,
            chain_id INTEGER,
            input TEXT,
            nonce INTEGER,
            v INTEGER,
            r TEXT,
            s TEXT,
            access_list TEXT,
            gas_used INTEGER,
            cumulative_gas_used INTEGER,
            contract_address TEXT,
            effective_gas_price INTEGER,
            created_at TEXT
        );

        CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            block_number INTEGER,
            tx_hash TEXT,
            tx_index INTEGER,
            log_index INTEGER,
            contract_name TEXT,
            event_name TEXT,
            log_round INTEGER,
            round INTEGER,
            address TEXT,
            decoded_data TEXT,
            created_at TEXT
        );
        """
    )
    return conn


def insert_tx(
    conn: sqlite3.Connection,
    *,
    tx_hash: str,
    block_number: int,
    tx_index: int,
    tx_from: str,
    tx_to: str,
    value_wei: str = "0",
    input_data: str = "",
) -> None:
    conn.execute(
        """
        INSERT INTO transactions(
            block_number, block_hash, block_timestamp, tx_hash, tx_index, "from", "to", status, value_wei,
            amount, gas, gas_price, max_fee_per_gas, max_priority_fee_per_gas, type, chain_id, input, nonce, v, r, s,
            access_list, gas_used, cumulative_gas_used, contract_address, effective_gas_price, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            block_number,
            None,
            1710000000 + block_number,
            tx_hash,
            tx_index,
            tx_from,
            tx_to,
            value_wei,
            0,
            None,
            None,
            None,
            None,
            None,
            None,
            input_data,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            "2026-04-15T00:00:00+00:00",
        ),
    )


def insert_event(
    conn: sqlite3.Connection,
    *,
    tx_hash: str,
    block_number: int,
    tx_index: int,
    log_index: int,
    contract_name: str,
    event_name: str,
    address: str,
    payload: dict,
) -> None:
    conn.execute(
        """
        INSERT INTO events(
            block_number, tx_hash, tx_index, log_index, contract_name, event_name, log_round, round, address, decoded_data, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (block_number, tx_hash, tx_index, log_index, contract_name, event_name, None, None, address, json.dumps(payload), "2026-04-15T00:00:00+00:00"),
    )


class TimelineRuntimeTest(unittest.TestCase):
    def test_approval_only_tx_becomes_single_row(self) -> None:
        conn = make_conn()
        insert_tx(
            conn,
            tx_hash="0xaaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999",
            block_number=100,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=TOKEN,
            input_data="0x095ea7b3",
        )
        insert_event(
            conn,
            tx_hash="0xaaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999",
            block_number=100,
            tx_index=0,
            log_index=0,
            contract_name="TUSDT",
            event_name="Approval",
            address=TOKEN,
            payload={"owner": ACCOUNT, "spender": SPENDER, "value": "123456789"},
        )

        result = timeline_runtime.query_activity_rows_by_account(
            conn,
            {SPENDER: "uniswapV2Router02", TOKEN: "TUSDT"},
            ACCOUNT,
        )

        self.assertEqual(len(result["rows"]), 1)
        row = result["rows"][0]
        self.assertEqual(row["action_group"], "approval")
        self.assertEqual(row["amounts"], [{"token": "TUSDT", "raw": "123456789", "decimals": 18}])
        self.assertEqual(row["counterparties"][0]["address"], SPENDER)
        self.assertEqual(row["transaction"]["tx_hash"], "0xaaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999")
        self.assertEqual(len(row["events"]), 1)
        self.assertEqual(row["events"][0]["event_name"], "Approval")

    def test_group_verify_submit_tx_becomes_single_row(self) -> None:
        conn = make_conn()
        insert_tx(
            conn,
            tx_hash="0xbbbbccccddddeeeeffff0000111122223333444455556666777788889999aaaa",
            block_number=101,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=GROUP_VERIFY,
            input_data="0x1e481001",
        )
        insert_event(
            conn,
            tx_hash="0xbbbbccccddddeeeeffff0000111122223333444455556666777788889999aaaa",
            block_number=101,
            tx_index=0,
            log_index=0,
            contract_name="groupVerify",
            event_name="SubmitOriginScores",
            address=GROUP_VERIFY,
            payload={
                "tokenAddress": TOKEN,
                "round": 7,
                "actionId": 9,
                "groupId": 3,
                "startIndex": 0,
                "count": 4,
                "isComplete": True,
            },
        )

        result = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "LOVE20", GROUP_VERIFY: "groupVerify"},
            ACCOUNT,
        )

        self.assertEqual(len(result["rows"]), 1)
        row = result["rows"][0]
        self.assertEqual(row["action_group"], "verify")
        self.assertEqual(row["action"], "提交 groupVerify 评分")
        self.assertEqual(row["action_id_text"], "9")
        self.assertEqual(row["group_id_text"], "3")
        self.assertEqual(row["amounts"], [])
        self.assertEqual(row["transaction"]["to"], GROUP_VERIFY)
        self.assertEqual(len(row["events"]), 1)
        self.assertEqual(row["events"][0]["decoded_data"]["count"], 4)

    def test_multiple_transfer_events_in_one_tx_stay_one_row(self) -> None:
        conn = make_conn()
        tx_hash = "0xccccddddeeeeffff0000111122223333444455556666777788889999aaaabbbb"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=102,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=COUNTERPARTY,
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=102,
            tx_index=0,
            log_index=0,
            contract_name="TUSDT",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": ACCOUNT, "to": COUNTERPARTY, "value": "100"},
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=102,
            tx_index=0,
            log_index=1,
            contract_name="TUSDT",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": ACCOUNT, "to": COUNTERPARTY, "value": "50"},
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=102,
            tx_index=0,
            log_index=2,
            contract_name="TUSDT",
            event_name="Sync",
            address=TOKEN,
            payload={"reserve0": "1", "reserve1": "2"},
        )

        result = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "TUSDT", COUNTERPARTY: "receiver"},
            ACCOUNT,
        )

        self.assertEqual(len(result["rows"]), 1)
        row = result["rows"][0]
        self.assertEqual(row["tx_hash"], tx_hash)
        self.assertEqual(row["action_group"], "transfer")
        self.assertEqual(row["amounts"], [{"token": "TUSDT", "raw": "150", "decimals": 18}])
        self.assertEqual(len(row["events"]), 3)
        self.assertEqual(row["events"][-1]["event_name"], "Sync")

    def test_unclassified_zero_value_call_still_keeps_tx_row(self) -> None:
        conn = make_conn()
        tx_hash = "0xdddd0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=103,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=COUNTERPARTY,
            input_data="0x12345678",
        )

        result = timeline_runtime.query_activity_rows_by_account(
            conn,
            {COUNTERPARTY: "someContract"},
            ACCOUNT,
        )

        self.assertEqual(len(result["rows"]), 1)
        row = result["rows"][0]
        self.assertEqual(row["tx_hash"], tx_hash)
        self.assertEqual(row["action_group"], "other")
        self.assertEqual(row["action"], "未归类调用")
        self.assertEqual(row["amounts"], [])
        self.assertEqual(row["transaction"]["from"], ACCOUNT)
        self.assertEqual(row["events"], [])


if __name__ == "__main__":
    unittest.main()
