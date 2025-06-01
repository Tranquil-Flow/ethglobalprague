pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title ExternalSweeperSimple
 * @dev Simple contract that receives messages from OriginSweeper and sends responses back.
 * This version focuses only on LayerZero messaging without any DEX swap logic.
 */
contract ExternalSweeperSimple is OApp {
    using OptionsBuilder for bytes;

    uint32 public mainChainId;
    string public data;

    // Events
    event MessageReceived(uint32 srcEid, string message);
    event MessageSentBack(uint32 dstEid, string response);

    constructor(
        address _endpoint,
        address _delegate,
        uint32 _mainChainId
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        require(_mainChainId != 0, "Invalid main chain ID");
        mainChainId = _mainChainId;
        data = "Initial state";
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
        // Verify the sender is from the main chain
        require(_origin.srcEid == mainChainId, "Message not from main chain");
        
        // Decode the incoming message
        string memory message = abi.decode(payload, (string));
        
        // Update local state
        data = message;
        
        emit MessageReceived(_origin.srcEid, message);
        
        // Send response back to origin
        sendResponseBack(string.concat("Processed: ", message));
    }

    /**
     * @notice Send a response message back to the main chain
     * @param response The response message to send
     */
    function sendResponseBack(string memory response) internal {
        bytes memory payload = abi.encode(response);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        
        // Calculate the messaging fee
        MessagingFee memory fee = _quote(mainChainId, payload, options, false);
        
        // Send message back to main contract
        _lzSend(
            mainChainId,
            payload,
            options,
            fee,
            payable(address(this))
        );
        
        emit MessageSentBack(mainChainId, response);
    }

    /**
     * @notice Public function to send a test message (for testing purposes)
     * @param message The message to send back to origin
     */
    function sendTestMessage(string memory message) external payable onlyOwner {
        bytes memory payload = abi.encode(message);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        
        // Send message to main contract
        _lzSend(
            mainChainId,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
        
        emit MessageSentBack(mainChainId, message);
    }

    /**
     * @notice Get quote for sending a message
     * @param message The message to quote
     * @return fee The messaging fee required
     */
    function quote(string memory message) external view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(message);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        return _quote(mainChainId, payload, options, false);
    }

    /**
     * @dev Helper function to get default LayerZero options
     */
    function getDefaultOptions() public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    }

    // Function to receive ETH
    receive() external payable {}
}
