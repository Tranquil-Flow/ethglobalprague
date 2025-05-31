// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/Test7702Factory.sol";
import "../contracts/TestToken.sol";
import "../contracts/Test7702.sol";

contract DeployTest7702Script is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Test7702Factory
        Test7702Factory factory = new Test7702Factory();
        
        // Compute the address where Test7702 will be deployed
        address predictedAddress = factory.computeAddress();
        console.log("Test7702 will be deployed to:", predictedAddress);
        
        // Deploy Test7702 using the factory
        address deployedAddress = factory.deploy();
        
        // Verify the predicted address matches the actual address
        require(predictedAddress == deployedAddress, "Predicted address does not match deployed address");
        console.log("Test7702 deployed successfully at:", deployedAddress);
        
        // Deploy TestToken
        TestToken token = new TestToken(
            "Test EIP-7702 Token",
            "TEST7702",
            1000000, // 1 million initial supply
            msg.sender
        );
        console.log("TestToken deployed to:", address(token));
        
        // Summary
        console.log("\nDeployment Summary:");
        console.log("Test7702:", deployedAddress);
        console.log("TestToken:", address(token));
        
        vm.stopBroadcast();
    }
} 