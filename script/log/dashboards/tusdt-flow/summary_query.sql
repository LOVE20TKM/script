WITH params AS (
    SELECT CAST(? AS INTEGER) AS recent_rounds
),
tracked_pairs(token_key, swap_bucket, lp_bucket, pair_contract_name, tusdt_side) AS (
    VALUES
        ('love20', 'love20_swap', 'love20_lp', 'love20TusdtPair', 0),
        ('life20', 'life20_swap', 'life20_lp', 'life20TusdtPair', 0),
        ('grow20', 'grow20_swap', 'grow20_lp', 'grow20TusdtPair', 1),
        ('lively', 'lively_swap', 'lively_lp', 'livelyTusdtPair', 0),
        ('pretty', 'pretty_swap', 'pretty_lp', 'prettyTusdtPair', 0)
),
bounds AS (
    SELECT MAX(log_round) AS max_round
    FROM events
    WHERE log_round IS NOT NULL
),
window_rounds AS (
    SELECT
        max_round,
        CASE
            WHEN max_round IS NULL THEN NULL
            ELSE max_round - recent_rounds + 1
        END AS min_round
    FROM bounds
    CROSS JOIN params
),
recent_log_rounds AS (
    SELECT DISTINCT e.log_round
    FROM events e
    CROSS JOIN window_rounds w
    WHERE e.log_round IS NOT NULL
      AND w.min_round IS NOT NULL
      AND e.log_round >= w.min_round
      AND e.log_round <= w.max_round
),
flow_rows AS (
    SELECT *
    FROM (
        SELECT
            e.log_round,
            LOWER(COALESCE(t."from", json_extract(e.decoded_data, '$.to'))) AS address,
            p.swap_bucket AS bucket,
            'swap' AS flow_kind,
            'chain' AS flow_scope,
            CASE
                WHEN p.tusdt_side = 0 THEN
                    COALESCE(CAST(json_extract(e.decoded_data, '$.amount0In') AS REAL) / 1e18, 0)
                    - COALESCE(CAST(json_extract(e.decoded_data, '$.amount0Out') AS REAL) / 1e18, 0)
                ELSE
                    COALESCE(CAST(json_extract(e.decoded_data, '$.amount1In') AS REAL) / 1e18, 0)
                    - COALESCE(CAST(json_extract(e.decoded_data, '$.amount1Out') AS REAL) / 1e18, 0)
            END AS tusdt_flow
        FROM events e
        JOIN tracked_pairs p ON e.contract_name = p.pair_contract_name
        LEFT JOIN transactions t ON e.tx_hash = t.tx_hash
        CROSS JOIN window_rounds w
        WHERE e.event_name = 'Swap'
          AND e.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND e.log_round >= w.min_round
          AND e.log_round <= w.max_round

        UNION ALL

        SELECT
            e.log_round,
            LOWER(t."from") AS address,
            p.lp_bucket AS bucket,
            'lp' AS flow_kind,
            'chain' AS flow_scope,
            CASE WHEN e.event_name = 'Mint' THEN 1 ELSE -1 END
                * CASE
                    WHEN p.tusdt_side = 0 THEN COALESCE(CAST(json_extract(e.decoded_data, '$.amount0') AS REAL) / 1e18, 0)
                    ELSE COALESCE(CAST(json_extract(e.decoded_data, '$.amount1') AS REAL) / 1e18, 0)
                END AS tusdt_flow
        FROM events e
        JOIN tracked_pairs p ON e.contract_name = p.pair_contract_name
        LEFT JOIN transactions t ON e.tx_hash = t.tx_hash
        CROSS JOIN window_rounds w
        WHERE e.event_name IN ('Mint', 'Burn')
          AND e.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND e.log_round >= w.min_round
          AND e.log_round <= w.max_round

        UNION ALL

        SELECT
            v.log_round,
            LOWER(v.user) AS address,
            'crosschain' AS bucket,
            'crosschain' AS flow_kind,
            'crosschain' AS flow_scope,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS tusdt_flow
        FROM v_tusdt_crosschain v
        CROSS JOIN window_rounds w
        WHERE v.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND v.log_round >= w.min_round
          AND v.log_round <= w.max_round
    ) union_rows
    WHERE address IS NOT NULL
)
SELECT
    r.log_round,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'chain' AND f.tusdt_flow > 0 THEN f.tusdt_flow ELSE 0 END), 0), 6) AS chain_inflow_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'chain' AND f.tusdt_flow < 0 THEN -f.tusdt_flow ELSE 0 END), 0), 6) AS chain_outflow_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'chain' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS net_inflow_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_kind = 'swap' AND f.tusdt_flow > 0 THEN f.tusdt_flow ELSE 0 END), 0), 6) AS swap_in_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_kind = 'swap' AND f.tusdt_flow < 0 THEN -f.tusdt_flow ELSE 0 END), 0), 6) AS swap_out_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_kind = 'swap' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS net_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_kind = 'lp' AND f.tusdt_flow > 0 THEN f.tusdt_flow ELSE 0 END), 0), 6) AS lp_in_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_kind = 'lp' AND f.tusdt_flow < 0 THEN -f.tusdt_flow ELSE 0 END), 0), 6) AS lp_out_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_kind = 'lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS net_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'love20_swap' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS love20_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'life20_swap' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS life20_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'grow20_swap' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS grow20_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'lively_swap' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS lively_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'pretty_swap' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS pretty_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'love20_lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS love20_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'life20_lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS life20_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'grow20_lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS grow20_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'lively_lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS lively_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'pretty_lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS pretty_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'crosschain' AND f.tusdt_flow > 0 THEN f.tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_in_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'crosschain' AND f.tusdt_flow < 0 THEN -f.tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_out_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'crosschain' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_net_tusdt_flow
FROM recent_log_rounds r
LEFT JOIN flow_rows f ON f.log_round = r.log_round
GROUP BY r.log_round
ORDER BY r.log_round ASC;
