// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UniswapV4Helper
 * @dev Helper library for creating Uniswap V4 swap calldata and structures
 */
library UniswapV4Helper {
    // Deployment addresses for V4 contracts (from https://docs.uniswap.org/contracts/v4/deployments)
    address constant POOL_MANAGER_ETHEREUM = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant POOL_MANAGER_OPTIMISM = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
    address constant POOL_MANAGER_BASE = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POOL_MANAGER_UNICHAIN = 0x1F98400000000000000000000000000000000004;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // WETH addresses per chain
    address constant WETH_OPTIMISM = 0x4200000000000000000000000000000000000006;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address constant WETH_UNICHAIN = 0x4200000000000000000000000000000000000006;

    // Universal Router addresses per chain (from official V4 deployments)
    address constant UNIVERSAL_ROUTER_ETHEREUM = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address constant UNIVERSAL_ROUTER_OPTIMISM = 0x851116D9223fabED8E56C0E6b8Ad0c31d98B3507;
    address constant UNIVERSAL_ROUTER_BASE = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant UNIVERSAL_ROUTER_UNICHAIN = 0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3;

    // Universal Router Commands (from @uniswap/universal-router)
    uint8 constant V4_SWAP = 0x00;
    uint8 constant PERMIT2_TRANSFER_FROM = 0x01;
    uint8 constant WRAP_ETH = 0x0b;
    uint8 constant UNWRAP_WETH = 0x0c;

    // V4Router Actions (from @uniswap/v4-periphery)
    uint8 constant SWAP_EXACT_IN_SINGLE = 0x00;
    uint8 constant SETTLE_ALL = 0x12;
    uint8 constant TAKE_ALL = 0x13;

    struct SwapInfo {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint24 fee;
        address recipient;
        address dexRouter;
    }

    // PoolKey structure for V4
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    // ExactInputSingleParams for V4Router
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    /**
     * @dev Get Universal Router address for current chain
     */
    function getUniversalRouterAddress() internal view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return UNIVERSAL_ROUTER_ETHEREUM;    // Ethereum
        if (chainId == 10) return UNIVERSAL_ROUTER_OPTIMISM;   // Optimism
        if (chainId == 8453) return UNIVERSAL_ROUTER_BASE;     // Base
        if (chainId == 1301) return UNIVERSAL_ROUTER_UNICHAIN; // Unichain
        revert("Unsupported chain for Universal Router");
    }

    /**
     * @dev Get PoolManager address for current chain
     */
    function getPoolManagerAddress() internal view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return POOL_MANAGER_ETHEREUM;    // Ethereum
        if (chainId == 10) return POOL_MANAGER_OPTIMISM;   // Optimism
        if (chainId == 8453) return POOL_MANAGER_BASE;     // Base
        if (chainId == 1301) return POOL_MANAGER_UNICHAIN; // Unichain
        revert("Unsupported chain for PoolManager");
    }

    /**
     * @dev Get WETH address for current chain
     */
    function getWETHAddress() internal view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 10) return WETH_OPTIMISM;     // Optimism
        if (chainId == 8453) return WETH_BASE;       // Base
        if (chainId == 1301) return WETH_UNICHAIN;   // Unichain
        revert("Unsupported chain");
    }

    /**
     * @dev Get tick spacing for a given fee tier
     * @param fee The fee tier (100, 500, 3000, or 10000)
     * @return tickSpacing The corresponding tick spacing
     */
    function getTickSpacingForFee(uint24 fee) internal pure returns (int24) {
        if (fee == 100) return 1;    // 0.01%
        if (fee == 500) return 10;   // 0.05%
        if (fee == 3000) return 60;  // 0.3%
        if (fee == 10000) return 200; // 1%
        revert("Invalid fee tier");
    }

    /**
     * @dev Creates a PoolKey for Uniswap V4
     * @param tokenA First token address
     * @param tokenB Second token address  
     * @param fee Pool fee tier
     * @param tickSpacing Tick spacing for the pool
     * @param hooks Hooks contract address
     * @return key The constructed PoolKey
     */
    function createPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) internal pure returns (PoolKey memory key) {
        // Sort tokens to ensure currency0 < currency1
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks
        });
    }

    /**
     * @dev Creates calldata for V4 swap via Universal Router
     * @param tokenIn Input token address
     * @param amountIn Amount of input tokens to swap
     * @param minAmountOut Minimum amount of output tokens expected
     * @param fee Pool fee tier
     * @return Actual Universal Router calldata for executing the swap
     */
    function createV4SwapCalldata(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 fee
    ) internal view returns (bytes memory) {
        address tokenOut = getWETHAddress(); // Always swap to WETH
        
        // Create pool key for the pair
        PoolKey memory poolKey = createPoolKey(
            tokenIn,
            tokenOut,
            fee,
            getTickSpacingForFee(fee),
            address(0) // No hooks
        );

        // Determine swap direction
        bool zeroForOne = tokenIn == poolKey.currency0;

        // Create swap parameters
        ExactInputSingleParams memory swapParams = ExactInputSingleParams({
            poolKey: poolKey,
            zeroForOne: zeroForOne,
            amountIn: uint128(amountIn),
            amountOutMinimum: uint128(minAmountOut),
            hookData: bytes("")
        });

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            SWAP_EXACT_IN_SINGLE,
            SETTLE_ALL,
            TAKE_ALL
        );

        // Encode parameters for each action
        bytes[] memory params = new bytes[](3);
        
        // Swap parameters
        params[0] = abi.encode(swapParams);
        
        // Settle parameters (input currency and amount)
        params[1] = abi.encode(zeroForOne ? poolKey.currency0 : poolKey.currency1, amountIn);
        
        // Take parameters (output currency and minimum amount)
        params[2] = abi.encode(zeroForOne ? poolKey.currency1 : poolKey.currency0, minAmountOut);

        // Create Universal Router commands
        bytes memory commands = abi.encodePacked(
            PERMIT2_TRANSFER_FROM, // Transfer tokens from user
            V4_SWAP,              // Execute V4 swap
            UNWRAP_WETH           // Unwrap WETH to ETH if output is WETH
        );

        // Create inputs for Universal Router
        bytes[] memory inputs = new bytes[](3);
        
        // Permit2 transfer input
        inputs[0] = abi.encode(tokenIn, amountIn);
        
        // V4 swap input
        inputs[1] = abi.encode(actions, params);
        
        // Unwrap input (amount will be determined during execution)
        inputs[2] = abi.encode(0); // Amount set to 0, will unwrap all WETH received

        // Create the final calldata for Universal Router execute function
        uint256 deadline = block.timestamp + 300; // 5 minute deadline
        return abi.encodeWithSignature(
            "execute(bytes,bytes[],uint256)",
            commands,
            inputs,
            deadline
        );
    }

    /**
     * @dev Creates SwapInfo struct
     */
    function createSwapInfo(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 fee,
        address recipient,
        address dexRouter
    ) internal pure returns (SwapInfo memory) {
        return SwapInfo({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            fee: fee,
            recipient: recipient,
            dexRouter: dexRouter
        });
    }
} 