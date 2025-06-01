// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UniswapV4Helper
 * @dev Helper contract for creating Uniswap V4 swap calldata using Universal Router
 */
library UniswapV4Helper {
    // Commands for Universal Router
    uint256 constant V4_SWAP = 0x00;
    
    // Actions for V4 Router
    uint256 constant SWAP_EXACT_IN_SINGLE = 0x00;
    uint256 constant SETTLE_ALL = 0x01;
    uint256 constant TAKE_ALL = 0x02;

    // Universal Router interface
    interface IUniversalRouter {
        function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
    }

    // V4 PoolManager interface
    interface IPoolManager {
        struct PoolKey {
            address currency0;
            address currency1; 
            uint24 fee;
            int24 tickSpacing;
            address hooks;
        }
    }

    // V4 Router interface
    interface IV4Router {
        struct ExactInputSingleParams {
            IPoolManager.PoolKey poolKey;
            bool zeroForOne;
            uint128 amountIn;
            uint128 amountOutMinimum;
            bytes hookData;
        }
    }

    // Permit2 interface
    interface IPermit2 {
        function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    }

    /**
     * @dev Creates calldata for swapping tokens to ETH using Uniswap V4 Universal Router
     * @param tokenIn Address of the input token
     * @param amountIn Amount of input tokens to swap
     * @param amountOutMinimum Minimum amount of ETH to receive
     * @param fee The pool fee tier (e.g., 3000 for 0.3%)
     * @return calldata for Universal Router execute function
     */
    function createV4SwapCalldata(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint24 fee
    ) internal view returns (bytes memory) {
        // Create PoolKey for the token/ETH pool
        // For V4, ETH is represented as address(0)
        IPoolManager.PoolKey memory poolKey = IPoolManager.PoolKey({
            currency0: tokenIn < address(0) ? tokenIn : address(0), // Lower address first
            currency1: tokenIn < address(0) ? address(0) : tokenIn, // Higher address second
            fee: fee,
            tickSpacing: getTickSpacingForFee(fee),
            hooks: address(0) // No hooks for standard pools
        });

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(V4_SWAP));

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(SWAP_EXACT_IN_SINGLE),
            uint8(SETTLE_ALL),
            uint8(TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        
        // Action 1: Swap parameters
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: tokenIn < address(0), // true if swapping currency0 for currency1
                amountIn: uint128(amountIn),
                amountOutMinimum: uint128(amountOutMinimum),
                hookData: bytes("")
            })
        );
        
        // Action 2: Settle input token
        params[1] = abi.encode(poolKey.currency0, amountIn);
        
        // Action 3: Take output token (ETH)
        params[2] = abi.encode(poolKey.currency1, amountOutMinimum);

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Create the final calldata for Universal Router
        return abi.encodeWithSelector(
            IUniversalRouter.execute.selector,
            commands,
            inputs,
            block.timestamp + 1 hours // deadline
        );
    }

    /**
     * @dev Gets the appropriate tick spacing for a given fee tier
     * @param fee The pool fee
     * @return tickSpacing The tick spacing for the fee tier
     */
    function getTickSpacingForFee(uint24 fee) internal pure returns (int24 tickSpacing) {
        if (fee == 100) return 1;        // 0.01%
        if (fee == 500) return 10;       // 0.05%
        if (fee == 3000) return 60;      // 0.3%
        if (fee == 10000) return 200;    // 1%
        revert("Invalid fee tier");
    }

    /**
     * @dev Approves tokens for Permit2 and then approves Universal Router via Permit2
     * @param token The token to approve
     * @param permit2 The Permit2 contract address
     * @param universalRouter The Universal Router address
     * @param amount The amount to approve
     */
    function approveTokensForV4(
        address token,
        address permit2,
        address universalRouter,
        uint256 amount
    ) internal {
        // First approve Permit2 to spend tokens
        IERC20(token).approve(permit2, type(uint256).max);
        
        // Then use Permit2 to approve Universal Router
        IPermit2(permit2).approve(
            token,
            universalRouter,
            uint160(amount),
            uint48(block.timestamp + 1 hours)
        );
    }

    /**
     * @dev Creates a SwapInfo struct for OriginSweeper/ExternalSweeper with V4 calldata
     * @param token The token to swap
     * @param amount The amount to swap
     * @param universalRouter The Universal Router address
     * @param fee The pool fee tier
     * @return SwapInfo struct with V4 calldata
     */
    function createV4SwapInfo(
        address token,
        uint256 amount,
        address universalRouter,
        uint24 fee
    ) internal view returns (SwapInfo memory) {
        bytes memory dexCalldata = createV4SwapCalldata(
            token,
            amount,
            0, // No slippage protection for testing
            fee
        );

        return SwapInfo({
            dexContract: universalRouter,
            token: token,
            amount: amount,
            dexCalldata: dexCalldata
        });
    }

    // SwapInfo struct - matches the one in OriginSweeper/ExternalSweeper
    struct SwapInfo {
        address dexContract;
        address token;
        uint256 amount;
        bytes dexCalldata;
    }
} 