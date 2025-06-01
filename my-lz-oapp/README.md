# Cross-Chain Token Sweeper

This project implements a cross-chain token sweeper using LayerZero's OApp framework. It allows users to consolidate tokens from multiple chains into ETH on a main chain.

## Architecture

The system consists of two main contracts:

1. **OriginSweeper** - Deployed on the main chain (Optimism)
   - Coordinates token sales across multiple chains
   - Receives ETH from external chains
   - Transfers consolidated ETH to the final receiver

2. **ExternalSweeper** - Deployed on external chains (Base, Unichain)
   - Receives instructions from OriginSweeper
   - Sells tokens on its chain
   - Bridges ETH back to OriginSweeper
   - Notifies OriginSweeper when complete

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm
- API keys for Optimism, Base, and Unichain RPCs
- Private key for deployment

## Installation

1. Clone the repository
2. Install dependencies:

```bash
forge install
npm install
```

3. Copy `.env.example` to `.env` and fill in your RPC URLs and private key:

```bash
cp .env.example .env
```

## Testing with LayerZero TestHelper

The project uses LayerZero's TestHelper to simulate cross-chain interactions in a local testing environment.

### Running Tests

```bash
forge test -vvv
```

This will run the test suite including the `SweeperTest.t.sol` which simulates the full token sweeping flow across multiple chains.

### What the Tests Cover

- Deployment of OriginSweeper and ExternalSweeper contracts
- Creating mock tokens and DEX routers
- Executing token swaps on multiple chains
- Verifying cross-chain messages are sent and received
- Confirming ETH is correctly bridged back to the main chain
- Validating final ETH transfer to the receiver

## Deploying to Forked Networks

You can deploy and test on forked networks using the provided scripts:

### Setting Up Forks

Create forks of the target networks in your `.env` file:

```
OPTIMISM_RPC_URL=https://optimism-mainnet.infura.io/v3/YOUR_API_KEY
BASE_RPC_URL=https://base-mainnet.infura.io/v3/YOUR_API_KEY
UNICHAIN_RPC_URL=https://unichain-mainnet.example.com/YOUR_API_KEY
```

### Deploying to Forks

Deploy to Optimism (main chain) first:

```bash
forge script script/DeployForkTest.s.sol --rpc-url $OPTIMISM_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Note the deployed OriginSweeper address, then update the `knownOriginSweeper` address in the script.

Deploy to Base:

```bash
forge script script/DeployForkTest.s.sol --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Deploy to Unichain:

```bash
forge script script/DeployForkTest.s.sol --rpc-url $UNICHAIN_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### Using Deterministic Addresses (CREATE2)

For production deployments, the `DeploySweeper.s.sol` script uses CREATE2 to deploy contracts with deterministic addresses across all chains. This allows the contracts to find each other across chains without manual configuration.

## Usage Flow

1. User approves tokens for the OriginSweeper contract on the main chain
2. User calls `executeTokenSwaps` with:
   - Chain IDs for all chains where tokens will be sold
   - Swap information arrays for each chain
   - Privacy flag for optional privacy shielding

3. OriginSweeper:
   - Sells tokens on the main chain
   - Sends messages to ExternalSweeper contracts on other chains

4. ExternalSweeper contracts:
   - Receive messages from OriginSweeper
   - Sell tokens on their chains
   - Bridge ETH back to OriginSweeper
   - Send confirmation messages

5. OriginSweeper:
   - Receives ETH from all chains
   - When all chains have completed, transfers ETH to final receiver

## References

- [LayerZero Documentation](https://docs.layerzero.network/)
- [LayerZero TestHelper](https://docs.layerzero.network/v2/developers/evm/tooling/test-helper)
- [Foundry Book](https://book.getfoundry.sh/) 