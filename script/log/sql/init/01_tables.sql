-- sync_status: keep across runs for incremental sync (do not DROP)
CREATE TABLE IF NOT EXISTS sync_status (
    contract_name TEXT NOT NULL,
    event_name    TEXT NOT NULL,
    last_block    INTEGER NOT NULL,
    updated_at    TEXT NOT NULL,
    PRIMARY KEY (contract_name, event_name)
);

-- 事件记录主表，保存所有解析后的事件
CREATE TABLE IF NOT EXISTS events (
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
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_events_contract ON events(contract_name);
CREATE INDEX IF NOT EXISTS idx_events_contract_event ON events(contract_name, event_name);
CREATE INDEX IF NOT EXISTS idx_events_block ON events(block_number);
CREATE INDEX IF NOT EXISTS idx_events_round ON events(round);
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_unique ON events(tx_hash, log_index);
