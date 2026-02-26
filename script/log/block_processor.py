#!/usr/bin/env python3
"""
LOVE20 Block Processor - Fetches and maintains block header metadata.

Runs standalone after event_processor. Determines missing block range from blocks
table, fetches via eth_getBlockByNumber (batch), and inserts/updates blocks.
Writes all blocks including empty ones for contiguous coverage.
"""

import argparse
import asyncio
import os
import sqlite3
import sys
import threading
from datetime import datetime
from pathlib import Path

import httpx

_log_lock = threading.Lock()


def log(msg: str):
    with _log_lock:
        print(msg, file=sys.stderr, flush=True)


def init_db(db_path: str):
    """Ensure blocks table exists by running init SQL."""
    conn = sqlite3.connect(db_path)
    script_dir = Path(__file__).resolve().parent
    sql_init_dir = script_dir / 'sql' / 'init'
    if sql_init_dir.exists() and sql_init_dir.is_dir():
        for f in sorted(sql_init_dir.glob('*.sql')):
            try:
                with open(f, 'r', encoding='utf-8') as sql_file:
                    conn.executescript(sql_file.read())
                log(f"   Init: {f.name}")
            except Exception as e:
                log(f"❌ Error executing {f.name}: {e}")
    conn.commit()
    conn.close()


def get_last_block_in_db(db_path: str) -> int | None:
    """Return MAX(block_number) from blocks, or None if empty."""
    conn = sqlite3.connect(db_path)
    try:
        c = conn.execute("SELECT MAX(block_number) FROM blocks")
        row = c.fetchone()
        conn.close()
        return row[0] if row and row[0] is not None else None
    except sqlite3.OperationalError:
        conn.close()
        return None


async def fetch_blocks_batch(
    client: httpx.AsyncClient,
    rpc_url: str,
    block_numbers: list[int],
    max_retries: int = 5,
) -> list[dict | None]:
    """Fetch multiple blocks via JSON-RPC batch. Returns list aligned with block_numbers."""
    payload = [
        {"jsonrpc": "2.0", "method": "eth_getBlockByNumber", "params": [hex(n), False], "id": i}
        for i, n in enumerate(block_numbers)
    ]
    for attempt in range(max_retries):
        try:
            resp = await client.post(rpc_url, json=payload, timeout=60.0)
            data = resp.json()
            if isinstance(data, dict) and "error" in data:
                raise RuntimeError(data["error"].get("message", str(data["error"])))
            if not isinstance(data, list):
                raise RuntimeError(f"Expected batch response list, got {type(data)}")
            by_id = {r.get("id"): r for r in data if isinstance(r, dict)}
            result = []
            for i in range(len(block_numbers)):
                r = by_id.get(i, {})
                if "error" in r:
                    result.append(None)
                else:
                    result.append(r.get("result"))
            return result
        except httpx.TimeoutException:
            if attempt < max_retries - 1:
                await asyncio.sleep(0.5)
                continue
            raise
        except Exception as e:
            if attempt < max_retries - 1:
                await asyncio.sleep(0.2)
                continue
            raise


def hex_to_int(h: str | None) -> int | None:
    if h is None:
        return None
    try:
        return int(h, 16) if isinstance(h, str) else None
    except (ValueError, TypeError):
        return None


