-- Active: 1771748349049@@127.0.0.1@3306
-- per-round TUSDT flow stats (Liquidity + Swap)
SELECT 
    l.log_round,
    l.net_add_liquidity_tusdt,
    s.net_buy_tusdt,
    l.net_add_liquidity_tusdt + s.net_buy_tusdt AS net_inflow_tusdt
FROM (
    SELECT 
        log_round,
        COALESCE(SUM(CASE WHEN amount_sign = 1 THEN tusdt_amount ELSE 0 END), 0) 
        - COALESCE(SUM(CASE WHEN amount_sign = -1 THEN tusdt_amount ELSE 0 END), 0) AS net_add_liquidity_tusdt
    FROM v_liquidity_tusdt_love20
    WHERE log_round IS NOT NULL
    GROUP BY log_round
) l
LEFT JOIN (
    SELECT 
        log_round,
        COALESCE(SUM(tusdt_in_amount), 0) - COALESCE(SUM(tusdt_out_amount), 0) AS net_buy_tusdt
    FROM v_love20_tusdt_swap
    WHERE log_round IS NOT NULL
    GROUP BY log_round
) s ON l.log_round = s.log_round
ORDER BY l.log_round DESC
LIMIT 1000;

-- last 30 rounds: per-address TUSDT flow details
SELECT
    log_round,
    LOWER(address) AS address,
    SUM(liquidity_change) AS liquidity_change,
    SUM(swap_change) AS swap_change,
    SUM(liquidity_change) + SUM(swap_change) AS net_flow
FROM (
    SELECT
        v.log_round,
        LOWER(v.user) AS address,
        COALESCE(SUM(v.tusdt_amount), 0) AS liquidity_change,
        0 AS swap_change
    FROM v_liquidity_tusdt_love20 v
    WHERE v.log_round IS NOT NULL
        AND v.log_round >= (SELECT MAX(log_round) FROM v_liquidity_tusdt_love20 WHERE log_round IS NOT NULL) - 29
    GROUP BY v.log_round, LOWER(v.user)
    UNION ALL
    SELECT
        s.log_round,
        LOWER(s."to") AS address,
        0 AS liquidity_change,
        COALESCE(s.tusdt_in_amount, 0) - COALESCE(s.tusdt_out_amount, 0) AS swap_change
    FROM v_love20_tusdt_swap s
    WHERE s.log_round IS NOT NULL
        AND s.log_round >= (SELECT MAX(log_round) FROM v_love20_tusdt_swap WHERE log_round IS NOT NULL) - 29
) combined
GROUP BY log_round, LOWER(address)
ORDER BY log_round DESC, net_flow DESC;

