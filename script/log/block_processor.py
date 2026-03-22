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


def connect_db(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, timeout=30.0)
    conn.execute("PRAGMA busy_timeout = 30000")
    return conn


def init_db(db_path: str):
    """Ensure blocks table exists by running init SQL."""
    conn = connect_db(db_path)
    script_dir = Path(__file__).resolve().parent
    sql_init_dir = script_dir / 'sql' / 'init'
    if sql_init_dir.exists() and sql_init_dir.is_dir():
        for f in sorted(sql_init_dir.glob('*.sql')):
            try:
                with open(f, 'r', encoding='utf-8') as sql_file:
                    conn.executescript(sql_file.read())
                log(f"   Init: {f.name}")
            except Exception as e:
                conn.rollback()
                conn.close()
                raise RuntimeError(f"error executing {f.name}: {e}") from e
    conn.commit()
    conn.close()


def get_last_block_in_db(db_path: str) -> int | None:
    """Return MAX(block_number) from blocks, or None if empty."""
    conn = connect_db(db_path)
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
    conn = connect_db(db_path)
    try:
        c = conn.execute("SELECT MAX(block_number) FROM transactions")
        row = c.fetchone()
        conn.close()
        return row[0] if row and row[0] is not None else None
    except sqlite3.OperationalError:
        conn.close()
        return None


def get_gap_block_rows(db_path: str) -> list[tuple[int, int]]:
    """Return (block_number, missing_tx_rows) for blocks whose tx rows are fewer than block.tx_count."""
    conn = connect_db(db_path)
    try:
        c = conn.execute(
            """SELECT b.block_number, (b.tx_count - COALESCE(t.tx_rows, 0)) AS missing_rows
               FROM blocks b
               LEFT JOIN (
                   SELECT block_number, COUNT(*) AS tx_rows
                   FROM transactions
                   GROUP BY block_number
               ) t ON t.block_number = b.block_number
               WHERE b.tx_count > 0
                 AND COALESCE(t.tx_rows, 0) < b.tx_count
               ORDER BY b.block_number
               LIMIT 10000"""
        )
        rows = c.fetchall()
        conn.close()
        return [(r[0], r[1]) for r in rows]
    except sqlite3.OperationalError:
        conn.close()
        return []


def get_gap_blocks(db_path: str) -> list[int]:
    """Blocks whose stored transaction rows are fewer than block.tx_count. Max 10000 to avoid huge fetches."""
    return [block_number for block_number, _ in get_gap_block_rows(db_path)]


