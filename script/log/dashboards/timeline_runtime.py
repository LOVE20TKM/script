#!/usr/bin/env python3
import json
import sqlite3
from collections import OrderedDict, defaultdict
from datetime import datetime, timezone


ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
PAIR_CONTRACTS = {
    "love20tusdtpair",
    "love20tkm20pair",
    "love20life20pair",
    "life20tusdtpair",
}
PAIR_LABELS = {
    "love20tusdtpair": "LOVE20/TUSDT LP",
    "love20tkm20pair": "LOVE20/TKM20 LP",
    "love20life20pair": "LOVE20/LIFE20 LP",
    "life20tusdtpair": "LIFE20/TUSDT LP",
}
ROUTER_LABEL = "uniswapV2Router02"
ROUTER_SELECTORS = {
    "0x38ed1739": "swapExactTokensForTokens",
    "0x18cbafe5": "swapExactTokensForETH",
    "0x7ff36ab5": "swapExactETHForTokens",
    "0xe8e33700": "addLiquidity",
    "0xbaa2abde": "removeLiquidity",
}
RELEVANT_EVENT_NAMES = (
    "Transfer",
    "Approval",
    "ClaimReward",
    "MintActionReward",
    "MintGovReward",
    "Join",
    "Exit",
    "Withdraw",
    "Withdrawal",
    "SubmitOriginScores",
)
RELEVANT_EVENT_NAMES_SQL = ", ".join(f"'{name}'" for name in RELEVANT_EVENT_NAMES)
TIMELINE_INDEX_DEFINITIONS = (
    (
        "idx_events_event_account_expr",
        "CREATE INDEX IF NOT EXISTS idx_events_event_account_expr "
        "ON events(event_name, lower(json_extract(decoded_data, '$.account')))",
    ),
    (
        "idx_events_event_from_expr",
        "CREATE INDEX IF NOT EXISTS idx_events_event_from_expr "
        "ON events(event_name, lower(json_extract(decoded_data, '$.from')))",
    ),
    (
        "idx_events_event_to_expr",
        "CREATE INDEX IF NOT EXISTS idx_events_event_to_expr "
        "ON events(event_name, lower(json_extract(decoded_data, '$.to')))",
    ),
    (
        "idx_events_event_src_expr",
        "CREATE INDEX IF NOT EXISTS idx_events_event_src_expr "
        "ON events(event_name, lower(json_extract(decoded_data, '$.src')))",
    ),
    (
        "idx_events_event_dst_expr",
        "CREATE INDEX IF NOT EXISTS idx_events_event_dst_expr "
        "ON events(event_name, lower(json_extract(decoded_data, '$.dst')))",
    ),
)


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


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


def load_contract_map(conn: sqlite3.Connection) -> dict[str, str]:
    rows = conn.execute("SELECT lower(address) AS address, contract_name FROM v_contract").fetchall()
    return {row["address"]: row["contract_name"] for row in rows}


def is_known_contract(address: str | None, contract_map: dict[str, str]) -> bool:
    return normalize_address(address) in contract_map


def add_counterparty(
    items: list[dict],
    address: str | None,
    contract_map: dict[str, str],
    *,
    skip_address: str | None = None,
    known_only: bool = False,
) -> None:
    normalized = normalize_address(address)
    if not normalized or normalized == normalize_address(skip_address):
        return
    label = contract_map.get(normalized, "")
    if known_only and not label:
        return
    items.append({"address": normalized, "label": label})


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
        collapsed.append({"token": token, "raw": str(raw), "decimals": decimals})
    return collapsed


def collapse_approvals(items: list[dict]) -> list[dict]:
    latest: OrderedDict[tuple[str, str], dict] = OrderedDict()
    for item in items:
        latest[(item["token"], item["spender"])] = item
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
    return label or short_address(normalized)


def is_sl_token_label(label: str | None) -> bool:
    return bool(label) and str(label).lower().endswith("sltoken")


def transfer_amounts(items: list[dict]) -> list[dict]:
    return collapse_amounts(
        [
            {
                "token": item["token"],
                "raw": str(item["raw"]),
                "decimals": int(item.get("decimals", 18)),
            }
            for item in items
        ]
    )


def amount_item(token: str, raw: int | str, decimals: int = 18) -> dict:
    return {"token": token, "raw": str(raw), "decimals": decimals}


def selector_name(input_selector: str | None) -> str:
    return ROUTER_SELECTORS.get((input_selector or "").lower(), "")


def is_router_address(address: str | None, contract_map: dict[str, str]) -> bool:
    return contract_map.get(normalize_address(address)) == ROUTER_LABEL


def first_token_name(items: list[dict], fallback: str = "Token") -> str:
    for item in items:
        token = str(item.get("token") or "").strip()
        if token:
            return token
    return fallback


def is_lp_token(token: str | None) -> bool:
    return bool(token) and str(token).endswith("LP")


def pair_counterparties(items: list[dict], contract_map: dict[str, str]) -> list[str]:
    pairs: list[str] = []
    for item in items:
        counterparty = normalize_address(item.get("counterparty"))
        label = contract_map.get(counterparty, "")
        if is_lp_token(token_label(label)) or (label and label.lower().endswith("pair")):
            pairs.append(counterparty)
    return list(dict.fromkeys(pairs))


def failed_router_action(selector: str, *, for_router: bool) -> tuple[str, str]:
    if selector == "swapExactETHForTokens":
        return ("Router 买入失败", "收到失败的原生币买币调用") if for_router else ("买入代币失败", f"向 {ROUTER_LABEL} 发送原生币买币，但调用失败")
    if selector == "swapExactTokensForETH":
        return ("Router 卖出失败", "收到失败的卖币出金调用") if for_router else ("卖出代币失败", f"向 {ROUTER_LABEL} 发起卖币出金，但调用失败")
    if selector == "swapExactTokensForTokens":
        return ("Router 换币失败", "收到失败的换币调用") if for_router else ("兑换代币失败", f"通过 {ROUTER_LABEL} 换币，但调用失败")
    if selector == "addLiquidity":
        return ("Router 加池失败", "收到失败的加池调用") if for_router else ("加池失败", f"通过 {ROUTER_LABEL} 加池，但调用失败")
    if selector == "removeLiquidity":
        return ("Router 撤池失败", "收到失败的撤池调用") if for_router else ("撤池失败", f"通过 {ROUTER_LABEL} 撤池，但调用失败")
    return ("Router 调用失败", "收到失败的路由调用") if for_router else ("路由调用失败", f"调用 {ROUTER_LABEL} 失败")


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


def join_event_amounts(items: list[dict], contract_map: dict[str, str]) -> list[dict]:
    return collapse_amounts(
        [
            {
                "token": token_label(contract_map.get(item.get("token_address", ""), item.get("token_address"))),
                "raw": str(item["amount"]),
                "decimals": 18,
            }
            for item in items
            if int(item.get("amount") or 0) > 0
        ]
    )


def infer_action_join_amounts(summary: dict, tx_to: str, contract_map: dict[str, str]) -> list[dict]:
    outgoing = group_transfer_items(summary["transfers_out"], counterparty=tx_to)
    if outgoing:
        return outgoing
    tokens = {
        token_label(contract_map.get(normalize_address(item.get("token_address")), item.get("token_address")))
        for item in summary["action_joins"]
        if item.get("token_address")
    }
    token_matched = collapse_amounts(
        [
            {
                "token": item["token"],
                "raw": str(item["raw"]),
                "decimals": int(item.get("decimals", 18)),
            }
            for item in summary["transfers_out"]
            if item["token"] in tokens
        ]
    )
    if token_matched:
        return token_matched
    return join_event_amounts(summary["action_joins"], contract_map)


