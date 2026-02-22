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

