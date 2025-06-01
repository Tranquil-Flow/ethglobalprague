// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";

import "../contracts/OriginSweeper.sol";
import "../contracts/ExternalSweeper.sol";
import "../contracts/TestToken.sol";
import "../contracts/UniswapV4Helper.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

// Uniswap V4 interfaces and libraries
interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IPoolManager {
    struct PoolKey {
        address currency0;
        address currency1; 
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }
}

interface IV4Router {
    struct ExactInputSingleParams {
        IPoolManager.PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }
}

// Commands for Universal Router
library Commands {
    uint256 constant V4_SWAP = 0x00;
}

// Actions for V4 Router
library Actions {
    uint256 constant SWAP_EXACT_IN_SINGLE = 0x00;
    uint256 constant SETTLE_ALL = 0x01;
    uint256 constant TAKE_ALL = 0x02;
}

// Interface for WETH (needed for wrapping ETH)
interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

// Interface for Permit2
interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract SweeperTest is TestHelperOz5 {
    using OptionsBuilder for bytes;
    using UniswapV4Helper for *;

    // Chain IDs for LayerZero
    uint32 constant CHAIN_ID_OPTIMISM = 111;   // Optimism
    uint32 constant CHAIN_ID_BASE = 184;       // Base
    uint32 constant CHAIN_ID_UNICHAIN = 130;   // Unichain

    // Real token addresses
    address constant USDC_OPTIMISM = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address constant WETH_OPTIMISM = 0x4200000000000000000000000000000000000006;
    
    address constant USDC_BASE = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    
    address constant USDC_UNICHAIN = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; // placeholder
    address constant WETH_UNICHAIN = 0x4200000000000000000000000000000000000006; // placeholder

    // Uniswap V4 Universal Router addresses (these will need to be updated when V4 deploys)
    address constant UNIVERSAL_ROUTER_OPTIMISM = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD; // placeholder
    address constant UNIVERSAL_ROUTER_BASE = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD; // placeholder
    address constant UNIVERSAL_ROUTER_UNICHAIN = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD; // placeholder

    // V4 PoolManager addresses (these will need to be updated when V4 deploys)
    address constant POOL_MANAGER_OPTIMISM = 0x01C1a25D3e1C8CEdAE4c7b503e67F7b25fD6d1C4; // placeholder
    address constant POOL_MANAGER_BASE = 0x01C1a25D3e1C8CEdAE4c7b503e67F7b25fD6d1C4; // placeholder
    address constant POOL_MANAGER_UNICHAIN = 0x01C1a25D3e1C8CEdAE4c7b503e67F7b25fD6d1C4; // placeholder

    // Permit2 addresses
    address constant PERMIT2_OPTIMISM = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant PERMIT2_BASE = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant PERMIT2_UNICHAIN = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Fork IDs
    uint256 optimismFork;
    uint256 baseFork;
    uint256 unichainFork;
    
    // Our contracts
    OriginSweeper originSweeper;
    ExternalSweeper baseSweeper;
    ExternalSweeper unicSweeper;

    // User account
    address user;
    address finalReceiver;
    
    // Whale addresses (large holders of USDC on each chain)
    address constant USDC_WHALE_OPTIMISM = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address constant USDC_WHALE_BASE = 0x20FE51A9229EEf2cF8Ad9E89d91CAb9312cF3b7A;
    address constant USDC_WHALE_UNICHAIN = 0x625E7708f30cA75bfd92586e17077590C60eb4cD; // placeholder

    function setUp() public override {
        super.setUp();

        // Setup three endpoints for our three chains
        setUpEndpoints(3, LibraryType.UltraLightNode);

        // Create forks
        optimismFork = vm.createFork(vm.envString("OPTIMISM_RPC_URL"));
        baseFork = vm.createFork(vm.envString("BASE_RPC_URL"));
        // unichainFork = vm.createFork(vm.envString("UNICHAIN_RPC_URL")); // Uncomment when available

        // Create test accounts
        user = makeAddr("user");
        vm.deal(user, 100 ether);
        
        finalReceiver = makeAddr("finalReceiver");

        // Deploy our contracts and set up USDC for testing
        deploySweeperContracts();
        acquireUSDC();
    }

    function deploySweeperContracts() internal {
        // Set up total chains selling
        uint totalChainsSelling = 3;
        
        // Deploy OriginSweeper on Optimism
        vm.selectFork(optimismFork);
        originSweeper = new OriginSweeper(
            endpoints[1], // Optimism endpoint
            address(this),
            finalReceiver,
            totalChainsSelling
        );
        
        // Deploy ExternalSweeper on Base
        vm.selectFork(baseFork);
        baseSweeper = new ExternalSweeper(
            endpoints[2], // Base endpoint
            address(this),
            address(originSweeper),
            CHAIN_ID_OPTIMISM
        );
    }

    function acquireUSDC() internal {
        // Transfer USDC from whales to our test user
        
        // On Optimism
        vm.selectFork(optimismFork);
        vm.startPrank(USDC_WHALE_OPTIMISM);
        IERC20(USDC_OPTIMISM).transfer(user, 1000 * 10**6); // Transfer 1000 USDC
        vm.stopPrank();
        
        // On Base
        vm.selectFork(baseFork);
        vm.startPrank(USDC_WHALE_BASE);
        IERC20(USDC_BASE).transfer(user, 1000 * 10**6); // Transfer 1000 USDC
        vm.stopPrank();
    }

    function buyUSDCWithETH(uint256 fork, address router, address weth, address usdc, uint256 ethAmount) internal {
        vm.selectFork(fork);
        vm.startPrank(user);
        
        // Wrap ETH to WETH
        IWETH(weth).deposit{value: ethAmount}();
        
        // For V4, we would need to approve Permit2 and then use Universal Router
        UniswapV4Helper.approveTokensForV4(
            weth,
            getPermit2Address(fork),
            router,
            ethAmount
        );
        
        // Create V4 swap through Universal Router
        createV4SwapForETH(router, weth, usdc, ethAmount);
        
        vm.stopPrank();
    }

    function getPermit2Address(uint256 fork) internal pure returns (address) {
        if (fork == 1) return PERMIT2_OPTIMISM;
        if (fork == 2) return PERMIT2_BASE;
        return PERMIT2_UNICHAIN;
    }

    function createV4SwapForETH(address router, address tokenIn, address tokenOut, uint256 amountIn) internal {
        // This is a placeholder for V4 swap implementation
        // In real implementation, you'd create the proper V4 calldata
        // For now, we'll use a simple mock approach
        console.log("V4 swap would be executed here:", tokenIn, "->", tokenOut, "amount:", amountIn);
    }

    function createSwapInfo(address token, uint256 amount, address dexRouter) internal view returns (OriginSweeper.SwapInfo memory) {
        // Use the V4 helper library to create swap info
        return UniswapV4Helper.createV4SwapInfo(
            token,
            amount,
            dexRouter,
            3000 // 0.3% fee tier
        );
    }

    function test_fullTokenSweepFlow() public {
        console.log("Starting full token sweep test with Uniswap V4 and real USDC");

        // Prepare token approvals on Optimism
        vm.selectFork(optimismFork);
        
        vm.startPrank(user);
        IERC20(USDC_OPTIMISM).approve(address(originSweeper), 500 * 10**6);
        // Approve for V4 interactions using the helper
        UniswapV4Helper.approveTokensForV4(
            USDC_OPTIMISM,
            PERMIT2_OPTIMISM,
            UNIVERSAL_ROUTER_OPTIMISM,
            500 * 10**6
        );
        vm.stopPrank();
        
        // Check USDC balance
        uint256 usdcBalanceOp = IERC20(USDC_OPTIMISM).balanceOf(user);
        console.log("User USDC balance on Optimism:", usdcBalanceOp);
        
        // Prepare token approvals on Base
        vm.selectFork(baseFork);
        
        vm.startPrank(user);
        IERC20(USDC_BASE).approve(address(baseSweeper), 500 * 10**6);
        UniswapV4Helper.approveTokensForV4(
            USDC_BASE,
            PERMIT2_BASE,
            UNIVERSAL_ROUTER_BASE,
            500 * 10**6
        );
        vm.stopPrank();
        
        uint256 usdcBalanceBase = IERC20(USDC_BASE).balanceOf(user);
        console.log("User USDC balance on Base:", usdcBalanceBase);
        
        // Create swap info arrays for each chain using V4
        vm.selectFork(optimismFork);
        
        OriginSweeper.SwapInfo[] memory optimismSwaps = new OriginSweeper.SwapInfo[](1);
        optimismSwaps[0] = createSwapInfo(USDC_OPTIMISM, 500 * 10**6, UNIVERSAL_ROUTER_OPTIMISM);
        
        OriginSweeper.SwapInfo[] memory baseSwaps = new OriginSweeper.SwapInfo[](1);
        baseSwaps[0] = createSwapInfo(USDC_BASE, 500 * 10**6, UNIVERSAL_ROUTER_BASE);
        
        // Prepare the arrays for the executeTokenSwaps call
        uint32[] memory chainIds = new uint32[](2);
        chainIds[0] = CHAIN_ID_OPTIMISM;
        chainIds[1] = CHAIN_ID_BASE;
        
        OriginSweeper.SwapInfo[][] memory swapInfoArrays = new OriginSweeper.SwapInfo[][](2);
        swapInfoArrays[0] = optimismSwaps;
        swapInfoArrays[1] = baseSwaps;
        
        // Execute token swaps as user
        vm.startPrank(user);
        // Need to provide gas for cross-chain messages
        originSweeper.executeTokenSwaps{value: 1 ether}(
            chainIds,
            swapInfoArrays,
            false // privacy flag off for simplicity
        );
        vm.stopPrank();
        
        // Verify the messages were sent to external chains
        assertTrue(hasPendingPackets(CHAIN_ID_BASE, addressToBytes32(address(baseSweeper))), "No pending packets for Base");
        
        // Process the messages on Base
        verifyPackets(CHAIN_ID_BASE, addressToBytes32(address(baseSweeper)));
        
        // Verify that tokens were swapped on Base and ETH was bridged back
        assertTrue(hasPendingPackets(CHAIN_ID_OPTIMISM, addressToBytes32(address(originSweeper))), "No pending packets from Base to Optimism");
        
        // Process the messages back to Optimism
        verifyPackets(CHAIN_ID_OPTIMISM, addressToBytes32(address(originSweeper)));
        
        // Check if the finalReceiver got the ETH
        vm.selectFork(optimismFork);
        uint256 finalReceiverBalance = address(finalReceiver).balance;
        assertGt(finalReceiverBalance, 0, "Final receiver didn't receive ETH");
        
        console.log("Final receiver balance:", finalReceiverBalance);
        console.log("Uniswap V4 test completed successfully");
    }

    function test_v4SwapCalldataCreation() public {
        console.log("Testing V4 swap calldata creation");
        
        // Test creating swap calldata using the helper
        bytes memory calldata_ = UniswapV4Helper.createV4SwapCalldata(
            USDC_OPTIMISM,
            1000 * 10**6, // 1000 USDC
            0, // No minimum amount out
            3000 // 0.3% fee
        );
        
        assertTrue(calldata_.length > 0, "Calldata should not be empty");
        console.log("Generated calldata length:", calldata_.length);
        
        // Test creating SwapInfo
        UniswapV4Helper.SwapInfo memory swapInfo = UniswapV4Helper.createV4SwapInfo(
            USDC_OPTIMISM,
            1000 * 10**6,
            UNIVERSAL_ROUTER_OPTIMISM,
            3000
        );
        
        assertEq(swapInfo.token, USDC_OPTIMISM, "Token address should match");
        assertEq(swapInfo.amount, 1000 * 10**6, "Amount should match");
        assertEq(swapInfo.dexContract, UNIVERSAL_ROUTER_OPTIMISM, "DEX contract should match");
        assertTrue(swapInfo.dexCalldata.length > 0, "DEX calldata should not be empty");
        
        console.log("V4 swap calldata creation test passed");
    }
}

// Mock V4 Universal Router for testing (since V4 isn't deployed yet)
contract MockV4UniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable {
        // Decode and simulate V4 swap
        console.log("Mock V4 Universal Router executing swap");
        console.log("Commands length:", commands.length);
        console.log("Inputs length:", inputs.length);
        console.log("Deadline:", deadline);
        
        // For testing, just transfer some ETH back to simulate a successful swap
        uint256 ethToReturn = msg.value > 0 ? msg.value / 1000 : 0.001 ether;
        if (address(this).balance >= ethToReturn) {
            payable(msg.sender).transfer(ethToReturn);
        }
    }
    
    // Function to receive ETH
    receive() external payable {}
} 