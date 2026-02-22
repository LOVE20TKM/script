#!/usr/bin/env python3
"""
LOVE20 Event Log Processor - High Performance Python Implementation

Decodes all event logs for given contracts and stores them directly into SQLite.
Features intelligent batch fetching with per-contract sync status.
"""

import argparse
import asyncio
import json
import os
import re
import sqlite3
import sys
import threading
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx
from eth_abi import decode
from eth_utils import event_abi_to_log_topic, to_checksum_address

# Force unbuffered output for real-time logging
# Use stderr to avoid interleaving with any RPC/debug output on stdout
_log_lock = threading.Lock()

def log(msg: str):
    with _log_lock:
        print(msg, file=sys.stderr, flush=True)


# ============================================================================
# Data Classes
# ============================================================================

@dataclass
class EventParam:
    """Event parameter definition from ABI"""
    name: str
    type: str
    indexed: bool
    components: list | None = None  # For tuple types


@dataclass
class EventDef:
    """Event definition from ABI"""
    name: str
    params: list[EventParam]
    topic0: str  # Keccak256 hash of event signature
    contract_name: str # The name of the contract this event belongs to


@dataclass
class ProcessContractConfig:
    """Configuration and state for a single contract"""
    name: str
    address: str
    abi_file: str
    from_block: int
    event_defs: dict[str, EventDef]


@dataclass
class ProcessConfig:
    """Global processing configuration"""
    config_file: str         # Path to JSON config file containing contract info
    rpc_url: str
    to_block: int
    max_blocks_per_request: int = 50000
    max_concurrent_jobs: int = 50
    max_retries: int = 5
    db_path: str = None
    origin_blocks: int = 0
    phase_blocks: int = 0


# ============================================================================
# ABI Parsing
# ============================================================================

def load_abi(abi_file: str) -> list[dict]:
    """Load ABI from JSON file"""
    try:
        # Resolve path relative to script directory if not absolute
        if not os.path.isabs(abi_file):
            script_dir = Path(__file__).resolve().parent
            abi_file = os.path.join(script_dir, abi_file)
            
        with open(abi_file, 'r') as f:
            data = json.load(f)
        return data.get('abi', data)  # Handle both {abi: [...]} and [...] formats
    except Exception as e:
        log(f"❌ Error loading ABI from {abi_file}: {e}")
        return []


def get_all_event_defs(abi: list[dict], contract_name: str) -> dict[str, EventDef]:
    """Extract all event definitions from ABI, returning topic0 -> EventDef map"""
    events = {}
    for item in abi:
        if item.get('type') == 'event':
            event_name = item.get('name', 'Unknown')
            params = []
            for inp in item.get('inputs', []):
                params.append(EventParam(
                    name=inp.get('name', ''),
                    type=inp.get('type', ''),
                    indexed=inp.get('indexed', False),
                    components=inp.get('components')
                ))
            
            # Calculate topic0 (event signature hash)
            topic0 = '0x' + event_abi_to_log_topic(item).hex()
            
            events[topic0] = EventDef(name=event_name, params=params, topic0=topic0, contract_name=contract_name)
            
    return events


# ============================================================================
# SQLite Database Operations
# ============================================================================

def calc_round(block_number: int, origin_blocks: int, phase_blocks: int) -> int | None:
    """Calculate protocol round from block number"""
    if phase_blocks <= 0 or block_number < origin_blocks:
        return None
    return (block_number - origin_blocks) // phase_blocks


def init_db(db_path: str):
    """Initialize DB by executing SQL files from script/log/sql/init"""
    conn = sqlite3.connect(db_path)
    
    script_dir = Path(__file__).resolve().parent
    sql_init_dir = script_dir / 'sql' / 'init'
    
    if sql_init_dir.exists() and sql_init_dir.is_dir():
        sql_files = sorted(sql_init_dir.glob('*.sql'))
        for f in sql_files:
            log(f"   Executing SQL init file: {f.name}")
            try:
                with open(f, 'r', encoding='utf-8') as sql_file:
                    conn.executescript(sql_file.read())
            except Exception as e:
                log(f"❌ Error executing {f.name}: {e}")
    else:
        log(f"⚠️ SQL init directory not found: {sql_init_dir}")
        
    conn.commit()
    conn.close()


