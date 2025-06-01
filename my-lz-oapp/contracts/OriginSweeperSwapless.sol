pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStargateNativePool, IStargateRouterETH } from "./interfaces/IStargate.sol";

/**
 * @title OriginSweeperSwapless
 * @author Tranquil-Flow
 * @dev A contract that simulates selling tokens on the origin chain without actual DEX swaps, 
 *      coordinates messaging with external chains, and uses Stargate for final ETH transfers.
 */
contract OriginSweeperSwapless is OApp, OAppOptionsType3 {
    using OptionsBuilder for bytes;

    constructor(
        address _endpoint, 
        address _delegate,
        address _finalReceiverAddress,
        uint _totalChainsSelling,
        address _stargateNativePool,
        address _stargateRouterETH
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        finalReceiverAddress = _finalReceiverAddress;
        totalChainsSelling = _totalChainsSelling;
        stargateNativePool = _stargateNativePool;
        stargateRouterETH = _stargateRouterETH;
        currentChainId = block.chainid;
        
        // Set up Stargate destination IDs
        stargateDestIds[10] = 30111;  // Optimism
        stargateDestIds[8453] = 30184; // Base  
        stargateDestIds[1301] = 30320; // Unichain
    }

    // Counter that tracks the amount of chains that we expect to receive ETH from
    uint public totalChainsSelling;

    // Counter that tracks the amount of chains that have sent ETH to this contract
    uint public totalChainsSentETH;

    // Address to send ETH to if privacy is not enabled
    address public finalReceiverAddress;
    
    // Chain ID where final receiver is located (0 means same chain)
    uint32 public finalReceiverChainId;

    // Privacy flag for the current operation
    bool public privacy;
    
    // Stargate contract addresses
    address public stargateNativePool;
    address public stargateRouterETH;
    
    // Chain-specific Stargate destination IDs
    mapping(uint32 => uint32) public stargateDestIds;
    
    // Current chain ID for determining which Stargate method to use
    uint256 public currentChainId;

    // Struct to define swap information for a token (simplified for testing)
    struct SwapInfo {
        address dexContract;       // The DEX contract (not used in swapless version)
        address token;             // The token to be "swapped"
        uint256 amount;            // The amount of tokens to "swap"
        bytes dexCalldata;         // Encoded calldata (not used in swapless version)
    }

    // Message types for cross-chain communication
    enum MessageType { SWAP_REQUEST, ETH_BRIDGED }

    // Events
    event TokenSwapsInitiated(uint32[] chainIds, uint totalChains);
    event ETHReceived(uint chainsSentSoFar, uint totalExpected);
    event PrivacyShieldingInitiated(uint totalETH);
    event SimulatedSwap(address token, uint256 amount, uint256 ethReceived);
    event StargateETHSent(uint256 amount, uint32 dstChainId, address recipient);
    event LocalETHSent(uint256 amount, address recipient);

    /**
     * @notice Execute token swaps across multiple chains (swapless simulation version)
     * @param chainIds Array of chain IDs where tokens will be "sold"
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
                bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2000000, 0);
                
                // Send message to the chain
                _lzSend(
                    chainIds[i], 
                    payload, 
                    options, 
                    MessagingFee(msg.value / chainIds.length, 0), // Distribute ETH for fees
                    payable(msg.sender)
                );
            }
        }

        // 2. "Sell" tokens on this chain if specified (simulation)
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
                
                simulateSwapToken(
                    localSwaps[i].token, 
                    localSwaps[i].amount
                );
            }
            
            // Count local chain as completed
            totalChainsSentETH++;
            
            emit ETHReceived(totalChainsSentETH, totalChainsSelling);
            
            // Check if all chains have completed (rare case where only local chain had tokens)
            if (totalChainsSentETH == totalChainsSelling) {
                finalizeOperation();
            }
        }
    }

    /// @notice Receives ETH from a selling contract on a different chain
    function receiveETH() public {
        totalChainsSentETH++;
        
        emit ETHReceived(totalChainsSentETH, totalChainsSelling);

        if (totalChainsSentETH == totalChainsSelling) {
            finalizeOperation();
        }
    }

    /// @notice Finalize the operation based on privacy setting and recipient location
    function finalizeOperation() internal {
        if (privacy) {
            shieldETH();
        } else {
            // Send ETH to the specified address (local or cross-chain)
            uint256 balance = address(this).balance;
            if (balance > 0) {
                if (finalReceiverChainId == 0 || finalReceiverChainId == currentChainId) {
                    // Send locally
                    payable(finalReceiverAddress).transfer(balance);
                    emit LocalETHSent(balance, finalReceiverAddress);
                } else {
                    // Send cross-chain via Stargate
                    bridgeETHToReceiver(balance, finalReceiverChainId);
                }
            }
        }
    }

    /// @notice Returns available ETH on contract (replaces actual swapping)
    /// @dev Instead of actual DEX interaction, this just returns available ETH
    /// @param token The address of the token (not used in swapless version)
    /// @param amount The amount of tokens (not used in swapless version)
    /// @return amountReceived The amount of ETH available on the contract
    function simulateSwapToken(
        address token,
        uint256 amount
    ) internal returns (uint256 amountReceived) {
        // Return the available ETH balance on the contract
        amountReceived = address(this).balance;
        
        emit SimulatedSwap(token, amount, amountReceived);
        
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
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(2000000, 0);
    }

    /**
     * @dev Function to receive ETH for testing (simulates ETH from swaps)
     */
    receive() external payable {
        // Allow contract to receive ETH for testing
    }

    /**
     * @dev Test helper function to deposit ETH for simulation
     */
    function depositETHForTesting() external payable {
        // Allows depositing ETH to simulate swap proceeds
    }

    /**
     * @dev Override _payNative to fix NotEnoughNative error
     * The original implementation requires exact equality, but we only need sufficient funds
     */
    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    /// @notice Bridge ETH to the final receiver on a different chain using Stargate
    /// @param amount The amount of ETH to bridge
    /// @param dstChainId The destination chain ID where the receiver is located
    function bridgeETHToReceiver(uint256 amount, uint32 dstChainId) internal {
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient ETH balance");
        
        // If in test mode (no Stargate contracts set), just simulate
        if (stargateNativePool == address(0) && stargateRouterETH == address(0)) {
            emit StargateETHSent(amount, dstChainId, finalReceiverAddress);
            return;
        }
        
        uint32 stargateDestId = stargateDestIds[dstChainId];
        require(stargateDestId != 0, "Unsupported destination chain");
        
        if (currentChainId == 8453) {
            // Base chain uses RouterETH swapETH function
            _bridgeWithRouterETH(amount, stargateDestId, dstChainId);
        } else {
            // Other chains use Native Pool send function
            _bridgeWithNativePool(amount, stargateDestId, dstChainId);
        }
        
        emit StargateETHSent(amount, dstChainId, finalReceiverAddress);
    }
    
    /// @notice Bridge ETH using Stargate Native Pool (for Optimism, Unichain, etc.)
    /// @param amount The amount of ETH to bridge
    /// @param dstEid The destination Stargate endpoint ID
    /// @param dstChainId The destination chain ID
    function _bridgeWithNativePool(uint256 amount, uint32 dstEid, uint32 dstChainId) internal {
        require(stargateNativePool != address(0), "Stargate Native Pool not set");
        
        // Convert final receiver address to bytes32
        bytes32 toAddress = bytes32(uint256(uint160(finalReceiverAddress)));
        
        // Create SendParam struct
        IStargateNativePool.SendParam memory sendParam = IStargateNativePool.SendParam({
            dstEid: dstEid,
            to: toAddress,
            amountLD: amount,
            minAmountLD: (amount * 995) / 1000, // 0.5% slippage tolerance
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        // Quote the fee
        IStargateNativePool.MessagingFee memory fee = IStargateNativePool(stargateNativePool)
            .quoteSend(sendParam, false);
        
        // Ensure we have enough ETH for amount + fee
        require(address(this).balance >= amount + fee.nativeFee, "Insufficient ETH for bridging");
        
        // Send via Stargate
        IStargateNativePool(stargateNativePool).send{value: amount + fee.nativeFee}(
            sendParam,
            fee,
            address(this) // refund address
        );
    }
    
    /// @notice Bridge ETH using Stargate Router ETH (for Base chain)
    /// @param amount The amount of ETH to bridge
    /// @param dstEid The destination Stargate endpoint ID (not used for RouterETH)
    /// @param dstChainId The destination chain ID
    function _bridgeWithRouterETH(uint256 amount, uint32 dstEid, uint32 dstChainId) internal {
        require(stargateRouterETH != address(0), "Stargate Router ETH not set");
        
        // Convert to uint16 for Base RouterETH (Base uses different chain ID format)
        uint16 baseChainId = 111; // Base to Optimism uses chain ID 111
        if (dstChainId == 8453) {
            baseChainId = 184; // Base to Base (shouldn't happen)
        }
        
        // Convert final receiver address to bytes
        bytes memory toAddress = abi.encodePacked(finalReceiverAddress);
        
        // Estimate fee (roughly 0.02 ETH based on examples)
        uint256 estimatedFee = 0.025 ether;
        require(address(this).balance >= amount + estimatedFee, "Insufficient ETH for bridging");
        
        // Bridge via Stargate Router ETH
        IStargateRouterETH(stargateRouterETH).swapETH{value: amount + estimatedFee}(
            baseChainId,
            payable(address(this)), // refund address
            toAddress,
            amount,
            (amount * 995) / 1000 // 0.5% slippage tolerance
        );
    }
    
    /// @notice Set the final receiver's chain ID
    /// @param chainId The chain ID where the final receiver is located (0 for same chain)
    function setFinalReceiverChainId(uint32 chainId) external onlyOwner {
        finalReceiverChainId = chainId;
    }
}