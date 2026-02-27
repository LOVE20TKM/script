-- Active: 1771748349049@@127.0.0.1@3306
SELECT max(block_number) AS max_block_number,COUNT(*) AS total_transactions
FROM transactions;