def infer_action_exit_amounts(summary: dict, tx_to: str, contract_map: dict[str, str]) -> list[dict]:
    incoming = group_transfer_items(summary["transfers_in"], counterparty=tx_to)
    if incoming:
        return incoming
    tokens = {
        token_label(contract_map.get(normalize_address(item.get("token_address")), item.get("token_address")))
        for item in summary["action_exits"]
        if item.get("token_address")
    }
    token_matched = collapse_amounts(
        [
            {
                "token": item["token"],
                "raw": str(item["raw"]),
                "decimals": int(item.get("decimals", 18)),
            }
            for item in summary["transfers_in"]
            if item["token"] in tokens
        ]
    )
    if token_matched:
        return token_matched
    return join_event_amounts(summary["action_exits"], contract_map)


def has_non_lp(items: list[dict]) -> bool:
    return any(not is_lp_token(item["token"]) for item in items)


def has_token_activity(summary: dict) -> bool:
    return any(
        summary[key]
        for key in (
            "claims",
            "reward_mints",
            "group_joins",
            "group_exits",
            "action_joins",
            "action_exits",
            "group_verify_submissions",
            "approvals",
            "transfers_in",
            "transfers_out",
            "mints_in",
            "burns_out",
            "native_in",
            "native_out",
        )
    )


def action_membership_key(account: str, item: dict) -> tuple[str, str, str, int]:
    return (
        normalize_address(account),
        normalize_address(item.get("contract_address")),
        normalize_address(item.get("token_address")),
        int(item.get("action_id") or 0),
    )


def group_membership_key(account: str, item: dict) -> tuple[str, str, str, int, int]:
    return (
        normalize_address(account),
        normalize_address(item.get("contract_address")),
        normalize_address(item.get("token_address")),
        int(item.get("action_id") or 0),
        int(item.get("group_id") or 0),
    )


def parse_transfer_payload(payload: dict, contract_name: str, contract_map: dict[str, str]) -> dict | None:
    from_address = normalize_address(payload.get("from") or payload.get("_from") or payload.get("src"))
    to_address = normalize_address(payload.get("to") or payload.get("_to") or payload.get("dst"))

    if payload.get("_tokenId") is not None:
        token_id = int(payload.get("_tokenId") or 0)
        return {
            "from_address": from_address,
            "to_address": to_address,
            "token": f"{token_label(contract_name)} #{token_id}",
            "raw": 1,
            "decimals": 0,
        }

    value = payload.get("value")
    if value is None:
        value = payload.get("wad")
    if value is None:
        return None

    return {
        "from_address": from_address,
        "to_address": to_address,
        "token": token_label(contract_name),
        "raw": int(value or 0),
        "decimals": 18,
    }


