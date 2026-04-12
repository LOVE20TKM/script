#!/usr/bin/env python3
import argparse
import json
import sqlite3
from collections import OrderedDict, defaultdict
from datetime import datetime, timezone
from pathlib import Path


ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
PAIR_CONTRACTS = {
    "love20tusdtpair",
    "love20tkm20pair",
    "love20life20pair",
}
PAIR_LABELS = {
    "love20tusdtpair": "LOVE20/TUSDT LP",
    "love20tkm20pair": "LOVE20/TKM20 LP",
    "love20life20pair": "LOVE20/LIFE20 LP",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build wallet activity timeline dashboard DB.")
    parser.add_argument("--source-db", required=True, help="Path to source events.db")
    parser.add_argument("--output-db", required=True, help="Path to output dashboard DB")
    parser.add_argument("--network", required=True, help="Network label")
    return parser.parse_args()


def normalize_address(value: str | None) -> str:
    return (value or "").strip().lower()


def is_zero_address(value: str | None) -> bool:
    return normalize_address(value) in {"", ZERO_ADDRESS}


def token_label(contract_name: str | None) -> str:
    if not contract_name:
        return "Token"
    lowered = contract_name.lower()
    if lowered in PAIR_LABELS:
        return PAIR_LABELS[lowered]
    if lowered in PAIR_CONTRACTS or lowered.endswith("pair"):
        return f"{contract_name} LP"
    return contract_name


def short_address(value: str | None) -> str:
    address = normalize_address(value)
    if len(address) < 12:
        return address or "-"
    return f"{address[:10]}...{address[-6:]}"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load_contract_map(conn: sqlite3.Connection) -> dict[str, str]:
    rows = conn.execute("SELECT lower(address) AS address, contract_name FROM v_contract").fetchall()
    return {row["address"]: row["contract_name"] for row in rows}


def add_counterparty(items: list[dict], address: str | None, contract_map: dict[str, str]) -> None:
    normalized = normalize_address(address)
    if not normalized:
        return
    items.append(
        {
            "address": normalized,
            "label": contract_map.get(normalized, ""),
        }
    )


def add_community(items: list[dict], token_address: str | None, contract_map: dict[str, str]) -> None:
    normalized = normalize_address(token_address)
    if not normalized:
        return
    items.append(
        {
            "address": normalized,
            "label": contract_map.get(normalized, short_address(normalized)),
        }
    )


def unique_counterparties(items: list[dict]) -> list[dict]:
    seen: set[str] = set()
    ordered: list[dict] = []
    for item in items:
        address = item.get("address", "")
        if not address or address in seen:
            continue
        seen.add(address)
        ordered.append(item)
    return ordered


def collapse_amounts(items: list[dict]) -> list[dict]:
    totals: OrderedDict[tuple[str, int], int] = OrderedDict()
    for item in items:
        token = item["token"]
        decimals = int(item.get("decimals", 18))
        raw = int(item.get("raw", 0))
        key = (token, decimals)
        totals[key] = totals.get(key, 0) + raw

    collapsed: list[dict] = []
    for (token, decimals), raw in totals.items():
        collapsed.append(
            {
                "token": token,
                "raw": str(raw),
                "decimals": decimals,
            }
        )
    return collapsed


def collapse_approvals(items: list[dict]) -> list[dict]:
    latest: OrderedDict[tuple[str, str], dict] = OrderedDict()
    for item in items:
        key = (item["token"], item["spender"])
        latest[key] = item
    return [
        {
            "token": item["token"],
            "raw": str(item["raw"]),
            "decimals": int(item.get("decimals", 18)),
        }
        for item in latest.values()
    ]


def stringify_numbers(values: list[int]) -> str:
    cleaned = sorted({int(value) for value in values})
    return ",".join(str(value) for value in cleaned)


def group_transfer_items(items: list[dict], *, counterparty: str | None = None) -> list[dict]:
    filtered = []
    normalized_counterparty = normalize_address(counterparty)
    for item in items:
        if normalized_counterparty and normalize_address(item.get("counterparty")) != normalized_counterparty:
            continue
        filtered.append(
            {
                "token": item["token"],
                "raw": str(item["raw"]),
                "decimals": int(item.get("decimals", 18)),
            }
        )
    return collapse_amounts(filtered)


def describe_counterparty(counterparty: str | None, contract_map: dict[str, str]) -> str:
    normalized = normalize_address(counterparty)
    if not normalized:
        return "-"
    label = contract_map.get(normalized)
    if label:
        return label
    return short_address(normalized)


def infer_lp_label_for_token(token_address: str | None, contract_map: dict[str, str]) -> str:
    token_name = contract_map.get(normalize_address(token_address), "")
    if token_name in {"LIFE20", "TUSDT", "TKM20"}:
        return f"LOVE20/{token_name} LP"
    return "LP"


def infer_group_amounts(summary: dict, tx_to: str, contract_map: dict[str, str]) -> list[dict]:
    outgoing = group_transfer_items(summary["transfers_out"], counterparty=tx_to)
    if outgoing:
        return outgoing
    return [
        {
            "token": infer_lp_label_for_token(summary["group_joins"][0].get("token_address"), contract_map),
            "raw": str(summary["group_joins"][0]["amount"]),
            "decimals": 18,
        }
    ]


def infer_exit_amounts(summary: dict, tx_to: str, contract_map: dict[str, str]) -> list[dict]:
    incoming = group_transfer_items(summary["transfers_in"], counterparty=tx_to)
    if incoming:
        return incoming
    return [
        {
            "token": infer_lp_label_for_token(summary["group_exits"][0].get("token_address"), contract_map),
            "raw": str(summary["group_exits"][0]["amount"]),
            "decimals": 18,
        }
    ]


def has_non_lp(items: list[dict]) -> bool:
    return any(not is_lp_token(item["token"]) for item in items)


def is_lp_token(token: str | None) -> bool:
    return bool(token) and str(token).endswith("LP")


def build_row(
    account: str,
    summary: dict,
    tx_meta: dict,
    contract_map: dict[str, str],
) -> dict:
    tx_to = normalize_address(tx_meta["tx_to"])
    tx_from = normalize_address(tx_meta["tx_from"])

    action = ""
    action_group = "other"
    action_id_text = ""
    group_id_text = ""
    description = ""
    amounts: list[dict] = []
    counterparties: list[dict] = []
    communities: list[dict] = []

    if summary["claims"] or summary["reward_mints"]:
        action_group = "reward"
        action_ids = [
            item["action_id"]
            for item in summary["claims"]
            if item.get("action_id")
        ] + [
            item["action_id"]
            for item in summary["reward_mints"]
            if item.get("action_id")
        ]
        action_id_text = stringify_numbers(action_ids) if action_ids else ""

        if summary["claims"] and not summary["reward_mints"]:
            action = "领取奖励"
            description = f"从 {summary['claims'][0]['contract_name']} 领取 actionId={summary['claims'][0]['action_id']} 奖励"
        elif summary["reward_mints"] and not summary["claims"]:
            reward_kinds = {item["kind"] for item in summary["reward_mints"]}
            if reward_kinds == {"MintGovReward"}:
                action = "治理奖励入账"
                description = f"mint 合约给该地址铸入治理奖励，第 {summary['reward_mints'][0]['round']} 轮"
            elif reward_kinds == {"MintActionReward"} and len(summary["reward_mints"]) == 1:
                action = "行动奖励入账"
                description = f"mint 合约给该地址铸入 actionId={summary['reward_mints'][0]['action_id']} 奖励"
            else:
                action = "奖励入账"
                description = "mint 合约给该地址铸入奖励"
        else:
            action = "奖励入账"
            description = f"批量领取奖励，actionId={action_id_text}"
        amounts = collapse_amounts(
            [
                {
                    "token": item["token"],
                    "raw": str(item["mint_amount"]),
                    "decimals": 18,
                }
                for item in summary["claims"]
                if item["mint_amount"] > 0
            ]
            + [
                {
                    "token": item["token"],
                    "raw": str(item["burn_amount"]),
                    "decimals": 18,
                }
                for item in summary["claims"]
                if item["burn_amount"] > 0
            ]
            + [
                {
                    "token": item["token"],
                    "raw": str(item["reward_amount"]),
                    "decimals": 18,
                }
                for item in summary["reward_mints"]
                if item["reward_amount"] > 0
            ]
        )
        first_contract = (
            summary["claims"][0]["contract_address"]
            if summary["claims"]
            else summary["reward_mints"][0]["contract_address"]
        )
        add_counterparty(counterparties, tx_to or first_contract, contract_map)
        for item in summary["claims"]:
            add_community(communities, item.get("token_address"), contract_map)
        for item in summary["reward_mints"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["group_joins"]:
        action = "加入 groupJoin"
        action_group = "groupJoin"
        action_id_text = stringify_numbers([item["action_id"] for item in summary["group_joins"]])
        group_id_text = stringify_numbers([item["group_id"] for item in summary["group_joins"]])
        description = f"加入 groupJoin，actionId={action_id_text}，groupId={group_id_text}"
        amounts = infer_group_amounts(summary, tx_to, contract_map)
        add_counterparty(counterparties, tx_to or summary["group_joins"][0]["contract_address"], contract_map)
        for item in summary["group_joins"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["group_exits"]:
        action = "退出 groupJoin"
        action_group = "groupJoin"
        action_id_text = stringify_numbers([item["action_id"] for item in summary["group_exits"]])
        group_id_text = stringify_numbers([item["group_id"] for item in summary["group_exits"]])
        description = f"退出 groupJoin，actionId={action_id_text}，groupId={group_id_text}"
        amounts = infer_exit_amounts(summary, tx_to, contract_map)
        add_counterparty(counterparties, tx_to or summary["group_exits"][0]["contract_address"], contract_map)
        for item in summary["group_exits"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["mints_in"] and has_non_lp(summary["transfers_out"]) and any(is_lp_token(item["token"]) for item in summary["mints_in"]):
        action = "加池 / LP 铸造"
        action_group = "liquidity"
        description = "把代币放入池子，收到 LP"
        amounts = collapse_amounts(
            [
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": 18}
                    for item in summary["transfers_out"]
                    if item["token"] != "LP"
                ],
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": 18}
                    for item in summary["mints_in"]
                    if is_lp_token(item["token"])
                ],
            ]
        )
        add_counterparty(counterparties, tx_to, contract_map)
    elif summary["approvals"] and not summary["transfers_in"] and not summary["transfers_out"] and not summary["mints_in"] and not summary["burns_out"]:
        action_group = "approval"
        if len(summary["approvals"]) == 1:
            approval = summary["approvals"][0]
            action = f"授权 {approval['token']}"
            description = f"授权 {approval['token']} 给 {describe_counterparty(approval['spender'], contract_map)}"
        else:
            action = "批量授权"
            description = f"同一笔交易里完成 {len(summary['approvals'])} 条授权"
        amounts = collapse_approvals(summary["approvals"])
        for item in summary["approvals"]:
            add_counterparty(counterparties, item["spender"], contract_map)
    elif summary["transfers_in"] and not summary["transfers_out"] and not summary["mints_in"]:
        single_token = len({item["token"] for item in summary["transfers_in"]}) == 1
        first_token = summary["transfers_in"][0]["token"]
        action = f"接收 {first_token}" if single_token and first_token.endswith("LP") else "转入"
        action_group = "transfer"
        description = f"从 {describe_counterparty(summary['transfers_in'][0]['counterparty'], contract_map)} 接收代币"
        amounts = collapse_amounts(
            [
                {
                    "token": item["token"],
                    "raw": str(item["raw"]),
                    "decimals": 18,
                }
                for item in summary["transfers_in"]
            ]
        )
        for item in summary["transfers_in"]:
            add_counterparty(counterparties, item["counterparty"], contract_map)
    elif summary["transfers_out"] and not summary["transfers_in"] and not summary["mints_in"]:
        single_token = len({item["token"] for item in summary["transfers_out"]}) == 1
        first_token = summary["transfers_out"][0]["token"]
        action = f"转出 {first_token}" if single_token and first_token.endswith("LP") else "转出"
        action_group = "transfer"
        description = f"转给 {describe_counterparty(summary['transfers_out'][0]['counterparty'], contract_map)}"
        amounts = collapse_amounts(
            [
                {
                    "token": item["token"],
                    "raw": str(item["raw"]),
                    "decimals": 18,
                }
                for item in summary["transfers_out"]
            ]
        )
        for item in summary["transfers_out"]:
            add_counterparty(counterparties, item["counterparty"], contract_map)
    elif summary["transfers_in"] and summary["transfers_out"]:
        action = "复杂代币交互"
        action_group = "complex"
        description = "同一笔交易里同时发生代币转入和转出"
        amounts = collapse_amounts(
            [
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": 18}
                    for item in summary["transfers_out"]
                ],
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": 18}
                    for item in summary["transfers_in"]
                ],
            ]
        )
        for item in summary["transfers_out"]:
            add_counterparty(counterparties, item["counterparty"], contract_map)
        for item in summary["transfers_in"]:
            add_counterparty(counterparties, item["counterparty"], contract_map)
    elif summary["native_out"] > 0:
        action = "原生币转账"
        action_group = "native"
        description = f"向 {describe_counterparty(tx_to, contract_map)} 转出原生币"
        amounts = [{"token": "原生币", "raw": str(summary["native_out"]), "decimals": 18}]
        add_counterparty(counterparties, tx_to, contract_map)
    elif summary["native_in"] > 0:
        action = "原生币转入"
        action_group = "native"
        description = f"从 {describe_counterparty(tx_from, contract_map)} 收到原生币"
        amounts = [{"token": "原生币", "raw": str(summary["native_in"]), "decimals": 18}]
        add_counterparty(counterparties, tx_from, contract_map)
    else:
        action = "未归类调用"
        action_group = "other"
        description = "这笔交易没有匹配到已归类的事件模式"
        add_counterparty(counterparties, tx_to, contract_map)

    return {
        "account": account,
        "block_number": int(tx_meta["block_number"]),
        "block_timestamp": int(tx_meta["block_timestamp"]),
        "tx_hash": tx_meta["tx_hash"],
        "tx_index": int(tx_meta.get("tx_index") or 0),
        "status": tx_meta.get("status"),
        "action": action,
        "action_group": action_group,
        "action_id_text": action_id_text,
        "group_id_text": group_id_text,
        "communities_json": json.dumps(unique_counterparties(communities), ensure_ascii=False),
        "amounts_json": json.dumps(amounts, ensure_ascii=False),
        "counterparties_json": json.dumps(unique_counterparties(counterparties), ensure_ascii=False),
        "description": description,
        "tx_from": tx_from,
        "tx_to": tx_to,
        "input_selector": (tx_meta.get("input") or "")[:10],
    }


