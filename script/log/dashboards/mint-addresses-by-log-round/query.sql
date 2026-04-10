SELECT
    log_round,
    total_mint_address_count,
    new_gov_mint_address_count,
    new_action_mint_address_count,
    gov_mint_address_count,
    action_mint_address_count,
    avg_action_count_per_address,
    overlap_mint_address_count
FROM round_stats
ORDER BY log_round ASC;