def build_row(account: str, summary: dict, tx_meta: dict, contract_map: dict[str, str]) -> dict:
    account_address = normalize_address(account)
    tx_to = normalize_address(tx_meta.get("tx_to"))
    tx_from = normalize_address(tx_meta.get("tx_from"))
    input_selector = (tx_meta.get("input") or "")[:10]
    selector = selector_name(input_selector)
    tx_to_is_router = is_router_address(tx_to, contract_map)
    account_is_router = contract_map.get(account_address) == ROUTER_LABEL

    action = ""
    action_group = "other"
    action_id_text = ""
    group_id_text = ""
    description = ""
    amounts: list[dict] = []
    counterparties: list[dict] = []
    communities: list[dict] = []

    if account_is_router and selector == "swapExactTokensForETH" and summary["transfers_in"]:
        action = "Router 卖出代币"
        action_group = "swap"
        received_token = first_token_name(summary["transfers_in"])
        description = f"{ROUTER_LABEL} 从池子收回 {received_token} 并继续出金"
        amounts = collapse_amounts(
            [
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_in"]],
                *([amount_item("原生币", summary["native_out"], 18)] if summary["native_out"] > 0 else []),
            ]
        )
        for pair_address in pair_counterparties(summary["transfers_in"], contract_map):
            add_counterparty(counterparties, pair_address, contract_map, skip_address=account_address)
        add_counterparty(counterparties, tx_from, contract_map, skip_address=account_address)
    elif account_is_router and selector == "swapExactETHForTokens" and summary["transfers_out"]:
        action = "Router 买入代币"
        action_group = "swap"
        paid_token = first_token_name(summary["transfers_out"])
        description = f"{ROUTER_LABEL} 把原生币换成 {paid_token} 并送入池子"
        amounts = collapse_amounts(
            [
                amount_item("原生币", int(tx_meta.get("value_wei") or 0), 18),
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_out"]],
            ]
        )
        for pair_address in pair_counterparties(summary["transfers_out"], contract_map):
            add_counterparty(counterparties, pair_address, contract_map, skip_address=account_address)
        add_counterparty(counterparties, tx_from, contract_map, skip_address=account_address)
    elif tx_to_is_router and selector == "swapExactTokensForTokens" and summary["transfers_in"] and summary["transfers_out"]:
        action = "兑换代币"
        action_group = "swap"
        sold_token = first_token_name(summary["transfers_out"])
        bought_token = first_token_name(summary["transfers_in"])
        description = f"通过 {ROUTER_LABEL} 把 {sold_token} 换成 {bought_token}"
        amounts = collapse_amounts(
            [
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_out"]],
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_in"]],
            ]
        )
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
        for pair_address in pair_counterparties([*summary["transfers_out"], *summary["transfers_in"]], contract_map):
            add_counterparty(counterparties, pair_address, contract_map, skip_address=account_address)
    elif tx_to_is_router and selector == "swapExactTokensForETH" and summary["transfers_out"]:
        action = "卖出代币"
        action_group = "swap"
        sold_token = first_token_name(summary["transfers_out"])
        description = f"通过 {ROUTER_LABEL} 卖出 {sold_token} 换原生币"
        amounts = collapse_amounts(
            [
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_out"]],
                *([amount_item("原生币", summary["native_in"], 18)] if account_address == tx_from and summary["native_in"] > 0 else []),
            ]
        )
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
        for pair_address in pair_counterparties(summary["transfers_out"], contract_map):
            add_counterparty(counterparties, pair_address, contract_map, skip_address=account_address)
    elif tx_to_is_router and selector == "swapExactETHForTokens" and (summary["transfers_in"] or int(tx_meta.get("value_wei") or 0) > 0):
        action = "买入代币"
        action_group = "swap"
        bought_token = first_token_name(summary["transfers_in"])
        description = f"通过 {ROUTER_LABEL} 用原生币买入 {bought_token}"
        amounts = collapse_amounts(
            [
                amount_item("原生币", int(tx_meta.get("value_wei") or 0), 18),
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_in"]],
            ]
        )
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
        for pair_address in pair_counterparties(summary["transfers_in"], contract_map):
            add_counterparty(counterparties, pair_address, contract_map, skip_address=account_address)
    elif tx_to_is_router and selector == "removeLiquidity" and summary["transfers_out"] and summary["transfers_in"] and any(is_lp_token(item["token"]) for item in summary["transfers_out"]):
        action = "撤池"
        action_group = "liquidity"
        lp_token = first_token_name([item for item in summary["transfers_out"] if is_lp_token(item["token"])], "LP")
        description = f"通过 {ROUTER_LABEL} 销毁 {lp_token} 取回底层资产"
        amounts = collapse_amounts(
            [
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_out"]],
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_in"]],
            ]
        )
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
        for pair_address in pair_counterparties([*summary["transfers_out"], *summary["transfers_in"]], contract_map):
            add_counterparty(counterparties, pair_address, contract_map, skip_address=account_address)
    elif tx_to_is_router and selector == "removeLiquidity" and summary["burns_out"] and summary["transfers_in"]:
        action = "撤池"
        action_group = "liquidity"
        lp_token = first_token_name(summary["burns_out"], "LP")
        description = f"通过 {ROUTER_LABEL} 销毁 {lp_token} 取回底层资产"
        amounts = collapse_amounts(
            [
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["burns_out"]],
                *[amount_item(item["token"], item["raw"], int(item.get("decimals", 18))) for item in summary["transfers_in"]],
            ]
        )
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
        for pair_address in pair_counterparties([*summary["burns_out"], *summary["transfers_in"]], contract_map):
            add_counterparty(counterparties, pair_address, contract_map, skip_address=account_address)
    elif summary["claims"] or summary["reward_mints"]:
        action_group = "reward"
        action_ids = [item["action_id"] for item in summary["claims"] if item.get("action_id")] + [
            item["action_id"] for item in summary["reward_mints"] if item.get("action_id")
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
                {"token": item["token"], "raw": str(item["mint_amount"]), "decimals": 18}
                for item in summary["claims"]
                if item["mint_amount"] > 0
            ]
            + [
                {"token": item["token"], "raw": str(item["burn_amount"]), "decimals": 18}
                for item in summary["claims"]
                if item["burn_amount"] > 0
            ]
            + [
                {"token": item["token"], "raw": str(item["reward_amount"]), "decimals": 18}
                for item in summary["reward_mints"]
                if item["reward_amount"] > 0
            ]
        )
        first_contract = summary["claims"][0]["contract_address"] if summary["claims"] else summary["reward_mints"][0]["contract_address"]
        add_counterparty(counterparties, tx_to or first_contract, contract_map, skip_address=account_address)
        for item in summary["claims"]:
            add_community(communities, item.get("token_address"), contract_map)
        for item in summary["reward_mints"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["group_joins"]:
        is_additional = any(item.get("is_additional") for item in summary["group_joins"])
        action = "追加行动代币" if is_additional else "参与行动"
        action_group = "actionJoin"
        action_id_text = stringify_numbers([item["action_id"] for item in summary["group_joins"]])
        group_id_text = stringify_numbers([item["group_id"] for item in summary["group_joins"]])
        description = f"{action}，actionId={action_id_text}"
        amounts = infer_group_amounts(summary, tx_to, contract_map)
        add_counterparty(counterparties, tx_to or summary["group_joins"][0]["contract_address"], contract_map, skip_address=account_address)
        for item in summary["group_joins"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["group_exits"]:
        action = "退出行动"
        action_group = "actionJoin"
        action_id_text = stringify_numbers([item["action_id"] for item in summary["group_exits"]])
        group_id_text = stringify_numbers([item["group_id"] for item in summary["group_exits"]])
        description = f"退出行动，actionId={action_id_text}"
        amounts = infer_exit_amounts(summary, tx_to, contract_map)
        add_counterparty(counterparties, tx_to or summary["group_exits"][0]["contract_address"], contract_map, skip_address=account_address)
        for item in summary["group_exits"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["action_joins"]:
        is_additional = any(item.get("is_additional") for item in summary["action_joins"])
        action = "追加行动代币" if is_additional else "参与行动"
        action_group = "actionJoin"
        action_id_text = stringify_numbers([item["action_id"] for item in summary["action_joins"]])
        description = f"{action}，actionId={action_id_text}"
        amounts = infer_action_join_amounts(summary, tx_to, contract_map)
        add_counterparty(counterparties, tx_to or summary["action_joins"][0]["contract_address"], contract_map, skip_address=account_address)
        for item in summary["action_joins"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["action_exits"]:
        action = "退出行动"
        action_group = "actionJoin"
        action_id_text = stringify_numbers([item["action_id"] for item in summary["action_exits"]])
        description = f"退出行动，actionId={action_id_text}"
        amounts = infer_action_exit_amounts(summary, tx_to, contract_map)
        add_counterparty(counterparties, tx_to or summary["action_exits"][0]["contract_address"], contract_map, skip_address=account_address)
        for item in summary["action_exits"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["group_verify_submissions"]:
        action = "提交 groupVerify 评分"
        action_group = "verify"
        action_id_text = stringify_numbers([item["action_id"] for item in summary["group_verify_submissions"]])
        group_id_text = stringify_numbers([item["group_id"] for item in summary["group_verify_submissions"]])
        total_count = sum(int(item["count"]) for item in summary["group_verify_submissions"])
        description = f"向 groupVerify 提交原始评分，actionId={action_id_text}，groupId={group_id_text}，共 {total_count} 条"
        add_counterparty(counterparties, tx_to or summary["group_verify_submissions"][0]["contract_address"], contract_map, skip_address=account_address)
        for item in summary["group_verify_submissions"]:
            add_community(communities, item.get("token_address"), contract_map)
    elif summary["mints_in"] and has_non_lp(summary["transfers_out"]) and any(is_sl_token_label(item["token"]) for item in summary["mints_in"]):
        sl_mints = [item for item in summary["mints_in"] if is_sl_token_label(item["token"])]
        action = "质押流动性"
        action_group = "liquidity"
        first_sl_token = sl_mints[0]["token"]
        description = f"通过 hub 质押流动性，收到 {first_sl_token}" if contract_map.get(tx_to) == "hub" else f"质押流动性，收到 {first_sl_token}"
        amounts = collapse_amounts(
            [
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                    for item in summary["transfers_out"]
                    if not is_sl_token_label(item["token"])
                ],
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                    for item in sl_mints
                ],
            ]
        )
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
        for item in sl_mints:
            add_counterparty(counterparties, item.get("contract_address"), contract_map, skip_address=account_address)
    elif summary["mints_in"] and has_non_lp(summary["transfers_out"]) and any(is_lp_token(item["token"]) for item in summary["mints_in"]):
        action = "加池 / LP 铸造"
        action_group = "liquidity"
        description = f"通过 {ROUTER_LABEL} 把代币放入池子，收到 LP" if tx_to_is_router and selector == "addLiquidity" else "把代币放入池子，收到 LP"
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
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
    elif contract_map.get(account_address) == "hub" and summary["transfers_in"] and summary["transfers_out"]:
        sl_targets = [
            item["counterparty"]
            for item in summary["transfers_out"]
            if is_sl_token_label(contract_map.get(normalize_address(item.get("counterparty"))))
        ]
        if sl_targets:
            action = "Hub 中转质押"
            action_group = "liquidity"
            description = f"hub 收到用户代币后转给 {describe_counterparty(sl_targets[0], contract_map)}"
            amounts = transfer_amounts(
                [
                    item
                    for item in summary["transfers_out"]
                    if normalize_address(item.get("counterparty")) in {normalize_address(addr) for addr in sl_targets}
                ]
            )
            for item in summary["transfers_in"]:
                add_counterparty(counterparties, item["counterparty"], contract_map, skip_address=account_address)
            for counterparty in sl_targets:
                add_counterparty(counterparties, counterparty, contract_map, skip_address=account_address)
        else:
            action = "复杂代币交互"
            action_group = "complex"
            description = "同一笔交易里同时发生代币转入和转出"
            add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address, known_only=True)
            amounts = collapse_amounts(
                [
                    *[
                        {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                        for item in summary["transfers_out"]
                    ],
                    *[
                        {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                        for item in summary["transfers_in"]
                    ],
                ]
            )
            for item in summary["transfers_out"]:
                add_counterparty(counterparties, item["counterparty"], contract_map, skip_address=account_address)
            for item in summary["transfers_in"]:
                add_counterparty(counterparties, item["counterparty"], contract_map, skip_address=account_address)
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
            add_counterparty(counterparties, item["spender"], contract_map, skip_address=account_address)
    elif summary["transfers_in"] and not summary["transfers_out"] and not summary["mints_in"]:
        single_token = len({item["token"] for item in summary["transfers_in"]}) == 1
        first_token = summary["transfers_in"][0]["token"]
        action = f"接收 {first_token}" if single_token and first_token.endswith("LP") else "转入"
        action_group = "transfer"
        description = f"从 {describe_counterparty(summary['transfers_in'][0]['counterparty'], contract_map)} 接收代币"
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address, known_only=True)
        amounts = collapse_amounts(
            [
                {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                for item in summary["transfers_in"]
            ]
        )
        for item in summary["transfers_in"]:
            add_counterparty(counterparties, item["counterparty"], contract_map, skip_address=account_address)
    elif summary["transfers_out"] and not summary["transfers_in"] and not summary["mints_in"]:
        single_token = len({item["token"] for item in summary["transfers_out"]}) == 1
        first_token = summary["transfers_out"][0]["token"]
        action = f"转出 {first_token}" if single_token and first_token.endswith("LP") else "转出"
        action_group = "transfer"
        description = f"转给 {describe_counterparty(summary['transfers_out'][0]['counterparty'], contract_map)}"
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address, known_only=True)
        amounts = collapse_amounts(
            [
                {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                for item in summary["transfers_out"]
            ]
        )
        for item in summary["transfers_out"]:
            add_counterparty(counterparties, item["counterparty"], contract_map, skip_address=account_address)
    elif summary["transfers_in"] and summary["transfers_out"]:
        action = "复杂代币交互"
        action_group = "complex"
        description = "同一笔交易里同时发生代币转入和转出"
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address, known_only=True)
        amounts = collapse_amounts(
            [
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                    for item in summary["transfers_out"]
                ],
                *[
                    {"token": item["token"], "raw": str(item["raw"]), "decimals": int(item.get("decimals", 18))}
                    for item in summary["transfers_in"]
                ],
            ]
        )
        for item in summary["transfers_out"]:
            add_counterparty(counterparties, item["counterparty"], contract_map, skip_address=account_address)
        for item in summary["transfers_in"]:
            add_counterparty(counterparties, item["counterparty"], contract_map, skip_address=account_address)
    elif summary["native_out"] > 0:
        action = "原生币转账"
        action_group = "native"
        description = f"向 {describe_counterparty(tx_to, contract_map)} 转出原生币"
        amounts = [{"token": "原生币", "raw": str(summary["native_out"]), "decimals": 18}]
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)
    elif summary["native_in"] > 0:
        action = "原生币转入"
        action_group = "native"
        description = f"从 {describe_counterparty(tx_from, contract_map)} 收到原生币"
        amounts = [{"token": "原生币", "raw": str(summary["native_in"]), "decimals": 18}]
        add_counterparty(counterparties, tx_from, contract_map, skip_address=account_address)
    else:
        action = "未归类调用"
        action_group = "other"
        description = "这笔交易没有匹配到已归类的事件模式"
        add_counterparty(counterparties, tx_to, contract_map, skip_address=account_address)

    return {
        "account": account_address,
        "block_number": int(tx_meta["block_number"]),
        "block_timestamp": int(tx_meta["block_timestamp"] or 0),
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
        "input_selector": input_selector,
    }


def default_summary() -> dict:
    return {
        "claims": [],
        "reward_mints": [],
        "group_joins": [],
        "group_exits": [],
        "action_joins": [],
        "action_exits": [],
        "group_verify_submissions": [],
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


def write_metadata(dest: sqlite3.Connection, network: str, source_db: str) -> None:
    record_count = dest.execute("SELECT COUNT(*) FROM tx_activity").fetchone()[0]
    dest.execute(
        """
        INSERT INTO metadata (network, source_db, generated_at, record_count)
        VALUES (?, ?, ?, ?)
        """,
        (network, source_db, now_iso(), record_count),
    )


def summary_rows_for_accounts(
    summaries: dict[str, dict],
    tx_meta: dict,
    contract_map: dict[str, str],
    *,
    account_filter: str | None = None,
) -> list[dict]:
    rows: list[dict] = []
    normalized_filter = normalize_address(account_filter)
    for account, summary in summaries.items():
        if normalized_filter and normalize_address(account) != normalized_filter:
            continue
        if not account or is_zero_address(account) or not has_token_activity(summary):
            continue
        rows.append(build_row(account, summary, tx_meta, contract_map))
    return rows


def apply_event_to_summaries(
    row: sqlite3.Row | dict,
    summaries: defaultdict[str, dict],
    action_memberships: set[tuple[str, str, str, int]],
    group_memberships: set[tuple[str, str, str, int, int]],
    contract_map: dict[str, str],
    *,
    tx_meta: dict | None = None,
) -> None:
    payload = json.loads(row["decoded_data"])
    contract_name = row["contract_name"]
    event_name = row["event_name"]
    contract_address = normalize_address(row["address"])
    current_meta = tx_meta or {
        "tx_from": row["tx_from"],
        "tx_to": row["tx_to"],
        "input": row["input"] or "",
    }

    if event_name == "ClaimReward":
        account = normalize_address(payload.get("account"))
        if not account:
            return
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
        return

    if event_name == "MintActionReward":
        account = normalize_address(payload.get("account"))
        if not account:
            return
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
        return

    if event_name == "MintGovReward":
        account = normalize_address(payload.get("account"))
        if not account:
            return
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
        return

    if event_name == "Approval":
        owner = normalize_address(payload.get("owner") or payload.get("_owner") or payload.get("src"))
        spender = normalize_address(payload.get("spender") or payload.get("_spender") or payload.get("guy"))
        value = payload.get("value")
        if value is None:
            value = payload.get("wad")
        if not owner or not spender or value is None:
            return
        summaries[owner]["approvals"].append(
            {
                "token": token_label(contract_name),
                "raw": int(value or 0),
                "decimals": 18,
                "spender": spender,
                "contract_address": contract_address,
            }
        )
        return

    if event_name == "Transfer":
        transfer = parse_transfer_payload(payload, contract_name, contract_map)
        if not transfer:
            return
        from_address = transfer["from_address"]
        to_address = transfer["to_address"]
        value = int(transfer["raw"])
        token = transfer["token"]
        decimals = int(transfer["decimals"])
        if is_zero_address(from_address):
            if to_address:
                summaries[to_address]["mints_in"].append(
                    {
                        "token": token,
                        "raw": value,
                        "decimals": decimals,
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
                        "decimals": decimals,
                        "counterparty": to_address,
                        "contract_address": contract_address,
                    }
                )
        else:
            summaries[from_address]["transfers_out"].append(
                {
                    "token": token,
                    "raw": value,
                    "decimals": decimals,
                    "counterparty": to_address,
                    "contract_address": contract_address,
                }
            )
            summaries[to_address]["transfers_in"].append(
                {
                    "token": token,
                    "raw": value,
                    "decimals": decimals,
                    "counterparty": from_address,
                    "contract_address": contract_address,
                }
            )
        return

    if event_name == "Withdrawal":
        amount = int(payload.get("wad") or payload.get("value") or 0)
        source_address = normalize_address(payload.get("src") or payload.get("from") or payload.get("account"))
        tx_sender = normalize_address(current_meta.get("tx_from"))
        tx_receiver = normalize_address(current_meta.get("tx_to"))
        selector = selector_name((current_meta.get("input") or "")[:10])
        if amount <= 0:
            return
        if source_address:
            summaries[source_address]["native_out"] += amount
        if tx_sender and is_router_address(tx_receiver, contract_map) and selector == "swapExactTokensForETH":
            summaries[tx_sender]["native_in"] += amount
        return

    if contract_name == "groupVerify" and event_name == "SubmitOriginScores":
        account = normalize_address(current_meta.get("tx_from"))
        if not account:
            return
        summaries[account]["group_verify_submissions"].append(
            {
                "contract_address": contract_address,
                "token_address": normalize_address(payload.get("tokenAddress")),
                "action_id": int(payload.get("actionId") or 0),
                "group_id": int(payload.get("groupId") or 0),
                "count": int(payload.get("count") or 0),
            }
        )
        return

    if event_name in {"Join", "Exit"} and contract_name == "groupJoin":
        account = normalize_address(payload.get("account"))
        if not account:
            return
        entry = {
            "contract_address": contract_address,
            "token_address": normalize_address(payload.get("tokenAddress")),
            "action_id": int(payload.get("actionId") or 0),
            "group_id": int(payload.get("groupId") or 0),
            "amount": int(payload.get("amount") or 0),
        }
        membership_key = group_membership_key(account, entry)
        if event_name == "Join":
            entry["is_additional"] = membership_key in group_memberships
            summaries[account]["group_joins"].append(entry)
            group_memberships.add(membership_key)
        else:
            summaries[account]["group_exits"].append(entry)
            group_memberships.discard(membership_key)
        return

    if contract_name == "join" and event_name in {"Join", "Withdraw"}:
        account = normalize_address(payload.get("account"))
        if not account:
            return
        entry = {
            "contract_address": contract_address,
            "token_address": normalize_address(payload.get("tokenAddress")),
            "action_id": int(payload.get("actionId") or 0),
            "amount": int(payload.get("additionalStakeAmount") or payload.get("amount") or 0),
        }
        membership_key = action_membership_key(account, entry)
        if event_name == "Join":
            entry["is_additional"] = membership_key in action_memberships
            summaries[account]["action_joins"].append(entry)
            action_memberships.add(membership_key)
        else:
            summaries[account]["action_exits"].append(entry)
            action_memberships.discard(membership_key)
        return

    if event_name in {"Join", "Exit"} and payload.get("actionId") is not None and payload.get("amount") is not None and payload.get("account"):
        account = normalize_address(payload.get("account"))
        if not account:
            return
        entry = {
            "contract_address": contract_address,
            "token_address": normalize_address(payload.get("tokenAddress")),
            "action_id": int(payload.get("actionId") or 0),
            "amount": int(payload.get("amount") or 0),
        }
        membership_key = action_membership_key(account, entry)
        if event_name == "Join":
            entry["is_additional"] = membership_key in action_memberships
            summaries[account]["action_joins"].append(entry)
            action_memberships.add(membership_key)
        else:
            summaries[account]["action_exits"].append(entry)
            action_memberships.discard(membership_key)


def process_event_stream(source: sqlite3.Connection, dest: sqlite3.Connection, contract_map: dict[str, str]) -> int:
    relevant_count = source.execute(
        f"""
        SELECT COUNT(*)
        FROM events
        WHERE event_name IN ({RELEVANT_EVENT_NAMES_SQL})
        """
    ).fetchone()[0]
    print(f"Relevant events: {relevant_count}")

    query = f"""
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
        WHERE e.event_name IN ({RELEVANT_EVENT_NAMES_SQL})
        ORDER BY e.block_number, COALESCE(e.tx_index, t.tx_index, 0), e.log_index, e.id
    """

    cursor = source.execute(query)
    current_key: tuple[int, str] | None = None
    current_meta: dict | None = None
    summaries: defaultdict[str, dict] = defaultdict(default_summary)
    action_memberships: set[tuple[str, str, str, int]] = set()
    group_memberships: set[tuple[str, str, str, int, int]] = set()
    buffer: list[dict] = []
    inserted = 0
    processed = 0

    def flush_tx() -> None:
        nonlocal inserted, summaries
        if not current_meta:
            return
        buffer.extend(summary_rows_for_accounts(summaries, current_meta, contract_map))
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
                "block_timestamp": int(row["block_timestamp"] or 0),
                "tx_hash": row["tx_hash"],
                "tx_index": int(row["tx_index"] or 0),
                "tx_from": row["tx_from"],
                "tx_to": row["tx_to"],
                "status": row["status"],
                "value_wei": row["value_wei"],
                "input": row["input"] or "",
            }
        apply_event_to_summaries(row, summaries, action_memberships, group_memberships, contract_map, tx_meta=current_meta)
        if processed % 100000 == 0:
            print(f"Processed events: {processed}/{relevant_count}")

    flush_tx()
    inserted += flush_rows(dest, buffer)
    print(f"Inserted rows from event summaries: {inserted}")
    return inserted


def rows_for_native_only_transaction(
    tx_meta: dict,
    contract_map: dict[str, str],
    *,
    account_filter: str | None = None,
) -> list[dict]:
    rows: list[dict] = []
    value_raw = int(tx_meta.get("value_wei") or 0)
    sender = normalize_address(tx_meta.get("tx_from"))
    receiver = normalize_address(tx_meta.get("tx_to"))
    selector = selector_name((tx_meta.get("input") or "")[:10])
    normalized_filter = normalize_address(account_filter)

    def should_include(account: str) -> bool:
        if not account:
            return False
        if not normalized_filter:
            return True
        return normalize_address(account) == normalized_filter

    if tx_meta.get("status") == 0 and is_router_address(receiver, contract_map):
        sender_action, sender_description = failed_router_action(selector, for_router=False)
        router_action, router_description = failed_router_action(selector, for_router=True)
        if should_include(sender):
            rows.append(
                {
                    "account": sender,
                    "block_number": tx_meta["block_number"],
                    "block_timestamp": tx_meta["block_timestamp"],
                    "tx_hash": tx_meta["tx_hash"],
                    "tx_index": tx_meta["tx_index"],
                    "status": tx_meta["status"],
                    "action": sender_action,
                    "action_group": "swap" if selector.startswith("swap") else "other",
                    "action_id_text": "",
                    "group_id_text": "",
                    "communities_json": "[]",
                    "amounts_json": json.dumps([{"token": "原生币", "raw": str(value_raw), "decimals": 18}], ensure_ascii=False),
                    "counterparties_json": json.dumps(unique_counterparties([{"address": receiver, "label": contract_map.get(receiver, "")}]), ensure_ascii=False),
                    "description": sender_description,
                    "tx_from": sender,
                    "tx_to": receiver,
                    "input_selector": (tx_meta.get("input") or "")[:10],
                }
            )
        if should_include(receiver):
            rows.append(
                {
                    "account": receiver,
                    "block_number": tx_meta["block_number"],
                    "block_timestamp": tx_meta["block_timestamp"],
                    "tx_hash": tx_meta["tx_hash"],
                    "tx_index": tx_meta["tx_index"],
                    "status": tx_meta["status"],
                    "action": router_action,
                    "action_group": "swap" if selector.startswith("swap") else "other",
                    "action_id_text": "",
                    "group_id_text": "",
                    "communities_json": "[]",
                    "amounts_json": json.dumps([{"token": "原生币", "raw": str(value_raw), "decimals": 18}], ensure_ascii=False),
                    "counterparties_json": json.dumps(unique_counterparties([{"address": sender, "label": contract_map.get(sender, "")}]), ensure_ascii=False),
                    "description": router_description,
                    "tx_from": sender,
                    "tx_to": receiver,
                    "input_selector": (tx_meta.get("input") or "")[:10],
                }
            )
        return rows

    if should_include(sender):
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
                "input_selector": (tx_meta.get("input") or "")[:10],
            }
        )
    if should_include(receiver):
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
                "input_selector": (tx_meta.get("input") or "")[:10],
            }
        )
    return rows


