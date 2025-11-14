// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract VaultEmergencyTest is VaultTestBase {
    function test_EmergencyWithdraw_Basic() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        address receiver = makeAddr("receiver");
        uint256 vaultAssets = vault.totalAssets();

        vault.emergencyWithdraw(receiver);

        uint256 receiverBalance = asset.balanceOf(receiver);

        assertEq(receiverBalance, vaultAssets);
        assertEq(vault.totalAssets(), 0);
    }

    function test_EmergencyWithdraw_RevertIf_NotEmergencyRole() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.EMERGENCY_ROLE()
            )
        );
        vm.prank(alice);
        vault.emergencyWithdraw(alice);
    }

    function test_EmergencyWithdraw_WithEmergencyRole() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        address emergency = makeAddr("emergency");
        vault.grantRole(vault.EMERGENCY_ROLE(), emergency);

        address receiver = makeAddr("receiver");

        vm.prank(emergency);
        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), 100_000e6);
    }

    function test_EmergencyWithdraw_WithZeroAssets() public {
        address receiver = makeAddr("receiver");

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), 0);
    }

    function test_EmergencyWithdraw_RevertIf_ReceiverZeroAddress() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.emergencyWithdraw(address(0));
    }

    function test_EmergencyWithdraw_DoesNotAffectShares() public {
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100_000e6, alice);

        address receiver = makeAddr("receiver");

        vault.emergencyWithdraw(receiver);

        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.totalSupply(), aliceShares);
    }

    function test_EmergencyWithdraw_PausesVault() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        assertFalse(vault.paused());

        address receiver = makeAddr("receiver");
        vault.emergencyWithdraw(receiver);

        assertTrue(vault.paused());
    }

    function test_EmergencyWithdraw_EmitsEventAndTransfersProfit() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        // simulate protocol profit
        asset.mint(address(vault), 25_000e6);

        address receiver = makeAddr("receiver");
        uint256 totalBefore = vault.totalAssets();

        vm.expectEmit(true, false, false, true);
        emit Vault.EmergencyWithdrawal(receiver, totalBefore);

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), totalBefore);
        assertEq(vault.totalAssets(), 0);
    }

    function test_EmergencyWithdraw_WhenAlreadyPaused() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vault.pause();
        assertTrue(vault.paused());

        address receiver = makeAddr("receiver");
        uint256 totalAssetsBefore = vault.totalAssets();

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), totalAssetsBefore);
        assertEq(vault.totalAssets(), 0);
        assertTrue(vault.paused());
    }

    function test_EmergencyWithdraw_MultipleDepositors() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        vm.prank(bob);
        vault.deposit(30_000e6, bob);

        address receiver = makeAddr("receiver");
        uint256 totalAssets = vault.totalAssets();

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), totalAssets);
    }

    function test_EmergencyWithdraw_UsersCanWithdrawAfter() public {
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100_000e6, alice);

        address receiver = makeAddr("receiver");
        vault.emergencyWithdraw(receiver);

        assertTrue(vault.paused());

        asset.mint(address(vault), 100_000e6);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);
        assertGt(aliceBalanceAfter - aliceBalanceBefore, 0);
    }

    function test_EmergencyWithdraw_BlocksNewDeposits() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        address receiver = makeAddr("receiver");
        vault.emergencyWithdraw(receiver);

        assertTrue(vault.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(bob);
        vault.deposit(10_000e6, bob);
    }

    function testFuzz_EmergencyWithdraw_ResetsLastTotalAssets(uint96 amount) public {
        amount = uint96(bound(uint256(amount), vault.MIN_FIRST_DEPOSIT() + 1, type(uint96).max / 2));
        asset.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        assertEq(vault.totalAssets(), vault.lastTotalAssets());
        assertGt(vault.lastTotalAssets(), 0);

        address receiver = makeAddr("receiver");
        vault.emergencyWithdraw(receiver);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.lastTotalAssets(), 0);
    }

    function testFuzz_EmergencyWithdraw_Basic(uint96 depositAmount) public {
        depositAmount = uint96(bound(depositAmount, vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2));
        asset.mint(alice, depositAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        address receiver = makeAddr("receiver");
        uint256 vaultAssets = vault.totalAssets();

        vault.emergencyWithdraw(receiver);

        uint256 receiverBalance = asset.balanceOf(receiver);

        assertEq(receiverBalance, vaultAssets);
        assertEq(vault.totalAssets(), 0);
    }

    function testFuzz_EmergencyWithdraw_DoesNotAffectShares(uint96 depositAmount) public {
        depositAmount = uint96(bound(depositAmount, vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2));
        asset.mint(alice, depositAmount);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        address receiver = makeAddr("receiver");

        vault.emergencyWithdraw(receiver);

        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.totalSupply(), aliceShares);
    }

    function testFuzz_EmergencyWithdraw_EmitsEventAndTransfersProfit(uint96 depositAmount, uint96 profitAmount)
        public
    {
        depositAmount = uint96(bound(depositAmount, vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 4));
        profitAmount = uint96(bound(profitAmount, 1, type(uint96).max / 4));
        asset.mint(alice, depositAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // simulate protocol profit
        asset.mint(address(vault), profitAmount);

        address receiver = makeAddr("receiver");
        uint256 totalBefore = vault.totalAssets();

        vm.expectEmit(true, false, false, true);
        emit Vault.EmergencyWithdrawal(receiver, totalBefore);

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), totalBefore);
        assertEq(vault.totalAssets(), 0);
    }

    function testFuzz_EmergencyWithdraw_MultipleDepositors(uint96 aliceAmount, uint96 bobAmount) public {
        aliceAmount = uint96(bound(aliceAmount, vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 4));
        bobAmount = uint96(bound(bobAmount, 1, type(uint96).max / 4));
        asset.mint(alice, aliceAmount);
        asset.mint(bob, bobAmount);

        vm.prank(alice);
        vault.deposit(aliceAmount, alice);

        vm.prank(bob);
        vault.deposit(bobAmount, bob);

        address receiver = makeAddr("receiver");
        uint256 totalAssets = vault.totalAssets();

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), totalAssets);
    }
}
