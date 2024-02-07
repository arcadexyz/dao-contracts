#!/bin/zsh

# navigate to the latest broadcast directory
cd broadcast/DeployLockingPool.s.sol/1 || exit

# find the most recent JSON file
LATEST_JSON=$(ls -Art | tail -n 1)

# extract the contract address and arguments length
CONTRACT_ADDRESS=$(jq -r '.transactions[0].contractAddress' "$LATEST_JSON")
ARGUMENTS_LENGTH=$(jq -r '.transactions[0].arguments | length' "$LATEST_JSON")

# check if the contract address exists and arguments length is greater than 0
if [[ $CONTRACT_ADDRESS != "null" && $ARGUMENTS_LENGTH -eq 11 ]]; then
    echo "Success! Deployment check passed: Contract address exists and constructor arguments length is 11."
else
    echo "Deployment check failed."
fi
