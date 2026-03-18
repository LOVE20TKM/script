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
