#!/usr/bin/env python3
"""
Rebuild auto-discovered extension config entries from events.db.

Discovery rules:
1. Read ActionCreate events from submit.
2. Extract actionBody.whiteListAddress as the candidate extension address.
3. Keep only monitored tokens (LOVE20 and optional LIFE20) with non-zero whitelist addresses.
4. Match whitelist address + token address against CreateExtension events emitted by
   known extension factories configured in contracts.json.
5. Generate extension config entries using the matching factory's extension_abi_files.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any


ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
AUTO_DISCOVERY_MARKER = "auto-discovery"
SYNC_RELEVANT_KEYS = ("address", "from_block", "abi_files")


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def normalize_address(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    if not stripped:
        return None
    hex_value = stripped[2:] if stripped.startswith("0x") else stripped
    if len(hex_value) != 40:
        return None
    return "0x" + hex_value.lower()


def load_config(config_path: Path) -> list[dict[str, Any]]:
    with config_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError("contracts config must be a JSON array")
    return data


def coerce_block_number(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def resolve_entry_address(entry: dict[str, Any]) -> str | None:
    env_var = entry.get("address_env_var")
    if isinstance(env_var, str) and env_var:
        resolved = normalize_address(os.environ.get(env_var))
        if resolved:
            return resolved
    return normalize_address(entry.get("address"))


def connect_db(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")
    return conn


def query_rows(
    conn: sqlite3.Connection,
    sql: str,
    params: tuple[Any, ...] = (),
) -> list[sqlite3.Row]:
    try:
        return conn.execute(sql, params).fetchall()
    except sqlite3.OperationalError as exc:
        raise RuntimeError(f"database query failed: {exc}") from exc


def resolve_monitored_tokens(config_entries: list[dict[str, Any]]) -> dict[str, str]:
    tokens: dict[str, str] = {}

    love20 = normalize_address(os.environ.get("firstTokenAddress"))
    if not love20:
        for entry in config_entries:
            if entry.get("name") == "LOVE20":
                love20 = resolve_entry_address(entry)
                break
    if love20:
        tokens[love20] = "love20"

    life20 = normalize_address(os.environ.get("life20Address"))
    if not life20:
        for entry in config_entries:
            if entry.get("name") == "LIFE20":
                life20 = resolve_entry_address(entry)
                break
    if life20:
        tokens[life20] = "life20"

    if not tokens:
        raise RuntimeError("failed to resolve monitored token addresses")

    return tokens


def load_extension_factories(config_entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    factories: list[dict[str, Any]] = []
    for entry in config_entries:
        if entry.get("contract_type") != "extension_factory":
            continue
        abi_files = entry.get("extension_abi_files")
        if not isinstance(abi_files, list) or not abi_files:
            continue

        address = resolve_entry_address(entry)
        if not address:
            log(f"⚠️ Skipping extension_factory {entry.get('name')}: unresolved address")
            continue

        factories.append(
            {
                "name": entry["name"],
                "address": address,
                "extension_abi_files": abi_files,
            }
        )

    if not factories:
        raise RuntimeError("no extension_factory entries found in contracts config")

    return factories


def load_action_creates(
    conn: sqlite3.Connection,
    monitored_tokens: dict[str, str],
) -> dict[tuple[str, int], dict[str, Any]]:
    rows = query_rows(
        conn,
        """
        SELECT block_number, decoded_data
        FROM events
        WHERE contract_name = 'submit' AND event_name = 'ActionCreate'
        ORDER BY block_number ASC
        """,
    )

    actions: dict[tuple[str, int], dict[str, Any]] = {}
    for row in rows:
        decoded = json.loads(row["decoded_data"])
        token = normalize_address(decoded.get("tokenAddress"))
        if token not in monitored_tokens:
            continue

        action_id_raw = decoded.get("actionId")
        if not isinstance(action_id_raw, int):
            continue

        whitelist = normalize_address(decoded.get("actionBody.whiteListAddress"))
        if not whitelist or whitelist == ZERO_ADDRESS:
            continue

        key = (token, action_id_raw)
        existing = actions.get(key)
        if existing and existing["block_number"] <= row["block_number"]:
            continue

        actions[key] = {
            "token_address": token,
            "action_id": action_id_raw,
            "whitelist_address": whitelist,
            "block_number": int(row["block_number"]),
        }

    return actions


def load_create_extension_events(
    conn: sqlite3.Connection,
    factories: list[dict[str, Any]],
) -> dict[tuple[str, str], list[dict[str, Any]]]:
    factory_by_address = {factory["address"]: factory for factory in factories}
    placeholders = ",".join("?" for _ in factory_by_address)
    rows = query_rows(
        conn,
        f"""
        SELECT address, block_number, decoded_data
        FROM events
        WHERE event_name = 'CreateExtension'
          AND lower(address) IN ({placeholders})
        ORDER BY block_number ASC
        """,
        tuple(factory_by_address.keys()),
    )

    created: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for row in rows:
        factory_address = normalize_address(row["address"])
        factory = factory_by_address.get(factory_address or "")
        if not factory:
            continue

        decoded = json.loads(row["decoded_data"])
        extension = normalize_address(decoded.get("extension"))
        token = normalize_address(decoded.get("tokenAddress"))
        if not extension or not token:
            continue

        created.setdefault((extension, token), []).append(
            {
                "factory_name": factory["name"],
                "factory_address": factory["address"],
                "extension_abi_files": factory["extension_abi_files"],
                "block_number": int(row["block_number"]),
            }
        )

    return created


def load_register_actions(
    conn: sqlite3.Connection,
    monitored_tokens: dict[str, str],
) -> dict[tuple[str, int], str]:
    rows = query_rows(
        conn,
        """
        SELECT block_number, decoded_data
        FROM events
        WHERE contract_name = 'center' AND event_name = 'RegisterAction'
        ORDER BY block_number ASC
        """,
    )

    registered: dict[tuple[str, int], str] = {}
    for row in rows:
        decoded = json.loads(row["decoded_data"])
        token = normalize_address(decoded.get("tokenAddress"))
        if token not in monitored_tokens:
            continue

        action_id = decoded.get("actionId")
        extension = normalize_address(decoded.get("extension"))
        if not isinstance(action_id, int) or not extension:
            continue
        registered[(token, action_id)] = extension
    return registered


def generate_extension_entries(
    action_creates: dict[tuple[str, int], dict[str, Any]],
    created_extensions: dict[tuple[str, str], list[dict[str, Any]]],
    monitored_tokens: dict[str, str],
) -> list[dict[str, Any]]:
    love20_entries: list[dict[str, Any]] = []
    life20_entries: list[dict[str, Any]] = []

    for key, action in sorted(action_creates.items(), key=lambda item: (item[0][0], item[0][1])):
        matches = created_extensions.get((action["whitelist_address"], action["token_address"]))
        if not matches:
            continue

        match = min(matches, key=lambda item: item["block_number"])
        if len(matches) > 1:
            factories = ", ".join(
                f"{item['factory_name']}@{item['factory_address']}" for item in matches
            )
            log(
                "⚠️ Multiple factories matched "
                f"{action['whitelist_address']} for token={action['token_address']} "
                f"actionId={action['action_id']}; choosing earliest create block. "
                f"Candidates: {factories}"
            )

        token_kind = monitored_tokens[action["token_address"]]
        if token_kind == "life20":
            name = f"life20Ext{action['action_id']}"
        else:
            name = f"ext{action['action_id']}"

        entry = {
            "name": name,
            "address": action["whitelist_address"],
            "from_block": match["block_number"],
            "abi_files": match["extension_abi_files"],
            "token_address": action["token_address"],
            "action_id": action["action_id"],
            "factory_name": match["factory_name"],
            "factory_address": match["factory_address"],
            "managed_by": AUTO_DISCOVERY_MARKER,
        }

        if token_kind == "life20":
            life20_entries.append(entry)
        else:
            love20_entries.append(entry)

    love20_entries.sort(key=lambda item: int(item["action_id"]))
    life20_entries.sort(key=lambda item: int(item["action_id"]))
    return love20_entries + life20_entries


def rebuild_config(
    config_entries: list[dict[str, Any]],
    generated_entries: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    generated_names = {entry["name"] for entry in generated_entries}
    rebuilt: list[dict[str, Any]] = []

    for entry in config_entries:
        if entry.get("managed_by") == AUTO_DISCOVERY_MARKER:
            continue
        if entry.get("name") in generated_names:
            continue
        rebuilt.append(entry)

    rebuilt.extend(generated_entries)
    return rebuilt


def make_sync_fingerprint(entry: dict[str, Any]) -> dict[str, Any]:
    abi_files = entry.get("abi_files")
    return {
        "address": resolve_entry_address(entry),
        "from_block": coerce_block_number(entry.get("from_block")),
        "abi_files": list(abi_files) if isinstance(abi_files, list) else [],
    }


def analyze_sync_changes(
    config_entries: list[dict[str, Any]],
    generated_entries: list[dict[str, Any]],
) -> tuple[bool, list[str]]:
    existing_by_name = {
        str(entry.get("name")): entry
        for entry in config_entries
        if isinstance(entry.get("name"), str)
    }

    sync_needed = False
    reset_contract_names: list[str] = []

    for generated in generated_entries:
        name = generated["name"]
        existing = existing_by_name.get(name)
        if not existing:
            sync_needed = True
            continue

        existing_fp = make_sync_fingerprint(existing)
        generated_fp = {key: generated.get(key) for key in SYNC_RELEVANT_KEYS}
        if existing_fp != generated_fp:
            sync_needed = True
            reset_contract_names.append(name)

    return sync_needed, sorted(set(reset_contract_names))


def reset_sync_status(conn: sqlite3.Connection, contract_names: list[str]) -> int:
    if not contract_names:
        return 0

    placeholders = ",".join("?" for _ in contract_names)
    cursor = conn.execute(
        f"DELETE FROM sync_status WHERE contract_name IN ({placeholders})",
        tuple(contract_names),
    )
    conn.commit()
    return int(cursor.rowcount or 0)


def write_status_file(
    status_path: Path,
    *,
    config_changed: bool,
    sync_needed: bool,
    generated_count: int,
    reset_contract_names: list[str],
) -> None:
    status_text = "\n".join(
        [
            f"DISCOVER_CONFIG_CHANGED={1 if config_changed else 0}",
            f"DISCOVER_SYNC_NEEDED={1 if sync_needed else 0}",
            f"DISCOVER_GENERATED_COUNT={generated_count}",
            f"DISCOVER_RESET_CONTRACTS={','.join(reset_contract_names)}",
            "",
        ]
    )
    status_path.write_text(status_text, encoding="utf-8")


def audit_register_actions(
    generated_entries: list[dict[str, Any]],
    registered_actions: dict[tuple[str, int], str],
) -> None:
    for entry in generated_entries:
        key = (entry["token_address"], int(entry["action_id"]))
        registered = registered_actions.get(key)
        if registered and registered != normalize_address(entry["address"]):
            log(
                "⚠️ RegisterAction mismatch for "
                f"{entry['name']}: discovered={entry['address']} registered={registered}"
            )


def write_config_if_changed(config_path: Path, config_entries: list[dict[str, Any]]) -> bool:
    new_text = json.dumps(config_entries, ensure_ascii=False, indent=2) + "\n"
    old_text = config_path.read_text(encoding="utf-8")
    if old_text == new_text:
        return False
    config_path.write_text(new_text, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rebuild auto-discovered extension entries from events.db"
    )
    parser.add_argument("--config", required=True, help="Path to contracts.json")
    parser.add_argument("--db-path", required=True, help="Path to events.db")
    parser.add_argument(
        "--status-file",
        help="Optional path to write discovery status for one_click_process.sh",
    )
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    db_path = Path(args.db_path).resolve()
    status_path = Path(args.status_file).resolve() if args.status_file else None

    config_entries = load_config(config_path)
    monitored_tokens = resolve_monitored_tokens(config_entries)
    extension_factories = load_extension_factories(config_entries)

    if not db_path.exists():
        raise RuntimeError(f"events.db not found: {db_path}")

    conn = connect_db(db_path)
    try:
        action_creates = load_action_creates(conn, monitored_tokens)
        created_extensions = load_create_extension_events(conn, extension_factories)
        registered_actions = load_register_actions(conn, monitored_tokens)
        generated_entries = generate_extension_entries(
            action_creates=action_creates,
            created_extensions=created_extensions,
            monitored_tokens=monitored_tokens,
        )
        audit_register_actions(generated_entries, registered_actions)

        sync_needed, reset_contract_names = analyze_sync_changes(
            config_entries=config_entries,
            generated_entries=generated_entries,
        )
        reset_count = reset_sync_status(conn, reset_contract_names)
    finally:
        conn.close()

    rebuilt_entries = rebuild_config(config_entries, generated_entries)
    config_changed = write_config_if_changed(config_path, rebuilt_entries)

    if status_path:
        write_status_file(
            status_path,
            config_changed=config_changed,
            sync_needed=sync_needed,
            generated_count=len(generated_entries),
            reset_contract_names=reset_contract_names,
        )

    summary = (
        f"✅ discovered {len(generated_entries)} extension entries from {db_path.name}"
        + (" and updated contracts.json" if config_changed else "; contracts.json unchanged")
        + ("; second sync needed" if sync_needed else "; second sync not needed")
    )
    if reset_contract_names:
        summary += (
            f"; reset sync_status for {len(reset_contract_names)} contract(s)"
            f" ({', '.join(reset_contract_names)})"
        )
        if reset_count:
            summary += f", deleted {reset_count} sync_status row(s)"
    log(summary)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"❌ discover_extensions failed: {exc}")
        raise SystemExit(1)
