-- 统一的 Transfer 视图，提取所有 ERC20/Token 合约的转账记录
CREATE VIEW IF NOT EXISTS v_transfer AS
SELECT
    id,
    contract_name,
    round,
    block_number,
    tx_hash,
    tx_index,
    log_index,
    address,
    json_extract(decoded_data, '$.from')  AS "from",
    json_extract(decoded_data, '$.to')    AS "to",
    json_extract(decoded_data, '$.value') AS value,
    CAST(json_extract(decoded_data, '$.value') AS REAL) / 1e18 AS amount,
    created_at
FROM events
WHERE event_name = 'Transfer';

-- 提取 Contribute 视图
CREATE VIEW IF NOT EXISTS v_contribute AS
SELECT
    id,
    contract_name,
    round,
    block_number,
    tx_hash,
    address,
    json_extract(decoded_data, '$.user') AS user,
    json_extract(decoded_data, '$.amount') AS amount_raw,
    CAST(json_extract(decoded_data, '$.amount') AS REAL) / 1e18 AS amount,
    created_at
FROM events
WHERE event_name = 'Contribute';

-- 提取 PairCreated (UniswapV2Factory) 视图
CREATE VIEW IF NOT EXISTS v_pair_created AS
SELECT
    id,
    contract_name,
    block_number,
    tx_hash,
    json_extract(decoded_data, '$.token0') AS token0,
    json_extract(decoded_data, '$.token1') AS token1,
    json_extract(decoded_data, '$.pair') AS pair,
    created_at
FROM events
WHERE event_name = 'PairCreated';

-- LOVE20-TKM20 pair Swap (LOVE20=token0, TKM20=token1)
-- love20_in/out: LOVE20 flow; tkm20_in/out: TKM20 flow
DROP VIEW IF EXISTS v_love20_tkm20_swap;
CREATE VIEW v_love20_tkm20_swap AS
SELECT
    id,
    contract_name,
    round,
    block_number,
    tx_hash,
    tx_index,
    log_index,
    address,
    json_extract(decoded_data, '$.sender') AS sender,
    json_extract(decoded_data, '$.to') AS "to",
    json_extract(decoded_data, '$.amount0In') AS love20_in,
    json_extract(decoded_data, '$.amount0Out') AS love20_out,
    json_extract(decoded_data, '$.amount1In') AS tkm20_in,
    json_extract(decoded_data, '$.amount1Out') AS tkm20_out,
    CAST(json_extract(decoded_data, '$.amount0In') AS REAL) / 1e18 AS love20_in_amount,
    CAST(json_extract(decoded_data, '$.amount0Out') AS REAL) / 1e18 AS love20_out_amount,
    CAST(json_extract(decoded_data, '$.amount1In') AS REAL) / 1e18 AS tkm20_in_amount,
    CAST(json_extract(decoded_data, '$.amount1Out') AS REAL) / 1e18 AS tkm20_out_amount,
    (CAST(json_extract(decoded_data, '$.amount0In') AS REAL) > 0) AS is_sell_love20,
    created_at
FROM events
WHERE contract_name = 'love20Tkm20Pair' AND event_name = 'Swap';

-- LOVE20-TUSDT pair Swap (TUSDT=token0, LOVE20=token1)
-- love20_in/out: LOVE20 flow (18 decimals); tusdt_in/out: TUSDT flow (6 decimals)
DROP VIEW IF EXISTS v_love20_tusdt_swap;
CREATE VIEW v_love20_tusdt_swap AS
SELECT
    id,
    contract_name,
    round,
    block_number,
    tx_hash,
    tx_index,
    log_index,
    address,
    json_extract(decoded_data, '$.sender') AS sender,
    json_extract(decoded_data, '$.to') AS "to",
    json_extract(decoded_data, '$.amount1In') AS love20_in,
    json_extract(decoded_data, '$.amount1Out') AS love20_out,
    json_extract(decoded_data, '$.amount0In') AS tusdt_in,
    json_extract(decoded_data, '$.amount0Out') AS tusdt_out,
    CAST(json_extract(decoded_data, '$.amount1In') AS REAL) / 1e18 AS love20_in_amount,
    CAST(json_extract(decoded_data, '$.amount1Out') AS REAL) / 1e18 AS love20_out_amount,
    CAST(json_extract(decoded_data, '$.amount0In') AS REAL) / 1e6 AS tusdt_in_amount,
    CAST(json_extract(decoded_data, '$.amount0Out') AS REAL) / 1e6 AS tusdt_out_amount,
    (CAST(json_extract(decoded_data, '$.amount1In') AS REAL) > 0) AS is_sell_love20,
    created_at
FROM events
WHERE contract_name = 'love20TusdtPair' AND event_name = 'Swap';
