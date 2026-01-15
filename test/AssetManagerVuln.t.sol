// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {AssetManager} from "../src/asset-manager/AssetManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract AssetManagerFlowTest is Test {
    MockUSDC usdc;
    AssetManager am;
    address treasury = address(0x1);
    address admin = address(0x2);
    address governance = address(0x3);
    address strategy1 = address(0x4);
    address strategy2 = address(0x5);

    function setUp() public {
        // Deploy USDC
        usdc = new MockUSDC();
        
        // Deploy AssetManager
        AssetManager amImpl = new AssetManager(address(usdc), treasury);
        bytes memory initData = abi.encodeCall(AssetManager.initialize, (admin, governance));
        ERC1967Proxy proxy = new ERC1967Proxy(address(amImpl), initData);
        am = AssetManager(address(proxy));
        
        // Set up weights for two strategies
        vm.prank(admin);
        am.updateWeight(strategy1, 50);
        vm.prank(admin);
        am.updateWeight(strategy2, 50);
        
        // Give treasury USDC
        deal(address(usdc), treasury, 1000e6);
        vm.prank(treasury);
        usdc.approve(address(am), type(uint256).max);
    }

    function test_assetManager_cannotWithdrawAfterDeposit() public {
        console.log("=== Testing AssetManager Fund Flow Bug ===");
        
        // Step 1: Treasury deposits 100 USDC to AssetManager
        console.log("Treasury USDC before deposit:", usdc.balanceOf(treasury));
        console.log("AssetManager USDC before deposit:", usdc.balanceOf(address(am)));
        
        vm.prank(treasury);
        am.deposit(100e6);
        
        // Step 2: Check balances after deposit
        console.log("Treasury USDC after deposit:", usdc.balanceOf(treasury));
        console.log("AssetManager USDC after deposit:", usdc.balanceOf(address(am)));
        console.log("Strategy1 USDC:", usdc.balanceOf(strategy1));
        console.log("Strategy2 USDC:", usdc.balanceOf(strategy2));
        
        // Step 3: Try to withdraw - THIS SHOULD FAIL!
        console.log("\nAttempting to withdraw 100 USDC from AssetManager...");
        
        vm.prank(treasury);
        vm.expectRevert(); // Should revert because AM has 0 USDC
        am.withdraw(100e6);
        
        console.log("CONFIRMED: AssetManager cannot withdraw after deposit!");
        console.log("Funds are distributed to strategies but cannot be retrieved!");
    }
}
