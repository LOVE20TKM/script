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

-- per-round LOVE20 buy/sell stats (TUSDT pair, TUSDT flow perspective)
SELECT
  log_round,
  COALESCE(SUM(tusdt_in_amount), 0) AS buy_total,
  COALESCE(SUM(tusdt_out_amount), 0) AS sell_total,
  COALESCE(SUM(tusdt_in_amount), 0) - COALESCE(SUM(tusdt_out_amount), 0) AS net_buy,
  COUNT(DISTINCT CASE WHEN tusdt_in_amount > 0 THEN "to" END) AS buy_address_count,
  COUNT(DISTINCT CASE WHEN tusdt_out_amount > 0 THEN "to" END) AS sell_address_count
FROM v_love20_tusdt_swap
WHERE log_round IS NOT NULL
GROUP BY log_round
ORDER BY log_round DESC;

-- last 7 rounds: per-address buy/sell details (TUSDT pair)
WITH last_7_rounds AS (
  SELECT log_round
  FROM v_love20_tusdt_swap
  WHERE log_round IS NOT NULL
  GROUP BY log_round
  ORDER BY log_round DESC
  LIMIT 7
)
SELECT
  v.log_round,
  v."to" AS address,
  COALESCE(SUM(v.tusdt_in_amount), 0) AS buy_tusdt,
  COALESCE(SUM(v.tusdt_out_amount), 0) AS sell_tusdt,
  COALESCE(SUM(v.love20_out_amount), 0) AS buy_love20,
  COALESCE(SUM(v.love20_in_amount), 0) AS sell_love20,
  COUNT(*) AS tx_count
FROM v_love20_tusdt_swap v
WHERE v.log_round IN (SELECT log_round FROM last_7_rounds)
GROUP BY v.log_round, v."to"
ORDER BY v.log_round DESC, buy_tusdt + sell_tusdt DESC;



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