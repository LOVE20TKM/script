SELECT
  contract_name,
  event_name,
  COUNT(*) AS count
FROM
  events
GROUP BY
  contract_name,
  event_name
ORDER BY
  count DESC;





-- per-round mint address counts: action, gov, total
SELECT
  r.log_round,
  COALESCE(action.action_mint_address_count, 0) AS action_mint_address_count,
  COALESCE(gov.gov_mint_address_count, 0) AS gov_mint_address_count,
  COALESCE(total.total_mint_address_count, 0) AS total_mint_address_count
FROM (
  SELECT DISTINCT log_round FROM (
    SELECT log_round FROM v_mint_gov_reward WHERE log_round IS NOT NULL
    UNION
    SELECT log_round FROM v_mint_action_reward WHERE log_round IS NOT NULL
    UNION
    SELECT log_round FROM v_claim_reward WHERE log_round IS NOT NULL AND mint_amount > 0
  )
) r
LEFT JOIN (
  SELECT log_round, COUNT(DISTINCT account) AS action_mint_address_count
  FROM (
    SELECT log_round, account FROM v_mint_action_reward
    UNION ALL
    SELECT log_round, account FROM v_claim_reward WHERE mint_amount > 0
  )
  WHERE log_round IS NOT NULL
  GROUP BY log_round
) action ON r.log_round = action.log_round
LEFT JOIN (
  SELECT log_round, COUNT(DISTINCT account) AS gov_mint_address_count
  FROM v_mint_gov_reward
  WHERE log_round IS NOT NULL
  GROUP BY log_round
) gov ON r.log_round = gov.log_round
LEFT JOIN (
  SELECT log_round, COUNT(DISTINCT account) AS total_mint_address_count
  FROM (
    SELECT log_round, account FROM v_mint_gov_reward
    UNION
    SELECT log_round, account FROM v_mint_action_reward
    UNION
    SELECT log_round, account FROM v_claim_reward WHERE mint_amount > 0
  )
  WHERE log_round IS NOT NULL
  GROUP BY log_round
) total ON r.log_round = total.log_round
ORDER BY r.log_round DESC;

-- 每个地址投票数
SELECT
  json_extract(decoded_data, '$.voter') AS voter,
  SUM(CAST(json_extract(decoded_data, '$.votes') AS REAL) / 1e18) AS total_vote_amount
FROM events
WHERE contract_name = 'vote' AND event_name = 'Vote'
GROUP BY voter
ORDER BY total_vote_amount DESC;