def rows_for_unclassified_transaction(
    tx_meta: dict,
    contract_map: dict[str, str],
    *,
    account_filter: str | None = None,
) -> list[dict]:
    rows: list[dict] = []
    sender = normalize_address(tx_meta.get("tx_from"))
    receiver = normalize_address(tx_meta.get("tx_to"))
    input_selector = (tx_meta.get("input") or "")[:10]
    selector = selector_name(input_selector)
    normalized_filter = normalize_address(account_filter)

    def should_include(account: str) -> bool:
        if not account:
            return False
        if not normalized_filter:
            return True
        return normalize_address(account) == normalized_filter

    if selector.startswith("swap"):
        action_group = "swap"
    elif selector in {"addLiquidity", "removeLiquidity"}:
        action_group = "liquidity"
    else:
        action_group = "other"

    if tx_meta.get("status") == 0 and is_router_address(receiver, contract_map):
        sender_action, sender_description = failed_router_action(selector, for_router=False)
        router_action, router_description = failed_router_action(selector, for_router=True)
        if should_include(sender):
            rows.append(
                {
                    "account": sender,
                    "block_number": tx_meta["block_number"],
                    "block_timestamp": tx_meta["block_timestamp"],
                    "tx_hash": tx_meta["tx_hash"],
                    "tx_index": tx_meta["tx_index"],
                    "status": tx_meta["status"],
                    "action": sender_action,
                    "action_group": action_group,
                    "action_id_text": "",
                    "group_id_text": "",
                    "communities_json": "[]",
                    "amounts_json": "[]",
                    "counterparties_json": json.dumps(unique_counterparties([{"address": receiver, "label": contract_map.get(receiver, "")}]), ensure_ascii=False),
                    "description": sender_description,
                    "tx_from": sender,
                    "tx_to": receiver,
                    "input_selector": input_selector,
                }
            )
        if receiver != sender and should_include(receiver):
            rows.append(
                {
                    "account": receiver,
                    "block_number": tx_meta["block_number"],
                    "block_timestamp": tx_meta["block_timestamp"],
                    "tx_hash": tx_meta["tx_hash"],
                    "tx_index": tx_meta["tx_index"],
                    "status": tx_meta["status"],
                    "action": router_action,
                    "action_group": action_group,
                    "action_id_text": "",
                    "group_id_text": "",
                    "communities_json": "[]",
                    "amounts_json": "[]",
                    "counterparties_json": json.dumps(unique_counterparties([{"address": sender, "label": contract_map.get(sender, "")}]), ensure_ascii=False),
                    "description": router_description,
                    "tx_from": sender,
                    "tx_to": receiver,
                    "input_selector": input_selector,
                }
            )
        return rows

    if should_include(sender):
        rows.append(
            {
                "account": sender,
                "block_number": tx_meta["block_number"],
                "block_timestamp": tx_meta["block_timestamp"],
                "tx_hash": tx_meta["tx_hash"],
                "tx_index": tx_meta["tx_index"],
                "status": tx_meta["status"],
                "action": "未归类调用",
                "action_group": action_group,
                "action_id_text": "",
                "group_id_text": "",
                "communities_json": "[]",
                "amounts_json": "[]",
                "counterparties_json": json.dumps(unique_counterparties([{"address": receiver, "label": contract_map.get(receiver, "")}]), ensure_ascii=False),
                "description": f"向 {describe_counterparty(receiver, contract_map)} 发起调用，未命中已解析事件模式",
                "tx_from": sender,
                "tx_to": receiver,
                "input_selector": input_selector,
            }
        )
    if receiver != sender and should_include(receiver):
        rows.append(
            {
                "account": receiver,
                "block_number": tx_meta["block_number"],
                "block_timestamp": tx_meta["block_timestamp"],
                "tx_hash": tx_meta["tx_hash"],
                "tx_index": tx_meta["tx_index"],
                "status": tx_meta["status"],
                "action": "收到未归类调用",
                "action_group": action_group,
                "action_id_text": "",
                "group_id_text": "",
                "communities_json": "[]",
                "amounts_json": "[]",
                "counterparties_json": json.dumps(unique_counterparties([{"address": sender, "label": contract_map.get(sender, "")}]), ensure_ascii=False),
                "description": f"收到 {describe_counterparty(sender, contract_map)} 发起的调用，未命中已解析事件模式",
                "tx_from": sender,
                "tx_to": receiver,
                "input_selector": input_selector,
            }
        )
    return rows


