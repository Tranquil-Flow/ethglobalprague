// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../contracts/ExternalSweeper.sol";
import "../contracts/OriginSweeper.sol";
import "../contracts/TestToken.sol";

contract DeployForkTestScript is Script {
    // Chain IDs for LayerZero
    uint32 constant CHAIN_ID_OPTIMISM = 111;  // Optimism
    uint32 constant CHAIN_ID_BASE = 184;      // Base
    uint32 constant CHAIN_ID_UNICHAIN = 130;  // Unichain
    
    // Endpoint addresses on each chain
    address constant ENDPOINT_OPTIMISM = 0x1a44076050125825900e736c501f859c50fE728c;  // Optimism
    address constant ENDPOINT_BASE = 0x1a44076050125825900e736c501f859c50fE728c;      // Base
    address constant ENDPOINT_UNICHAIN = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;  // Unichain
    
    // USDC addresses on each chain
    address constant USDC_OPTIMISM = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;  // USDC on Optimism
    address constant USDC_BASE = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;       // USDC on Base
    address constant USDC_UNICHAIN = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;   // USDC on Unichain
    
    // Addresses for deployed contracts
    address public originSweeper;
    address public baseExternalSweeper;
    address public unichainExternalSweeper;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get network info based on current chain
        (string memory networkName, address endpoint, uint32 mainChainId) = getNetworkInfo();
        
        vm.startBroadcast(deployerPrivateKey);
        
        if (block.chainid == 10) { // Optimism
            console.log("Deploying on Optimism (Main Chain)");
            
            // Deploy OriginSweeper on Optimism
            address finalReceiverAddress = deployer;
            uint totalChainsSelling = 3;
            
            OriginSweeper origin = new OriginSweeper(
                ENDPOINT_OPTIMISM,
                deployer,
                finalReceiverAddress,
                totalChainsSelling
            );
            
            originSweeper = address(origin);
            console.log("OriginSweeper deployed on Optimism at:", originSweeper);
            
            // Precalculate external sweeper addresses (for configuration)
            console.log("Expected ExternalSweeper address on Base: [Precalculated Address]");
            console.log("Expected ExternalSweeper address on Unichain: [Precalculated Address]");
            
        } else if (block.chainid == 8453) { // Base
            console.log("Deploying on Base (External Chain)");
            
            // You would need to know the address of OriginSweeper on Optimism
            address knownOriginSweeper = 0x0000000000000000000000000000000000000000; // Replace with actual address
            
            ExternalSweeper externalSweeper = new ExternalSweeper(
                ENDPOINT_BASE,
                deployer,
                knownOriginSweeper,
                CHAIN_ID_OPTIMISM
            );
            
            baseExternalSweeper = address(externalSweeper);
            console.log("ExternalSweeper deployed on Base at:", baseExternalSweeper);
            
        } else if (block.chainid == 130) { // Unichain (replace with actual chainId)
            console.log("Deploying on Unichain (External Chain)");
            
            // You would need to know the address of OriginSweeper on Optimism
            address knownOriginSweeper = 0x0000000000000000000000000000000000000000; // Replace with actual address
            
            ExternalSweeper externalSweeper = new ExternalSweeper(
                ENDPOINT_UNICHAIN,
                deployer,
                knownOriginSweeper,
                CHAIN_ID_OPTIMISM
            );
            
            unichainExternalSweeper = address(externalSweeper);
            console.log("ExternalSweeper deployed on Unichain at:", unichainExternalSweeper);
        } else {
            revert("Unsupported chain");
        }
        
        vm.stopBroadcast();
        
        // Print deployment summary
        console.log("\nDeployment Summary for", networkName);
        if (block.chainid == 10) {
            console.log("OriginSweeper:", originSweeper);
        } else {
            console.log("ExternalSweeper:", block.chainid == 8453 ? baseExternalSweeper : unichainExternalSweeper);
        }
    }
    
    function getNetworkInfo() internal view returns (string memory networkName, address endpoint, uint32 mainChainId) {
        if (block.chainid == 10) {
            return ("Optimism", ENDPOINT_OPTIMISM, CHAIN_ID_OPTIMISM);
        } else if (block.chainid == 8453) {
            return ("Base", ENDPOINT_BASE, CHAIN_ID_OPTIMISM);
        } else if (block.chainid == 130) { // Replace with actual Unichain chainId
            return ("Unichain", ENDPOINT_UNICHAIN, CHAIN_ID_OPTIMISM);
        } else {
            revert("Unsupported chain");
        }
    }
    
    // Helper function to run forks and tests locally
    function setupLocalForks() internal {
        // Create Optimism fork
        uint256 optimismFork = vm.createFork("optimism");
        
        // Create Base fork
        uint256 baseFork = vm.createFork("base");
        
        // Create Unichain fork (replace with actual RPC)
        uint256 unichainFork = vm.createFork("unichain");
        
        // Deploy on Optimism
        vm.selectFork(optimismFork);
        // Deploy OriginSweeper
        
        // Deploy on Base
        vm.selectFork(baseFork);
        // Deploy ExternalSweeper
        
        // Deploy on Unichain
        vm.selectFork(unichainFork);
        // Deploy ExternalSweeper
    }
} 