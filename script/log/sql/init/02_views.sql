-- Active: 1771748349049@@127.0.0.1@3306
-- v_contract: created by event_processor from contracts.json (address + contract_name mapping)

-- 统一的 Transfer 视图，提取所有 ERC20/Token 合约的转账记录
DROP VIEW IF EXISTS v_transfer;
CREATE VIEW v_transfer AS
SELECT
    id,
    contract_name,
    log_round,
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
DROP VIEW IF EXISTS v_contribute;
CREATE VIEW v_contribute AS
SELECT
    id,
    contract_name,
    log_round,
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
DROP VIEW IF EXISTS v_pair_created;
CREATE VIEW v_pair_created AS
SELECT
    id,
    contract_name,
    log_round,
    round,
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
    log_round,
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
-- love20_in/out: LOVE20 flow (18 decimals); tusdt_in/out: TUSDT flow (18 decimals)
DROP VIEW IF EXISTS v_love20_tusdt_swap;
CREATE VIEW v_love20_tusdt_swap AS
SELECT
    e.id,
    e.contract_name,
    e.log_round,
    e.round,
    e.block_number,
    e.tx_hash,
    e.tx_index,
    e.log_index,
    e.address,
    json_extract(e.decoded_data, '$.sender') AS sender,
    json_extract(e.decoded_data, '$.to') AS "to",
    t."from" AS user,
    json_extract(e.decoded_data, '$.amount1In') AS love20_in,
    json_extract(e.decoded_data, '$.amount1Out') AS love20_out,
    json_extract(e.decoded_data, '$.amount0In') AS tusdt_in,
    json_extract(e.decoded_data, '$.amount0Out') AS tusdt_out,
    CAST(json_extract(e.decoded_data, '$.amount1In') AS REAL) / 1e18 AS love20_in_amount,
    CAST(json_extract(e.decoded_data, '$.amount1Out') AS REAL) / 1e18 AS love20_out_amount,
    CAST(json_extract(e.decoded_data, '$.amount0In') AS REAL) / 1e18 AS tusdt_in_amount,
    CAST(json_extract(e.decoded_data, '$.amount0Out') AS REAL) / 1e18 AS tusdt_out_amount,
    (CAST(json_extract(e.decoded_data, '$.amount1In') AS REAL) > 0) AS is_sell_love20,
    e.created_at
FROM events e
LEFT JOIN transactions t ON e.tx_hash = t.tx_hash
WHERE e.contract_name = 'love20TusdtPair' AND e.event_name = 'Swap';

-- LOVE20-TUSDT pair Liquidity (Mint/Burn) view
-- tusdt_amount: TUSDT amount (token0); love20_amount: LOVE20 amount (token1)
DROP VIEW IF EXISTS v_liquidity_tusdt_love20;
CREATE VIEW v_liquidity_tusdt_love20 AS
SELECT
    e.id,
    -- e.contract_name,
    e.log_round,
    -- e.round,
    e.block_number,
    e.tx_hash,
    e.tx_index,
    e.log_index,
    -- e.address,
    -- e.event_name, 
    CASE 
        WHEN e.event_name = 'Mint' THEN 1  
        ELSE -1  
    END AS amount_sign,
    -- json_extract(e.decoded_data, '$.sender') AS sender
    t."from" AS user,
    CASE WHEN e.event_name = 'Mint' THEN NULL ELSE json_extract(e.decoded_data, '$.to') END AS "to",
    -- json_extract(e.decoded_data, '$.amount0') AS tusdt_amount_raw,
    -- json_extract(e.decoded_data, '$.amount1') AS love20_amount_raw,
    CAST(json_extract(e.decoded_data, '$.amount0') AS REAL) / 1e18 AS tusdt_amount,
    CAST(json_extract(e.decoded_data, '$.amount1') AS REAL) / 1e18 AS love20_amount,
    e.created_at
FROM events e
LEFT JOIN transactions t ON e.tx_hash = t.tx_hash
WHERE e.contract_name = 'love20TusdtPair' AND e.event_name IN ('Mint', 'Burn');

-- LIFE20-TUSDT pair Swap (TUSDT=token0, LIFE20=token1)
-- life20_in/out: LIFE20 flow (18 decimals); tusdt_in/out: TUSDT flow (18 decimals)
DROP VIEW IF EXISTS v_life20_tusdt_swap;
CREATE VIEW v_life20_tusdt_swap AS
SELECT
    e.id,
    e.contract_name,
    e.log_round,
    e.round,
    e.block_number,
    e.tx_hash,
    e.tx_index,
    e.log_index,
    e.address,
    json_extract(e.decoded_data, '$.sender') AS sender,
    json_extract(e.decoded_data, '$.to') AS "to",
    t."from" AS user,
    json_extract(e.decoded_data, '$.amount1In') AS life20_in,
    json_extract(e.decoded_data, '$.amount1Out') AS life20_out,
    json_extract(e.decoded_data, '$.amount0In') AS tusdt_in,
    json_extract(e.decoded_data, '$.amount0Out') AS tusdt_out,
    CAST(json_extract(e.decoded_data, '$.amount1In') AS REAL) / 1e18 AS life20_in_amount,
    CAST(json_extract(e.decoded_data, '$.amount1Out') AS REAL) / 1e18 AS life20_out_amount,
    CAST(json_extract(e.decoded_data, '$.amount0In') AS REAL) / 1e18 AS tusdt_in_amount,
    CAST(json_extract(e.decoded_data, '$.amount0Out') AS REAL) / 1e18 AS tusdt_out_amount,
    (CAST(json_extract(e.decoded_data, '$.amount1In') AS REAL) > 0) AS is_sell_life20,
    e.created_at
