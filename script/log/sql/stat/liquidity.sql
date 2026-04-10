-- Active: 1771748349049@@127.0.0.1@3306
SELECT 
    log_round, 
    SUM(amount_sign * tusdt_amount) AS tusdt_amount 
FROM 
    v_liquidity_tusdt_love20 
GROUP BY 
    log_round
ORDER BY 
    log_round DESC 
LIMIT 1000

SELECT 
    log_round,
    user,
    amount_sign, 
    SUM(amount_sign * tusdt_amount) AS tusdt_amount 
FROM 
    v_liquidity_tusdt_love20 
GROUP BY 
    log_round, 
    user 
ORDER BY 
    log_round DESC 
LIMIT 1000


