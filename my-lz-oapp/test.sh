#!/bin/bash

# Check if .env file exists and source it
if [ -f ".env" ]; then
  source .env
else
  echo "Error: .env file not found. Please create one with your RPC URLs."
  echo "See .env.example for the required format."
  exit 1
fi

# Verify that we have the necessary RPC URLs
if [ -z "$OPTIMISM_RPC_URL" ] || [ -z "$BASE_RPC_URL" ]; then
  echo "Error: Missing required RPC URLs in .env file."
  echo "Make sure OPTIMISM_RPC_URL and BASE_RPC_URL are set."
  exit 1
fi

echo "Running cross-chain token sweeper tests with real USDC on fork networks..."
echo "- Using Optimism fork: $OPTIMISM_RPC_URL"
echo "- Using Base fork: $BASE_RPC_URL"

# Run the tests with verbosity level 3 and force create forks
forge test --match-path "test/SweeperTest.t.sol" -vvv 