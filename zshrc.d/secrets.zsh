# This script re-exports secrets from 1Password to the shell.
# 
# For anything that doesn't need to be available in every shell session,
# use the `with-secrets` function.

export ETH_RPC_URL="{{ op://Machine/secrets.zshrc/ETH_RPC_URL }}"
export ETHERSCAN_API_KEY="{{ op://Machine/secrets.zshrc/ETHERSCAN_API_KEY }}"