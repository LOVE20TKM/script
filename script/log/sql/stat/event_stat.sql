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

-- per-round LOVE20 buy/sell stats (TUSDT pair / u pool only)
SELECT
  round,
  COALESCE(SUM(love20_out_amount), 0) AS buy_total,
  COALESCE(SUM(love20_in_amount), 0) AS sell_total,
  COALESCE(SUM(love20_out_amount), 0) - COALESCE(SUM(love20_in_amount), 0) AS net_buy,
  COUNT(DISTINCT CASE WHEN love20_out_amount > 0 THEN "to" END) AS buy_address_count,
  COUNT(DISTINCT CASE WHEN love20_in_amount > 0 THEN "to" END) AS sell_address_count
FROM v_love20_tusdt_swap
WHERE round IS NOT NULL
GROUP BY round
ORDER BY round DESC;

-- per-round mint address counts: action, gov, total
SELECT
  r.round,
  COALESCE(action.action_mint_address_count, 0) AS action_mint_address_count,
  COALESCE(gov.gov_mint_address_count, 0) AS gov_mint_address_count,
  COALESCE(total.total_mint_address_count, 0) AS total_mint_address_count
FROM (
  SELECT DISTINCT round FROM (
    SELECT round FROM v_mint_gov_reward WHERE round IS NOT NULL
    UNION
    SELECT round FROM v_mint_action_reward WHERE round IS NOT NULL
    UNION
    SELECT round FROM v_claim_reward WHERE round IS NOT NULL AND mint_amount > 0
  )
) r
LEFT JOIN (
  SELECT round, COUNT(DISTINCT account) AS action_mint_address_count
  FROM (
    SELECT round, account FROM v_mint_action_reward
    UNION ALL
    SELECT round, account FROM v_claim_reward WHERE mint_amount > 0
  )
  WHERE round IS NOT NULL
  GROUP BY round
) action ON r.round = action.round
LEFT JOIN (
  SELECT round, COUNT(DISTINCT account) AS gov_mint_address_count
  FROM v_mint_gov_reward
  WHERE round IS NOT NULL
  GROUP BY round
) gov ON r.round = gov.round
LEFT JOIN (
  SELECT round, COUNT(DISTINCT account) AS total_mint_address_count
  FROM (
    SELECT round, account FROM v_mint_gov_reward
    UNION
    SELECT round, account FROM v_mint_action_reward
    UNION
    SELECT round, account FROM v_claim_reward WHERE mint_amount > 0
  )
  WHERE round IS NOT NULL
  GROUP BY round
) total ON r.round = total.round
ORDER BY r.round DESC;

