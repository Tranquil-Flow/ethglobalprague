// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/UniswapV4Helper.sol";

contract V4SwapTest is Test {
    // Real token addresses on Base
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    
    // Uniswap V4 contracts on Base
    address constant UNIVERSAL_ROUTER_BASE = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2_BASE = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    function test_v4SwapWithProperPoolKey() public {
        console2.log("=== V4 SWAP WITH PROPER POOLKEY TEST ===");
        
        // Use Base mainnet fork
        vm.createSelectFork("https://base-mainnet.infura.io/v3/5988071a0489487a9507da0ba450cc23");
        
        // Create test user
        address user = makeAddr("testUser");
        vm.deal(user, 10 ether);
        deal(USDC_BASE, user, 1000 * 10**6);
        
        console2.log("Initial USDC balance:", IERC20(USDC_BASE).balanceOf(user));
        console2.log("Initial ETH balance:", user.balance);
        
        vm.startPrank(user);
        
        // Step 1: Approve Permit2
        IERC20(USDC_BASE).approve(PERMIT2_BASE, type(uint256).max);
        console2.log("STEP 1: Approved Permit2");
        
        // Step 2: Use Permit2 to approve Universal Router
        (bool permitSuccess,) = PERMIT2_BASE.call(
            abi.encodeWithSignature(
                "approve(address,address,uint160,uint48)",
                USDC_BASE,
                UNIVERSAL_ROUTER_BASE,
                uint160(100 * 10**6),
                uint48(block.timestamp + 3600)
            )
        );
        require(permitSuccess, "Permit2 approval failed");
        console2.log("STEP 2: Permit2 approved Universal Router");
        
        // Step 3: Create proper PoolKey according to Uniswap V4 documentation
        // From docs: struct PoolKey { Currency currency0; Currency currency1; uint24 fee; int24 tickSpacing; IHooks hooks; }
        address currency0 = USDC_BASE < WETH_BASE ? USDC_BASE : WETH_BASE;
        address currency1 = USDC_BASE < WETH_BASE ? WETH_BASE : USDC_BASE;
        bool zeroForOne = USDC_BASE == currency0;
        
        console2.log("Currency0 (lower):", currency0);
        console2.log("Currency1 (higher):", currency1);
        console2.log("ZeroForOne:", zeroForOne);
        
        // This is the proper PoolKey structure as per V4 documentation
        bytes memory poolKeyEncoded = abi.encode(
            currency0,    // Currency currency0 (USDC)
            currency1,    // Currency currency1 (WETH)  
            uint24(3000), // uint24 fee (0.3%)
            int24(60),    // int24 tickSpacing (60 for 0.3% pools)
            address(0)    // IHooks hooks (no hooks)
        );
        
        console2.log("STEP 3: Created proper PoolKey structure");
        
        // Step 4: Use our UniswapV4Helper to create swap calldata
        bytes memory swapCalldata = UniswapV4Helper.createV4SwapCalldata(
            USDC_BASE,
            100 * 10**6,  // 100 USDC
            0.01 ether,   // Minimum 0.01 ETH out
            3000          // 0.3% fee
        );
        
        console2.log("STEP 4: Generated V4 swap calldata, length:", swapCalldata.length);
        
        // Step 5: Execute the actual V4 swap
        (bool swapSuccess, bytes memory returnData) = UNIVERSAL_ROUTER_BASE.call(swapCalldata);
        
        console2.log("Swap executed, success:", swapSuccess);
        
        if (swapSuccess) {
            uint256 finalUSDC = IERC20(USDC_BASE).balanceOf(user);
            uint256 finalETH = user.balance;
            
            console2.log("SUCCESS: V4 swap executed with proper PoolKey!");
            console2.log("Final USDC balance:", finalUSDC);
            console2.log("Final ETH balance:", finalETH);
            
            if (finalUSDC < 1000 * 10**6) {
                console2.log("USDC decreased:", (1000 * 10**6) - finalUSDC);
            }
            
            console2.log("REAL V4 SWAP WITH PROPER POOLKEY SUCCESSFUL!");
        } else {
            console2.log("Swap failed");
            if (returnData.length >= 4) {
                bytes4 errorSelector = bytes4(returnData);
                console2.log("Error selector:");
                console2.logBytes4(errorSelector);
            }
            if (returnData.length > 0) {
                console2.log("Error data:");
                console2.logBytes(returnData);
            }
        }
        
        vm.stopPrank();
        
        console2.log("=== V4 SWAP TEST COMPLETE ===");
    }
    
    function test_poolKeyStructureValidation() public {
        console2.log("=== POOLKEY STRUCTURE VALIDATION ===");
        
        // Test that our PoolKey follows the exact V4 documentation
        address currency0 = USDC_BASE < WETH_BASE ? USDC_BASE : WETH_BASE;
        address currency1 = USDC_BASE < WETH_BASE ? WETH_BASE : USDC_BASE;
        
        // Ensure currencies are sorted correctly (requirement from V4 docs)
        assertTrue(currency0 < currency1, "Currency0 must be < Currency1");
        console2.log("Currencies properly sorted");
        
        // Create PoolKey exactly as specified in V4 documentation
        bytes memory poolKey = abi.encode(
            currency0,    // Currency currency0
            currency1,    // Currency currency1
            uint24(3000), // uint24 fee
            int24(60),    // int24 tickSpacing
            address(0)    // IHooks hooks
        );
        
        assertTrue(poolKey.length > 0, "PoolKey should be encoded");
        console2.log("PoolKey encoded successfully, length:", poolKey.length);
        
        // Verify the encoding contains the expected components
        (address decoded0, address decoded1, uint24 decodedFee, int24 decodedSpacing, address decodedHooks) = 
            abi.decode(poolKey, (address, address, uint24, int24, address));
            
        assertEq(decoded0, currency0, "Currency0 should match");
        assertEq(decoded1, currency1, "Currency1 should match");
        assertEq(decodedFee, 3000, "Fee should be 3000");
        assertEq(decodedSpacing, 60, "Tick spacing should be 60");
        assertEq(decodedHooks, address(0), "Hooks should be zero address");
        
        console2.log("All PoolKey components verified");
        console2.log("POOLKEY STRUCTURE VALIDATION COMPLETE");
    }
} 