def process_native_only_transactions(source: sqlite3.Connection, dest: sqlite3.Connection, contract_map: dict[str, str]) -> int:
    query = """
        SELECT
            COALESCE(t.block_number, 0) AS block_number,
            COALESCE(b.timestamp, t.block_timestamp, 0) AS block_timestamp,
            t.tx_hash,
            COALESCE(t.tx_index, 0) AS tx_index,
            t."from" AS tx_from,
            t."to" AS tx_to,
            t.status,
            t.value_wei,
            t.input
        FROM transactions t
        LEFT JOIN blocks b ON b.block_number = t.block_number
        WHERE CAST(t.value_wei AS TEXT) != '0'
        ORDER BY t.block_number, COALESCE(t.tx_index, 0)
    """

    inserted = 0
    rows: list[dict] = []
    for row in source.execute(query):
        tx_meta = {
            "block_number": int(row["block_number"] or 0),
            "block_timestamp": int(row["block_timestamp"] or 0),
            "tx_hash": row["tx_hash"],
            "tx_index": int(row["tx_index"] or 0),
            "tx_from": row["tx_from"],
            "tx_to": row["tx_to"],
            "status": row["status"],
            "value_wei": row["value_wei"],
            "input": row["input"] or "",
        }
        rows.extend(rows_for_native_only_transaction(tx_meta, contract_map))
        if len(rows) >= 1000:
            inserted += flush_rows(dest, rows)

    inserted += flush_rows(dest, rows)
    print(f"Inserted rows from native transfers: {inserted}")
    return inserted


