-- Build history_summary from the source events.db.
--
-- 口径：
-- 1. 治理铸币：MintGovReward
-- 2. 行动铸币：MintActionReward + ClaimReward(mintAmount > 0)
-- 3. 历史唯一总铸币地址：治理铸币地址 与 行动铸币地址 的去重并集

WITH gov_mint AS (
    SELECT LOWER(account) AS account
    FROM v_mint_gov_reward
    WHERE log_round IS NOT NULL
),
action_mint AS (
    SELECT LOWER(account) AS account
    FROM v_mint_action_reward
    WHERE log_round IS NOT NULL

    UNION

    SELECT LOWER(account) AS account
    FROM v_claim_reward
    WHERE log_round IS NOT NULL
      AND mint_amount > 0
)
SELECT
    (SELECT COUNT(DISTINCT account) FROM gov_mint) AS history_gov_unique_address_count,
    (SELECT COUNT(DISTINCT account) FROM action_mint) AS history_action_unique_address_count,
    (
        SELECT COUNT(DISTINCT account)
        FROM (
            SELECT account FROM gov_mint
            UNION
            SELECT account FROM action_mint
        )
    ) AS history_total_unique_address_count