def save_blocks(db_path: str, blocks: list[dict]) -> int:
    """Insert or replace blocks. Returns inserted count."""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    inserted = 0
    for b in blocks:
        if not b:
            continue
        num = hex_to_int(b.get("number"))
        if num is None:
            continue
        ts = hex_to_int(b.get("timestamp"))
        if ts is None:
            ts = 0
        txs = b.get("transactions") or []
        tx_count = len(txs) if isinstance(txs, list) else 0
        try:
            c.execute(
                """INSERT OR REPLACE INTO blocks
                   (block_number, block_hash, parent_hash, timestamp, gas_limit, gas_used,
                    base_fee_per_gas, difficulty, total_difficulty, size, nonce, mix_hash,
                    state_root, transactions_root, receipts_root, miner, extra_data,
                    sha3_uncles, tx_count, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    num,
                    b.get("hash"),
                    b.get("parentHash"),
                    ts,
                    hex_to_int(b.get("gasLimit")),
                    hex_to_int(b.get("gasUsed")),
                    hex_to_int(b.get("baseFeePerGas")),
                    b.get("difficulty"),
                    b.get("totalDifficulty"),
                    hex_to_int(b.get("size")),
                    b.get("nonce"),
                    b.get("mixHash"),
                    b.get("stateRoot"),
                    b.get("transactionsRoot"),
                    b.get("receiptsRoot"),
                    b.get("miner"),
                    b.get("extraData"),
                    b.get("sha3Uncles") or b.get("unclesHash"),
                    tx_count,
                    datetime.now().isoformat(),
                ),
            )
            inserted += 1
        except Exception as e:
            log(f"⚠️  Failed to insert block {num}: {e}")
    conn.commit()
    conn.close()
    return inserted


async def run(
    rpc_url: str,
    to_block: int,
    db_path: str,
    origin_blocks: int,
    batch_size: int = 100,
    max_concurrent: int = 5,
    max_retries: int = 5,
) -> bool:
    log("")
    log("━" * 50)
    log("📦 Block Processor - Fetch and maintain block metadata")
    log(f"🌐 RPC: {rpc_url}")
    log("━" * 50)

    os.makedirs(os.path.dirname(db_path) or ".", exist_ok=True)
    init_db(db_path)

    last = get_last_block_in_db(db_path)
    from_block = (last + 1) if last is not None else origin_blocks

    if from_block > to_block:
        log(f"✅ Blocks already up to date (last={last}, to_block={to_block})")
        return True

    total = to_block - from_block + 1
    log(f"📦 Fetching blocks {from_block} → {to_block} ({total:,} blocks)")

    ranges = []
    cur = from_block
    while cur <= to_block:
        end = min(cur + batch_size - 1, to_block)
        ranges.append((cur, end))
        cur = end + 1

    limits = httpx.Limits(max_connections=max_concurrent + 20, max_keepalive_connections=50)
    timeout = httpx.Timeout(60.0, connect=10.0)
    total_inserted = 0
    write_lock = asyncio.Lock()

    async with httpx.AsyncClient(limits=limits, timeout=timeout) as client:
        sem = asyncio.Semaphore(max_concurrent)

        async def fetch_and_save(lo: int, hi: int) -> int:
            async with sem:
                nums = list(range(lo, hi + 1))
                results = await fetch_blocks_batch(client, rpc_url, nums, max_retries)
                blocks = [r for r in results if r is not None]
            if blocks:
                async with write_lock:
                    return save_blocks(db_path, blocks)
            return 0

        start_time = datetime.now()
        tasks = [asyncio.create_task(fetch_and_save(lo, hi)) for lo, hi in ranges]
        done = 0
        for coro in asyncio.as_completed(tasks):
            total_inserted += await coro
            done += 1
            if done % 100 == 0 or done == len(ranges):
                elapsed = (datetime.now() - start_time).total_seconds()
                rate = total_inserted / elapsed if elapsed > 0 else 0
                log(f"   Progress: {done}/{len(ranges)} ranges | {total_inserted:,} blocks | {rate:.0f} blocks/s | {elapsed:.1f}s")

    elapsed = (datetime.now() - start_time).total_seconds()
    log("")
    log("━" * 50)
    log("📊 Block processing complete")
    log("━" * 50)
    log(f"✅ Inserted {total_inserted:,} blocks in {elapsed:.2f}s")
    log(f"📁 DB: {db_path}")
    return True


def main():
    parser = argparse.ArgumentParser(description="LOVE20 Block Processor")
    parser.add_argument("--rpc", "-r", required=True, help="RPC URL")
    parser.add_argument("--to-block", "-t", type=int, required=True, help="Ending block number")
    parser.add_argument("--db-path", required=True, help="SQLite database path")
    parser.add_argument("--origin-blocks", type=int, default=0, help="Origin block (first block to consider)")
    parser.add_argument("--batch-size", type=int, default=500, help="Blocks per RPC batch request")
    parser.add_argument("--concurrency", type=int, default=20, help="Concurrent batch requests")
    parser.add_argument("--retries", type=int, default=5, help="Max retries per batch")
    args = parser.parse_args()

    success = asyncio.run(
        run(
            rpc_url=args.rpc,
            to_block=args.to_block,
            db_path=args.db_path,
            origin_blocks=args.origin_blocks,
            batch_size=args.batch_size,
            max_concurrent=args.concurrency,
            max_retries=args.retries,
        )
    )
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
