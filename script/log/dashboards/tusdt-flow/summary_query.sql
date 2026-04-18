WITH params AS (
    SELECT CAST(? AS INTEGER) AS recent_rounds
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
            s.log_round,
            LOWER(COALESCE(s.user, s."to")) AS address,
            'love20_swap' AS bucket,
            'swap' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(s.tusdt_in_amount, 0) - COALESCE(s.tusdt_out_amount, 0) AS tusdt_flow
        FROM v_love20_tusdt_swap s
        CROSS JOIN window_rounds w
        WHERE s.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND s.log_round >= w.min_round
          AND s.log_round <= w.max_round

        UNION ALL

        SELECT
            s.log_round,
            LOWER(COALESCE(s.user, s."to")) AS address,
            'life20_swap' AS bucket,
            'swap' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(s.tusdt_in_amount, 0) - COALESCE(s.tusdt_out_amount, 0) AS tusdt_flow
        FROM v_life20_tusdt_swap s
        CROSS JOIN window_rounds w
        WHERE s.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND s.log_round >= w.min_round
          AND s.log_round <= w.max_round

        UNION ALL

        SELECT
            v.log_round,
            LOWER(v.user) AS address,
            'love20_lp' AS bucket,
            'lp' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS tusdt_flow
        FROM v_liquidity_tusdt_love20 v
        CROSS JOIN window_rounds w
        WHERE v.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND v.log_round >= w.min_round
          AND v.log_round <= w.max_round

        UNION ALL

        SELECT
            v.log_round,
            LOWER(v.user) AS address,
            'life20_lp' AS bucket,
            'lp' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS tusdt_flow
        FROM v_liquidity_tusdt_life20 v
        CROSS JOIN window_rounds w
        WHERE v.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND v.log_round >= w.min_round
          AND v.log_round <= w.max_round

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
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'love20_lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS love20_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.bucket = 'life20_lp' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS life20_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'crosschain' AND f.tusdt_flow > 0 THEN f.tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_in_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'crosschain' AND f.tusdt_flow < 0 THEN -f.tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_out_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN f.flow_scope = 'crosschain' THEN f.tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_net_tusdt_flow
FROM recent_log_rounds r
LEFT JOIN flow_rows f ON f.log_round = r.log_round
GROUP BY r.log_round
ORDER BY r.log_round ASC;
