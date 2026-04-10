-- Build round_stats from the source events.db.
--
-- 口径：
-- 1. 治理铸币：MintGovReward
-- 2. 行动铸币：MintActionReward + ClaimReward(mintAmount > 0)
-- 3. 总铸币地址数：治理铸币地址 与 行动铸币地址 的去重并集
-- 4. 平均每个地址参与行动数量：同一 log_round 下，所有有铸币地址参与的 distinct actionId 数平均值；
--    仅有治理铸币、没有行动铸币的地址按 0 计入分母
-- 5. 治理铸币新增地址数：当轮发生治理铸币，且此前任意 log_round 从未发生治理铸币的地址数
-- 6. 行动铸币新增地址数：当轮发生行动铸币，且此前任意 log_round 从未发生行动铸币的地址数

WITH gov_mint AS (
    SELECT
        log_round,
        LOWER(account) AS account
    FROM v_mint_gov_reward
    WHERE log_round IS NOT NULL
),
action_mint AS (
    SELECT
        log_round,
        LOWER(account) AS account
    FROM v_mint_action_reward
    WHERE log_round IS NOT NULL

    UNION

    SELECT
        log_round,
        LOWER(account) AS account
    FROM v_claim_reward
    WHERE log_round IS NOT NULL
      AND mint_amount > 0
),
all_mint AS (
    SELECT log_round, account FROM gov_mint
    UNION
    SELECT log_round, account FROM action_mint
),
rounds AS (
    SELECT log_round FROM gov_mint
    UNION
    SELECT log_round FROM action_mint
),
gov_counts AS (
    SELECT
        log_round,
        COUNT(DISTINCT account) AS gov_mint_address_count
    FROM gov_mint
    GROUP BY log_round
),
gov_first_rounds AS (
    SELECT
        account,
        MIN(log_round) AS first_log_round
    FROM gov_mint
    GROUP BY account
),
gov_new_counts AS (
    SELECT
        first_log_round AS log_round,
        COUNT(*) AS new_gov_mint_address_count
    FROM gov_first_rounds
    GROUP BY first_log_round
),
action_counts AS (
    SELECT
        log_round,
        COUNT(DISTINCT account) AS action_mint_address_count
    FROM action_mint
    GROUP BY log_round
),
action_first_rounds AS (
    SELECT
        account,
        MIN(log_round) AS first_log_round
    FROM action_mint
    GROUP BY account
),
action_new_counts AS (
    SELECT
        first_log_round AS log_round,
        COUNT(*) AS new_action_mint_address_count
    FROM action_first_rounds
    GROUP BY first_log_round
),
total_counts AS (
    SELECT
        log_round,
        COUNT(DISTINCT account) AS total_mint_address_count
    FROM all_mint
    GROUP BY log_round
),
overlap_counts AS (
    SELECT
        g.log_round,
        COUNT(DISTINCT g.account) AS overlap_mint_address_count
    FROM gov_mint g
    INNER JOIN action_mint a
        ON a.log_round = g.log_round
       AND a.account = g.account
    GROUP BY g.log_round
),
action_participation AS (
    SELECT
        log_round,
        LOWER(account) AS account,
        CAST(action_id AS TEXT) AS action_id
    FROM v_mint_action_reward
    WHERE log_round IS NOT NULL

    UNION

    SELECT
        log_round,
        LOWER(account) AS account,
        CAST(action_id AS TEXT) AS action_id
    FROM v_claim_reward
    WHERE log_round IS NOT NULL
      AND mint_amount > 0
),
action_participation_per_account AS (
    SELECT
        log_round,
        account,
        COUNT(DISTINCT action_id) AS action_count_per_account
    FROM action_participation
    GROUP BY log_round, account
),
action_participation_stats AS (
    SELECT
        m.log_round,
        ROUND(AVG(COALESCE(a.action_count_per_account, 0)), 4) AS avg_action_count_per_address
    FROM all_mint m
    LEFT JOIN action_participation_per_account a
        ON a.log_round = m.log_round
       AND a.account = m.account
    GROUP BY m.log_round
)
SELECT
    r.log_round,
    COALESCE(t.total_mint_address_count, 0) AS total_mint_address_count,
    COALESCE(gn.new_gov_mint_address_count, 0) AS new_gov_mint_address_count,
    COALESCE(an.new_action_mint_address_count, 0) AS new_action_mint_address_count,
    COALESCE(g.gov_mint_address_count, 0) AS gov_mint_address_count,
    COALESCE(a.action_mint_address_count, 0) AS action_mint_address_count,
    COALESCE(o.overlap_mint_address_count, 0) AS overlap_mint_address_count,
    COALESCE(p.avg_action_count_per_address, 0) AS avg_action_count_per_address
FROM rounds r
LEFT JOIN total_counts t
    ON t.log_round = r.log_round
LEFT JOIN gov_new_counts gn
    ON gn.log_round = r.log_round
LEFT JOIN action_new_counts an
    ON an.log_round = r.log_round
LEFT JOIN gov_counts g
    ON g.log_round = r.log_round
LEFT JOIN action_counts a
    ON a.log_round = r.log_round
LEFT JOIN overlap_counts o
    ON o.log_round = r.log_round
LEFT JOIN action_participation_stats p
    ON p.log_round = r.log_round
ORDER BY r.log_round ASC