def default_summary() -> dict:
    return {
        "claims": [],
        "reward_mints": [],
        "group_joins": [],
        "group_exits": [],
        "approvals": [],
        "transfers_in": [],
        "transfers_out": [],
        "mints_in": [],
        "burns_out": [],
        "native_in": 0,
        "native_out": 0,
    }


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA journal_mode = DELETE;
        PRAGMA synchronous = OFF;
        PRAGMA temp_store = MEMORY;

        CREATE TABLE tx_activity (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            account           TEXT NOT NULL,
            block_number      INTEGER NOT NULL,
            block_timestamp   INTEGER NOT NULL,
            tx_hash           TEXT NOT NULL,
            tx_index          INTEGER NOT NULL DEFAULT 0,
            status            INTEGER,
            action            TEXT NOT NULL,
            action_group      TEXT NOT NULL,
            action_id_text    TEXT,
            group_id_text     TEXT,
            communities_json  TEXT NOT NULL,
            amounts_json      TEXT NOT NULL,
            counterparties_json TEXT NOT NULL,
            description       TEXT NOT NULL,
            tx_from           TEXT,
            tx_to             TEXT,
            input_selector    TEXT,
            UNIQUE(account, tx_hash)
        );

        CREATE TABLE metadata (
            network           TEXT NOT NULL,
            source_db         TEXT NOT NULL,
            generated_at      TEXT NOT NULL,
            record_count      INTEGER NOT NULL
        );
        """
    )


def create_indexes(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE INDEX idx_tx_activity_account_block ON tx_activity(account, block_number, tx_index);
        CREATE INDEX idx_tx_activity_action_group ON tx_activity(action_group);
        """
    )