CANDIDATE_TXS_INSERT_SQL = """
INSERT OR IGNORE INTO temp_candidate_txs(tx_hash)
SELECT tx_hash
FROM transactions
WHERE "from" = :address

UNION

SELECT tx_hash
FROM transactions
WHERE "to" = :address

UNION

SELECT tx_hash
FROM events
WHERE event_name IN ('ClaimReward', 'MintActionReward', 'MintGovReward', 'Join', 'Exit', 'Withdraw', 'Withdrawal')
  AND lower(json_extract(decoded_data, '$.account')) = :address

UNION

SELECT tx_hash
FROM events
WHERE event_name = 'Transfer'
  AND lower(json_extract(decoded_data, '$.from')) = :address

UNION

SELECT tx_hash
FROM events
WHERE event_name = 'Transfer'
  AND lower(json_extract(decoded_data, '$.to')) = :address

UNION

SELECT tx_hash
FROM events
WHERE event_name = 'Transfer'
  AND lower(json_extract(decoded_data, '$.src')) = :address

UNION

SELECT tx_hash
FROM events
WHERE event_name = 'Transfer'
  AND lower(json_extract(decoded_data, '$.dst')) = :address
"""


def prepare_candidate_txs(source: sqlite3.Connection, account: str) -> None:
    source.execute("DROP TABLE IF EXISTS temp_candidate_txs")
    source.execute("DROP TABLE IF EXISTS temp_page_txs")
    source.execute(
        """
        CREATE TEMP TABLE temp_candidate_txs (
            tx_hash TEXT PRIMARY KEY
        ) WITHOUT ROWID
        """
    )
    source.execute(CANDIDATE_TXS_INSERT_SQL, {"address": account})


