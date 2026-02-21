#!/usr/bin/env python3
"""
LOVE20 Event Log Processor - High Performance Python Implementation

Replaces shell-based event processing with Python for 50-100x performance improvement.
Uses httpx for direct RPC calls, asyncio for parallel fetching, eth-abi for decoding.
"""

import asyncio
import json
import os
import re
import sqlite3
import sys
import argparse
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx
import pandas as pd
from eth_abi import decode
from eth_utils import event_abi_to_log_topic, to_checksum_address

# Force unbuffered output for real-time logging
def log(msg: str):
    print(msg, flush=True)


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


@dataclass
class ProcessConfig:
    """Processing configuration"""
    contract_address: str
    abi_file: str
    event_name: str
    rpc_url: str
    from_block: int
    to_block: int
    output_dir: str
    max_blocks_per_request: int = 50000  # Large chunks to reduce request count
    max_concurrent_jobs: int = 50        # High concurrency
    max_retries: int = 5
    output_name: str = None  # Custom output file name prefix (overrides ABI-derived name)
    db_path: str = None      # SQLite database path for persistent storage & incremental sync
    origin_blocks: int = 0   # Origin block number for round calculation
    phase_blocks: int = 0    # Blocks per round for round calculation


# ============================================================================
# ABI Parsing
# ============================================================================

def load_abi(abi_file: str) -> list[dict]:
    """Load ABI from JSON file"""
    with open(abi_file, 'r') as f:
        data = json.load(f)
    return data.get('abi', data)  # Handle both {abi: [...]} and [...] formats


def get_event_def(abi: list[dict], event_name: str) -> EventDef:
    """Extract event definition from ABI"""
    for item in abi:
        if item.get('type') == 'event' and item.get('name') == event_name:
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
            
            return EventDef(name=event_name, params=params, topic0=topic0)
    
    raise ValueError(f"Event '{event_name}' not found in ABI")


def expand_tuple_params(params: list[EventParam]) -> list[tuple[str, str]]:
    """
    Expand tuple parameters into flat list of (name, type) pairs.
    Returns list of (column_name, solidity_type) tuples.
    """
    result = []
    
    for param in params:
        if param.type == 'tuple' and param.components:
            # Expand tuple components
            for comp in param.components:
                col_name = f"{param.name}.{comp.get('name', '')}"
                result.append((col_name, comp.get('type', '')))
        else:
            result.append((param.name, param.type))
    
    return result


def get_non_indexed_types(params: list[EventParam]) -> str:
    """Get comma-separated non-indexed types for ABI decoding"""
    types = []
    for param in params:
        if not param.indexed:
            if param.type == 'tuple' and param.components:
                comp_types = ','.join(c.get('type', '') for c in param.components)
                types.append(f"({comp_types})")
            else:
                types.append(param.type)
    return ','.join(types)


# ============================================================================
# SQLite Database Operations
# ============================================================================

def calc_round(block_number: int, origin_blocks: int, phase_blocks: int) -> int | None:
    """Calculate protocol round from block number"""
    if phase_blocks <= 0 or block_number < origin_blocks:
        return None
    return (block_number - origin_blocks) // phase_blocks


