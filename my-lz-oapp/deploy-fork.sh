#!/bin/bash

# Load environment variables
source .env

# Check which chain to deploy to
if [ "$1" == "optimism" ]; then
    echo "Deploying to Optimism (Main Chain)..."
    forge script script/DeployForkTest.s.sol --rpc-url $OPTIMISM_RPC_URL --private-key $PRIVATE_KEY --broadcast
elif [ "$1" == "base" ]; then
    echo "Deploying to Base (External Chain)..."
    forge script script/DeployForkTest.s.sol --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
elif [ "$1" == "unichain" ]; then
    echo "Deploying to Unichain (External Chain)..."
    forge script script/DeployForkTest.s.sol --rpc-url $UNICHAIN_RPC_URL --private-key $PRIVATE_KEY --broadcast
else
    echo "Please specify a chain: optimism, base, or unichain"
    echo "Usage: ./deploy-fork.sh <chain>"
    exit 1
fi 