def build_cursor_filter(cursor: dict | None) -> tuple[str, dict]:
    if not cursor:
        return "", {}
    return (
        """
        WHERE t.block_number < :cursor_block_number
           OR (t.block_number = :cursor_block_number AND COALESCE(t.tx_index, 0) < :cursor_tx_index)
           OR (t.block_number = :cursor_block_number AND COALESCE(t.tx_index, 0) = :cursor_tx_index AND c.tx_hash < :cursor_tx_hash)
        """,
        {
            "cursor_block_number": int(cursor["block_number"]),
            "cursor_tx_index": int(cursor["tx_index"]),
            "cursor_tx_hash": str(cursor["tx_hash"]).lower(),
        },
    )


def select_candidate_meta_batch(source: sqlite3.Connection, limit: int, cursor: dict | None) -> tuple[list[sqlite3.Row], bool]:
    where_sql, params = build_cursor_filter(cursor)
    params["page_limit"] = int(limit) + 1
    rows = source.execute(
        f"""
        WITH page AS (
            SELECT
                c.tx_hash,
                t.id,
                t.block_number,
                t.block_hash,
                COALESCE(t.block_timestamp, 0) AS block_timestamp,
                COALESCE(t.tx_index, 0) AS tx_index,
                t."from" AS tx_from,
                t."to" AS tx_to,
                t.amount,
                t.gas,
                t.gas_price,
                t.max_fee_per_gas,
                t.max_priority_fee_per_gas,
                t.type,
                t.chain_id,
                t.status,
                t.value_wei,
                COALESCE(t.input, '') AS input,
                t.nonce,
                t.v,
                t.r,
                t.s,
                t.access_list,
                t.gas_used,
                t.cumulative_gas_used,
                t.contract_address,
                t.effective_gas_price,
                t.created_at
            FROM temp_candidate_txs c
            JOIN transactions t ON t.tx_hash = c.tx_hash
            {where_sql}
            ORDER BY t.block_number DESC, COALESCE(t.tx_index, 0) DESC, c.tx_hash DESC
            LIMIT :page_limit
        )
        SELECT
            id,
            block_number,
            block_hash,
            block_timestamp,
            tx_hash,
            tx_index,
            tx_from,
            tx_to,
            amount,
            gas,
            gas_price,
            max_fee_per_gas,
            max_priority_fee_per_gas,
            type,
            chain_id,
            status,
            value_wei,
            input,
            nonce,
            v,
            r,
            s,
            access_list,
            gas_used,
            cumulative_gas_used,
            contract_address,
            effective_gas_price,
            created_at
        FROM page
        ORDER BY block_number DESC, tx_index DESC, tx_hash DESC
        """,
        params,
    ).fetchall()
    return rows[:limit], len(rows) > limit


def refresh_temp_page_txs(
    source: sqlite3.Connection,
    tx_meta_rows: list[sqlite3.Row],
) -> None:
    source.execute("DROP TABLE IF EXISTS temp_page_txs")
    source.execute(
        """
        CREATE TEMP TABLE temp_page_txs (
            tx_hash TEXT PRIMARY KEY
        ) WITHOUT ROWID
        """
    )
    source.executemany(
        "INSERT INTO temp_page_txs(tx_hash) VALUES (?)",
        [(row["tx_hash"],) for row in tx_meta_rows],
    )


def load_event_rows_by_tx(
    source: sqlite3.Connection,
    tx_meta_rows: list[sqlite3.Row],
) -> dict[str, list[sqlite3.Row]]:
    refresh_temp_page_txs(source, tx_meta_rows)

    event_rows_by_tx: defaultdict[str, list[sqlite3.Row]] = defaultdict(list)
    for row in source.execute(
        f"""
        SELECT
            e.block_number,
            COALESCE(t.block_timestamp, 0) AS block_timestamp,
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
        JOIN temp_page_txs p ON p.tx_hash = e.tx_hash
        LEFT JOIN transactions t ON t.tx_hash = e.tx_hash
        WHERE e.event_name IN ({RELEVANT_EVENT_NAMES_SQL})
        ORDER BY e.block_number, COALESCE(e.tx_index, t.tx_index, 0), e.log_index, e.id
        """
    ):
        event_rows_by_tx[row["tx_hash"]].append(row)
    return event_rows_by_tx


def load_all_event_rows_by_tx(
    source: sqlite3.Connection,
    tx_meta_rows: list[sqlite3.Row],
) -> dict[str, list[sqlite3.Row]]:
    refresh_temp_page_txs(source, tx_meta_rows)

    event_rows_by_tx: defaultdict[str, list[sqlite3.Row]] = defaultdict(list)
    for row in source.execute(
        """
        SELECT
            e.id,
            e.contract_name,
            e.event_name,
            e.log_round,
            e.round,
            e.block_number,
            e.tx_hash,
            e.tx_index,
            e.log_index,
            e.address,
            e.decoded_data,
            e.created_at
        FROM events e
        JOIN temp_page_txs p ON p.tx_hash = e.tx_hash
        ORDER BY e.block_number, COALESCE(e.tx_index, 0), COALESCE(e.log_index, 0), e.id
        """
    ):
        event_rows_by_tx[row["tx_hash"]].append(row)
    return event_rows_by_tx


def seed_membership_state(
    source: sqlite3.Connection,
    account: str,
    oldest_row: sqlite3.Row,
) -> tuple[set[tuple[str, str, str, int]], set[tuple[str, str, str, int, int]]]:
    action_memberships: set[tuple[str, str, str, int]] = set()
    group_memberships: set[tuple[str, str, str, int, int]] = set()
    summaries: defaultdict[str, dict] = defaultdict(default_summary)
    for row in source.execute(
        """
        SELECT
            e.block_number,
            COALESCE(e.tx_index, t.tx_index, 0) AS tx_index,
            e.log_index,
            e.tx_hash,
            e.contract_name,
            e.event_name,
            e.address,
            e.decoded_data,
            t."from" AS tx_from,
            t."to" AS tx_to,
            COALESCE(t.input, '') AS input
        FROM events e
        LEFT JOIN transactions t ON t.tx_hash = e.tx_hash
        WHERE lower(json_extract(e.decoded_data, '$.account')) = :address
          AND (
                (e.contract_name = 'groupJoin' AND e.event_name IN ('Join', 'Exit'))
             OR (e.contract_name = 'join' AND e.event_name IN ('Join', 'Withdraw'))
             OR (
                    e.event_name IN ('Join', 'Exit')
                AND json_extract(e.decoded_data, '$.actionId') IS NOT NULL
                AND json_extract(e.decoded_data, '$.amount') IS NOT NULL
             )
          )
          AND (
                e.block_number < :oldest_block_number
             OR (e.block_number = :oldest_block_number AND COALESCE(e.tx_index, t.tx_index, 0) < :oldest_tx_index)
             OR (e.block_number = :oldest_block_number AND COALESCE(e.tx_index, t.tx_index, 0) = :oldest_tx_index AND e.tx_hash < :oldest_tx_hash)
          )
        ORDER BY e.block_number, COALESCE(e.tx_index, t.tx_index, 0), e.log_index, e.id
        """,
        {
            "address": account,
            "oldest_block_number": int(oldest_row["block_number"]),
            "oldest_tx_index": int(oldest_row["tx_index"] or 0),
            "oldest_tx_hash": oldest_row["tx_hash"],
        },
    ):
        apply_event_to_summaries(row, summaries, action_memberships, group_memberships, {}, tx_meta={})
    return action_memberships, group_memberships