def init_db(db_path: str):
    """Create tables and indices if they don't exist"""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS sync_status (
        contract_name TEXT NOT NULL,
        event_name    TEXT NOT NULL,
        last_block    INTEGER NOT NULL,
        updated_at    TEXT NOT NULL,
        PRIMARY KEY (contract_name, event_name)
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS events (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        contract_name   TEXT NOT NULL,
        event_name      TEXT NOT NULL,
        round           INTEGER,
        block_number    INTEGER NOT NULL,
        tx_hash         TEXT NOT NULL,
        tx_index        INTEGER,
        log_index       INTEGER,
        address         TEXT,
        decoded_data    TEXT NOT NULL,
        created_at      TEXT DEFAULT CURRENT_TIMESTAMP
    )''')
    c.execute('CREATE INDEX IF NOT EXISTS idx_events_contract_event ON events(contract_name, event_name)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_events_block ON events(block_number)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_events_round ON events(round)')
    c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_events_unique ON events(tx_hash, log_index)')
    _ensure_transfer_views_for_existing(conn)
    conn.commit()
    conn.close()


def _safe_view_name(contract_name: str) -> str:
    """Sanitize contract_name for use in view name (alphanumeric + underscore only)"""
    safe = re.sub(r'[^a-zA-Z0-9_]', '', contract_name)
    return safe or 'unknown'


def _ensure_transfer_view(conn: sqlite3.Connection, contract_name: str):
    """Create view v_<contract_name> for Transfer events with from, to, value, amount."""
    safe_name = _safe_view_name(contract_name)
    escaped = contract_name.replace("'", "''")
    conn.execute(f"""CREATE VIEW IF NOT EXISTS v_{safe_name} AS
        SELECT
            id, contract_name, event_name, round, block_number, tx_hash, tx_index, log_index, address,
            json_extract(decoded_data, '$.from')  AS "from",
            json_extract(decoded_data, '$.to')    AS "to",
            json_extract(decoded_data, '$.value') AS value,
            CAST(json_extract(decoded_data, '$.value') AS REAL) / 1e18 AS amount,
            created_at
        FROM events
        WHERE event_name = 'Transfer' AND contract_name = '{escaped}'""")


def _ensure_transfer_views_for_existing(conn: sqlite3.Connection):
    """Create v_<name> views for every contract_name that has Transfer events."""
    c = conn.cursor()
    c.execute("SELECT DISTINCT contract_name FROM events WHERE event_name = 'Transfer'")
    for (name,) in c.fetchall():
        _ensure_transfer_view(conn, name)


def get_last_synced_block(db_path: str, contract_name: str, event_name: str) -> int | None:
    """Query the last synced block for a given contract + event"""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('SELECT last_block FROM sync_status WHERE contract_name = ? AND event_name = ?',
              (contract_name, event_name))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def save_events_to_db(db_path: str, contract_name: str, event_name: str,
                      decoded_events: list[dict], last_block: int,
                      origin_blocks: int = 0, phase_blocks: int = 0) -> int:
    """Batch insert decoded events and update sync_status. Returns inserted count."""
    base_fields = {'blockNumber', 'transactionHash', 'transactionIndex', 'logIndex', 'address', 'round'}
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    inserted = 0

    for event in decoded_events:
        decoded_data = {k: v for k, v in event.items() if k not in base_fields}
        decoded_json = json.dumps(decoded_data, default=str)
        block_num = event.get('blockNumber', 0)
        rnd = calc_round(block_num, origin_blocks, phase_blocks)
        try:
            c.execute('''INSERT OR IGNORE INTO events
                        (contract_name, event_name, round, block_number, tx_hash, tx_index, log_index, address, decoded_data)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                      (contract_name, event_name, rnd,
                       block_num, event.get('transactionHash'),
                       event.get('transactionIndex'), event.get('logIndex'),
                       event.get('address'), decoded_json))
            inserted += c.rowcount
        except Exception as e:
            log(f"⚠️  Failed to insert event: {e}")

    c.execute('''INSERT OR REPLACE INTO sync_status (contract_name, event_name, last_block, updated_at)
                VALUES (?, ?, ?, ?)''',
              (contract_name, event_name, last_block, datetime.now().isoformat()))

    conn.commit()
    if event_name == 'Transfer':
        _ensure_transfer_view(conn, contract_name)
        conn.commit()
    conn.close()
    return inserted


