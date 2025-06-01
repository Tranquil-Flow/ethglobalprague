// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.15;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import "../../contracts/OriginSweeperSimple.sol";

/**
 * @title SweeperSimpleTest
 * @dev This contract is a test suite for OriginSweeperSimple, which demonstrates simple message passing using LayerZero.
 */
contract SweeperSimpleTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    OriginSweeperSimple private aOriginSweeper;
    OriginSweeperSimple private bOriginSweeper;

    /**
     * @dev Sets up the testing environment.
     * This includes setting up endpoints and deploying instances of OriginSweeperSimple on different chains.
     */
    function setUp() public virtual override {
        super.setUp();

        // Set up two endpoints to simulate two different chains
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy instances of OriginSweeperSimple on these chains
        address[] memory uas = setupOApps(type(OriginSweeperSimple).creationCode, 1, 2);
        aOriginSweeper = OriginSweeperSimple(payable(uas[0]));
        bOriginSweeper = OriginSweeperSimple(payable(uas[1]));
    }

    /**
     * @dev Tests the basic message passing functionality from Chain A to Chain B using OriginSweeperSimple.
     * It sends a message from aOriginSweeper to bOriginSweeper and checks if the message is received correctly.
     */
    function test_message() public {
        string memory messageBefore = "Initial state";
        string memory message = "test message";

        // Get quote for sending the message and send it
        MessagingFee memory fee = aOriginSweeper.quote(bEid, message);
        aOriginSweeper.sendMessage{value: fee.nativeFee}(bEid, message);

        // Ensure the message at the destination is not changed before delivery
        assertEq(bOriginSweeper.data(), messageBefore, "shouldn't change message until packet is delivered");

        // Manually deliver the packet to the destination contract
        verifyPackets(bEid, addressToBytes32(address(bOriginSweeper)));

        // Check if the message has been updated after packet delivery
        assertEq(bOriginSweeper.data(), message, "message storage failure");
    }
}