def get_block_numbers_for_tx_hashes(db_path: str, tx_hashes: list[str]) -> set[int]:
    """Return block numbers that currently hold any of the given transaction hashes."""
    if not tx_hashes:
        return set()

    conn = connect_db(db_path)
    try:
        block_numbers: set[int] = set()
        chunk_size = 500
        for i in range(0, len(tx_hashes), chunk_size):
            chunk = tx_hashes[i : i + chunk_size]
            placeholders = ",".join("?" for _ in chunk)
            rows = conn.execute(
                f"SELECT DISTINCT block_number FROM transactions WHERE tx_hash IN ({placeholders})",
                chunk,
            ).fetchall()
            block_numbers.update(int(r[0]) for r in rows if r and r[0] is not None)
        return block_numbers
    finally:
        conn.close()


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
            failed_blocks = []
            for i in range(len(block_numbers)):
                r = by_id.get(i)
                if not isinstance(r, dict) or "error" in r or r.get("result") is None:
                    failed_blocks.append(block_numbers[i])
                    continue
                result.append(r.get("result"))
            if failed_blocks:
                sample = ", ".join(str(n) for n in failed_blocks[:5])
                raise RuntimeError(
                    f"failed to fetch {len(failed_blocks)} blocks in batch; sample block numbers: {sample}"
                )
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
            failed_hashes = []
            for i, tx_hash in enumerate(tx_hashes):
                r = by_id.get(i)
                if not isinstance(r, dict) or "error" in r or r.get("result") is None:
                    failed_hashes.append(tx_hash)
                    continue
                result[tx_hash] = r.get("result")
            if failed_hashes:
                sample = ", ".join(failed_hashes[:3])
                raise RuntimeError(
                    f"failed to fetch {len(failed_hashes)} receipts in batch; sample tx hashes: {sample}"
                )
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

    raise RuntimeError(f"failed to fetch receipts after {max_retries} retries")


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
        receipts.update(await fetch_receipts_batch(client, rpc_url, chunk, max_retries))
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
    receipt_block_number = None
    receipt_block_hash = None
    receipt_tx_index = None
    if receipt:
        gas_used = hex_to_int(receipt.get("gasUsed"))
        cumulative_gas_used = hex_to_int(receipt.get("cumulativeGasUsed"))
        status = hex_to_int(receipt.get("status"))
        contract_address = receipt.get("contractAddress")
        effective_gas_price = hex_to_int(receipt.get("effectiveGasPrice"))
        receipt_block_number = hex_to_int(receipt.get("blockNumber"))
        receipt_block_hash = receipt.get("blockHash")
        receipt_tx_index = hex_to_int(receipt.get("transactionIndex"))

    canonical_block_number = receipt_block_number if receipt_block_number is not None else block_number
    canonical_block_hash = receipt_block_hash or block_hash or tx.get("blockHash")
    canonical_tx_index = receipt_tx_index if receipt_tx_index is not None else hex_to_int(tx.get("transactionIndex"))
    canonical_block_timestamp = block_timestamp if canonical_block_number == block_number else None

    return {
        "block_number": canonical_block_number,
        "block_hash": canonical_block_hash,
        "block_timestamp": canonical_block_timestamp,
        "tx_hash": tx.get("hash"),
        "tx_index": canonical_tx_index,
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


def refresh_transaction_block_context(conn: sqlite3.Connection, block_numbers: set[int]):
    """Refresh block_hash and block_timestamp from the canonical blocks table for affected transactions."""
    if not block_numbers:
        return

    chunk_size = 500
    for block_number_chunk_start in range(0, len(block_numbers), chunk_size):
        chunk = list(block_numbers)[block_number_chunk_start : block_number_chunk_start + chunk_size]
        placeholders = ",".join("?" for _ in chunk)
        conn.execute(
            f"""UPDATE transactions
                SET block_hash = COALESCE(
                        (SELECT b.block_hash FROM blocks b WHERE b.block_number = transactions.block_number),
                        block_hash
                    ),
                    block_timestamp = COALESCE(
                        (SELECT b.timestamp FROM blocks b WHERE b.block_number = transactions.block_number),
                        block_timestamp
                    )
                WHERE block_number IN ({placeholders})""",
            chunk,
        )


def get_canonical_tx_count(block: dict, receipts: dict[str, dict | None] | None = None) -> int:
    """Count only transactions whose receipts confirm they belong to this block."""
    txs = block.get("transactions") or []
    if not isinstance(txs, list):
        return 0

    if not receipts:
        return len(txs)

    block_number = hex_to_int(block.get("number"))
    if block_number is None:
        return 0

    canonical_count = 0
    for tx in txs:
        if not isinstance(tx, dict):
            continue
        tx_hash = tx.get("hash")
        if not tx_hash:
            continue
        receipt = receipts.get(tx_hash)
        receipt_block_number = hex_to_int(receipt.get("blockNumber")) if receipt else None
        if receipt_block_number == block_number:
            canonical_count += 1
    return canonical_count


def save_blocks(
    db_path: str,
    blocks: list[dict],
    receipts: dict[str, dict | None] | None = None,
) -> int:
    """Insert or replace blocks. Returns inserted count."""
    conn = connect_db(db_path)
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
        tx_count = get_canonical_tx_count(b, receipts)
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
            conn.rollback()
            conn.close()
            raise RuntimeError(f"failed to insert block {num}: {e}") from e
    conn.commit()
    conn.close()
    return inserted


def save_transactions(db_path: str, blocks: list[dict], receipts: dict[str, dict | None] | None = None) -> int:
    """Insert or refresh transactions from blocks (fullTx). Returns affected row count.

    If receipts dict is provided (tx_hash -> receipt), also inserts status, gas_used, etc.
    """
    conn = connect_db(db_path)
    c = conn.cursor()
    inserted = 0
    affected_block_numbers: set[int] = set()
    ins = """INSERT INTO transactions
        (block_number, block_hash, block_timestamp, tx_hash, tx_index, "from", "to",
         value_wei, amount, gas, gas_price, max_fee_per_gas, max_priority_fee_per_gas,
         type, chain_id, input, nonce, v, r, s, access_list,
         gas_used, cumulative_gas_used, status, contract_address, effective_gas_price,
         created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(tx_hash) DO UPDATE SET
            block_number = excluded.block_number,
            block_hash = excluded.block_hash,
            block_timestamp = excluded.block_timestamp,
            tx_index = excluded.tx_index,
            "from" = excluded."from",
            "to" = excluded."to",
            value_wei = excluded.value_wei,
            amount = excluded.amount,
            gas = excluded.gas,
            gas_price = excluded.gas_price,
            max_fee_per_gas = excluded.max_fee_per_gas,
            max_priority_fee_per_gas = excluded.max_priority_fee_per_gas,
            type = excluded.type,
            chain_id = excluded.chain_id,
            input = excluded.input,
            nonce = excluded.nonce,
            v = excluded.v,
            r = excluded.r,
            s = excluded.s,
            access_list = excluded.access_list,
            gas_used = excluded.gas_used,
            cumulative_gas_used = excluded.cumulative_gas_used,
            status = excluded.status,
            contract_address = excluded.contract_address,
            effective_gas_price = excluded.effective_gas_price"""
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
                    inserted += c.rowcount
                affected_block_numbers.add(row["block_number"])
            except Exception as e:
                conn.rollback()
                conn.close()
                raise RuntimeError(f"failed to insert tx {row.get('tx_hash')}: {e}") from e
    refresh_transaction_block_context(conn, affected_block_numbers)
    conn.commit()
    conn.close()
    return inserted


def update_transaction_sync(db_path: str, last_block: int):
    """Update transaction_sync with last processed block."""
    conn = connect_db(db_path)
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
                        blk_count = save_blocks(db_path, blocks, receipts)
                        tx_count = save_transactions(db_path, blocks, receipts)
                        return blk_count, tx_count
                return 0, 0

            start_time = datetime.now()
            tasks = [asyncio.create_task(fetch_and_save(lo, hi)) for lo, hi in ranges]
            done = 0
            try:
                for coro in asyncio.as_completed(tasks):
                    blk, tx = await coro
                    total_blocks += blk
                    total_txs += tx
                    done += 1
                    if done % 100 == 0 or done == len(ranges):
                        elapsed = (datetime.now() - start_time).total_seconds()
                        rate = total_blocks / elapsed if elapsed > 0 else 0
                        log(f"   Progress: {done}/{len(ranges)} ranges | {total_blocks:,} blocks | {total_txs:,} txs | {rate:.0f} blocks/s | {elapsed:.1f}s")
            except Exception:
                for task in tasks:
                    task.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)
                raise
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
    """Re-fetch blocks whose stored transaction rows are fewer than block.tx_count. Returns filled count."""
    batch_size = 50
    total_txs = 0
    pass_num = 0
    seen_gap_signatures: set[tuple[int, ...]] = set()

    while True:
        gap_rows = get_gap_block_rows(db_path)
        if not gap_rows:
            if pass_num > 0:
                log(f"✅ Gap fill complete: {total_txs} transactions across {pass_num} pass(es)")
            return total_txs

        gaps = [block_number for block_number, _ in gap_rows]
        missing_rows = sum(missing for _, missing in gap_rows)
        signature = tuple(gaps)
        if signature in seen_gap_signatures:
            raise RuntimeError(
                f"gap fill cycled without convergence: {len(gaps)} blocks still missing {missing_rows} tx rows"
            )
        seen_gap_signatures.add(signature)

        pass_num += 1
        pass_txs = 0
        log(f"")
        log(
            f"🔧 Gap fill pass {pass_num}: {len(gaps)} blocks need repair "
            f"({missing_rows} missing tx rows)"
        )

        for i in range(0, len(gaps), batch_size):
            batch = gaps[i : i + batch_size]
            pending_blocks = set(batch)
            fetched_blocks: dict[int, dict] = {}

            while pending_blocks:
                frontier = sorted(pending_blocks)
                pending_blocks = set()
                results = await fetch_blocks_batch(client, rpc_url, frontier, max_retries)
                blocks = [r for r in results if r is not None]
                if not blocks:
                    continue

                frontier_hashes: list[str] = []
                for block in blocks:
                    block_number = hex_to_int(block.get("number"))
                    if block_number is None:
                        continue
                    fetched_blocks[block_number] = block
                    txs = block.get("transactions") or []
                    for tx in txs:
                        if isinstance(tx, dict) and "hash" in tx:
                            frontier_hashes.append(tx["hash"])

                holder_blocks = get_block_numbers_for_tx_hashes(db_path, frontier_hashes)
                for block_number in holder_blocks:
                    if block_number not in fetched_blocks:
                        pending_blocks.add(block_number)

            blocks = list(fetched_blocks.values())
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

                save_blocks(db_path, blocks, receipts)
                pass_txs += save_transactions(db_path, blocks, receipts)
            if (i + batch_size) % 500 < batch_size or i + batch_size >= len(gaps):
                log(
                    f"   Gap fill pass {pass_num}: {min(i + batch_size, len(gaps))}/{len(gaps)} "
                    f"blocks, {pass_txs} tx upserts"
                )

        total_txs += pass_txs


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

    try:
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
    except Exception as e:
        log(f"❌ Block processor failed: {e}")
        success = False
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