def flush_rows(dest: sqlite3.Connection, rows: list[dict]) -> int:
    if not rows:
        return 0
    dest.executemany(
        """
        INSERT OR IGNORE INTO tx_activity (
            account,
            block_number,
            block_timestamp,
            tx_hash,
            tx_index,
            status,
            action,
            action_group,
            action_id_text,
            group_id_text,
            communities_json,
            amounts_json,
            counterparties_json,
            description,
            tx_from,
            tx_to,
            input_selector
        ) VALUES (
            :account,
            :block_number,
            :block_timestamp,
            :tx_hash,
            :tx_index,
            :status,
            :action,
            :action_group,
            :action_id_text,
            :group_id_text,
            :communities_json,
            :amounts_json,
            :counterparties_json,
            :description,
            :tx_from,
            :tx_to,
            :input_selector
        )
        """,
        rows,
    )
    count = len(rows)
    rows.clear()
    return count


def process_event_stream(
    source: sqlite3.Connection,
    dest: sqlite3.Connection,
    contract_map: dict[str, str],
) -> int:
    relevant_count = source.execute(
        """
        SELECT COUNT(*)
        FROM events
        WHERE event_name IN ('Transfer', 'Approval', 'ClaimReward', 'MintActionReward', 'MintGovReward')
           OR (contract_name = 'groupJoin' AND event_name IN ('Join', 'Exit'))
        """
    ).fetchone()[0]
    print(f"Relevant events: {relevant_count}")

    query = """
        SELECT
            e.block_number,
            b.timestamp AS block_timestamp,
            e.tx_hash,
            COALESCE(e.tx_index, t.tx_index, 0) AS tx_index,
            e.log_index,
            e.contract_name,
            e.event_name,
            e.address,
            e.decoded_data,
            t."from" AS tx_from,
            t."to" AS tx_to,
            t.status,
            t.value_wei,
            t.input
        FROM events e
        JOIN blocks b ON b.block_number = e.block_number
        LEFT JOIN transactions t ON t.tx_hash = e.tx_hash
        WHERE e.event_name IN ('Transfer', 'Approval', 'ClaimReward', 'MintActionReward', 'MintGovReward')
           OR (e.contract_name = 'groupJoin' AND e.event_name IN ('Join', 'Exit'))
        ORDER BY e.block_number, COALESCE(e.tx_index, t.tx_index, 0), e.log_index, e.id
    """

    cursor = source.execute(query)
    current_key: tuple[int, str] | None = None
    current_meta: dict | None = None
    summaries: defaultdict[str, dict] = defaultdict(default_summary)
    buffer: list[dict] = []
    inserted = 0
    processed = 0

    def flush_tx() -> None:
        nonlocal inserted, summaries, current_meta
        if not current_meta:
            return

        tx_from = normalize_address(current_meta.get("tx_from"))
        tx_to = normalize_address(current_meta.get("tx_to"))
        value_raw = int(current_meta.get("value_wei") or 0)
        if value_raw > 0:
            if tx_from:
                summaries[tx_from]["native_out"] += value_raw
            if tx_to:
                summaries[tx_to]["native_in"] += value_raw

        for account, summary in summaries.items():
            if not account or is_zero_address(account):
                continue
            buffer.append(build_row(account, summary, current_meta, contract_map))
            if len(buffer) >= 1000:
                inserted += flush_rows(dest, buffer)

        summaries = defaultdict(default_summary)

    for row in cursor:
        processed += 1
        key = (int(row["block_number"]), row["tx_hash"])
        if current_key and key != current_key:
            flush_tx()
        if key != current_key:
            current_key = key
            current_meta = {
                "block_number": int(row["block_number"]),
                "block_timestamp": int(row["block_timestamp"]),
                "tx_hash": row["tx_hash"],
                "tx_index": int(row["tx_index"] or 0),
                "tx_from": row["tx_from"],
                "tx_to": row["tx_to"],
                "status": row["status"],
                "value_wei": row["value_wei"],
                "input": row["input"] or "",
            }

        payload = json.loads(row["decoded_data"])
        contract_name = row["contract_name"]
        event_name = row["event_name"]
        contract_address = normalize_address(row["address"])

        if event_name == "ClaimReward":
            account = normalize_address(payload.get("account"))
            if not account:
                continue
            token_address = normalize_address(payload.get("tokenAddress"))
            token_name = token_label(contract_map.get(token_address, payload.get("tokenAddress")))
            summaries[account]["claims"].append(
                {
                    "contract_name": contract_name,
                    "contract_address": contract_address,
                    "action_id": int(payload.get("actionId") or 0),
                    "token": token_name,
                    "token_address": token_address,
                    "mint_amount": int(payload.get("mintAmount") or 0),
                    "burn_amount": int(payload.get("burnAmount") or 0),
                }
            )
        elif event_name == "MintActionReward":
            account = normalize_address(payload.get("account"))
            if not account:
                continue
            token_address = normalize_address(payload.get("tokenAddress"))
            token_name = token_label(contract_map.get(token_address, payload.get("tokenAddress")))
            summaries[account]["reward_mints"].append(
                {
                    "kind": event_name,
                    "contract_address": contract_address,
                    "action_id": int(payload.get("actionId") or 0),
                    "round": int(payload.get("round") or 0),
                    "token": token_name,
                    "token_address": token_address,
                    "reward_amount": int(payload.get("reward") or 0),
                }
            )
        elif event_name == "MintGovReward":
            account = normalize_address(payload.get("account"))
            if not account:
                continue
            token_address = normalize_address(payload.get("tokenAddress"))
            token_name = token_label(contract_map.get(token_address, payload.get("tokenAddress")))
            reward_total = int(payload.get("verifyReward") or 0) + int(payload.get("boostReward") or 0) + int(payload.get("burnReward") or 0)
            summaries[account]["reward_mints"].append(
                {
                    "kind": event_name,
                    "contract_address": contract_address,
                    "action_id": 0,
                    "round": int(payload.get("round") or 0),
                    "token": token_name,
                    "token_address": token_address,
                    "reward_amount": reward_total,
                }
            )
        elif event_name == "Approval":
            owner = normalize_address(payload.get("owner"))
            spender = normalize_address(payload.get("spender"))
            if not owner:
                continue
            summaries[owner]["approvals"].append(
                {
                    "token": token_label(contract_name),
                    "spender": spender,
                    "raw": int(payload.get("value") or 0),
                    "contract_address": contract_address,
                }
            )
        elif event_name == "Transfer":
            from_address = normalize_address(payload.get("from"))
            to_address = normalize_address(payload.get("to"))
            value = int(payload.get("value") or 0)
            token = token_label(contract_name)
            if is_zero_address(from_address):
                if to_address:
                    summaries[to_address]["mints_in"].append(
                        {
                            "token": token,
                            "raw": value,
                            "counterparty": from_address,
                            "contract_address": contract_address,
                        }
                    )
            elif is_zero_address(to_address):
                if from_address:
                    summaries[from_address]["burns_out"].append(
                        {
                            "token": token,
                            "raw": value,
                            "counterparty": to_address,
                            "contract_address": contract_address,
                        }
                    )
            else:
                summaries[from_address]["transfers_out"].append(
                    {
                        "token": token,
                        "raw": value,
                        "counterparty": to_address,
                        "contract_address": contract_address,
                    }
                )
                summaries[to_address]["transfers_in"].append(
                    {
                        "token": token,
                        "raw": value,
                        "counterparty": from_address,
                        "contract_address": contract_address,
                    }
                )
        elif event_name in {"Join", "Exit"} and contract_name == "groupJoin":
            account = normalize_address(payload.get("account"))
            if not account:
                continue
            entry = {
                "contract_address": contract_address,
                "token_address": normalize_address(payload.get("tokenAddress")),
                "action_id": int(payload.get("actionId") or 0),
                "group_id": int(payload.get("groupId") or 0),
                "amount": int(payload.get("amount") or 0),
            }
            key_name = "group_joins" if event_name == "Join" else "group_exits"
            summaries[account][key_name].append(entry)

        if processed % 100000 == 0:
            print(f"Processed events: {processed}/{relevant_count}")

    flush_tx()
    inserted += flush_rows(dest, buffer)
    print(f"Inserted rows from event summaries: {inserted}")
    return inserted


