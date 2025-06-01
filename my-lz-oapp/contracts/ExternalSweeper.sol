pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ExternalSweeper
 * @dev Contract that sweeps all tokens of a user on this chain, and bridges ETH back to the origin chain contract.
 */
contract ExternalSweeper is OApp, OAppOptionsType3 {
    using OptionsBuilder for bytes;

    address public mainContract;
    uint32 public mainChainId;

    // Events
    event SwapRequestReceived(uint256 numSwaps);
    event TokenSwapped(address token, uint256 amount, uint256 ethReceived);
    event ETHBridgeInitiated(uint256 amount);
    event MessageSentToMain();

    constructor(
        address _endpoint,
        address _delegate,
        address _mainContract,
        uint32 _mainChainId
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        require(_mainContract != address(0), "Invalid main contract address");
        require(_mainChainId != 0, "Invalid main chain ID");
        
        mainContract = _mainContract;
        mainChainId = _mainChainId;
    }

    // Define the swap info struct matching OriginSweeper
    struct SwapInfo {
        address dexContract;       // The DEX contract to interact with
        address token;             // The token to be swapped
        uint256 amount;            // The amount of tokens to swap
        bytes dexCalldata;         // Encoded calldata for the DEX interaction
    }

    // Message types for cross-chain communication
    enum MessageType { SWAP_REQUEST, ETH_BRIDGED }

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
        
        // Decode the message type and payload
        (MessageType messageType, bytes memory messageData) = abi.decode(payload, (MessageType, bytes));
        
        if (messageType == MessageType.SWAP_REQUEST) {
            // Properly decode the SwapInfo array
            SwapInfo[] memory swapInfos = abi.decode(abi.decode(messageData, (bytes)), (SwapInfo[]));
            
            // Verify we have swaps to perform
            require(swapInfos.length > 0, "No swap information provided");
            
            emit SwapRequestReceived(swapInfos.length);
            
            uint256 ethBalanceBefore = address(this).balance;
            
            // Perform token swaps
            for (uint i = 0; i < swapInfos.length; i++) {
                SwapInfo memory info = swapInfos[i];
                
                // Validate swap info
                require(info.dexContract != address(0), "Invalid DEX contract");
                require(info.token != address(0), "Invalid token address");
                require(info.amount > 0, "Amount must be greater than 0");
                
                uint256 ethReceived = swapToken(
                    info.dexContract,
                    info.token,
                    info.amount,
                    info.dexCalldata
                );
                
                emit TokenSwapped(info.token, info.amount, ethReceived);
            }
            
            uint256 totalEthReceived = address(this).balance - ethBalanceBefore;
            
            // Bridge ETH back to the main contract
            bridgeETH(totalEthReceived);
            
            // Send message back to main contract that ETH is on the way
            sendETHBridgedMessage();
        }
    }

    /// @notice Swaps a specified amount of a token for ETH at a specified dex contract
    /// @dev Uses a generalized approach to interact with any DEX contract using custom calldata
    /// @param dexContract The address of the DEX contract
    /// @param token The address of the token to swap
    /// @param amount The amount of tokens to swap
    /// @param dexCalldata The encoded calldata for the DEX interaction
    /// @return amountReceived The amount of ETH received from the swap
    function swapToken(
        address dexContract,
        address token,
        uint256 amount,
        bytes memory dexCalldata
    ) internal returns (uint256 amountReceived) {
        // 1. Record ETH balance before swap to calculate received amount
        uint256 ethBalanceBefore = address(this).balance;
        
        // 2. Approve the DEX contract to spend tokens
        IERC20(token).approve(dexContract, amount);
        
        // 3. Call the DEX contract with the provided calldata
        (bool success, bytes memory returnData) = dexContract.call(dexCalldata);
        
        // Check if the call was successful
        if (!success) {
            // Extract error message if available
            if (returnData.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert("DEX swap failed without message");
            }
        }
        
        // 4. Unwrap the WETH to ETH
        

        // 5. Calculate the amount of ETH received
        amountReceived = address(this).balance - ethBalanceBefore;
        require(amountReceived > 0, "No ETH received from swap");
        
        return amountReceived;
    }

    /// @notice Bridge ETH received from selling tokens to the main contract
    /// @param amount The amount of ETH to bridge
    function bridgeETH(uint256 amount) internal {
        // Implementation will be added later
        // This would call a bridging protocol to send ETH back to OriginSweeper

        emit ETHBridgeInitiated(amount);
    }

    /// @notice Send a message back to main contract indicating ETH has been bridged
    function sendETHBridgedMessage() internal {
        bytes memory payload = abi.encode(MessageType.ETH_BRIDGED, "");
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        
        // Send message back to main contract on OriginSweeper
        _lzSend(
            mainChainId,
            payload,
            options,
            MessagingFee(address(this).balance, 0), // TODO: change to be calculated and taken from user
            payable(address(this))
        );
        
        emit MessageSentToMain();
    }

    /**
     * @dev Helper function to get default LayerZero options
     */
    function getDefaultOptions() public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    }

    /**
     * @dev Test function to execute swapToken externally (for testing only)
     * @param dexContract The address of the DEX contract
     * @param token The address of the token to swap
     * @param amount The amount of tokens to swap
     * @param dexCalldata The encoded calldata for the DEX interaction
     * @return amountReceived The amount of ETH received from the swap
     */
    function testSwapToken(
        address dexContract,
        address token,
        uint256 amount,
        bytes memory dexCalldata
    ) external onlyOwner returns (uint256 amountReceived) {
        return swapToken(dexContract, token, amount, dexCalldata);
    }
}
