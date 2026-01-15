// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {AssetManager} from "../src/asset-manager/AssetManager.sol";
import {MockAssetManager} from "../src/mocks/MockAssetManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/**
 * @title Critical AssetManager Vulnerability
 * @notice Demonstrates fund freezing bug - bounty scope: "Permanent freezing of funds"
 */
contract CriticalVuln is Test {
    MockUSDC usdc;
    address treasury = address(0x1234567890123456789012345678901234567890);
    address admin = address(0x2234567890123456789012345678901234567890);
    address governance = address(0x3234567890123456789012345678901234567890);
    address strategy1 = address(0x1111111111111111111111111111111111111111);
    address strategy2 = address(0x2222222222222222222222222222222222222222);

    function setUp() public {
        usdc = new MockUSDC();
        deal(address(usdc), treasury, 1_000_000e6);
    }

    /**
     * @notice Shows MockAssetManager works correctly (tests pass)
     */
    function test_mock_assetManager_works() public {
        console.log("=== MockAssetManager (used in tests) ===");
        
        MockAssetManager mock = new MockAssetManager(address(usdc));
        
        vm.prank(treasury);
        usdc.approve(address(mock), type(uint256).max);
        
        // Deposit
        vm.prank(treasury);
        mock.deposit(100e6);
        console.log("After deposit - Mock balance:", usdc.balanceOf(address(mock)));
        
        // Withdraw works!
        vm.prank(treasury);
        mock.withdraw(100e6);
        console.log("After withdraw - Mock balance:", usdc.balanceOf(address(mock)));
        console.log("Treasury balance:", usdc.balanceOf(treasury));
        console.log("SUCCESS: MockAssetManager can withdraw\n");
    }

    /**
     * @notice CRITICAL: Real AssetManager CANNOT withdraw after deposit
     * @dev Bounty: "Permanent freezing of funds" - CRITICAL
     */
    function test_CRITICAL_real_assetManager_freezes_funds() public {
        console.log("=== Real AssetManager (PRODUCTION CODE) ===");
        
        // Deploy real AssetManager
        AssetManager amImpl = new AssetManager(address(usdc), treasury);
        bytes memory initData = abi.encodeCall(AssetManager.initialize, (admin, governance));
        ERC1967Proxy proxy = new ERC1967Proxy(address(amImpl), initData);
        AssetManager real = AssetManager(address(proxy));
        
        // Setup weights
        vm.prank(admin);
        real.updateWeight(strategy1, 50);
        vm.prank(admin);
        real.updateWeight(strategy2, 50);
        
        vm.prank(treasury);
        usdc.approve(address(real), type(uint256).max);
        
        // Deposit
        console.log("Before deposit:");
        console.log("  Treasury:", usdc.balanceOf(treasury));
        console.log("  AssetManager:", usdc.balanceOf(address(real)));
        
        vm.prank(treasury);
        real.deposit(100e6);
        
        console.log("\nAfter deposit:");
        console.log("  Treasury:", usdc.balanceOf(treasury));
        console.log("  AssetManager:", usdc.balanceOf(address(real)), "<-- ZERO!");
        console.log("  Strategy1:", usdc.balanceOf(strategy1));
        console.log("  Strategy2:", usdc.balanceOf(strategy2));
        
        // Try to withdraw - FAILS!
        console.log("\nTrying to withdraw 100 USDC...");
        vm.prank(treasury);
        vm.expectRevert(); // Will revert - no funds!
        real.withdraw(100e6);
        
        console.log("CRITICAL: withdraw() REVERTED!");
        console.log("Funds distributed to strategies cannot be retrieved.");
        console.log("User deposits are PERMANENTLY FROZEN!");
    }
    
    /**
     * @notice Shows the root cause of the vulnerability
     */
    function test_root_cause_analysis() public view {
        console.log("=== ROOT CAUSE ANALYSIS ===\n");
        console.log("MockAssetManager.deposit():");
        console.log("  -> Keeps funds in contract");
        console.log("  -> withdraw() can return them\n");
        
        console.log("Real AssetManager.deposit():");
        console.log("  -> Distributes ALL funds to weighted strategies");
        console.log("  -> AssetManager ends up with 0 USDC");
        console.log("  -> withdraw() fails - nothing to send!\n");
        
        console.log("IMPACT:");
        console.log("  - Bounty: Permanent freezing of funds = CRITICAL");
        console.log("  - All allocator tests pass (use Mock)");
        console.log("  - Production deployment will FREEZE USER FUNDS");
    }
}
