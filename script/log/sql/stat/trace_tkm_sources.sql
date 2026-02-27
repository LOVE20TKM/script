-- TKM inflows: which addresses sent native TKM to target addresses.
-- Targets: addresses that sold > 400 TUSDT in last 14 rounds (same as sell_400).
-- Requires: transactions table synced.
-- Usage: ./export.sh thinkium70001_public sql/stat/trace_tkm_sources.sql

WITH last_14 AS (
  SELECT MAX(log_round) - 13 AS min_round
  FROM v_love20_tusdt_swap
  WHERE log_round IS NOT NULL
),
per_round_sell AS (
  SELECT log_round, LOWER("to") AS addr, SUM(tusdt_out_amount) AS tusdt_out
  FROM v_love20_tusdt_swap
  WHERE log_round >= (SELECT min_round FROM last_14)
    AND log_round IS NOT NULL
  GROUP BY log_round, LOWER("to")
),
target_addr AS (
  SELECT DISTINCT addr FROM per_round_sell WHERE tusdt_out > 400
)
SELECT
  t."to" AS address,
  t."from" AS from_address,
  SUM(t.amount) AS tkm_received
FROM transactions t
JOIN target_addr a ON LOWER(t."to") = a.addr
WHERE t.amount > 0
GROUP BY LOWER(t."to"), LOWER(t."from")
ORDER BY LOWER(t."to"), tkm_received DESC;
