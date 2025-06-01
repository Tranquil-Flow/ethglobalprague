// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.15;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import "../../contracts/OriginSweeperSwapless.sol";
import "../../contracts/ExternalSweeperSwapless.sol";

/**
 * @title SweeperSwaplessTest
 * @dev This contract is a test suite for OriginSweeperSwapless and ExternalSweeperSwapless,
 *      which demonstrates cross-chain token sweeping without actual DEX swaps using LayerZero.
 */
contract SweeperSwaplessTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1; // Optimism (10)
    uint32 private bEid = 2; // Base (8453)

    OriginSweeperSwapless private originSweeper;
    ExternalSweeperSwapless private externalSweeper;

    address private finalReceiver = address(0x123);
    address private mockToken = address(0x456);

    /**
     * @dev Sets up the testing environment.
     * This includes setting up endpoints and deploying sweeper contracts on different chains.
     */
    function setUp() public virtual override {
        super.setUp();

        // Set up two endpoints to simulate two different chains (like SweeperSimpleTest)
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // We can't use setupOApps because our contracts have custom constructor parameters
        // Deploy OriginSweeperSwapless on endpoint A
        originSweeper = new OriginSweeperSwapless(
            address(endpoints[aEid]),
            address(this),
            finalReceiver,
            1, // totalChainsSelling
            address(0), // stargateNativePool (not used in test)
            address(0)  // stargateRouterETH (not used in test)
        );

        // Deploy ExternalSweeperSwapless on endpoint B
        externalSweeper = new ExternalSweeperSwapless(
            address(endpoints[bEid]),
            address(this),
            address(originSweeper), // mainContract
            aEid, // mainChainId
            address(0), // stargateNativePool (not used in test)
            address(0)  // stargateRouterETH (not used in test)
        );

        // Set up peer connections using the LayerZero test helper
        address[] memory oapps = new address[](2);
        oapps[0] = address(originSweeper);
        oapps[1] = address(externalSweeper);
        this.wireOApps(oapps);
    }

    /**
     * @dev Tests the cross-chain sweeping functionality.
     * Simulates token swapping by depositing ETH to contracts and tests the messaging flow.
     */
    function test_crossChainSweeping() public {
        // Prepare swap info for external chain (chain B)
        OriginSweeperSwapless.SwapInfo[] memory externalSwaps = new OriginSweeperSwapless.SwapInfo[](1);
        externalSwaps[0] = OriginSweeperSwapless.SwapInfo({
            dexContract: address(0), // Not used in swapless version
            token: mockToken,
            amount: 1000,
            dexCalldata: "" // Not used in swapless version
        });

        // Only include external chains in chainIds (not the origin chain)
        uint32[] memory chainIds = new uint32[](1);
        chainIds[0] = bEid; // External chain only

        OriginSweeperSwapless.SwapInfo[][] memory swapInfoArrays = new OriginSweeperSwapless.SwapInfo[][](1);
        swapInfoArrays[0] = externalSwaps; // Swaps on external chain

        // Deposit ETH to external sweeper to simulate swap proceeds
        uint256 simulatedETHFromSwaps = 5 ether; // Increased amount for fees
        vm.deal(address(externalSweeper), simulatedETHFromSwaps);

        // Verify initial state
        assertEq(originSweeper.totalChainsSentETH(), 0, "Initial chains sent should be 0");
        assertEq(address(originSweeper).balance, 0, "Origin sweeper should start with 0 ETH");

        // Give the origin sweeper some ETH for gas fees (after initial verification)
        vm.deal(address(originSweeper), 2 ether);

        // Execute token swaps with sufficient ETH for LayerZero fees
        uint256 totalFeeValue = 0.1 ether;
        originSweeper.executeTokenSwaps{value: totalFeeValue}(chainIds, swapInfoArrays, false);

        // Verify that the external chain hasn't received message yet
        assertEq(originSweeper.totalChainsSentETH(), 0, "External chain shouldn't be counted yet");

        // Manually deliver the packet to the external sweeper
        verifyPackets(bEid, addressToBytes32(address(externalSweeper)));

        // After packet delivery, external sweeper should send ETH bridged message back
        // Manually deliver the return packet to origin sweeper
        verifyPackets(aEid, addressToBytes32(address(originSweeper)));

        // Verify final state
        assertEq(originSweeper.totalChainsSentETH(), 1, "One external chain should have completed");
        
        // Since privacy is false, ETH should be sent to finalReceiver
        // Note: In this test the ETH stays on the external contract since we're not actually bridging
        // but the message flow and state updates should work correctly
    }

    /**
     * @dev Tests the basic message passing from origin to external chain.
     */
    function test_messageToExternalChain() public {
        // Prepare minimal swap info
        OriginSweeperSwapless.SwapInfo[] memory swaps = new OriginSweeperSwapless.SwapInfo[](1);
        swaps[0] = OriginSweeperSwapless.SwapInfo({
            dexContract: address(0),
            token: mockToken,
            amount: 100,
            dexCalldata: ""
        });

        uint32[] memory chainIds = new uint32[](1);
        chainIds[0] = bEid;

        OriginSweeperSwapless.SwapInfo[][] memory swapInfoArrays = new OriginSweeperSwapless.SwapInfo[][](1);
        swapInfoArrays[0] = swaps;

        // Deposit ETH to external sweeper
        vm.deal(address(externalSweeper), 0.5 ether);

        // Give origin sweeper ETH for gas fees
        vm.deal(address(originSweeper), 1 ether);

        // Send message with ETH for fees
        originSweeper.executeTokenSwaps{value: 0.1 ether}(chainIds, swapInfoArrays, false);

        // Deliver the packet
        verifyPackets(bEid, addressToBytes32(address(externalSweeper)));

        // Verify the external sweeper received and processed the message
        // The external sweeper should now send a message back
        verifyPackets(aEid, addressToBytes32(address(originSweeper)));

        // Check that the operation completed
        assertEq(originSweeper.totalChainsSentETH(), 1, "External chain should have completed");
    }

    /**
     * @dev Tests depositing ETH for simulation purposes.
     */
    function test_depositETHForTesting() public {
        uint256 depositAmount = 2 ether;
        
        // Test depositing to origin sweeper
        originSweeper.depositETHForTesting{value: depositAmount}();
        assertEq(address(originSweeper).balance, depositAmount, "Origin sweeper should receive ETH");

        // Test depositing to external sweeper
        externalSweeper.depositETHForTesting{value: depositAmount}();
        assertEq(address(externalSweeper).balance, depositAmount, "External sweeper should receive ETH");
    }
} 