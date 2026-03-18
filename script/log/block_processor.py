#!/usr/bin/env python3
"""
LOVE20 Block Processor - Fetches block metadata and transactions.

Runs standalone after event_processor. Fetches via eth_getBlockByNumber(fullTx=true),
inserts blocks and transactions. Supports backfill when transactions empty but blocks exist.
"""

import argparse
import asyncio
import json
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


def get_last_transaction_block(db_path: str) -> int | None:
    """Return MAX(block_number) from transactions, or None if empty."""
    conn = sqlite3.connect(db_path)
    try:
        c = conn.execute("SELECT MAX(block_number) FROM transactions")
        row = c.fetchone()
        conn.close()
        return row[0] if row and row[0] is not None else None
    except sqlite3.OperationalError:
        conn.close()
        return None


def get_gap_blocks(db_path: str) -> list[int]:
    """Blocks with tx_count>0 but no transactions. Max 10000 to avoid huge fetches."""
    conn = sqlite3.connect(db_path)
    try:
        c = conn.execute(
            """SELECT b.block_number FROM blocks b
               WHERE b.tx_count > 0
                 AND NOT EXISTS (SELECT 1 FROM transactions t WHERE t.block_number = b.block_number)
               ORDER BY b.block_number
               LIMIT 10000"""
        )
        rows = c.fetchall()
        conn.close()
        return [r[0] for r in rows]
    except sqlite3.OperationalError:
        conn.close()
        return []


