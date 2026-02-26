-- sync_status: keep across runs for incremental sync (do not DROP)
CREATE TABLE IF NOT EXISTS sync_status (
    contract_name TEXT NOT NULL,
    event_name    TEXT NOT NULL,
    last_block    INTEGER NOT NULL,
    updated_at    TEXT NOT NULL,
    PRIMARY KEY (contract_name, event_name)
);

-- 事件记录主表，保存所有解析后的事件
-- log_round: block-calculated protocol round; round: event param (round/currentRound from decoded_data)
CREATE TABLE IF NOT EXISTS events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    contract_name   TEXT NOT NULL,
    event_name      TEXT NOT NULL,
    log_round       INTEGER,
    round           INTEGER,
    block_number    INTEGER NOT NULL,
    tx_hash         TEXT NOT NULL,
    tx_index        INTEGER,
    log_index       INTEGER,
    address         TEXT,
    decoded_data    TEXT NOT NULL,
    created_at      TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_events_contract ON events(contract_name);
CREATE INDEX IF NOT EXISTS idx_events_contract_event ON events(contract_name, event_name);
CREATE INDEX IF NOT EXISTS idx_events_block ON events(block_number);
CREATE INDEX IF NOT EXISTS idx_events_log_round ON events(log_round);
CREATE INDEX IF NOT EXISTS idx_events_round ON events(round);
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_unique ON events(tx_hash, log_index);

-- blocks: block header metadata (fetched via eth_getBlockByNumber, maintained by block_processor)
-- Constant on Thinkium: gas_limit(30M), difficulty(0x0), size(0), nonce(0x..), miner(0x0..), extra_data(0x), sha3_uncles
-- Always NULL: base_fee_per_gas, total_difficulty
-- Always 0 on Thinkium: gas_used
CREATE TABLE IF NOT EXISTS blocks (
    block_number     INTEGER PRIMARY KEY,
    block_hash       TEXT,
    parent_hash      TEXT,
    timestamp        INTEGER NOT NULL,
    gas_limit        INTEGER,
    gas_used         INTEGER,
    base_fee_per_gas INTEGER,
    difficulty       TEXT,
    total_difficulty TEXT,
    size             INTEGER,
    nonce            TEXT,
    mix_hash         TEXT,
    state_root       TEXT,
    transactions_root TEXT,
    receipts_root    TEXT,
    miner            TEXT,
    extra_data       TEXT,
    sha3_uncles      TEXT,
    tx_count         INTEGER,
    created_at       TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_blocks_timestamp ON blocks(timestamp);