-- last X rounds: per-address TUSDT inflow details (LOVE20 + LIFE20)
-- 口径：
-- 0. 最近 X 轮窗口基于 events 总表的 log_round
-- 1. swap 侧：卖出 LOVE20/LIFE20 = 负数；买入 LOVE20/LIFE20 = 正数
-- 2. LP 侧：添加 LOVE20/LIFE20 与 TUSDT LP = 正数；移除 = 负数
-- 3. 跨链侧：TUSDT 铸造跨入 = 正数；TUSDT 销毁跨出 = 负数
-- 4. net_inflow_tusdt 先只算 swap + LP（正表示净流入）
-- 5. 跨链 3 列单独展示，暂不并入 net_inflow_tusdt
-- 改 recent_rounds 就是 X
WITH params AS (
    SELECT 15 AS recent_rounds
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
swap_flows AS (
    SELECT
        address,
        SUM(love20_swap_tusdt_flow) AS love20_swap_tusdt_flow,
        SUM(life20_swap_tusdt_flow) AS life20_swap_tusdt_flow
    FROM (
        SELECT
            LOWER(COALESCE(s.user, s."to")) AS address,
            COALESCE(s.tusdt_in_amount, 0) - COALESCE(s.tusdt_out_amount, 0) AS love20_swap_tusdt_flow,
            0 AS life20_swap_tusdt_flow
        FROM v_love20_tusdt_swap s
        CROSS JOIN window_rounds w
        WHERE s.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND s.log_round >= w.min_round

        UNION ALL

        SELECT
            LOWER(COALESCE(s.user, s."to")) AS address,
            0 AS love20_swap_tusdt_flow,
            COALESCE(s.tusdt_in_amount, 0) - COALESCE(s.tusdt_out_amount, 0) AS life20_swap_tusdt_flow
        FROM v_life20_tusdt_swap s
        CROSS JOIN window_rounds w
        WHERE s.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND s.log_round >= w.min_round
    ) swap_rows
    WHERE address IS NOT NULL
    GROUP BY address
),
lp_flows AS (
    SELECT
        address,
        SUM(love20_lp_tusdt_flow) AS love20_lp_tusdt_flow,
        SUM(life20_lp_tusdt_flow) AS life20_lp_tusdt_flow
    FROM (
        SELECT
            LOWER(v.user) AS address,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS love20_lp_tusdt_flow,
            0 AS life20_lp_tusdt_flow
        FROM v_liquidity_tusdt_love20 v
        CROSS JOIN window_rounds w
        WHERE v.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND v.log_round >= w.min_round

        UNION ALL

        SELECT
            LOWER(v.user) AS address,
            0 AS love20_lp_tusdt_flow,
            COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0) AS life20_lp_tusdt_flow
        FROM v_liquidity_tusdt_life20 v
        CROSS JOIN window_rounds w
        WHERE v.log_round IS NOT NULL
          AND w.min_round IS NOT NULL
          AND v.log_round >= w.min_round
    ) lp_rows
    WHERE address IS NOT NULL
    GROUP BY address
),
crosschain_flows AS (
    SELECT
        LOWER(v.user) AS address,
        SUM(CASE WHEN v.amount_sign = 1 THEN COALESCE(v.tusdt_amount, 0) ELSE 0 END) AS tusdt_crosschain_in_tusdt,
        SUM(CASE WHEN v.amount_sign = -1 THEN -COALESCE(v.tusdt_amount, 0) ELSE 0 END) AS tusdt_crosschain_out_tusdt,
        SUM(COALESCE(v.amount_sign, 0) * COALESCE(v.tusdt_amount, 0)) AS tusdt_crosschain_net_tusdt_flow
    FROM v_tusdt_crosschain v
    CROSS JOIN window_rounds w
    WHERE v.log_round IS NOT NULL
      AND w.min_round IS NOT NULL
      AND v.log_round >= w.min_round
      AND v.user IS NOT NULL
    GROUP BY LOWER(v.user)
),
addresses AS (
    SELECT address FROM swap_flows
    UNION
    SELECT address FROM lp_flows
    UNION
    SELECT address FROM crosschain_flows
)
SELECT
    a.address,
    ROUND(COALESCE(s.love20_swap_tusdt_flow, 0), 6) AS love20_swap_tusdt_flow,
    ROUND(COALESCE(s.life20_swap_tusdt_flow, 0), 6) AS life20_swap_tusdt_flow,
    ROUND(COALESCE(l.love20_lp_tusdt_flow, 0), 6) AS love20_lp_tusdt_flow,
    ROUND(COALESCE(l.life20_lp_tusdt_flow, 0), 6) AS life20_lp_tusdt_flow,
    ROUND(COALESCE(s.love20_swap_tusdt_flow, 0) + COALESCE(s.life20_swap_tusdt_flow, 0), 6) AS net_swap_tusdt_flow,
    ROUND(COALESCE(l.love20_lp_tusdt_flow, 0) + COALESCE(l.life20_lp_tusdt_flow, 0), 6) AS net_lp_tusdt_flow,
    ROUND(
        COALESCE(s.love20_swap_tusdt_flow, 0)
        + COALESCE(s.life20_swap_tusdt_flow, 0)
        + COALESCE(l.love20_lp_tusdt_flow, 0)
        + COALESCE(l.life20_lp_tusdt_flow, 0),
        6
    ) AS net_inflow_tusdt,
    ROUND(COALESCE(c.tusdt_crosschain_in_tusdt, 0), 6) AS tusdt_crosschain_in_tusdt,
    ROUND(COALESCE(c.tusdt_crosschain_out_tusdt, 0), 6) AS tusdt_crosschain_out_tusdt,
    ROUND(COALESCE(c.tusdt_crosschain_net_tusdt_flow, 0), 6) AS tusdt_crosschain_net_tusdt_flow
FROM addresses a
LEFT JOIN swap_flows s ON s.address = a.address
LEFT JOIN lp_flows l ON l.address = a.address
LEFT JOIN crosschain_flows c ON c.address = a.address
ORDER BY net_inflow_tusdt DESC, a.address;
