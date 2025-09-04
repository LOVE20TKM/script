
# SECONDS_PER_BLOCK=3


network=$1
if [ -z "$network" ] || [ ! -d "../network/$network" ]; then
    echo -e "\033[31mError:\033[0m Network parameter is required."
    echo -e "\nAvailable networks:"
    for net in $(ls ../network); do
        echo "  - $net"
    done
    return 1
fi

echo "===================="
echo "      flow_all      "
echo "===================="

# init
source 000_init.sh $network



source weth_deposit.sh
source weth_withdraw.sh
source weth_deposit.sh

source launch_contribute.sh

# wait for WITHDRAW_WAITING_BLOCKS
skip_withdraw_waiting_blocks

source launch_withdraw.sh

source launch_contribute.sh

skip_second_half_min_blocks

source launch_contribute.sh

# wait for 1 second to make sure can claim
countdown 1

source launch_claim.sh
source burnForParentToken.sh

# gov start

source stake_liquidity.sh

source stake_token.sh

source stake_unstake.sh

skip_promised_waiting_phases

source stake_withdraw.sh

source stake_liquidity.sh

source stake_token.sh

# round n + 1 
source submit_new_action.sh

source vote.sh

next_phase

source join.sh

source join_withdraw.sh

source join.sh

source join_update.sh

next_phase

source verify.sh

next_phase

source mint_action_reward.sh

source mint_gov_reward.sh

next_phase

# round n + 2

source submit.sh

source vote.sh

next_phase

source join.sh

next_phase

source verify.sh

next_phase

source mint_action_reward.sh
source mint_gov_reward.sh

#deploy child token 
source launch_deploy.sh

# exist
source join_withdraw.sh

source stake_unstake.sh
skip_promised_waiting_phases
source stake_withdraw.sh