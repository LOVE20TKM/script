-- Active: 1772299349150@@127.0.0.1@3306
-- per-round stats (TUSDT-LOVE20 pair)
SELECT
  log_round,
  COALESCE(SUM(tusdt_in_amount), 0) AS tusdt_in_total,
  COALESCE(SUM(tusdt_out_amount), 0) AS tusdt_out_total,
  COALESCE(SUM(tusdt_in_amount), 0) - COALESCE(SUM(tusdt_out_amount), 0) AS tusdt_net_in,
  COALESCE(SUM(love20_in_amount), 0) AS love20_in_total,
  COALESCE(SUM(love20_out_amount), 0) AS love20_out_total,
  COALESCE(SUM(love20_in_amount), 0) - COALESCE(SUM(love20_out_amount), 0) AS love20_net_in,
  COUNT(DISTINCT CASE WHEN tusdt_in_amount > 0 THEN "to" END) AS tusdt_in_address_count,
  COUNT(DISTINCT CASE WHEN tusdt_out_amount > 0 THEN "to" END) AS tusdt_out_address_count
FROM v_love20_tusdt_swap
WHERE log_round IS NOT NULL
GROUP BY log_round
ORDER BY log_round DESC;

-- last 30 rounds: per-address details (TUSDT pair)
SELECT
  v.log_round,
  v."to" AS address,
  COALESCE(SUM(v.tusdt_in_amount), 0) AS tusdt_in,
  COALESCE(SUM(v.tusdt_out_amount), 0) AS tusdt_out,
  COALESCE(SUM(v.love20_out_amount), 0) AS love20_out,
  COALESCE(SUM(v.love20_in_amount), 0) AS love20_in,
  COUNT(*) AS tx_count
FROM v_love20_tusdt_swap v
WHERE v.log_round IS NOT NULL
  AND v.log_round >= (SELECT MAX(log_round) FROM v_love20_tusdt_swap WHERE log_round IS NOT NULL) - 29
GROUP BY v.log_round, v."to"
ORDER BY v.log_round DESC, tusdt_in + tusdt_out DESC;

-- per-round stats (LOVE20-TKM20 pair)
SELECT
  log_round,
  COALESCE(SUM(love20_in_amount), 0) AS love20_in_total,
  COALESCE(SUM(love20_out_amount), 0) AS love20_out_total,
  COALESCE(SUM(love20_in_amount), 0) - COALESCE(SUM(love20_out_amount), 0) AS love20_net_in,
  COALESCE(SUM(tkm20_in_amount), 0) AS tkm20_in_total,
  COALESCE(SUM(tkm20_out_amount), 0) AS tkm20_out_total,
  COALESCE(SUM(tkm20_in_amount), 0) - COALESCE(SUM(tkm20_out_amount), 0) AS tkm20_net_in,
  COUNT(DISTINCT CASE WHEN tkm20_in_amount > 0 THEN "to" END) AS tkm20_in_address_count,
  COUNT(DISTINCT CASE WHEN tkm20_out_amount > 0 THEN "to" END) AS tkm20_out_address_count
FROM v_love20_tkm20_swap
WHERE log_round IS NOT NULL
GROUP BY log_round
ORDER BY log_round DESC;

-- last 7 rounds: per-address details (TKM20 pair)
SELECT
  v.log_round,
  v."to" AS address,
  COALESCE(SUM(v.tkm20_in_amount), 0) AS tkm20_in,
  COALESCE(SUM(v.tkm20_out_amount), 0) AS tkm20_out,
  COALESCE(SUM(v.love20_out_amount), 0) AS love20_out,
  COALESCE(SUM(v.love20_in_amount), 0) AS love20_in,
  COUNT(*) AS tx_count
FROM v_love20_tkm20_swap v
WHERE v.log_round IS NOT NULL
  AND v.log_round >= (SELECT MAX(log_round) FROM v_love20_tkm20_swap WHERE log_round IS NOT NULL) - 6
GROUP BY v.log_round, v."to"
ORDER BY v.log_round DESC, tkm20_in + tkm20_out DESC;