def load_all_events_from_db(db_path: str, contract_name: str, event_name: str) -> list[dict]:
    """Load all stored events from DB for CSV/XLSX full export"""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''SELECT round, block_number, tx_hash, tx_index, log_index, address, decoded_data
                 FROM events WHERE contract_name = ? AND event_name = ?
                 ORDER BY block_number, log_index''',
              (contract_name, event_name))

    events = []
    for row in c.fetchall():
        event = {
            'round': row[0],
            'blockNumber': row[1],
            'transactionHash': row[2],
            'transactionIndex': row[3],
            'logIndex': row[4],
            'address': row[5],
        }
        event.update(json.loads(row[6]))
        events.append(event)

    conn.close()
    return events


# ============================================================================
# Event Log Fetching (Direct RPC - High Performance)
# ============================================================================

async def fetch_logs_range_rpc(
    client: httpx.AsyncClient,
    contract_address: str,
    topic0: str,
    from_block: int,
    to_block: int,
    rpc_url: str,
    request_id: int,
    max_retries: int = 5
) -> tuple[int, int, list[dict] | None, str | None]:
    """
    Fetch logs for a specific block range using direct RPC call.
    Returns (from_block, to_block, logs_list, error).
    """
    payload = {
        "jsonrpc": "2.0",
        "method": "eth_getLogs",
        "params": [{
            "address": contract_address,
            "topics": [topic0],
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
                # Check if error is due to range too large
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
    contract_address: str,
    topic0: str,
    from_block: int,
    to_block: int,
    rpc_url: str,
    request_id: int,
    max_retries: int = 5
) -> list[dict]:
    """
    Fetch logs with automatic range splitting on failure.
    If a range fails due to being too large, split it and retry.
    """
    result = await fetch_logs_range_rpc(
        client, contract_address, topic0, from_block, to_block, 
        rpc_url, request_id, max_retries
    )
    
    if result[2] is not None:  # Success
        return result[2]
    
    # If range is small enough, don't split further
    if to_block - from_block < 1000:
        return []
    
    # Split the range and retry
    mid = (from_block + to_block) // 2
    logs1 = await fetch_logs_with_split(
        client, contract_address, topic0, from_block, mid,
        rpc_url, request_id * 2, max_retries
    )
    logs2 = await fetch_logs_with_split(
        client, contract_address, topic0, mid + 1, to_block,
        rpc_url, request_id * 2 + 1, max_retries
    )
    
    return logs1 + logs2


async def fetch_all_logs_rpc(config: ProcessConfig, event_def: EventDef) -> list[dict]:
    """
    Fetch all logs in parallel using direct RPC calls with automatic splitting.
    Returns list of raw log dicts from RPC.
    """
    # Create block ranges
    ranges = []
    current = config.from_block
    while current <= config.to_block:
        end = min(current + config.max_blocks_per_request - 1, config.to_block)
        ranges.append((current, end))
        current = end + 1
    
    total_ranges = len(ranges)
    total_blocks = config.to_block - config.from_block + 1
    log(f"📦 Block range: {config.from_block} → {config.to_block} ({total_blocks:,} blocks)")
    log(f"⚙️  Processing {total_ranges} ranges with {config.max_concurrent_jobs} concurrent jobs...")
    log(f"📊 Blocks per request: {config.max_blocks_per_request:,}")
    
    # Use semaphore for concurrency control
    semaphore = asyncio.Semaphore(config.max_concurrent_jobs)
    
    # Create shared HTTP client with connection pooling
    limits = httpx.Limits(max_connections=config.max_concurrent_jobs + 20, max_keepalive_connections=50)
    timeout = httpx.Timeout(30.0, connect=10.0)
    
    async with httpx.AsyncClient(limits=limits, timeout=timeout) as client:
        # Test connectivity first
        log("🔗 Testing RPC connection...")
        test_result = await fetch_logs_range_rpc(
            client, config.contract_address, event_def.topic0,
            config.from_block, min(config.from_block + 100, config.to_block),
            config.rpc_url, 0, 1
        )
        if test_result[3]:
            log(f"❌ RPC connection failed: {test_result[3]}")
            return []
        log(f"✅ RPC connection OK, found {len(test_result[2] or [])} logs in test range")
        
        async def fetch_with_semaphore_and_split(from_block: int, to_block: int, req_id: int) -> list[dict]:
            async with semaphore:
                return await fetch_logs_with_split(
                    client,
                    config.contract_address,
                    event_def.topic0,
                    from_block,
                    to_block,
                    config.rpc_url,
                    req_id,
                    config.max_retries
                )
        
        # Create all tasks
        tasks = [fetch_with_semaphore_and_split(start, end, i) for i, (start, end) in enumerate(ranges)]
        
        # Progress tracking
        completed = 0
        all_logs = []
        start_time = datetime.now()
        last_log_time = start_time
        
        log("🚀 Starting parallel fetch...")
        log(f"📤 Submitting {len(tasks)} tasks to async executor...")
        for coro in asyncio.as_completed(tasks):
            logs = await coro
            all_logs.extend(logs)
            completed += 1
            now = datetime.now()
            # Log every 2 seconds or at milestones
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

def decode_event(event: dict, event_def: EventDef) -> dict:
    """
    Decode a single event log into a dict of field values.
    Uses eth-abi for decoding.
    """
    result = {
        'blockNumber': event.get('blockNumber', ''),
        'transactionHash': event.get('transactionHash', ''),
        'transactionIndex': event.get('transactionIndex', ''),
        'logIndex': event.get('logIndex', ''),
        'address': event.get('address', '')
    }
    
    topics = event.get('topics', [])
    data = event.get('data', '0x')
    
    # Track indices
    topic_index = 1  # Skip topic0 (event signature)
    
    # Decode non-indexed parameters from data
    non_indexed_types = []
    non_indexed_params = []
    
    for param in event_def.params:
        if not param.indexed:
            if param.type == 'tuple' and param.components:
                comp_types = tuple(c.get('type', '') for c in param.components)
                non_indexed_types.append(comp_types)
            else:
                non_indexed_types.append(param.type)
            non_indexed_params.append(param)
    
    # Decode data if present
    decoded_data = []
    if data != '0x' and non_indexed_types:
        try:
            # Build type string for decoding
            type_strs = []
            for t in non_indexed_types:
                if isinstance(t, tuple):
                    type_strs.append(f"({','.join(t)})")
                else:
                    type_strs.append(t)
            
            decoded_data = list(decode(type_strs, bytes.fromhex(data[2:])))
        except Exception as e:
            print(f"⚠️  Failed to decode data: {e}")
            decoded_data = [None] * len(non_indexed_types)
    
    # Process each parameter
    data_index = 0
    for param in event_def.params:
        if param.indexed:
            # Get value from topics
            if topic_index < len(topics):
                raw_value = topics[topic_index]
                value = decode_indexed_value(raw_value, param.type)
                topic_index += 1
            else:
                value = None
            
            result[param.name] = value
            
        else:
            # Get value from decoded data
            if data_index < len(decoded_data):
                raw_value = decoded_data[data_index]
                
                if param.type == 'tuple' and param.components:
                    # Expand tuple into separate columns
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
    """Decode an indexed parameter value from topic"""
    if not raw_value:
        return None
    
    try:
        if param_type == 'address':
            # Extract address from 32-byte topic (last 20 bytes)
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
    """Format a decoded value for CSV output"""
    if value is None:
        return ''
    
    try:
        if param_type == 'address':
            return to_checksum_address(value) if value else ''
        
        elif param_type.endswith('[]'):
            # Array type - format as semicolon-separated for CSV safety
            if isinstance(value, (list, tuple)):
                return '[' + ';'.join(str(v) for v in value) + ']'
            return str(value)
        
        elif param_type.startswith('bytes'):
            if isinstance(value, bytes):
                return '0x' + value.hex()
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
# CSV/XLSX Generation
# ============================================================================

def generate_csv(events: list[dict], event_def: EventDef, output_file: str) -> int:
    """
    Generate CSV file from decoded events using pandas.
    Returns number of rows written.
    """
    if not events:
        log("⚠️  No events to write")
        return 0
    
    # Build column order (round first if present)
    base_columns = ['round', 'blockNumber', 'transactionHash', 'transactionIndex', 'logIndex', 'address']
    param_columns = []
    
    for param in event_def.params:
        if param.type == 'tuple' and param.components:
            for comp in param.components:
                param_columns.append(f"{param.name}.{comp.get('name', '')}")
        else:
            param_columns.append(param.name)
    
    columns = base_columns + param_columns
    
    # Create DataFrame
    df = pd.DataFrame(events)
    
    # Reorder columns (add missing ones as empty)
    for col in columns:
        if col not in df.columns:
            df[col] = ''
    
    df = df[columns]
    
    # Write CSV
    df.to_csv(output_file, index=False)
    
    return len(df)


def convert_csv_to_xlsx(csv_file: str, xlsx_file: str) -> bool:
    """Convert CSV to XLSX with formatting"""
    try:
        df = pd.read_csv(csv_file)
        
        with pd.ExcelWriter(xlsx_file, engine='openpyxl') as writer:
            df.to_excel(writer, sheet_name='Events', index=False, freeze_panes=(1, 0))
            
            # Get workbook and worksheet for formatting
            workbook = writer.book
            worksheet = writer.sheets['Events']
            
            # Auto-adjust column widths
            for column in worksheet.columns:
                max_length = 0
                column_letter = column[0].column_letter
                
                for cell in column:
                    try:
                        if len(str(cell.value)) > max_length:
                            max_length = len(str(cell.value))
                    except Exception:
                        pass
                
                adjusted_width = min(max_length + 2, 50)
                worksheet.column_dimensions[column_letter].width = adjusted_width
            
            # Header formatting
            from openpyxl.styles import Font, PatternFill, Border, Side
            
            header_font = Font(bold=True, color="FFFFFF")
            header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
            header_border = Border(
                left=Side(style='thin'),
                right=Side(style='thin'),
                top=Side(style='thin'),
                bottom=Side(style='thin')
            )
            
            for cell in worksheet[1]:
                cell.font = header_font
                cell.fill = header_fill
                cell.border = header_border
            
            # Add summary sheet
            summary_data = {
                'Metric': ['Total Rows', 'Total Columns', 'Source File', 'Conversion Time', 'Generated By'],
                'Value': [len(df), len(df.columns), csv_file, datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'LOVE20 Event Processor (Python)']
            }
            summary_df = pd.DataFrame(summary_data)
            summary_df.to_excel(writer, sheet_name='Summary', index=False)
        
        return True
        
    except Exception as e:
        log(f"❌ Failed to convert to XLSX: {e}")
        return False


# ============================================================================
# Main Processing
# ============================================================================

async def process_events(config: ProcessConfig) -> bool:
    """Main processing function using direct RPC calls"""
    log("")
    log("━" * 50)
    log(f"🚀 High Performance Event Processor (Direct RPC)")
    log(f"📊 Event: {config.event_name}")
    log(f"📍 Contract: {config.contract_address}")
    log(f"🌐 RPC: {config.rpc_url}")
    log("━" * 50)
    
    start_time = datetime.now()
    
    # Resolve output name
    if config.output_name:
        contract_name = config.output_name
    else:
        abi_basename = os.path.basename(config.abi_file)
        contract_name = abi_basename.split('.')[0]
        if contract_name.startswith('I'):
            contract_name = contract_name[1:]
    
    # Incremental sync: adjust from_block based on DB state
    actual_from_block = config.from_block
    if config.db_path:
        init_db(config.db_path)
        last_block = get_last_synced_block(config.db_path, contract_name, config.event_name)
        if last_block is not None:
            actual_from_block = max(config.from_block, last_block + 1)
            log(f"📌 DB last synced block: {last_block}, resuming from {actual_from_block}")
        else:
            log(f"📌 No previous sync found, starting from {actual_from_block}")
    
    # Load ABI and get event definition
    log("📖 Loading ABI...")
    abi = load_abi(config.abi_file)
    event_def = get_event_def(abi, config.event_name)
    log(f"✅ Event topic0: {event_def.topic0}")
    
    fetch_elapsed = 0.0
    decode_elapsed = 0.0
    new_event_count = 0
    
    if actual_from_block > config.to_block:
        log(f"✅ Already up to date (last_block={actual_from_block - 1} >= to_block={config.to_block})")
    else:
        # Fetch logs using direct RPC (high performance)
        fetch_config = ProcessConfig(
            contract_address=config.contract_address,
            abi_file=config.abi_file,
            event_name=config.event_name,
            rpc_url=config.rpc_url,
            from_block=actual_from_block,
            to_block=config.to_block,
            output_dir=config.output_dir,
            max_blocks_per_request=config.max_blocks_per_request,
            max_concurrent_jobs=config.max_concurrent_jobs,
            max_retries=config.max_retries,
            output_name=config.output_name,
            db_path=config.db_path,
        )
        
        log("\n📡 Fetching event logs via direct RPC...")
        fetch_start = datetime.now()
        raw_logs = await fetch_all_logs_rpc(fetch_config, event_def)
        fetch_elapsed = (datetime.now() - fetch_start).total_seconds()
        log(f"✅ Fetched {len(raw_logs)} logs in {fetch_elapsed:.2f}s")
        
        if raw_logs:
            # Convert and decode events
            log("\n🔓 Decoding events...")
            decode_start = datetime.now()
            decoded_events = []
            
            for i, raw_log in enumerate(raw_logs):
                event = convert_rpc_log_to_event(raw_log)
                decoded = decode_event(event, event_def)
                decoded['round'] = calc_round(
                    decoded.get('blockNumber', 0), config.origin_blocks, config.phase_blocks
                )
                decoded_events.append(decoded)
                
                if (i + 1) % 5000 == 0:
                    log(f"   Decoded {i + 1}/{len(raw_logs)} events...")
            
            decode_elapsed = (datetime.now() - decode_start).total_seconds()
            log(f"✅ Decoded {len(decoded_events)} events in {decode_elapsed:.2f}s")
            new_event_count = len(decoded_events)
            
            # Save to SQLite
            if config.db_path:
                log(f"\n💾 Saving {new_event_count} events to SQLite...")
                inserted = save_events_to_db(
                    config.db_path, contract_name, config.event_name,
                    decoded_events, config.to_block,
                    config.origin_blocks, config.phase_blocks
                )
                log(f"✅ Inserted {inserted} new rows (duplicates ignored)")
        elif config.db_path:
            # No new events, but still update sync_status to record progress
            save_events_to_db(config.db_path, contract_name, config.event_name, [], config.to_block,
                              config.origin_blocks, config.phase_blocks)
            log("📌 Sync status updated (no new events)")
    
    # Generate CSV/XLSX: export ALL events from DB if available, otherwise only current batch
    if config.db_path:
        log(f"\n📤 Exporting all events from SQLite...")
        all_events = load_all_events_from_db(config.db_path, contract_name, config.event_name)
        export_events = all_events
        log(f"   Total events in DB: {len(all_events)}")
    else:
        export_events = locals().get('decoded_events', [])
    
    output_base = f"{config.output_dir}/{contract_name}.{config.event_name}"
    csv_file = f"{output_base}.csv"
    xlsx_file = f"{output_base}.xlsx"
    
    if export_events:
        log(f"\n💾 Writing CSV: {csv_file}")
        row_count = generate_csv(export_events, event_def, csv_file)
        log(f"✅ Wrote {row_count} rows")
        
        log(f"\n📊 Converting to Excel: {xlsx_file}")
        if convert_csv_to_xlsx(csv_file, xlsx_file):
            log("✅ Excel file created")
    else:
        log("⚠️  No events to export")
    
    # Final report
    elapsed = (datetime.now() - start_time).total_seconds()
    total_events = len(export_events) if export_events else 0
    events_per_sec = total_events / elapsed if elapsed > 0 else 0
    log("")
    log("━" * 50)
    log("📊 Processing Complete")
    log("━" * 50)
    log(f"✅ New events fetched: {new_event_count}")
    log(f"✅ Total events exported: {total_events}")
    log(f"⏱️  Total time: {elapsed:.2f}s ({events_per_sec:.0f} events/s)")
    if fetch_elapsed > 0:
        log(f"   - Fetching: {fetch_elapsed:.2f}s")
    if decode_elapsed > 0:
        log(f"   - Decoding: {decode_elapsed:.2f}s")
    log(f"📁 CSV: {csv_file}")
    log(f"📁 Excel: {xlsx_file}")
    if config.db_path:
        log(f"📁 SQLite: {config.db_path}")
    
    return True


def main():
    """CLI entry point"""
    parser = argparse.ArgumentParser(
        description='LOVE20 Event Log Processor - High Performance Python Implementation'
    )
    parser.add_argument('--contract', '-c', required=True, help='Contract address')
    parser.add_argument('--abi', '-a', required=True, help='Path to ABI JSON file')
    parser.add_argument('--event', '-e', required=True, help='Event name')
    parser.add_argument('--rpc', '-r', required=True, help='RPC URL')
    parser.add_argument('--from-block', '-f', type=int, required=True, help='Starting block number')
    parser.add_argument('--to-block', '-t', type=int, required=True, help='Ending block number')
    parser.add_argument('--output-dir', '-o', default='./output', help='Output directory')
    parser.add_argument('--name', '-n', default=None, help='Custom output file name prefix (e.g., "erc20" produces "erc20.Transfer.csv")')
    parser.add_argument('--max-blocks', type=int, default=4000, help='Max blocks per request')
    parser.add_argument('--concurrency', type=int, default=10, help='Max concurrent requests')
    parser.add_argument('--retries', type=int, default=3, help='Max retries per request')
    parser.add_argument('--db-path', default=None, help='SQLite database path for persistent storage & incremental sync')
    parser.add_argument('--origin-blocks', type=int, default=0, help='Origin block number for round calculation')
    parser.add_argument('--phase-blocks', type=int, default=0, help='Blocks per round for round calculation')
    
    args = parser.parse_args()
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Create db directory if db-path is specified
    if args.db_path:
        os.makedirs(os.path.dirname(args.db_path), exist_ok=True)
    
    config = ProcessConfig(
        contract_address=args.contract,
        abi_file=args.abi,
        event_name=args.event,
        rpc_url=args.rpc,
        from_block=args.from_block,
        to_block=args.to_block,
        output_dir=args.output_dir,
        max_blocks_per_request=args.max_blocks,
        max_concurrent_jobs=args.concurrency,
        max_retries=args.retries,
        output_name=args.name,
        db_path=args.db_path,
        origin_blocks=args.origin_blocks,
        phase_blocks=args.phase_blocks
    )
    
    success = asyncio.run(process_events(config))
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()