FROM events e
LEFT JOIN transactions t ON e.tx_hash = t.tx_hash
WHERE e.contract_name = 'life20TusdtPair' AND e.event_name = 'Swap';

-- LIFE20-TUSDT pair Liquidity (Mint/Burn) view
-- tusdt_amount: TUSDT amount (token0); life20_amount: LIFE20 amount (token1)
DROP VIEW IF EXISTS v_liquidity_tusdt_life20;
CREATE VIEW v_liquidity_tusdt_life20 AS
SELECT
    e.id,
    e.log_round,
    e.block_number,
    e.tx_hash,
    e.tx_index,
    e.log_index,
    CASE
        WHEN e.event_name = 'Mint' THEN 1
        ELSE -1
    END AS amount_sign,
    t."from" AS user,
    CASE WHEN e.event_name = 'Mint' THEN NULL ELSE json_extract(e.decoded_data, '$.to') END AS "to",
    CAST(json_extract(e.decoded_data, '$.amount0') AS REAL) / 1e18 AS tusdt_amount,
    CAST(json_extract(e.decoded_data, '$.amount1') AS REAL) / 1e18 AS life20_amount,
    e.created_at
FROM events e
LEFT JOIN transactions t ON e.tx_hash = t.tx_hash
WHERE e.contract_name = 'life20TusdtPair' AND e.event_name IN ('Mint', 'Burn');

-- TUSDT cross-chain mint/burn view
-- amount_sign: +1 = mint/cross-in from zero address; -1 = burn/cross-out to zero address
DROP VIEW IF EXISTS v_tusdt_crosschain;
CREATE VIEW v_tusdt_crosschain AS
SELECT
    e.id,
    e.contract_name,
    e.log_round,
    e.round,
    e.block_number,
    e.tx_hash,
    e.tx_index,
    e.log_index,
    e.address,
    json_extract(e.decoded_data, '$.from') AS "from",
    json_extract(e.decoded_data, '$.to') AS "to",
    CASE
        WHEN LOWER(json_extract(e.decoded_data, '$.from')) = '0x0000000000000000000000000000000000000000' THEN 1
        ELSE -1
    END AS amount_sign,
    CASE
        WHEN LOWER(json_extract(e.decoded_data, '$.from')) = '0x0000000000000000000000000000000000000000'
            THEN json_extract(e.decoded_data, '$.to')
        ELSE json_extract(e.decoded_data, '$.from')
    END AS user,
    CAST(json_extract(e.decoded_data, '$.value') AS REAL) / 1e18 AS tusdt_amount,
    e.created_at
FROM events e
WHERE e.contract_name = 'TUSDT'
  AND e.event_name = 'Transfer'
  AND (
        LOWER(json_extract(e.decoded_data, '$.from')) = '0x0000000000000000000000000000000000000000'
        OR LOWER(json_extract(e.decoded_data, '$.to')) = '0x0000000000000000000000000000000000000000'
    );

-- MintGovReward (LOVE20Mint) view
DROP VIEW IF EXISTS v_mint_gov_reward;
CREATE VIEW v_mint_gov_reward AS
SELECT
    id,
    contract_name,
    log_round,
    round,
    block_number,
    tx_hash,
    address,
    json_extract(decoded_data, '$.tokenAddress') AS token_address,
    json_extract(decoded_data, '$.account') AS account,
    json_extract(decoded_data, '$.verifyReward') AS verify_reward_raw,
    json_extract(decoded_data, '$.boostReward') AS boost_reward_raw,
    json_extract(decoded_data, '$.burnReward') AS burn_reward_raw,
    CAST(json_extract(decoded_data, '$.verifyReward') AS REAL) / 1e18 AS verify_reward,
    CAST(json_extract(decoded_data, '$.boostReward') AS REAL) / 1e18 AS boost_reward,
    CAST(json_extract(decoded_data, '$.burnReward') AS REAL) / 1e18 AS burn_reward,
    created_at
FROM events
WHERE event_name = 'MintGovReward';

-- MintActionReward (LOVE20Mint) view
DROP VIEW IF EXISTS v_mint_action_reward;
CREATE VIEW v_mint_action_reward AS
SELECT
    id,
    contract_name,
    log_round,
    round,
    block_number,
    tx_hash,
    address,
    json_extract(decoded_data, '$.tokenAddress') AS token_address,
    json_extract(decoded_data, '$.actionId') AS action_id,
    json_extract(decoded_data, '$.account') AS account,
    json_extract(decoded_data, '$.reward') AS reward_raw,
    CAST(json_extract(decoded_data, '$.reward') AS REAL) / 1e18 AS reward,
    created_at
FROM events
WHERE event_name = 'MintActionReward';

-- ClaimReward (IReward) view
DROP VIEW IF EXISTS v_claim_reward;
CREATE VIEW v_claim_reward AS
SELECT
    id,
    contract_name,
    log_round,
    round,
    block_number,
    tx_hash,
    tx_index,
    log_index,
    address,
    json_extract(decoded_data, '$.tokenAddress') AS token_address,
    json_extract(decoded_data, '$.actionId') AS action_id,
    json_extract(decoded_data, '$.account') AS account,
    json_extract(decoded_data, '$.mintAmount') AS mint_amount_raw,
    json_extract(decoded_data, '$.burnAmount') AS burn_amount_raw,
    CAST(json_extract(decoded_data, '$.mintAmount') AS REAL) / 1e18 AS mint_amount,
    CAST(json_extract(decoded_data, '$.burnAmount') AS REAL) / 1e18 AS burn_amount,
    created_at
FROM events
WHERE event_name = 'ClaimReward';
