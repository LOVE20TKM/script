#!/usr/bin/env python3
import argparse
import asyncio
import csv
import sqlite3
from collections.abc import Iterable
from pathlib import Path

import httpx


def hex_to_int(value):
    if value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 16) if value.startswith("0x") else int(value)
    return int(value)


def connect_db(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, timeout=30.0)
    conn.execute("PRAGMA busy_timeout = 30000")
    return conn


def chunked(values: list[int], size: int) -> Iterable[list[int]]:
    for i in range(0, len(values), size):
        yield values[i : i + size]


def chunked_str(values: list[str], size: int) -> Iterable[list[str]]:
    for i in range(0, len(values), size):
        yield values[i : i + size]


def get_block_range(db_path: str) -> tuple[int, int]:
    conn = connect_db(db_path)
    try:
        row = conn.execute("SELECT MIN(block_number), MAX(block_number) FROM blocks").fetchone()
        if not row or row[0] is None or row[1] is None:
            raise RuntimeError("blocks table is empty")
        return int(row[0]), int(row[1])
    finally:
        conn.close()


def get_block_counts(db_path: str, block_numbers: list[int]) -> dict[int, int]:
    if not block_numbers:
        return {}
    conn = connect_db(db_path)
    try:
        result = {}
        for batch in chunked(block_numbers, 900):
            placeholders = ",".join("?" for _ in batch)
            rows = conn.execute(
                f"SELECT block_number, tx_count FROM blocks WHERE block_number IN ({placeholders})",
                batch,
            ).fetchall()
            result.update({int(row[0]): int(row[1]) for row in rows})
        return result
    finally:
        conn.close()


def get_canonical_transactions(db_path: str, tx_hashes: list[str]) -> dict[str, tuple[int, int | None]]:
    if not tx_hashes:
        return {}
    conn = connect_db(db_path)
    try:
        result: dict[str, tuple[int, int | None]] = {}
        for batch in chunked_str(tx_hashes, 900):
            placeholders = ",".join("?" for _ in batch)
            rows = conn.execute(
                f"SELECT tx_hash, block_number, tx_index FROM transactions WHERE tx_hash IN ({placeholders})",
                batch,
            ).fetchall()
            for tx_hash, block_number, tx_index in rows:
                result[str(tx_hash)] = (int(block_number), None if tx_index is None else int(tx_index))
        return result
    finally:
        conn.close()


async def rpc_batch(client: httpx.AsyncClient, rpc_url: str, requests: list[dict]) -> list[dict]:
    response = await client.post(rpc_url, json=requests)
    response.raise_for_status()
    data = response.json()
    if not isinstance(data, list):
        raise RuntimeError(f"expected batch response list, got {type(data)}")
    return data


async def fetch_transaction_counts(
    client: httpx.AsyncClient,
    rpc_url: str,
    block_numbers: list[int],
) -> dict[int, int]:
    requests = [
        {
            "jsonrpc": "2.0",
            "id": block_number,
            "method": "eth_getBlockTransactionCountByNumber",
            "params": [hex(block_number)],
        }
        for block_number in block_numbers
    ]
    results = await rpc_batch(client, rpc_url, requests)
    raw_counts = {}
    for item in results:
        block_number = int(item["id"])
        if "error" in item or item.get("result") is None:
            raise RuntimeError(f"failed to fetch tx count for block {block_number}")
        raw_counts[block_number] = hex_to_int(item["result"]) or 0
    return raw_counts


async def fetch_blocks_fulltx(
    client: httpx.AsyncClient,
    rpc_url: str,
    block_numbers: list[int],
) -> dict[int, dict]:
    requests = [
        {
            "jsonrpc": "2.0",
            "id": block_number,
            "method": "eth_getBlockByNumber",
            "params": [hex(block_number), True],
        }
        for block_number in block_numbers
    ]
    results = await rpc_batch(client, rpc_url, requests)
    blocks = {}
    for item in results:
        block_number = int(item["id"])
        if "error" in item or item.get("result") is None:
            raise RuntimeError(f"failed to fetch fullTx block {block_number}")
        blocks[block_number] = item["result"]
    return blocks


async def find_candidate_blocks(
    client: httpx.AsyncClient,
    rpc_url: str,
    db_path: str,
    start_block: int,
    end_block: int,
    batch_size: int,
    concurrency: int,
) -> list[tuple[int, int, int]]:
    sem = asyncio.Semaphore(concurrency)
    candidates: list[tuple[int, int, int]] = []
    all_blocks = list(range(start_block, end_block + 1))

    async def worker(batch: list[int]) -> list[tuple[int, int, int]]:
        async with sem:
            db_counts = get_block_counts(db_path, batch)
            rpc_counts = await fetch_transaction_counts(client, rpc_url, batch)
        mismatches = []
        for block_number in batch:
            db_count = db_counts.get(block_number, 0)
            rpc_count = rpc_counts.get(block_number, 0)
            if rpc_count != db_count:
                mismatches.append((block_number, rpc_count, db_count))
        return mismatches

    tasks = [asyncio.create_task(worker(batch)) for batch in chunked(all_blocks, batch_size)]
    checked = 0
    for task in asyncio.as_completed(tasks):
        result = await task
        checked += batch_size
        candidates.extend(result)
        if checked % 50000 < batch_size or checked >= len(all_blocks):
            print(
                f"checked {min(checked, len(all_blocks)):,}/{len(all_blocks):,} blocks, "
                f"found {len(candidates):,} mismatched blocks",
                flush=True,
            )
    candidates.sort(key=lambda item: item[0])
    return candidates


