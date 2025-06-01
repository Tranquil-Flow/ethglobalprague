// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IStargateNativePool
 * @dev Interface for Stargate Native Pool contract
 */
interface IStargateNativePool {
    struct SendParam {
        uint32 dstEid;          // Destination endpoint ID
        bytes32 to;             // Recipient address as bytes32
        uint256 amountLD;       // Amount in local decimals
        uint256 minAmountLD;    // Minimum amount in local decimals
        bytes extraOptions;     // Extra options
        bytes composeMsg;       // Compose message
        bytes oftCmd;           // OFT command
    }

    struct MessagingFee {
        uint256 nativeFee;      // Native fee amount
        uint256 lzTokenFee;     // LayerZero token fee
    }

    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable;

    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);
}

/**
 * @title IStargateRouterETH
 * @dev Interface for Stargate Router ETH contract (used on Base)
 */
interface IStargateRouterETH {
    function swapETH(
        uint16 _dstChainId,                         // destination Stargate chainId
        address payable _refundAddress,             // refund additional messageFee to this address
        bytes calldata _toAddress,                  // the receiver of the destination ETH
        uint256 _amountLD,                          // the amount, in Local Decimals, to be swapped
        uint256 _minAmountLD                        // the minimum amount accepted out on destination
    ) external payable;
} 