def query_activity_rows_by_account(
    source: sqlite3.Connection,
    contract_map: dict[str, str],
    account: str,
    *,
    limit: int = 200,
    cursor: dict | None = None,
) -> dict:
    account = normalize_address(account)
    if not account:
        return {"rows": [], "has_more": False, "next_cursor": None, "page_size": int(limit)}

    safe_limit = max(1, int(limit))
    prepare_candidate_txs(source, account)

    tx_meta_rows, has_more = select_candidate_meta_batch(source, safe_limit, cursor)
    if not tx_meta_rows:
        return {"rows": [], "has_more": False, "next_cursor": None, "page_size": safe_limit}

    event_rows_by_tx = load_event_rows_by_tx(source, tx_meta_rows)
    raw_event_rows_by_tx = load_all_event_rows_by_tx(source, tx_meta_rows)

    action_memberships, group_memberships = seed_membership_state(source, account, tx_meta_rows[-1])
    raw_rows: list[dict] = []

    for tx_meta_row in reversed(tx_meta_rows):
        tx_meta = {
            "block_number": int(tx_meta_row["block_number"] or 0),
            "block_timestamp": int(tx_meta_row["block_timestamp"] or 0),
            "tx_hash": tx_meta_row["tx_hash"],
            "tx_index": int(tx_meta_row["tx_index"] or 0),
            "tx_from": tx_meta_row["tx_from"],
            "tx_to": tx_meta_row["tx_to"],
            "status": tx_meta_row["status"],
            "value_wei": tx_meta_row["value_wei"],
            "input": tx_meta_row["input"] or "",
        }
        event_rows = event_rows_by_tx.get(tx_meta["tx_hash"], [])
        raw_transaction = materialize_detail_transaction_row(tx_meta_row)
        raw_events = [materialize_detail_event_row(row) for row in raw_event_rows_by_tx.get(tx_meta["tx_hash"], [])]

        def extend_with_raw_data(rows_to_extend: list[dict]) -> list[dict]:
            for item in rows_to_extend:
                item["transaction"] = raw_transaction
                item["events"] = raw_events
            return rows_to_extend

        if event_rows:
            summaries: defaultdict[str, dict] = defaultdict(default_summary)
            for event_row in event_rows:
                apply_event_to_summaries(event_row, summaries, action_memberships, group_memberships, contract_map, tx_meta=tx_meta)
            summary_rows = summary_rows_for_accounts(summaries, tx_meta, contract_map, account_filter=account)
            if summary_rows:
                raw_rows.extend(extend_with_raw_data(summary_rows))
            elif int(tx_meta.get("value_wei") or 0) > 0:
                raw_rows.extend(extend_with_raw_data(rows_for_native_only_transaction(tx_meta, contract_map, account_filter=account)))
            else:
                raw_rows.extend(extend_with_raw_data(rows_for_unclassified_transaction(tx_meta, contract_map, account_filter=account)))
        elif int(tx_meta.get("value_wei") or 0) > 0:
            raw_rows.extend(extend_with_raw_data(rows_for_native_only_transaction(tx_meta, contract_map, account_filter=account)))
        else:
            raw_rows.extend(extend_with_raw_data(rows_for_unclassified_transaction(tx_meta, contract_map, account_filter=account)))

    rows = [materialize_activity_row(row) for row in raw_rows]
    rows.sort(key=lambda item: (item["block_number"], item["tx_index"], item["tx_hash"]), reverse=True)
    next_cursor = None
    if has_more:
        last_row = tx_meta_rows[-1]
        next_cursor = {
            "block_number": int(last_row["block_number"]),
            "tx_index": int(last_row["tx_index"] or 0),
            "tx_hash": last_row["tx_hash"],
        }
    return {
        "rows": rows,
        "has_more": has_more,
        "next_cursor": next_cursor,
        "page_size": safe_limit,
    }


def materialize_activity_row(row: dict) -> dict:
    return {
        "block_number": int(row["block_number"]),
        "block_timestamp": int(row["block_timestamp"]),
        "tx_hash": row["tx_hash"],
        "tx_index": int(row.get("tx_index") or 0),
        "status": None if row.get("status") is None else int(row["status"]),
        "action": row["action"],
        "action_group": row["action_group"],
        "action_id_text": row.get("action_id_text") or "",
        "group_id_text": row.get("group_id_text") or "",
        "communities": json.loads(row.get("communities_json") or "[]"),
        "amounts": json.loads(row.get("amounts_json") or "[]"),
        "counterparties": json.loads(row.get("counterparties_json") or "[]"),
        "description": row["description"],
        "transaction": row.get("transaction"),
        "events": row.get("events") or [],
    }


def materialize_detail_transaction_row(row: sqlite3.Row | dict | None) -> dict | None:
    if row is None:
        return None
    return {
        "id": None if row["id"] is None else int(row["id"]),
        "block_number": None if row["block_number"] is None else int(row["block_number"]),
        "block_hash": row["block_hash"],
        "block_timestamp": None if row["block_timestamp"] is None else int(row["block_timestamp"]),
        "tx_hash": row["tx_hash"],
        "tx_index": None if row["tx_index"] is None else int(row["tx_index"]),
        "from": row["tx_from"],
        "to": row["tx_to"],
        "value_wei": row["value_wei"],
        "amount": row["amount"],
        "gas": None if row["gas"] is None else int(row["gas"]),
        "gas_price": None if row["gas_price"] is None else int(row["gas_price"]),
        "max_fee_per_gas": None if row["max_fee_per_gas"] is None else int(row["max_fee_per_gas"]),
        "max_priority_fee_per_gas": None if row["max_priority_fee_per_gas"] is None else int(row["max_priority_fee_per_gas"]),
        "type": None if row["type"] is None else int(row["type"]),
        "chain_id": None if row["chain_id"] is None else int(row["chain_id"]),
        "input": row["input"],
        "nonce": None if row["nonce"] is None else int(row["nonce"]),
        "v": None if row["v"] is None else int(row["v"]),
        "r": row["r"],
        "s": row["s"],
        "access_list": row["access_list"],
        "gas_used": None if row["gas_used"] is None else int(row["gas_used"]),
        "cumulative_gas_used": None if row["cumulative_gas_used"] is None else int(row["cumulative_gas_used"]),
        "status": None if row["status"] is None else int(row["status"]),
        "contract_address": row["contract_address"],
        "effective_gas_price": None if row["effective_gas_price"] is None else int(row["effective_gas_price"]),
        "created_at": row["created_at"],
    }


def materialize_detail_event_row(row: sqlite3.Row | dict) -> dict:
    decoded_data_raw = row["decoded_data"]
    try:
        decoded_data = json.loads(decoded_data_raw)
    except json.JSONDecodeError:
        decoded_data = decoded_data_raw
    return {
        "id": None if row["id"] is None else int(row["id"]),
        "contract_name": row["contract_name"],
        "event_name": row["event_name"],
        "log_round": None if row["log_round"] is None else int(row["log_round"]),
        "round": None if row["round"] is None else int(row["round"]),
        "block_number": None if row["block_number"] is None else int(row["block_number"]),
        "tx_hash": row["tx_hash"],
        "tx_index": None if row["tx_index"] is None else int(row["tx_index"]),
        "log_index": None if row["log_index"] is None else int(row["log_index"]),
        "address": row["address"],
        "decoded_data": decoded_data,
        "decoded_data_raw": decoded_data_raw,
        "created_at": row["created_at"],
    }
