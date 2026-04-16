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
    status: int = 1,
    value_wei: str = "0",
    input_data: str = "",
) -> None:
    conn.execute(
        """
        INSERT INTO transactions(
            block_number, block_hash, block_timestamp, tx_hash, tx_index, "from", "to", status, value_wei,
            amount, gas, gas_price, max_fee_per_gas, max_priority_fee_per_gas, type, chain_id, input, nonce, v, r, s,
            access_list, gas_used, cumulative_gas_used, contract_address, effective_gas_price, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            block_number,
            None,
            1710000000 + block_number,
            tx_hash,
            tx_index,
            tx_from,
            tx_to,
            status,
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
        self.assertEqual(row["communities"], [{"address": TOKEN, "label": "TUSDT"}])
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
        self.assertEqual(row["action_group"], "governance")
        self.assertEqual(row["action"], "提交 groupVerify 评分")
        self.assertEqual(row["action_id_text"], "9")
        self.assertEqual(row["group_id_text"], "3")
        self.assertEqual(row["amounts"], [])
        self.assertEqual(row["transaction"]["to"], GROUP_VERIFY)
        self.assertEqual(len(row["events"]), 1)
        self.assertEqual(row["events"][0]["decoded_data"]["count"], 4)

    def test_vote_event_becomes_vote_row(self) -> None:
        conn = make_conn()
        vote_contract = "0x6666666666666666666666666666666666666666"
        tx_hash = "0xeeee0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=104,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=vote_contract,
            input_data="0x22ad487f",
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=104,
            tx_index=0,
            log_index=0,
            contract_name="vote",
            event_name="Vote",
            address=vote_contract,
            payload={
                "tokenAddress": TOKEN,
                "round": 7,
                "voter": ACCOUNT,
                "actionId": 9,
                "votes": 123,
            },
        )

        row = timeline_runtime.query_activity_rows_by_account(conn, {TOKEN: "LOVE20", vote_contract: "vote"}, ACCOUNT)["rows"][0]
        self.assertEqual(row["action_group"], "governance")
        self.assertEqual(row["action"], "投票")
        self.assertEqual(row["action_id_text"], "9")
        self.assertEqual(row["amounts"], [{"token": "LOVE20", "raw": "123", "decimals": 18}])

    def test_verify_event_becomes_verify_row(self) -> None:
        conn = make_conn()
        verify_contract = "0x7777777777777777777777777777777777777777"
        tx_hash = "0xffff0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=105,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=verify_contract,
            input_data="0xfe43a47e",
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=105,
            tx_index=0,
            log_index=0,
            contract_name="verify",
            event_name="Verify",
            address=verify_contract,
            payload={
                "tokenAddress": TOKEN,
                "round": 7,
                "verifier": ACCOUNT,
                "actionId": 11,
                "abstentionScore": 0,
                "scores": "[12,34]",
            },
        )

        row = timeline_runtime.query_activity_rows_by_account(conn, {TOKEN: "LOVE20", verify_contract: "verify"}, ACCOUNT)["rows"][0]
        self.assertEqual(row["action_group"], "governance")
        self.assertEqual(row["action"], "提交验证")
        self.assertEqual(row["action_id_text"], "11")
        self.assertIn("2 条评分", row["description"])

    def test_gov_incentive_event_becomes_governance_incentive_row(self) -> None:
        conn = make_conn()
        mint_contract = "0x1212121212121212121212121212121212121212"
        tx_hash = "0x12120000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=1051,
            tx_index=0,
            tx_from=mint_contract,
            tx_to=ACCOUNT,
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=1051,
            tx_index=0,
            log_index=0,
            contract_name="mint",
            event_name="MintGovReward",
            address=mint_contract,
            payload={
                "tokenAddress": TOKEN,
                "round": 8,
                "account": ACCOUNT,
                "verifyReward": 12,
                "boostReward": 34,
                "burnReward": 56,
            },
        )

        row = timeline_runtime.query_activity_rows_by_account(conn, {TOKEN: "LOVE20", mint_contract: "mint"}, ACCOUNT)["rows"][0]
        self.assertEqual(row["action_group"], "incentive")
        self.assertEqual(row["action"], "治理激励入账")
        self.assertEqual(row["amounts"], [{"token": "LOVE20", "raw": "102", "decimals": 18}])

    def test_submit_new_action_becomes_creation_row(self) -> None:
        conn = make_conn()
        submit_contract = "0x8888888888888888888888888888888888888888"
        tx_hash = "0xabcd0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=106,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=submit_contract,
            input_data="0xca52204e",
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=106,
            tx_index=0,
            log_index=0,
            contract_name="submit",
            event_name="ActionCreate",
            address=submit_contract,
            payload={
                "tokenAddress": TOKEN,
                "round": 7,
                "author": ACCOUNT,
                "actionId": 14,
                "actionBody.title": "每天一杯茶",
            },
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=106,
            tx_index=0,
            log_index=1,
            contract_name="submit",
            event_name="ActionSubmit",
            address=submit_contract,
            payload={
                "tokenAddress": TOKEN,
                "round": 7,
                "submitter": ACCOUNT,
                "actionId": 14,
            },
        )

        row = timeline_runtime.query_activity_rows_by_account(conn, {TOKEN: "LOVE20", submit_contract: "submit"}, ACCOUNT)["rows"][0]
        self.assertEqual(row["action_group"], "submit")
        self.assertEqual(row["action"], "创建并提交行动")
        self.assertEqual(row["action_id_text"], "14")
        self.assertIn("每天一杯茶", row["description"])

    def test_stake_event_becomes_stake_row(self) -> None:
        conn = make_conn()
        stake_contract = "0x9999999999999999999999999999999999999999"
        st_token = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        tx_hash = "0xbcde0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=107,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=stake_contract,
            input_data="0xa1d43e1d",
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=107,
            tx_index=0,
            log_index=0,
            contract_name="LOVE20",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": ACCOUNT, "to": stake_contract, "value": "1000"},
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=107,
            tx_index=0,
            log_index=1,
            contract_name="stToken",
            event_name="Transfer",
            address=st_token,
            payload={"from": timeline_runtime.ZERO_ADDRESS, "to": ACCOUNT, "value": "800"},
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=107,
            tx_index=0,
            log_index=2,
            contract_name="stake",
            event_name="StakeToken",
            address=stake_contract,
            payload={
                "tokenAddress": TOKEN,
                "round": 7,
                "account": ACCOUNT,
                "tokenAmount": 1000,
                "promisedWaitingPhases": 120,
                "stAmount": 800,
            },
        )

        row = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "LOVE20", stake_contract: "stake", st_token: "stToken"},
            ACCOUNT,
        )["rows"][0]
        self.assertEqual(row["action_group"], "stake")
        self.assertEqual(row["action"], "质押代币")
        self.assertEqual(row["communities"], [{"address": TOKEN, "label": "LOVE20"}])
        self.assertEqual(
            row["amounts"],
            [
                {"token": "LOVE20", "raw": "1000", "decimals": 18},
                {"token": "stToken", "raw": "800", "decimals": 18},
            ],
        )

    def test_sl_mint_becomes_stake_row(self) -> None:
        conn = make_conn()
        hub_contract = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        sl_token = "0xcccccccccccccccccccccccccccccccccccccccc"
        tx_hash = "0xcdef0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=108,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=hub_contract,
            input_data="0x",
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=108,
            tx_index=0,
            log_index=0,
            contract_name="LOVE20",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": ACCOUNT, "to": hub_contract, "value": "2000"},
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=108,
            tx_index=0,
            log_index=1,
            contract_name="love20slToken",
            event_name="Transfer",
            address=sl_token,
            payload={"from": timeline_runtime.ZERO_ADDRESS, "to": ACCOUNT, "value": "1500"},
        )

        row = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "LOVE20", hub_contract: "hub", sl_token: "love20slToken"},
            ACCOUNT,
        )["rows"][0]
        self.assertEqual(row["action_group"], "stake")
        self.assertEqual(row["action"], "质押流动性")
        self.assertEqual(row["communities"], [{"address": TOKEN, "label": "LOVE20"}])
        self.assertEqual(
            row["amounts"],
            [
                {"token": "LOVE20", "raw": "2000", "decimals": 18},
                {"token": "love20slToken", "raw": "1500", "decimals": 18},
            ],
        )

    def test_launch_and_group_mint_events_are_classified(self) -> None:
        conn = make_conn()
        launch_contract = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        group_contract = "0xcccccccccccccccccccccccccccccccccccccccc"
        child_token = "0xdddddddddddddddddddddddddddddddddddddddd"

        launch_tx = "0xcdef0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=launch_tx,
            block_number=108,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=launch_contract,
            input_data="0x20fe512e",
        )
        insert_event(
            conn,
            tx_hash=launch_tx,
            block_number=108,
            tx_index=0,
            log_index=0,
            contract_name="GROW20",
            event_name="Transfer",
            address=child_token,
            payload={"from": timeline_runtime.ZERO_ADDRESS, "to": ACCOUNT, "value": "5000"},
        )
        insert_event(
            conn,
            tx_hash=launch_tx,
            block_number=108,
            tx_index=0,
            log_index=1,
            contract_name="launch",
            event_name="LaunchToken",
            address=launch_contract,
            payload={
                "tokenAddress": child_token,
                "tokenSymbol": "GROW20",
                "parentTokenAddress": TOKEN,
                "account": ACCOUNT,
            },
        )

        group_tx = "0xdef00000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=group_tx,
            block_number=109,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=group_contract,
            input_data="0xd85d3d27",
        )
        insert_event(
            conn,
            tx_hash=group_tx,
            block_number=109,
            tx_index=0,
            log_index=0,
            contract_name="LOVE20",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": ACCOUNT, "to": group_contract, "value": "600"},
        )
        insert_event(
            conn,
            tx_hash=group_tx,
            block_number=109,
            tx_index=0,
            log_index=1,
            contract_name="group",
            event_name="Transfer",
            address=group_contract,
            payload={"from": timeline_runtime.ZERO_ADDRESS, "to": ACCOUNT, "_tokenId": 7},
        )
        insert_event(
            conn,
            tx_hash=group_tx,
            block_number=109,
            tx_index=0,
            log_index=2,
            contract_name="group",
            event_name="Mint",
            address=group_contract,
            payload={"tokenId": 7, "owner": ACCOUNT, "groupName": "测试群组", "cost": 600},
        )

        rows = timeline_runtime.query_activity_rows_by_account(
            conn,
            {
                TOKEN: "LOVE20",
                launch_contract: "launch",
                child_token: "GROW20",
                group_contract: "group",
            },
            ACCOUNT,
        )["rows"]

        launch_row = next(row for row in rows if row["tx_hash"] == launch_tx)
        self.assertEqual(launch_row["action_group"], "launch")
        self.assertEqual(launch_row["action"], "发起代币")
        self.assertEqual(launch_row["amounts"], [{"token": "GROW20", "raw": "5000", "decimals": 18}])

        group_row = next(row for row in rows if row["tx_hash"] == group_tx)
        self.assertEqual(group_row["action_group"], "group")
        self.assertEqual(group_row["action"], "创建群组")
        self.assertEqual(group_row["communities"], [{"address": TOKEN, "label": "LOVE20"}])
        self.assertIn("测试群组", group_row["description"])

    def test_swap_and_hub_rows_are_counted_as_communities(self) -> None:
        conn = make_conn()
        router = "0x7777777777777777777777777777777777777777"
        pair = "0x8888888888888888888888888888888888888888"
        grow20 = "0x9999999999999999999999999999999999999999"
        hub_contract = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        sl_token = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        sell_tx = "0xaaaa0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=sell_tx,
            block_number=110,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=router,
            input_data="0x38ed1739",
        )
        insert_event(
            conn,
            tx_hash=sell_tx,
            block_number=110,
            tx_index=0,
            log_index=0,
            contract_name="LIFE20",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": ACCOUNT, "to": pair, "value": "100"},
        )
        insert_event(
            conn,
            tx_hash=sell_tx,
            block_number=110,
            tx_index=0,
            log_index=1,
            contract_name="GROW20",
            event_name="Transfer",
            address=grow20,
            payload={"from": pair, "to": ACCOUNT, "value": "80"},
        )

        router_tx = "0xbbbb0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=router_tx,
            block_number=111,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=router,
            input_data="0x18cbafe5",
        )
        insert_event(
            conn,
            tx_hash=router_tx,
            block_number=111,
            tx_index=0,
            log_index=0,
            contract_name="LIFE20",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": pair, "to": router, "value": "55"},
        )

        hub_tx = "0xcccc0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=hub_tx,
            block_number=112,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=hub_contract,
        )
        insert_event(
            conn,
            tx_hash=hub_tx,
            block_number=112,
            tx_index=0,
            log_index=0,
            contract_name="LIFE20",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": ACCOUNT, "to": hub_contract, "value": "200"},
        )
        insert_event(
            conn,
            tx_hash=hub_tx,
            block_number=112,
            tx_index=0,
            log_index=1,
            contract_name="LIFE20",
            event_name="Transfer",
            address=TOKEN,
            payload={"from": hub_contract, "to": sl_token, "value": "200"},
        )

        user_rows = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "LOVE20", grow20: "GROW20", pair: "love20grow20pair", router: "uniswapV2Router02"},
            ACCOUNT,
        )["rows"]
        user_by_hash = {row["tx_hash"]: row for row in user_rows}
        self.assertEqual(user_by_hash[sell_tx]["action_group"], "swap")
        self.assertTrue(any(item["label"] == "LOVE20" for item in user_by_hash[sell_tx]["communities"]))
        self.assertTrue(any(item["label"] == "GROW20" for item in user_by_hash[sell_tx]["communities"]))

        router_rows = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "LOVE20", pair: "love20grow20pair", router: "uniswapV2Router02"},
            router,
        )["rows"]
        router_by_hash = {row["tx_hash"]: row for row in router_rows}
        self.assertEqual(router_by_hash[router_tx]["action_group"], "swap")
        self.assertTrue(any(item["label"] == "LOVE20" for item in router_by_hash[router_tx]["communities"]))

        hub_rows = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "LOVE20", hub_contract: "hub", sl_token: "love20slToken"},
            hub_contract,
        )["rows"]
        hub_by_hash = {row["tx_hash"]: row for row in hub_rows}
        self.assertEqual(hub_by_hash[hub_tx]["action"], "Hub 中转质押")
        self.assertTrue(any(item["label"] == "LOVE20" for item in hub_by_hash[hub_tx]["communities"]))

    def test_known_selectors_without_events_are_decoded(self) -> None:
        conn = make_conn()
        join_contract = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        reward_contract = "0xffffffffffffffffffffffffffffffffffffffff"
        tx_approve = "0x11110000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        tx_join = "0x22220000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        tx_claim = "0x33330000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        tx_mint = "0x44440000111122223333444455556666777788889999aaaabbbbccccddddeeee"

        insert_tx(
            conn,
            tx_hash=tx_approve,
            block_number=110,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=TOKEN,
            input_data="0x095ea7b3" + ("0" * 24) + SPENDER[2:] + f"{123:064x}",
        )
        insert_tx(
            conn,
            tx_hash=tx_join,
            block_number=111,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=join_contract,
            status=0,
            input_data="0x7fc34362" + ("0" * 24) + TOKEN[2:] + f"{9:064x}" + f"{100:064x}" + f"{128:064x}",
        )
        insert_tx(
            conn,
            tx_hash=tx_claim,
            block_number=112,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=reward_contract,
            input_data="0xae169a50" + f"{12:064x}",
        )
        insert_tx(
            conn,
            tx_hash=tx_mint,
            block_number=113,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=reward_contract,
            status=0,
            input_data="0x823ed39d" + ("0" * 24) + TOKEN[2:] + f"{5:064x}" + f"{3:064x}",
        )

        rows = timeline_runtime.query_activity_rows_by_account(
            conn,
            {TOKEN: "LOVE20", SPENDER: "spender", join_contract: "join", reward_contract: "mint"},
            ACCOUNT,
        )["rows"]
        by_hash = {row["tx_hash"]: row for row in rows}

        self.assertEqual(by_hash[tx_approve]["action_group"], "approval")
        self.assertEqual(by_hash[tx_approve]["action"], "授权 LOVE20")
        self.assertEqual(by_hash[tx_join]["action"], "参与行动失败")
        self.assertEqual(by_hash[tx_join]["action_id_text"], "9")
        self.assertEqual(by_hash[tx_claim]["action_group"], "incentive")
        self.assertEqual(by_hash[tx_claim]["action"], "领取行动激励")
        self.assertEqual(by_hash[tx_mint]["action_group"], "incentive")
        self.assertEqual(by_hash[tx_mint]["action"], "铸造行动激励失败")

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
        self.assertEqual(row["communities"], [{"address": TOKEN, "label": "TUSDT"}])
        self.assertEqual(len(row["events"]), 3)
        self.assertEqual(row["events"][-1]["event_name"], "Sync")

    def test_life20_transfer_is_counted_as_community(self) -> None:
        conn = make_conn()
        tx_hash = "0xccccddddeeeeffff0000111122223333444455556666777788889999aaaabbbb"
        life20 = "0x6666666666666666666666666666666666666666"
        insert_tx(
            conn,
            tx_hash=tx_hash,
            block_number=103,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=COUNTERPARTY,
        )
        insert_event(
            conn,
            tx_hash=tx_hash,
            block_number=103,
            tx_index=0,
            log_index=0,
            contract_name="LIFE20",
            event_name="Transfer",
            address=life20,
            payload={"from": ACCOUNT, "to": COUNTERPARTY, "value": "88"},
        )

        result = timeline_runtime.query_activity_rows_by_account(
            conn,
            {life20: "LIFE20", COUNTERPARTY: "receiver"},
            ACCOUNT,
        )

        self.assertEqual(len(result["rows"]), 1)
        row = result["rows"][0]
        self.assertEqual(row["action_group"], "transfer")
        self.assertEqual(row["communities"], [{"address": life20, "label": "LIFE20"}])

    def test_liquidity_rows_are_counted_as_communities(self) -> None:
        conn = make_conn()
        router = "0x7777777777777777777777777777777777777777"
        pair = "0x8888888888888888888888888888888888888888"
        life20 = "0x6666666666666666666666666666666666666666"

        add_tx = "0xaaaa0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=add_tx,
            block_number=104,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=router,
            input_data="0xe8e33700",
        )
        insert_event(
            conn,
            tx_hash=add_tx,
            block_number=104,
            tx_index=0,
            log_index=0,
            contract_name="LIFE20",
            event_name="Transfer",
            address=life20,
            payload={"from": ACCOUNT, "to": pair, "value": "88"},
        )
        insert_event(
            conn,
            tx_hash=add_tx,
            block_number=104,
            tx_index=0,
            log_index=1,
            contract_name="love20life20pair",
            event_name="Transfer",
            address=pair,
            payload={"from": timeline_runtime.ZERO_ADDRESS, "to": ACCOUNT, "value": "77"},
        )

        remove_tx = "0xbbbb0000111122223333444455556666777788889999aaaabbbbccccddddeeee"
        insert_tx(
            conn,
            tx_hash=remove_tx,
            block_number=105,
            tx_index=0,
            tx_from=ACCOUNT,
            tx_to=router,
            input_data="0xbaa2abde",
        )
        insert_event(
            conn,
            tx_hash=remove_tx,
            block_number=105,
            tx_index=0,
            log_index=0,
            contract_name="love20life20pair",
            event_name="Transfer",
            address=pair,
            payload={"from": ACCOUNT, "to": pair, "value": "77"},
        )
        insert_event(
            conn,
            tx_hash=remove_tx,
            block_number=105,
            tx_index=0,
            log_index=1,
            contract_name="LIFE20",
            event_name="Transfer",
            address=life20,
            payload={"from": pair, "to": ACCOUNT, "value": "88"},
        )

        result = timeline_runtime.query_activity_rows_by_account(
            conn,
            {router: "uniswapV2Router02", pair: "love20life20pair", life20: "LIFE20"},
            ACCOUNT,
        )
        by_hash = {row["tx_hash"]: row for row in result["rows"]}
        self.assertIn(add_tx, by_hash)
        self.assertIn(remove_tx, by_hash)
        self.assertTrue(any(item["label"] == "LIFE20" for item in by_hash[add_tx]["communities"]))
        self.assertTrue(any(item["label"] == "LIFE20" for item in by_hash[remove_tx]["communities"]))

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
