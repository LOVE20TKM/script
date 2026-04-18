WITH params AS (
    SELECT
        CAST(? AS INTEGER) AS from_round,
        CAST(? AS INTEGER) AS to_round
),
flow_rows AS (
    SELECT *
    FROM (
        SELECT
            LOWER(COALESCE(s.user, s."to")) AS address,
            'love20_swap' AS bucket,
            'swap' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(s.tusdt_in_amount, 0) - COALESCE(s.tusdt_out_amount, 0) AS tusdt_flow
        FROM v_love20_tusdt_swap s
        CROSS JOIN params p
        WHERE s.log_round IS NOT NULL
          AND s.log_round >= p.from_round
          AND s.log_round <= p.to_round

        UNION ALL

        SELECT
            LOWER(COALESCE(s.user, s."to")) AS address,
            'life20_swap' AS bucket,
            'swap' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(s.tusdt_in_amount, 0) - COALESCE(s.tusdt_out_amount, 0) AS tusdt_flow
        FROM v_life20_tusdt_swap s
        CROSS JOIN params p
        WHERE s.log_round IS NOT NULL
          AND s.log_round >= p.from_round
          AND s.log_round <= p.to_round

        UNION ALL

        SELECT
            LOWER(v.user) AS address,
            'love20_lp' AS bucket,
            'lp' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS tusdt_flow
        FROM v_liquidity_tusdt_love20 v
        CROSS JOIN params p
        WHERE v.log_round IS NOT NULL
          AND v.log_round >= p.from_round
          AND v.log_round <= p.to_round

        UNION ALL

        SELECT
            LOWER(v.user) AS address,
            'life20_lp' AS bucket,
            'lp' AS flow_kind,
            'chain' AS flow_scope,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS tusdt_flow
        FROM v_liquidity_tusdt_life20 v
        CROSS JOIN params p
        WHERE v.log_round IS NOT NULL
          AND v.log_round >= p.from_round
          AND v.log_round <= p.to_round

        UNION ALL

        SELECT
            LOWER(v.user) AS address,
            'crosschain' AS bucket,
            'crosschain' AS flow_kind,
            'crosschain' AS flow_scope,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS tusdt_flow
        FROM v_tusdt_crosschain v
        CROSS JOIN params p
        WHERE v.log_round IS NOT NULL
          AND v.log_round >= p.from_round
          AND v.log_round <= p.to_round
    ) union_rows
    WHERE address IS NOT NULL
)
SELECT
    address,
    ROUND(COALESCE(SUM(CASE WHEN flow_scope = 'chain' AND tusdt_flow > 0 THEN tusdt_flow ELSE 0 END), 0), 6) AS chain_inflow_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_scope = 'chain' AND tusdt_flow < 0 THEN -tusdt_flow ELSE 0 END), 0), 6) AS chain_outflow_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_scope = 'chain' THEN tusdt_flow ELSE 0 END), 0), 6) AS net_inflow_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_kind = 'swap' AND tusdt_flow > 0 THEN tusdt_flow ELSE 0 END), 0), 6) AS swap_in_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_kind = 'swap' AND tusdt_flow < 0 THEN -tusdt_flow ELSE 0 END), 0), 6) AS swap_out_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_kind = 'swap' THEN tusdt_flow ELSE 0 END), 0), 6) AS net_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN flow_kind = 'lp' AND tusdt_flow > 0 THEN tusdt_flow ELSE 0 END), 0), 6) AS lp_in_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_kind = 'lp' AND tusdt_flow < 0 THEN -tusdt_flow ELSE 0 END), 0), 6) AS lp_out_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_kind = 'lp' THEN tusdt_flow ELSE 0 END), 0), 6) AS net_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN bucket = 'love20_swap' THEN tusdt_flow ELSE 0 END), 0), 6) AS love20_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN bucket = 'life20_swap' THEN tusdt_flow ELSE 0 END), 0), 6) AS life20_swap_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN bucket = 'love20_lp' THEN tusdt_flow ELSE 0 END), 0), 6) AS love20_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN bucket = 'life20_lp' THEN tusdt_flow ELSE 0 END), 0), 6) AS life20_lp_tusdt_flow,
    ROUND(COALESCE(SUM(CASE WHEN flow_scope = 'crosschain' AND tusdt_flow > 0 THEN tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_in_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_scope = 'crosschain' AND tusdt_flow < 0 THEN -tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_out_tusdt,
    ROUND(COALESCE(SUM(CASE WHEN flow_scope = 'crosschain' THEN tusdt_flow ELSE 0 END), 0), 6) AS tusdt_crosschain_net_tusdt_flow
FROM flow_rows
GROUP BY address;
