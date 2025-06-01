pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title OriginSweeper
 * @author Tranquil-Flow
 * @dev A contract that sells all tokens on the origin chain, and coordinates selling tokens on external chains.
        All tokens are consolidated into ETH on this contract, and then transferred to one address.
 */
contract OriginSweeper is OApp, OAppOptionsType3 {
    using OptionsBuilder for bytes;

    constructor(
        address _endpoint, 
        address _delegate,
        address _finalReceiverAddress,
        uint _totalChainsSelling
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        finalReceiverAddress = _finalReceiverAddress;
        totalChainsSelling = _totalChainsSelling;
    }

    // Counter that tracks the amount of chains that we expect to receive ETH from
    uint public totalChainsSelling;

    // Counter that tracks the amount of chains that have sent ETH to this contract
    uint public totalChainsSentETH;

    // Address to send ETH to if privacy is not enabled
    address public finalReceiverAddress;

    // Privacy flag for the current operation
    bool public privacy;

    // Struct to define swap information for a token
    struct SwapInfo {
        address dexContract;       // The DEX contract to interact with
        address token;             // The token to be swapped
        uint256 amount;            // The amount of tokens to swap
        bytes dexCalldata;         // Encoded calldata for the DEX interaction
    }

    // Message types for cross-chain communication
    enum MessageType { SWAP_REQUEST, ETH_BRIDGED }

    // Events
    event TokenSwapsInitiated(uint32[] chainIds, uint totalChains);
    event ETHReceived(uint chainsSentSoFar, uint totalExpected);
    event PrivacyShieldingInitiated(uint totalETH);

    /**
     * @notice Execute token swaps across multiple chains
     * @param chainIds Array of chain IDs where tokens will be sold
     * @param swapInfoArrays Array of arrays containing swap information for each chain
     * @param _privacy Flag indicating whether to shield ETH after all swaps are complete
     */
    function executeTokenSwaps(
        uint32[] calldata chainIds,
        SwapInfo[][] calldata swapInfoArrays,
        bool _privacy
    ) external payable {
        require(chainIds.length == swapInfoArrays.length, "Chain IDs and swap info arrays length mismatch");
        require(chainIds.length > 0, "No chains specified for swaps");
        
        totalChainsSelling = chainIds.length;
        totalChainsSentETH = 0;
        privacy = _privacy;
        
        emit TokenSwapsInitiated(chainIds, totalChainsSelling);

        // 1. Send bridging messages to other chains to sell tokens on that chain
        for (uint i = 0; i < chainIds.length; i++) {
            // Skip the current chain
            if (chainIds[i] != block.chainid) {
                // Verify the swapInfos array for this chain is not empty
                require(swapInfoArrays[i].length > 0, "Empty swap info array for chain");
                
                // Encode the SwapInfo array for this chain
                bytes memory payload = abi.encode(MessageType.SWAP_REQUEST, abi.encode(swapInfoArrays[i]));
                
                // Build options with default settings
                bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
                
                // Send message to the chain
                _lzSend(
                    chainIds[i], 
                    payload, 
                    options, 
                    MessagingFee(address(this).balance, 0), // TODO: change to be calculated and taken from user
                    payable(msg.sender)
                );
            }
        }

        // 2. Sell tokens on this chain if specified
        SwapInfo[] memory localSwaps;
        bool localChainIncluded = false;
        
        for (uint i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == block.chainid) {
                localSwaps = swapInfoArrays[i];
                localChainIncluded = true;
                break;
            }
        }

        if (localChainIncluded && localSwaps.length > 0) {
            uint256 ethBalanceBefore = address(this).balance;
            
            for (uint i = 0; i < localSwaps.length; i++) {
                // Verify token address and amount
                require(localSwaps[i].token != address(0), "Invalid token address");
                require(localSwaps[i].amount > 0, "Token amount must be greater than 0");
                
                swapToken(
                    localSwaps[i].dexContract, 
                    localSwaps[i].token, 
                    localSwaps[i].amount,
                    localSwaps[i].dexCalldata
                );
            }
            
            // Count local chain as completed
            totalChainsSentETH++;
            
            emit ETHReceived(totalChainsSentETH, totalChainsSelling);
            
            // Check if all chains have completed (rare case where only local chain had tokens)
            if (totalChainsSentETH == totalChainsSelling && privacy) {
                shieldETH();
            }
        }
    }

    /// @notice Receives ETH from a selling contract on a different chain
    function receiveETH() public {
        totalChainsSentETH++;
        
        emit ETHReceived(totalChainsSentETH, totalChainsSelling);

        if (totalChainsSentETH == totalChainsSelling) {
            // 3. If all chains have sent ETH, shield the ETH if privacy is enabled
            if (privacy) {
                shieldETH();
            } else {
                // If privacy is not enabled, send ETH to a specified address
                payable(finalReceiverAddress).transfer(address(this).balance);
            }
        }
    }

    /// @notice Swaps a specified amount of a token for the other token in the pair at a specified dex contract
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
        
        // 4. Calculate the amount of ETH received
        amountReceived = address(this).balance - ethBalanceBefore;
        require(amountReceived > 0, "No ETH received from swap");
        
        return amountReceived;
    }

    /// @notice Shield received ETH with Railgun TODO
    function shieldETH() internal {
        // Implementation will be added later
        uint256 totalETH = address(this).balance;
        emit PrivacyShieldingInitiated(totalETH);
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
        // Decode the message type and payload
        (MessageType messageType, bytes memory messageData) = abi.decode(payload, (MessageType, bytes));
        
        if (messageType == MessageType.ETH_BRIDGED) {
            // Handle ETH bridged notification from another chain
            receiveETH();
        }
    }

    /**
     * @dev Helper function to get default LayerZero options
     */
    function getDefaultOptions() public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    }
}