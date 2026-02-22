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

SELECT
  'v_erc20' as view_name,count(*) as count
FROM
  v_erc20
UNION ALL
SELECT
  'v_TUSDT' as view_name,count(*) as count
FROM
  v_TUSDT