def get_last_synced_block(db_path: str, contract_name: str, event_name: str) -> int | None:
    """Query the last synced block for a specific contract+event"""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    try:
        c.execute(
            "SELECT last_block FROM sync_status WHERE contract_name = ? AND event_name = ?",
            (contract_name, event_name)
        )
        row = c.fetchone()
        conn.close()
        return row[0] if row else None
    except sqlite3.OperationalError:
        conn.close()
        return None


def get_min_from_block_for_address(
    db_path: str,
    address: str,
    addr_topic_to_event_def: dict[str, dict[str, EventDef]],
    origin_blocks: int,
    to_block: int
) -> int:
    """Compute min from_block across all (contract_name, event_name) for this address."""
    topic_to_def = addr_topic_to_event_def.get(address, {})
    min_from = to_block + 1
    for ed in topic_to_def.values():
        last = get_last_synced_block(db_path, ed.contract_name, ed.name)
        from_b = (last + 1) if last is not None else origin_blocks
        min_from = min(min_from, from_b)
    return min_from


def save_events_to_db(
    db_path: str,
    decoded_events: list[dict],
    to_block: int,
    all_synced_keys: set[tuple[str, str]] | None = None,
) -> int:
    """Batch insert decoded events and update sync_status. Use to_block (processed range end) for last_block. Returns inserted count."""
    base_fields = {'blockNumber', 'transactionHash', 'transactionIndex', 'logIndex', 'address', 'round', 'event_name', 'contract_name'}
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    inserted = 0

    # Track max block per (contract_name, event_name)
    event_max_block: dict[tuple[str, str], int] = {}

    for event in decoded_events:
        event_name = event.get('event_name', 'Unknown')
        contract_name = event.get('contract_name', 'Unknown')
        block_num = event.get('blockNumber', 0)
        key = (contract_name, event_name)
        event_max_block[key] = max(event_max_block.get(key, 0), block_num)

        decoded_data = {k: v for k, v in event.items() if k not in base_fields}
        decoded_json = json.dumps(decoded_data, default=str)
        
        try:
            c.execute('''INSERT OR IGNORE INTO events
                        (contract_name, event_name, round, block_number, tx_hash, tx_index, log_index, address, decoded_data)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                      (contract_name, event_name, event.get('round'),
                       block_num, event.get('transactionHash'),
                       event.get('transactionIndex'), event.get('logIndex'),
                       event.get('address'), decoded_json))
            inserted += c.rowcount
        except Exception as e:
            log(f"⚠️  Failed to insert event: {e}")

    keys_to_update = event_max_block.keys() | (all_synced_keys or set())
    for (contract_name, event_name) in keys_to_update:
        c.execute('''INSERT OR REPLACE INTO sync_status (contract_name, event_name, last_block, updated_at)
                    VALUES (?, ?, ?, ?)''',
                  (contract_name, event_name, to_block, datetime.now().isoformat()))

    conn.commit()
    conn.close()
    return inserted


# ============================================================================
# Event Log Fetching (Direct RPC - High Performance)
# ============================================================================

async def fetch_logs_range_rpc(
    client: httpx.AsyncClient,
    contract_addresses: list[str],
    from_block: int,
    to_block: int,
    rpc_url: str,
    request_id: int,
    max_retries: int = 5
) -> tuple[int, int, list[dict] | None, str | None]:
    """
    Fetch all logs for a specific block range for multiple contracts.
    """
    payload = {
        "jsonrpc": "2.0",
        "method": "eth_getLogs",
        "params": [{
            "address": contract_addresses,
            "fromBlock": hex(from_block),
            "toBlock": hex(to_block)
        }],
        "id": request_id
    }
    
    for attempt in range(max_retries):
        try:
            response = await client.post(rpc_url, json=payload, timeout=30.0)
            data = response.json()
            
            if "error" in data:
                error_msg = data["error"].get("message", str(data["error"]))
                if "limit" in error_msg.lower() or "too many" in error_msg.lower():
                    return (from_block, to_block, None, f"RANGE_TOO_LARGE:{error_msg}")
                if attempt < max_retries - 1:
                    await asyncio.sleep(0.2)
                    continue
                return (from_block, to_block, None, error_msg)
            
            logs = data.get("result", [])
            return (from_block, to_block, logs, None)
            
        except httpx.TimeoutException:
            if attempt < max_retries - 1:
                await asyncio.sleep(0.5)
                continue
            return (from_block, to_block, None, "Timeout")
            
        except Exception as e:
            if attempt < max_retries - 1:
                await asyncio.sleep(0.2)
                continue
            return (from_block, to_block, None, str(e))
    
    return (from_block, to_block, None, "Max retries exceeded")


async def fetch_logs_with_split(
    client: httpx.AsyncClient,
    contract_addresses: list[str],
    from_block: int,
    to_block: int,
    rpc_url: str,
    request_id: int,
    max_retries: int = 5
) -> list[dict]:
    """
    Fetch logs with automatic range splitting on failure.
    """
    result = await fetch_logs_range_rpc(
        client, contract_addresses, from_block, to_block, 
        rpc_url, request_id, max_retries
    )
    
    if result[2] is not None:
        return result[2]
    
    if to_block - from_block < 1000:
        return []
    
    mid = (from_block + to_block) // 2
    logs1 = await fetch_logs_with_split(
        client, contract_addresses, from_block, mid,
        rpc_url, request_id * 2, max_retries
    )
    logs2 = await fetch_logs_with_split(
        client, contract_addresses, mid + 1, to_block,
        rpc_url, request_id * 2 + 1, max_retries
    )
    
    return logs1 + logs2


async def fetch_all_logs_rpc(config: ProcessConfig, contracts: list[ProcessContractConfig]) -> list[dict]:
    """
    Fetch logs intelligently. For each chunk, only include contracts that need syncing.
    """
    # Find the global minimum start block across all contracts
    min_from_block = min((c.from_block for c in contracts), default=config.to_block + 1)
    
    if min_from_block > config.to_block:
        return []
        
    ranges = []
    current = min_from_block
    while current <= config.to_block:
        end = min(current + config.max_blocks_per_request - 1, config.to_block)
        ranges.append((current, end))
        current = end + 1
    
    total_ranges = len(ranges)
    total_blocks = config.to_block - min_from_block + 1
    log(f"📦 Intelligent Block range: {min_from_block} → {config.to_block} ({total_blocks:,} blocks)")
    log(f"⚙️  Processing {total_ranges} ranges with {config.max_concurrent_jobs} concurrent jobs...")
    
    semaphore = asyncio.Semaphore(config.max_concurrent_jobs)
    limits = httpx.Limits(max_connections=config.max_concurrent_jobs + 20, max_keepalive_connections=50)
    timeout = httpx.Timeout(30.0, connect=10.0)
    
    async with httpx.AsyncClient(limits=limits, timeout=timeout) as client:
        # Test connection with one address
        test_address = contracts[0].address if contracts else None
        if test_address:
            log("🔗 Testing RPC connection...")
            test_result = await fetch_logs_range_rpc(
                client, [test_address],
                min_from_block, min(min_from_block + 100, config.to_block),
                config.rpc_url, 0, 1
            )
            if test_result[3]:
                log(f"❌ RPC connection failed: {test_result[3]}")
                return []
            log(f"✅ RPC connection OK")
            
        async def fetch_with_semaphore_and_split(chunk_start: int, chunk_end: int, req_id: int) -> list[dict]:
            async with semaphore:
                # Find contracts that actually need syncing in this chunk
                # i.e., their from_block is <= chunk_end
                active_contracts = [c for c in contracts if c.from_block <= chunk_end]
                
                if not active_contracts:
                    return []
                    
                addresses = [c.address for c in active_contracts]
                
                logs = await fetch_logs_with_split(
                    client,
                    addresses,
                    chunk_start,
                    chunk_end,
                    config.rpc_url,
                    req_id,
                    config.max_retries
                )
                
                # Filter out logs that are older than the specific contract's from_block
                # (since eth_getLogs might return logs for the whole chunk even if a contract only needed from the middle of the chunk)
                valid_logs = []
                for log_entry in logs:
                    log_addr = to_checksum_address(log_entry.get('address', ''))
                    log_block = int(log_entry.get('blockNumber', '0x0'), 16)
                    
                    contract = next((c for c in active_contracts if c.address == log_addr), None)
                    if contract and log_block >= contract.from_block:
                        valid_logs.append(log_entry)
                        
                return valid_logs
        
        tasks = [fetch_with_semaphore_and_split(start, end, i) for i, (start, end) in enumerate(ranges)]
        
        completed = 0
        all_logs = []
        start_time = datetime.now()
        last_log_time = start_time
        
        log("🚀 Starting intelligent parallel fetch...")
        for coro in asyncio.as_completed(tasks):
            logs = await coro
            all_logs.extend(logs)
            completed += 1
            now = datetime.now()
            if (now - last_log_time).total_seconds() >= 2 or completed == total_ranges or completed == 1:
                progress = completed * 100 // total_ranges
                elapsed = (now - start_time).total_seconds()
                rate = completed / elapsed if elapsed > 0 else 0
                eta = (total_ranges - completed) / rate if rate > 0 else 0
                log(f"🔄 Progress: {progress}% ({completed}/{total_ranges}) | {rate:.1f} req/s | ETA: {eta:.0f}s | Logs: {len(all_logs):,}")
                last_log_time = now
    
    return all_logs


def convert_rpc_log_to_event(log: dict) -> dict:
    """Convert RPC log format to internal event format"""
    return {
        'blockNumber': int(log.get('blockNumber', '0x0'), 16),
        'transactionHash': log.get('transactionHash', ''),
        'transactionIndex': int(log.get('transactionIndex', '0x0'), 16),
        'logIndex': int(log.get('logIndex', '0x0'), 16),
        'address': log.get('address', ''),
        'topics': log.get('topics', []),
        'data': log.get('data', '0x')
    }


# ============================================================================
# Event Decoding
# ============================================================================

def decode_event(event: dict, addr_topic_to_event_def: dict[str, dict[str, EventDef]]) -> dict | None:
    """Decode a single event log into a dict of field values."""
    topics = event.get('topics', [])
    if not topics:
        return None
        
    topic0 = topics[0]
    address = to_checksum_address(event.get('address', ''))
    
    topic_to_event_def = addr_topic_to_event_def.get(address)
    if not topic_to_event_def:
        return None
        
    event_def = topic_to_event_def.get(topic0)
    if not event_def:
        return None
        
    result = {
        'contract_name': event_def.contract_name,
        'event_name': event_def.name,
        'blockNumber': event.get('blockNumber', ''),
        'transactionHash': event.get('transactionHash', ''),
        'transactionIndex': event.get('transactionIndex', ''),
        'logIndex': event.get('logIndex', ''),
        'address': event.get('address', '')
    }
    
    data = event.get('data', '0x')
    topic_index = 1
    
    non_indexed_types = []
    
    for param in event_def.params:
        if not param.indexed:
            if param.type == 'tuple' and param.components:
                comp_types = tuple(c.get('type', '') for c in param.components)
                non_indexed_types.append(comp_types)
            else:
                non_indexed_types.append(param.type)
    
    decoded_data = []
    if data != '0x' and non_indexed_types:
        try:
            type_strs = []
            for t in non_indexed_types:
                if isinstance(t, tuple):
                    type_strs.append(f"({','.join(t)})")
                else:
                    type_strs.append(t)
            
            decoded_data = list(decode(type_strs, bytes.fromhex(data[2:])))
        except Exception:
            decoded_data = [None] * len(non_indexed_types)
    
    data_index = 0
    for param in event_def.params:
        if param.indexed:
            if topic_index < len(topics):
                raw_value = topics[topic_index]
                value = decode_indexed_value(raw_value, param.type)
                topic_index += 1
            else:
                value = None
            result[param.name] = value
        else:
            if data_index < len(decoded_data):
                raw_value = decoded_data[data_index]
                if param.type == 'tuple' and param.components:
                    if isinstance(raw_value, (list, tuple)):
                        for i, comp in enumerate(param.components):
                            col_name = f"{param.name}.{comp.get('name', '')}"
                            comp_value = raw_value[i] if i < len(raw_value) else None
                            result[col_name] = format_value(comp_value, comp.get('type', ''))
                    else:
                        for comp in param.components:
                            col_name = f"{param.name}.{comp.get('name', '')}"
                            result[col_name] = None
                else:
                    result[param.name] = format_value(raw_value, param.type)
                data_index += 1
            else:
                if param.type == 'tuple' and param.components:
                    for comp in param.components:
                        col_name = f"{param.name}.{comp.get('name', '')}"
                        result[col_name] = None
                else:
                    result[param.name] = None
    
    return result


def decode_indexed_value(raw_value: str, param_type: str) -> Any:
    if not raw_value: return None
    try:
        if param_type == 'address':
            addr = '0x' + raw_value[-40:]
            return to_checksum_address(addr)
        elif param_type.startswith('uint') or param_type.startswith('int'):
            return int(raw_value, 16)
        elif param_type == 'bool':
            return int(raw_value, 16) != 0
        elif param_type.startswith('bytes'):
            return raw_value
        else:
            return raw_value
    except Exception:
        return raw_value


def format_value(value: Any, param_type: str) -> Any:
    if value is None: return ''
    try:
        if param_type == 'address':
            return to_checksum_address(value) if value else ''
        elif param_type.endswith('[]'):
            if isinstance(value, (list, tuple)):
                return '[' + ';'.join(str(v) for v in value) + ']'
            return str(value)
        elif param_type.startswith('bytes'):
            if isinstance(value, bytes): return '0x' + value.hex()
            return str(value)
        elif param_type == 'bool':
            return 'true' if value else 'false'
        elif isinstance(value, bytes):
            return '0x' + value.hex()
        else:
            return value
    except Exception:
        return str(value) if value is not None else ''


# ============================================================================
# Main Processing
# ============================================================================

async def process_events(config: ProcessConfig) -> bool:
    log("")
    log("━" * 50)
    log(f"🚀 High Performance Event Processor (Direct RPC - Batch Mode)")
    log(f"🌐 RPC: {config.rpc_url}")
    log("━" * 50)
    
    start_time = datetime.now()
    
    log("📖 Loading contract configurations...")
    with open(config.config_file, 'r') as f:
        contracts_info = json.load(f)
        
    if config.db_path:
        log("📂 Initializing database...")
        init_db(config.db_path)
    else:
        log("❌ A database path (--db-path) is required to store events.")
        return False
        
    addr_topic_to_event_def: dict[str, dict[str, EventDef]] = {}
    
    # Build addr_topic_to_event_def from all configs
    for c in contracts_info:
        name = c['name']
        env_var = c.get('address_env_var')
        if env_var:
            raw_address = os.environ.get(env_var)
            if not raw_address:
                log(f"⚠️  Skipping {name}: Environment variable {env_var} not found")
                continue
        else:
            raw_address = c.get('address')
        if not raw_address:
            log(f"⚠️  Skipping {name}: No address provided")
            continue

        address = to_checksum_address(raw_address)
        abi_files = c.get('abi_files')
        if not abi_files:
            log(f"⚠️  Skipping {name}: No abi_files provided")
            continue
        event_defs = {}
        for abi_path in abi_files:
            abi = load_abi(abi_path)
            event_defs.update(get_all_event_defs(abi, name))
        if address not in addr_topic_to_event_def:
            addr_topic_to_event_def[address] = {}
        addr_topic_to_event_def[address].update(event_defs)

    # Compute from_block per address (min across all contract+event for that address)
    contract_configs: list[ProcessContractConfig] = []
    for address, topic_to_def in addr_topic_to_event_def.items():
        c_from_block = get_min_from_block_for_address(
            config.db_path, address, addr_topic_to_event_def,
            config.origin_blocks, config.to_block
        )
        event_summary = ", ".join(sorted({ed.name for ed in topic_to_def.values()}))
        log(f"   - {address}: from_block={c_from_block} (events: {event_summary})")
        if c_from_block > config.to_block:
            log(f"     ✅ Already up to date (>= {config.to_block})")

        contract_configs.append(ProcessContractConfig(
            name=address,  # Use address as identifier for fetch; event_defs carry contract_name
            address=address,
            abi_file="",
            from_block=c_from_block,
            event_defs=topic_to_def
        ))

    log(f"✅ Loaded {len(contract_configs)} unique addresses with event defs.")
    
    fetch_elapsed = 0.0
    decode_elapsed = 0.0
    new_event_count = 0
    
    # Identify contracts that actually need syncing
    contracts_to_sync = [c for c in contract_configs if c.from_block <= config.to_block]
    if not contracts_to_sync:
        log(f"\n✅ All contracts are already up to date (to_block={config.to_block})")
    else:
        log(f"\n📡 Fetching event logs for {len(contracts_to_sync)} addresses...")
        fetch_start = datetime.now()
        raw_logs = await fetch_all_logs_rpc(config, contracts_to_sync)
        fetch_elapsed = (datetime.now() - fetch_start).total_seconds()
        log(f"✅ Fetched {len(raw_logs)} total logs in {fetch_elapsed:.2f}s")
        
        all_synced_keys = {
            (ed.contract_name, ed.name)
            for c in contracts_to_sync
            for ed in c.event_defs.values()
        }
        if raw_logs:
            log("\n🔓 Decoding events dynamically by address and topic0...")
            decode_start = datetime.now()
            decoded_events = []
            for i, raw_log in enumerate(raw_logs):
                event = convert_rpc_log_to_event(raw_log)
                decoded = decode_event(event, addr_topic_to_event_def)
                if decoded:
                    decoded['round'] = calc_round(
                        decoded.get('blockNumber', 0), config.origin_blocks, config.phase_blocks
                    )
                    decoded_events.append(decoded)
                if (i + 1) % 5000 == 0:
                    log(f"   Decoded {i + 1}/{len(raw_logs)} events...")
            decode_elapsed = (datetime.now() - decode_start).total_seconds()
            log(f"✅ Successfully decoded {len(decoded_events)} known events in {decode_elapsed:.2f}s")
            new_event_count = len(decoded_events)
            log(f"\n💾 Saving {new_event_count} events to SQLite...")
            inserted = save_events_to_db(
                config.db_path, decoded_events, config.to_block, all_synced_keys
            )
            log(f"✅ Inserted {inserted} new rows (duplicates ignored)")
        else:
            save_events_to_db(config.db_path, [], config.to_block, all_synced_keys)
            log("📌 No new events in this batch (sync_status updated to to_block)")
    
    # Final report
    elapsed = (datetime.now() - start_time).total_seconds()
    events_per_sec = new_event_count / elapsed if elapsed > 0 else 0
    log("")
    log("━" * 50)
    log("📊 Processing Complete")
    log("━" * 50)
    log(f"✅ Processed {new_event_count} new events")
    log(f"⏱️  Total time: {elapsed:.2f}s ({events_per_sec:.0f} events/s)")
    if fetch_elapsed > 0:
        log(f"   - Fetching: {fetch_elapsed:.2f}s")
    if decode_elapsed > 0:
        log(f"   - Decoding: {decode_elapsed:.2f}s")
    log(f"📁 SQLite DB: {config.db_path}")
    
    return True


def main():
    parser = argparse.ArgumentParser(
        description='LOVE20 Event Log Processor - Intelligent Batch Implementation'
    )
    parser.add_argument('--config', required=True, help='Path to JSON config containing contracts info')
    parser.add_argument('--rpc', '-r', required=True, help='RPC URL')
    parser.add_argument('--to-block', '-t', type=int, required=True, help='Ending block number')
    parser.add_argument('--max-blocks', type=int, default=4000, help='Max blocks per request')
    parser.add_argument('--concurrency', type=int, default=10, help='Max concurrent requests')
    parser.add_argument('--retries', type=int, default=3, help='Max retries per request')
    parser.add_argument('--db-path', required=True, help='SQLite database path for persistent storage')
    parser.add_argument('--origin-blocks', type=int, default=0, help='Global Origin block number')
    parser.add_argument('--phase-blocks', type=int, default=0, help='Blocks per round for round calculation')
    
    args = parser.parse_args()
    
    if args.db_path:
        os.makedirs(os.path.dirname(args.db_path), exist_ok=True)
    
    config = ProcessConfig(
        config_file=args.config,
        rpc_url=args.rpc,
        to_block=args.to_block,
        max_blocks_per_request=args.max_blocks,
        max_concurrent_jobs=args.concurrency,
        max_retries=args.retries,
        db_path=args.db_path,
        origin_blocks=args.origin_blocks,
        phase_blocks=args.phase_blocks
    )
    
    success = asyncio.run(process_events(config))
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