async def fetch_blocks_batch(
    client: httpx.AsyncClient,
    rpc_url: str,
    block_numbers: list[int],
    max_retries: int = 5,
) -> list[dict | None]:
    """Fetch blocks with full transactions via JSON-RPC batch."""
    payload = [
        {"jsonrpc": "2.0", "method": "eth_getBlockByNumber", "params": [hex(n), True], "id": i}
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


async def fetch_receipts_batch(
    client: httpx.AsyncClient,
    rpc_url: str,
    tx_hashes: list[str],
    max_retries: int = 5,
) -> dict[str, dict | None]:
    """Fetch transaction receipts via JSON-RPC batch. Returns dict mapping tx_hash to receipt."""
    if not tx_hashes:
        return {}

    payload = [
        {"jsonrpc": "2.0", "method": "eth_getTransactionReceipt", "params": [tx_hash], "id": i}
        for i, tx_hash in enumerate(tx_hashes)
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
            result = {}
            for i, tx_hash in enumerate(tx_hashes):
                r = by_id.get(i, {})
                if "error" in r:
                    result[tx_hash] = None
                else:
                    result[tx_hash] = r.get("result")
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

    return {tx_hash: None for tx_hash in tx_hashes}


async def fetch_receipts_chunked(
    client: httpx.AsyncClient,
    rpc_url: str,
    tx_hashes: list[str],
    max_retries: int = 5,
    chunk_size: int = 100,
) -> dict[str, dict | None]:
    """Fetch receipts in bounded batches to avoid oversized JSON-RPC requests."""
    if not tx_hashes:
        return {}

    receipts: dict[str, dict | None] = {}
    for i in range(0, len(tx_hashes), chunk_size):
        chunk = tx_hashes[i : i + chunk_size]
        try:
            receipts.update(await fetch_receipts_batch(client, rpc_url, chunk, max_retries))
        except Exception as e:
            log(f"⚠️  Failed to fetch receipts for {len(chunk)} txs: {e}")
    return receipts


def _hex_to_value(h) -> tuple[str, float]:
    """Return (value_wei_str, amount_human)."""
    wei = 0
    try:
        wei = int(h, 16) if isinstance(h, str) else int(h) if h else 0
    except (ValueError, TypeError):
        pass
    return str(wei), wei / 1e18


def _parse_tx(tx: dict, block_number: int, block_hash: str | None, block_timestamp: int | None, receipt: dict | None = None) -> dict | None:
    """Extract tx fields for DB insert. Returns None if tx is hash-only (fullTx=false).

    If receipt is provided, also extracts status, gas_used, cumulative_gas_used, contract_address, effective_gas_price.
    """
    if not isinstance(tx, dict) or "hash" not in tx:
        return None
    value_wei, amount = _hex_to_value(tx.get("value") or "0")
    access_list = tx.get("accessList")
    if access_list is not None and isinstance(access_list, list):
        access_list = json.dumps(access_list) if access_list else None

    # Extract receipt fields if available
    gas_used = None
    cumulative_gas_used = None
    status = None
    contract_address = None
    effective_gas_price = None
    if receipt:
        gas_used = hex_to_int(receipt.get("gasUsed"))
        cumulative_gas_used = hex_to_int(receipt.get("cumulativeGasUsed"))
        status = hex_to_int(receipt.get("status"))
        contract_address = receipt.get("contractAddress")
        effective_gas_price = hex_to_int(receipt.get("effectiveGasPrice"))

    return {
        "block_number": block_number,
        "block_hash": block_hash or tx.get("blockHash"),
        "block_timestamp": block_timestamp,
        "tx_hash": tx.get("hash"),
        "tx_index": hex_to_int(tx.get("transactionIndex")),
        "from": tx.get("from") or "",
        "to": tx.get("to"),
        "value_wei": value_wei,
        "amount": amount,
        "gas": hex_to_int(tx.get("gas")),
        "gas_price": hex_to_int(tx.get("gasPrice")),
        "max_fee_per_gas": hex_to_int(tx.get("maxFeePerGas")),
        "max_priority_fee_per_gas": hex_to_int(tx.get("maxPriorityFeePerGas")),
        "type": hex_to_int(tx.get("type")),
        "chain_id": hex_to_int(tx.get("chainId")),
        "input": tx.get("input"),
        "nonce": hex_to_int(tx.get("nonce")),
        "v": hex_to_int(tx.get("v")),
        "r": tx.get("r"),
        "s": tx.get("s"),
        "access_list": access_list,
        "gas_used": gas_used,
        "cumulative_gas_used": cumulative_gas_used,
        "status": status,
        "contract_address": contract_address,
        "effective_gas_price": effective_gas_price,
    }


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


def save_transactions(db_path: str, blocks: list[dict], receipts: dict[str, dict | None] | None = None) -> int:
    """Insert transactions from blocks (fullTx). Returns inserted count.

    If receipts dict is provided (tx_hash -> receipt), also inserts status, gas_used, etc.
    """
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    inserted = 0
    ins = """INSERT OR IGNORE INTO transactions
        (block_number, block_hash, block_timestamp, tx_hash, tx_index, "from", "to",
         value_wei, amount, gas, gas_price, max_fee_per_gas, max_priority_fee_per_gas,
         type, chain_id, input, nonce, v, r, s, access_list,
         gas_used, cumulative_gas_used, status, contract_address, effective_gas_price,
         created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"""
    for b in blocks:
        if not b:
            continue
        num = hex_to_int(b.get("number"))
        if num is None:
            continue
        bhash = b.get("hash")
        ts = hex_to_int(b.get("timestamp"))
        txs = b.get("transactions") or []
        if not isinstance(txs, list):
            continue
        for tx in txs:
            tx_hash = tx.get("hash")
            receipt = receipts.get(tx_hash) if receipts else None
            row = _parse_tx(tx, num, bhash, ts, receipt)
            if not row:
                continue
            try:
                c.execute(
                    ins,
                    (
                        row["block_number"],
                        row["block_hash"],
                        row["block_timestamp"],
                        row["tx_hash"],
                        row["tx_index"],
                        row["from"],
                        row["to"],
                        row["value_wei"],
                        row["amount"],
                        row["gas"],
                        row["gas_price"],
                        row["max_fee_per_gas"],
                        row["max_priority_fee_per_gas"],
                        row["type"],
                        row["chain_id"],
                        row["input"],
                        row["nonce"],
                        row["v"],
                        row["r"],
                        row["s"],
                        row["access_list"],
                        row["gas_used"],
                        row["cumulative_gas_used"],
                        row["status"],
                        row["contract_address"],
                        row["effective_gas_price"],
                        datetime.now().isoformat(),
                    ),
                )
                if c.rowcount > 0:
                    inserted += 1
            except Exception as e:
                log(f"⚠️  Failed to insert tx {row.get('tx_hash')}: {e}")
    conn.commit()
    conn.close()
    return inserted


def update_transaction_sync(db_path: str, last_block: int):
    """Update transaction_sync with last processed block."""
    conn = sqlite3.connect(db_path)
    conn.execute(
        "INSERT OR REPLACE INTO transaction_sync (id, last_block, updated_at) VALUES (1, ?, ?)",
        (last_block, datetime.now().isoformat()),
    )
    conn.commit()
    conn.close()


async def run(
    rpc_url: str,
    to_block: int,
    db_path: str,
    origin_blocks: int,
    batch_size: int = 100,
    max_concurrent: int = 5,
    max_retries: int = 5,
    skip_gap_fill: bool = False,
) -> bool:
    log("")
    log("━" * 50)
    log("📦 Block Processor - Fetch and maintain block metadata")
    log(f"🌐 RPC: {rpc_url}")
    log("━" * 50)

    os.makedirs(os.path.dirname(db_path) or ".", exist_ok=True)
    init_db(db_path)

    last_block = get_last_block_in_db(db_path)
    last_tx_block = get_last_transaction_block(db_path)

    if last_tx_block is None:
        from_block = origin_blocks
        to_block_eff = min(last_block, to_block) if last_block is not None else to_block
        if from_block > to_block_eff:
            log(f"✅ Nothing to backfill (blocks empty or single block)")
        else:
            log(f"📥 Backfilling transactions for blocks {from_block} → {to_block_eff}")
    else:
        from_block = last_tx_block + 1
        to_block_eff = to_block
        if from_block > to_block_eff:
            log(f"✅ Already up to date (last_tx={last_tx_block}, to_block={to_block_eff})")

    need_main_sync = (
        (last_tx_block is None and from_block <= to_block_eff)
        or (last_tx_block is not None and from_block <= to_block_eff)
    )
    total = to_block_eff - from_block + 1 if need_main_sync else 0

    limits = httpx.Limits(max_connections=max_concurrent + 20, max_keepalive_connections=50)
    timeout = httpx.Timeout(60.0, connect=10.0)
    total_blocks = 0
    total_txs = 0

    async with httpx.AsyncClient(limits=limits, timeout=timeout) as client:
        if need_main_sync:
            log(f"📦 Fetching blocks {from_block} → {to_block_eff} ({total:,} blocks)")
            ranges = []
            cur = from_block
            while cur <= to_block_eff:
                end = min(cur + batch_size - 1, to_block_eff)
                ranges.append((cur, end))
                cur = end + 1
            write_lock = asyncio.Lock()
            sem = asyncio.Semaphore(max_concurrent)

            async def fetch_and_save(lo: int, hi: int) -> tuple[int, int]:
                async with sem:
                    nums = list(range(lo, hi + 1))
                    results = await fetch_blocks_batch(client, rpc_url, nums, max_retries)
                    blocks = [r for r in results if r is not None]
                if blocks:
                    # Collect all tx hashes for receipt fetching
                    all_tx_hashes = []
                    for b in blocks:
                        txs = b.get("transactions") or []
                        for tx in txs:
                            if isinstance(tx, dict) and "hash" in tx:
                                all_tx_hashes.append(tx["hash"])

                    # Fetch receipts in batch
                    receipts = await fetch_receipts_chunked(client, rpc_url, all_tx_hashes, max_retries)

                    async with write_lock:
                        blk_count = save_blocks(db_path, blocks)
                        tx_count = save_transactions(db_path, blocks, receipts)
                        return blk_count, tx_count
                return 0, 0

            start_time = datetime.now()
            tasks = [asyncio.create_task(fetch_and_save(lo, hi)) for lo, hi in ranges]
            done = 0
            for coro in asyncio.as_completed(tasks):
                blk, tx = await coro
                total_blocks += blk
                total_txs += tx
                done += 1
                if done % 100 == 0 or done == len(ranges):
                    elapsed = (datetime.now() - start_time).total_seconds()
                    rate = total_blocks / elapsed if elapsed > 0 else 0
                    log(f"   Progress: {done}/{len(ranges)} ranges | {total_blocks:,} blocks | {total_txs:,} txs | {rate:.0f} blocks/s | {elapsed:.1f}s")
            update_transaction_sync(db_path, to_block_eff)
            elapsed = (datetime.now() - start_time).total_seconds()
            log("")
            log("📊 Block processing complete")
            log(f"✅ Inserted {total_blocks:,} blocks, {total_txs:,} transactions in {elapsed:.2f}s")
        else:
            log("")

        if not skip_gap_fill:
            await run_gap_fill(client, rpc_url, db_path, max_retries)

    log(f"📁 DB: {db_path}")
    return True


async def run_gap_fill(
    client: httpx.AsyncClient,
    rpc_url: str,
    db_path: str,
    max_retries: int = 5,
) -> int:
    """Re-fetch blocks with tx_count>0 but no transactions. Returns filled count."""
    gaps = get_gap_blocks(db_path)
    if not gaps:
        return 0
    log(f"")
    log(f"🔧 Filling {len(gaps)} gap blocks (tx_count>0 but no transactions)...")
    batch_size = 50
    total_txs = 0
    for i in range(0, len(gaps), batch_size):
        batch = gaps[i : i + batch_size]
        results = await fetch_blocks_batch(client, rpc_url, batch, max_retries)
        blocks = [r for r in results if r is not None]
        if blocks:
            # Collect all tx hashes for receipt fetching
            all_tx_hashes = []
            for b in blocks:
                txs = b.get("transactions") or []
                for tx in txs:
                    if isinstance(tx, dict) and "hash" in tx:
                        all_tx_hashes.append(tx["hash"])

            # Fetch receipts in batch
            receipts = await fetch_receipts_chunked(client, rpc_url, all_tx_hashes, max_retries)

            total_txs += save_transactions(db_path, blocks, receipts)
        if (i + batch_size) % 500 < batch_size or i + batch_size >= len(gaps):
            log(f"   Gap fill: {min(i + batch_size, len(gaps))}/{len(gaps)} blocks, {total_txs} txs")
    if gaps:
        log(f"✅ Gap fill complete: {total_txs} transactions from {len(gaps)} blocks")
    return total_txs


def main():
    parser = argparse.ArgumentParser(description="LOVE20 Block Processor")
    parser.add_argument("--rpc", "-r", required=True, help="RPC URL")
    parser.add_argument("--to-block", "-t", type=int, required=True, help="Ending block number")
    parser.add_argument("--db-path", required=True, help="SQLite database path")
    parser.add_argument("--origin-blocks", type=int, default=0, help="Origin block (first block to consider)")
    parser.add_argument("--batch-size", type=int, default=500, help="Blocks per RPC batch request")
    parser.add_argument("--concurrency", type=int, default=20, help="Concurrent batch requests")
    parser.add_argument("--retries", type=int, default=5, help="Max retries per batch")
    parser.add_argument("--skip-gap-fill", action="store_true", help="Skip filling gap blocks")
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
            skip_gap_fill=args.skip_gap_fill,
        )
    )
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
