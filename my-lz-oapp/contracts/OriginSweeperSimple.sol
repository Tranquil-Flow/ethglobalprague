pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title OriginSweeperSimple
 * @author Tranquil-Flow
 * @dev Simple contract that sends messages to ExternalSweeper and receives responses.
 * This version focuses only on LayerZero messaging without any DEX swap logic.
 */
contract OriginSweeperSimple is OApp {
    using OptionsBuilder for bytes;

    string public data;
    uint256 public messagesSent;
    uint256 public messagesReceived;

    // Events
    event MessageSent(uint32 dstEid, string message);
    event ResponseReceived(uint32 srcEid, string response);

    constructor(
        address _endpoint, 
        address _delegate
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        data = "Initial state";
        messagesSent = 0;
        messagesReceived = 0;
    }

    /**
     * @notice Send a message to a destination chain
     * @param dstEid The destination endpoint ID
     * @param message The message to send
     */
    function sendMessage(uint32 dstEid, string memory message) external payable {
        bytes memory payload = abi.encode(message);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        
        // Send message to destination chain
        _lzSend(
            dstEid,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
        
        messagesSent++;
        emit MessageSent(dstEid, message);
    }

    /**
     * @dev Internal function override to handle incoming messages from another chain.
     * @param _origin A struct containing information about the message sender.
     * @param payload The encoded message payload being received.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        // Decode the incoming response
        string memory response = abi.decode(payload, (string));
        
        // Update local state
        data = response;
        messagesReceived++;
        
        emit ResponseReceived(_origin.srcEid, response);
    }

    /**
     * @notice Get quote for sending a message
     * @param dstEid The destination endpoint ID
     * @param message The message to quote
     * @return fee The messaging fee required
     */
    function quote(uint32 dstEid, string memory message) external view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(message);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        return _quote(dstEid, payload, options, false);
    }

    /**
     * @dev Helper function to get default LayerZero options
     */
    function getDefaultOptions() public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    }

    /**
     * @notice Reset message counters (for testing)
     */
    function resetCounters() external onlyOwner {
        messagesSent = 0;
        messagesReceived = 0;
        data = "Reset state";
    }

    // Function to receive ETH
    receive() external payable {}
}