async def export_duplicates(
    rpc_url: str,
    db_path: str,
    output_path: str,
    scan_batch_size: int,
    fetch_batch_size: int,
    concurrency: int,
):
    start_block, end_block = get_block_range(db_path)
    print(f"scanning blocks {start_block} -> {end_block}", flush=True)

    limits = httpx.Limits(max_connections=concurrency + 10, max_keepalive_connections=50)
    timeout = httpx.Timeout(120.0, connect=10.0)
    async with httpx.AsyncClient(limits=limits, timeout=timeout) as client:
        candidates = await find_candidate_blocks(
            client, rpc_url, db_path, start_block, end_block, scan_batch_size, concurrency
        )

        print(f"candidate mismatched blocks: {len(candidates):,}", flush=True)

        output = Path(output_path)
        output.parent.mkdir(parents=True, exist_ok=True)

        rows_written = 0
        unique_tx_hashes: set[str] = set()
        with output.open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "raw_block_number",
                    "raw_tx_index",
                    "raw_tx_count",
                    "canonical_tx_count",
                    "tx_hash",
                    "canonical_block_number",
                    "canonical_tx_index",
                    "block_offset",
                ]
            )

            candidate_blocks = [block_number for block_number, _, _ in candidates]
            candidate_count_map = {block_number: (raw_count, db_count) for block_number, raw_count, db_count in candidates}

            for i, batch in enumerate(chunked(candidate_blocks, fetch_batch_size), start=1):
                blocks = await fetch_blocks_fulltx(client, rpc_url, batch)
                tx_hashes = []
                for block_number in batch:
                    for tx in blocks[block_number].get("transactions") or []:
                        if isinstance(tx, dict) and tx.get("hash"):
                            tx_hashes.append(tx["hash"])
                canonical_map = get_canonical_transactions(db_path, tx_hashes)

                for block_number in batch:
                    block = blocks[block_number]
                    raw_count, canonical_count = candidate_count_map[block_number]
                    for tx in block.get("transactions") or []:
                        if not isinstance(tx, dict):
                            continue
                        tx_hash = tx.get("hash")
                        if not tx_hash or tx_hash not in canonical_map:
                            continue
                        canonical_block_number, canonical_tx_index = canonical_map[tx_hash]
                        if canonical_block_number == block_number:
                            continue
                        raw_tx_index = hex_to_int(tx.get("transactionIndex"))
                        writer.writerow(
                            [
                                block_number,
                                raw_tx_index,
                                raw_count,
                                canonical_count,
                                tx_hash,
                                canonical_block_number,
                                canonical_tx_index,
                                canonical_block_number - block_number,
                            ]
                        )
                        rows_written += 1
                        unique_tx_hashes.add(tx_hash)

                if i % 20 == 0 or i * fetch_batch_size >= len(candidate_blocks):
                    print(
                        f"exported {rows_written:,} duplicate rows from {min(i * fetch_batch_size, len(candidate_blocks)):,}/"
                        f"{len(candidate_blocks):,} candidate blocks",
                        flush=True,
                    )

        print(
            f"done: wrote {rows_written:,} duplicate rows covering {len(unique_tx_hashes):,} unique tx hashes "
            f"to {output}",
            flush=True,
        )


def main():
    parser = argparse.ArgumentParser(description="Export duplicate tx hashes that appear in raw block fullTx across multiple blocks.")
    parser.add_argument("--rpc", required=True, help="RPC URL")
    parser.add_argument("--db-path", required=True, help="Path to SQLite db")
    parser.add_argument("--output", required=True, help="CSV output path")
    parser.add_argument("--scan-batch-size", type=int, default=500, help="Blocks per tx-count scan batch")
    parser.add_argument("--fetch-batch-size", type=int, default=100, help="Candidate blocks per fullTx fetch batch")
    parser.add_argument("--concurrency", type=int, default=20, help="Concurrent tx-count scan requests")
    args = parser.parse_args()

    asyncio.run(
        export_duplicates(
            rpc_url=args.rpc,
            db_path=args.db_path,
            output_path=args.output,
            scan_batch_size=args.scan_batch_size,
            fetch_batch_size=args.fetch_batch_size,
            concurrency=args.concurrency,
        )
    )


if __name__ == "__main__":
    main()
