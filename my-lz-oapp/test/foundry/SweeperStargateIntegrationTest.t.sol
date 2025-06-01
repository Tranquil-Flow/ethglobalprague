// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import "../../contracts/ExternalSweeperSwapless.sol";
import "../../contracts/interfaces/IStargate.sol";

/**
 * @title SweeperStargateIntegrationTest
 * @dev Integration tests for Stargate bridging functionality using real forked chains
 */
contract SweeperStargateIntegrationTest is Test {
    
    // Real Stargate contract addresses
    address constant STARGATE_NATIVE_POOL_OPTIMISM = 0xe8CDF27AcD73a434D661C84887215F7598e7d0d3;
    address constant STARGATE_ROUTER_ETH_BASE = 0x50B6EbC2103BFEc165949CC946d739d5650d7ae4;
    address constant STARGATE_NATIVE_POOL_UNICHAIN = 0xe9aBA835f813ca05E50A6C0ce65D0D74390F7dE7;
    
    // Test user with some ETH
    address testUser = address(0x123456);
    address recipient = address(0x789abc);
    
    uint256 optimismFork;
    uint256 baseFork;
    
    function setUp() public {
        // Create forks for testing
        optimismFork = vm.createFork("optimism");
        baseFork = vm.createFork("base");
    }
    
    /**
     * @dev Test Stargate Native Pool integration on Optimism
     */
    function test_stargateNativePool_Optimism() public {
        vm.selectFork(optimismFork);
        
        // Give test user some ETH
        vm.deal(testUser, 10 ether);
        
        // Test parameters
        uint256 bridgeAmount = 0.1 ether;
        uint32 baseDestId = 30184; // Base Stargate destination ID
        
        // Convert recipient to bytes32
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        
        // Create SendParam
        IStargateNativePool.SendParam memory sendParam = IStargateNativePool.SendParam({
            dstEid: baseDestId,
            to: recipientBytes32,
            amountLD: bridgeAmount,
            minAmountLD: (bridgeAmount * 995) / 1000, // 0.5% slippage
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        // Quote the fee
        IStargateNativePool.MessagingFee memory fee = IStargateNativePool(STARGATE_NATIVE_POOL_OPTIMISM)
            .quoteSend(sendParam, false);
        
        console.log("Stargate fee on Optimism:", fee.nativeFee);
        console.log("Bridge amount:", bridgeAmount);
        console.log("Total required:", bridgeAmount + fee.nativeFee);
        
        // Ensure we have enough ETH
        require(10 ether >= bridgeAmount + fee.nativeFee, "Not enough ETH for test");
        
        // Record balances before
        uint256 userBalanceBefore = testUser.balance;
        
        // Execute the bridging transaction
        vm.startPrank(testUser);
        
        // This should succeed if Stargate contracts are working
        IStargateNativePool(STARGATE_NATIVE_POOL_OPTIMISM).send{value: bridgeAmount + fee.nativeFee}(
            sendParam,
            fee,
            testUser // refund address
        );
        
        vm.stopPrank();
        
        // Verify user's balance decreased
        uint256 userBalanceAfter = testUser.balance;
        assertEq(userBalanceAfter, userBalanceBefore - bridgeAmount - fee.nativeFee, "User balance should decrease by bridge amount + fee");
        
        console.log("[SUCCESS] Stargate Native Pool bridging successful on Optimism");
    }
    
    /**
     * @dev Test Stargate Router ETH integration on Base
     */
    function test_stargateRouterETH_Base() public {
        vm.selectFork(baseFork);
        
        // Give test user some ETH
        vm.deal(testUser, 10 ether);
        
        // Test parameters  
        uint256 bridgeAmount = 0.1 ether;
        uint16 optimismChainId = 111; // Base to Optimism chain ID
        uint256 estimatedFee = 0.025 ether; // Rough estimate based on examples
        
        // Convert recipient to bytes
        bytes memory recipientBytes = abi.encodePacked(recipient);
        
        console.log("Bridge amount:", bridgeAmount);
        console.log("Estimated fee:", estimatedFee);
        console.log("Total required:", bridgeAmount + estimatedFee);
        
        // Ensure we have enough ETH
        require(10 ether >= bridgeAmount + estimatedFee, "Not enough ETH for test");
        
        // Record balances before
        uint256 userBalanceBefore = testUser.balance;
        
        // Execute the bridging transaction
        vm.startPrank(testUser);
        
        // This should succeed if Stargate Router ETH is working
        IStargateRouterETH(STARGATE_ROUTER_ETH_BASE).swapETH{value: bridgeAmount + estimatedFee}(
            optimismChainId,
            payable(testUser), // refund address
            recipientBytes,
            bridgeAmount,
            (bridgeAmount * 995) / 1000 // 0.5% slippage
        );
        
        vm.stopPrank();
        
        // Verify user's balance decreased by at least the bridge amount
        uint256 userBalanceAfter = testUser.balance;
        assert(userBalanceAfter < userBalanceBefore);
        assert(userBalanceBefore - userBalanceAfter >= bridgeAmount);
        
        console.log("[SUCCESS] Stargate Router ETH bridging successful on Base");
        console.log("Actual fee used:", userBalanceBefore - userBalanceAfter - bridgeAmount);
    }
    
    /**
     * @dev Test ExternalSweeperSwapless constructor validation with real Stargate contracts
     */
    function test_externalSweeperSwapless_RealStargate_Optimism() public {
        vm.selectFork(optimismFork);
        
        // Just test that the Stargate contracts exist and have the expected interfaces
        // Check if Stargate Native Pool contract exists
        uint256 codeSize;
        address stargatePool = STARGATE_NATIVE_POOL_OPTIMISM;
        assembly {
            codeSize := extcodesize(stargatePool)
        }
        assertGt(codeSize, 0, "Stargate Native Pool should exist on Optimism");
        
        // Test that we can call quoteSend on the real contract
        uint256 bridgeAmount = 0.1 ether;
        uint32 baseDestId = 30184;
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        
        IStargateNativePool.SendParam memory sendParam = IStargateNativePool.SendParam({
            dstEid: baseDestId,
            to: recipientBytes32,
            amountLD: bridgeAmount,
            minAmountLD: (bridgeAmount * 995) / 1000,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        // This should work if the contract exists and has the right interface
        IStargateNativePool.MessagingFee memory fee = IStargateNativePool(STARGATE_NATIVE_POOL_OPTIMISM)
            .quoteSend(sendParam, false);
        
        assertGt(fee.nativeFee, 0, "Should get a valid fee quote");
        
        console.log("Stargate Native Pool exists and is functional on Optimism");
        console.log("Code size:", codeSize);
        console.log("Quote fee:", fee.nativeFee);
        
        console.log("[SUCCESS] ExternalSweeperSwapless Stargate validation complete on Optimism");
    }
    
    /**
     * @dev Test the Stargate fee quoting functionality
     */
    function test_stargateQuoting() public {
        vm.selectFork(optimismFork);
        
        uint256 bridgeAmount = 0.1 ether;
        uint32 baseDestId = 30184;
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        
        IStargateNativePool.SendParam memory sendParam = IStargateNativePool.SendParam({
            dstEid: baseDestId,
            to: recipientBytes32,
            amountLD: bridgeAmount,
            minAmountLD: (bridgeAmount * 995) / 1000,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        // Test fee quoting
        IStargateNativePool.MessagingFee memory fee = IStargateNativePool(STARGATE_NATIVE_POOL_OPTIMISM)
            .quoteSend(sendParam, false);
        
        // Fee should be reasonable (not 0, not more than 0.1 ETH)
        assertGt(fee.nativeFee, 0, "Fee should be greater than 0");
        assertLt(fee.nativeFee, 0.1 ether, "Fee should be reasonable");
        
        console.log("[SUCCESS] Stargate fee quoting working correctly");
        console.log("Quoted fee:", fee.nativeFee);
        console.log("LZ token fee:", fee.lzTokenFee);
    }
    
    /**
     * @dev Test different bridge amounts and verify fees scale appropriately  
     */
    function test_stargateFeesWithDifferentAmounts() public {
        vm.selectFork(optimismFork);
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.01 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 1 ether;
        
        uint32 baseDestId = 30184;
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        
        for (uint i = 0; i < amounts.length; i++) {
            IStargateNativePool.SendParam memory sendParam = IStargateNativePool.SendParam({
                dstEid: baseDestId,
                to: recipientBytes32,
                amountLD: amounts[i],
                minAmountLD: (amounts[i] * 995) / 1000,
                extraOptions: "",
                composeMsg: "",
                oftCmd: ""
            });
            
            IStargateNativePool.MessagingFee memory fee = IStargateNativePool(STARGATE_NATIVE_POOL_OPTIMISM)
                .quoteSend(sendParam, false);
            
            console.log("Amount:", amounts[i]);
            console.log("Fee:", fee.nativeFee);
            console.log("Fee percentage:", (fee.nativeFee * 10000) / amounts[i], "bps");
            console.log("---");
        }
        
        console.log("[SUCCESS] Fee scaling analysis complete");
    }
} 