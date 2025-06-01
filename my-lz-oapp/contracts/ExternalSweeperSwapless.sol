pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MessagingParams } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IStargateNativePool, IStargateRouterETH } from "./interfaces/IStargate.sol";

/**
 * @title ExternalSweeperSwapless
 * @dev Contract that simulates sweeping tokens on external chains without actual DEX swaps,
 *      and uses Stargate to bridge ETH back to the origin chain contract.
 */
contract ExternalSweeperSwapless is OApp, OAppOptionsType3 {
    using OptionsBuilder for bytes;

    address public mainContract;
    uint32 public mainChainId;
    
    // Stargate contract addresses
    address public stargateNativePool;
    address public stargateRouterETH;
    
    // Chain-specific Stargate destination IDs
    mapping(uint32 => uint32) public stargateDestIds;
    
    // Current chain ID for determining which Stargate method to use
    uint256 public currentChainId;

    // Events
    event SwapRequestReceived(uint256 numSwaps);
    event TokenSwapped(address token, uint256 amount, uint256 ethReceived);
    event ETHBridgeInitiated(uint256 amount, uint32 destinationChain);
    event MessageSentToMain();
    event SimulatedSwap(address token, uint256 amount, uint256 ethReceived);
    event StargateETHBridged(uint256 amount, uint32 dstEid, address recipient);

    constructor(
        address _endpoint,
        address _delegate,
        address _mainContract,
        uint32 _mainChainId,
        address _stargateNativePool,
        address _stargateRouterETH
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        require(_mainContract != address(0), "Invalid main contract address");
        require(_mainChainId != 0, "Invalid main chain ID");
        
        mainContract = _mainContract;
        mainChainId = _mainChainId;
        stargateNativePool = _stargateNativePool;
        stargateRouterETH = _stargateRouterETH;
        currentChainId = block.chainid;
        
        // Set up Stargate destination IDs
        stargateDestIds[10] = 30111;  // Optimism
        stargateDestIds[8453] = 30184; // Base  
        stargateDestIds[1301] = 30320; // Unichain
    }

    // Define the swap info struct matching OriginSweeper (simplified for testing)
    struct SwapInfo {
        address dexContract;       // The DEX contract (not used in swapless version)
        address token;             // The token to be "swapped"
        uint256 amount;            // The amount of tokens to "swap"
        bytes dexCalldata;         // Encoded calldata (not used in swapless version)
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
            // Decode the SwapInfo array
            SwapInfo[] memory swapInfos = abi.decode(messageData, (SwapInfo[]));
            
            // Verify we have swaps to perform
            require(swapInfos.length > 0, "No swap information provided");
            
            emit SwapRequestReceived(swapInfos.length);
            
            uint256 totalEthReceived = 0;
            
            // Perform simulated token swaps
            for (uint i = 0; i < swapInfos.length; i++) {
                SwapInfo memory info = swapInfos[i];
                
                // Validate swap info
                require(info.token != address(0), "Invalid token address");
                require(info.amount > 0, "Amount must be greater than 0");
                
                uint256 ethReceived = simulateSwapToken(
                    info.token,
                    info.amount
                );
                
                totalEthReceived += ethReceived;
                emit TokenSwapped(info.token, info.amount, ethReceived);
            }
            
            // Simulate bridging ETH back to the main contract
            bridgeETHToMainChain(totalEthReceived);
            
            // Send message back to main contract that ETH is on the way
            sendETHBridgedMessage();
        }
    }

    /// @notice Returns simulated ETH from token swap (replaces actual swapping)
    /// @dev Instead of actual DEX interaction, this simulates converting tokens to ETH
    /// @param token The address of the token (not used in swapless version)
    /// @param amount The amount of tokens to "swap"
    /// @return amountReceived The simulated amount of ETH received from the swap
    function simulateSwapToken(
        address token,
        uint256 amount
    ) internal returns (uint256 amountReceived) {
        // Simulate a simple 1:1000 conversion rate (1000 tokens = 1 ETH)
        // This is just for testing purposes
        amountReceived = amount * 1e15; // Convert to wei (1000 tokens * 1e18 / 1000 = amount * 1e15)
        
        emit SimulatedSwap(token, amount, amountReceived);
        
        return amountReceived;
    }

    /// @notice Simulate bridging ETH to the main contract (for testing purposes)
    /// @param amount The amount of ETH to "bridge"
    function simulateBridgeETH(uint256 amount) internal {
        // In a real implementation, this would call a bridging protocol
        // For testing, we just emit an event to simulate the action
        emit ETHBridgeInitiated(amount, uint32(currentChainId));
    }

    /// @notice Send a message back to main contract indicating ETH has been bridged
    function sendETHBridgedMessage() internal {
        bytes memory payload = abi.encode(MessageType.ETH_BRIDGED, "");
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2000000, 0);
        
        // Quote the actual fee needed
        MessagingFee memory fee = _quote(mainChainId, payload, options, false);
        
        // Check that we have enough ETH to pay the fee
        require(address(this).balance >= fee.nativeFee, "Insufficient ETH for messaging fee");
        
        // Send message back using internal call with value
        this.sendMessageWithValue{value: fee.nativeFee}(payload, options, fee);
    }

    /// @notice External function to send message with value (called from internal)
    function sendMessageWithValue(
        bytes calldata payload,
        bytes calldata options,
        MessagingFee calldata fee
    ) external payable {
        require(msg.sender == address(this), "Only self can call");
        
        _lzSend(
            mainChainId,
            payload,
            options,
            fee,
            payable(address(this))
        );
        
        emit MessageSentToMain();
    }

    /**
     * @dev Helper function to get default LayerZero options
     */
    function getDefaultOptions() public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(2000000, 0);
    }

    /**
     * @dev Test function to simulate swapToken externally (for testing only)
     * @param token The address of the token to "swap"
     * @param amount The amount of tokens to "swap"
     * @return amountReceived The simulated amount of ETH received
     */
    function testSimulateSwapToken(
        address token,
        uint256 amount
    ) external onlyOwner returns (uint256 amountReceived) {
        return simulateSwapToken(token, amount);
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
     * @dev Helper function to convert address to bytes32 for LayerZero
     */
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    /**
     * @dev Override _payNative to fix NotEnoughNative error
     * The original implementation requires exact equality, but we only need sufficient funds
     */
    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    /// @notice Bridge ETH to the main contract using Stargate
    /// @param amount The amount of ETH to bridge
    function bridgeETHToMainChain(uint256 amount) internal {
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient ETH balance");
        
        // If in test mode (no Stargate contracts set), just simulate
        if (stargateNativePool == address(0) && stargateRouterETH == address(0)) {
            emit ETHBridgeInitiated(amount, mainChainId);
            return;
        }
        
        uint32 mainStargateId = stargateDestIds[mainChainId];
        require(mainStargateId != 0, "Unsupported destination chain");
        
        if (currentChainId == 8453) {
            // Base chain uses RouterETH swapETH function
            _bridgeWithRouterETH(amount, mainStargateId);
        } else {
            // Other chains use Native Pool send function
            _bridgeWithNativePool(amount, mainStargateId);
        }
        
        emit ETHBridgeInitiated(amount, mainChainId);
    }
    
    /// @notice Bridge ETH using Stargate Native Pool (for Optimism, Unichain, etc.)
    /// @param amount The amount of ETH to bridge
    /// @param dstEid The destination Stargate endpoint ID
    function _bridgeWithNativePool(uint256 amount, uint32 dstEid) internal {
        require(stargateNativePool != address(0), "Stargate Native Pool not set");
        
        // Convert main contract address to bytes32
        bytes32 toAddress = bytes32(uint256(uint160(mainContract)));
        
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
        
        emit StargateETHBridged(amount, dstEid, mainContract);
    }
    
    /// @notice Bridge ETH using Stargate Router ETH (for Base chain)
    /// @param amount The amount of ETH to bridge
    /// @param dstChainId The destination Stargate chain ID
    function _bridgeWithRouterETH(uint256 amount, uint32 dstChainId) internal {
        require(stargateRouterETH != address(0), "Stargate Router ETH not set");
        
        // Convert to uint16 for Base RouterETH (Base uses different chain ID format)
        uint16 baseChainId = 111; // Base to Optimism uses chain ID 111
        if (mainChainId == 8453) {
            baseChainId = 184; // Base to Base (shouldn't happen)
        }
        
        // Convert main contract address to bytes
        bytes memory toAddress = abi.encodePacked(mainContract);
        
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
        
        emit StargateETHBridged(amount, dstChainId, mainContract);
    }
}