def process_native_only_transactions(
    source: sqlite3.Connection,
    dest: sqlite3.Connection,
    contract_map: dict[str, str],
) -> int:
    query = """
        SELECT
            block_number,
            block_timestamp,
            tx_hash,
            COALESCE(tx_index, 0) AS tx_index,
            "from" AS tx_from,
            "to" AS tx_to,
            status,
            value_wei,
            input
        FROM transactions
        WHERE CAST(value_wei AS TEXT) != '0'
        ORDER BY block_number, COALESCE(tx_index, 0)
    """

    inserted = 0
    rows: list[dict] = []
    for row in source.execute(query):
        tx_meta = {
            "block_number": int(row["block_number"]),
            "block_timestamp": int(row["block_timestamp"] or 0),
            "tx_hash": row["tx_hash"],
            "tx_index": int(row["tx_index"] or 0),
            "tx_from": row["tx_from"],
            "tx_to": row["tx_to"],
            "status": row["status"],
            "input": row["input"] or "",
        }
        value_raw = int(row["value_wei"] or 0)

        sender = normalize_address(row["tx_from"])
        receiver = normalize_address(row["tx_to"])

        if sender:
            rows.append(
                {
                    "account": sender,
                    "block_number": tx_meta["block_number"],
                    "block_timestamp": tx_meta["block_timestamp"],
                    "tx_hash": tx_meta["tx_hash"],
                    "tx_index": tx_meta["tx_index"],
                    "status": tx_meta["status"],
                    "action": "原生币转账",
                    "action_group": "native",
                    "action_id_text": "",
                    "group_id_text": "",
                    "communities_json": "[]",
                    "amounts_json": json.dumps([{"token": "原生币", "raw": str(value_raw), "decimals": 18}], ensure_ascii=False),
                    "counterparties_json": json.dumps(unique_counterparties([{"address": receiver, "label": contract_map.get(receiver, "")}]), ensure_ascii=False),
                    "description": f"向 {describe_counterparty(receiver, contract_map)} 转出原生币",
                    "tx_from": sender,
                    "tx_to": receiver,
                    "input_selector": (tx_meta["input"] or "")[:10],
                }
            )
        if receiver:
            rows.append(
                {
                    "account": receiver,
                    "block_number": tx_meta["block_number"],
                    "block_timestamp": tx_meta["block_timestamp"],
                    "tx_hash": tx_meta["tx_hash"],
                    "tx_index": tx_meta["tx_index"],
                    "status": tx_meta["status"],
                    "action": "原生币转入",
                    "action_group": "native",
                    "action_id_text": "",
                    "group_id_text": "",
                    "communities_json": "[]",
                    "amounts_json": json.dumps([{"token": "原生币", "raw": str(value_raw), "decimals": 18}], ensure_ascii=False),
                    "counterparties_json": json.dumps(unique_counterparties([{"address": sender, "label": contract_map.get(sender, "")}]), ensure_ascii=False),
                    "description": f"从 {describe_counterparty(sender, contract_map)} 收到原生币",
                    "tx_from": sender,
                    "tx_to": receiver,
                    "input_selector": (tx_meta["input"] or "")[:10],
                }
            )

        if len(rows) >= 1000:
            inserted += flush_rows(dest, rows)

    inserted += flush_rows(dest, rows)
    print(f"Inserted rows from native transfers: {inserted}")
    return inserted


def write_metadata(dest: sqlite3.Connection, network: str, source_db: str) -> None:
    record_count = dest.execute("SELECT COUNT(*) FROM tx_activity").fetchone()[0]
    dest.execute(
        """
        INSERT INTO metadata (network, source_db, generated_at, record_count)
        VALUES (?, ?, ?, ?)
        """,
        (network, source_db, now_iso(), record_count),
    )


def main() -> None:
    args = parse_args()
    source_path = Path(args.source_db).expanduser().resolve()
    output_path = Path(args.output_db).expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    source = sqlite3.connect(source_path)
    source.row_factory = sqlite3.Row
    dest = sqlite3.connect(output_path)
    dest.row_factory = sqlite3.Row

    try:
        create_schema(dest)
        contract_map = load_contract_map(source)
        process_event_stream(source, dest, contract_map)
        process_native_only_transactions(source, dest, contract_map)
        create_indexes(dest)
        write_metadata(dest, args.network, str(source_path))
        dest.commit()
        print(f"Wrote dashboard db: {output_path}")
    finally:
        source.close()
        dest.close()


if __name__ == "__main__":
    main()
