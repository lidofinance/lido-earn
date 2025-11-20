// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "src/Vault.sol";
import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterDepositTest is ERC4626AdapterTestBase {
    function testFuzz_Deposit_EmitsEvent(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(true, true, false, true);
        emit Deposited(alice, alice, amount, expectedShares);

        vm.prank(alice);
        vault.deposit(amount, alice);
    }

    function testFuzz_Deposit_MultipleUsers(uint96 aliceAmount, uint96 bobAmount) public {
        uint256 aliceDeposit = bound(uint256(aliceAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        uint256 bobDeposit = bound(uint256(bobAmount), 1, type(uint96).max);
        usdc.mint(alice, aliceDeposit);
        usdc.mint(bob, bobDeposit);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDeposit, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);

        uint256 expectedAliceShares = aliceDeposit * 10 ** vault.OFFSET();
        uint256 expectedBobShares = bobDeposit * 10 ** vault.OFFSET();

        assertEq(aliceShares, expectedAliceShares);
        assertEq(bobShares, expectedBobShares);
        assertEq(vault.totalSupply(), aliceShares + bobShares);
        assertApproxEqAbs(vault.totalAssets(), aliceDeposit + bobDeposit, 2);
    }

    function testFuzz_Deposit_UpdatesTargetVaultBalance(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        uint256 targetBalanceBefore = targetVault.balanceOf(address(vault));
        assertEq(targetBalanceBefore, 0);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 targetBalanceAfter = targetVault.balanceOf(address(vault));
        uint256 expectedTargetShares = amount * 10 ** OFFSET;

        assertEq(targetBalanceAfter, expectedTargetShares);
    }

    function test_Deposit_RevertIf_TargetVaultReturnsZeroShares() public {
        targetVault.setForceZeroDeposit(true);

        vm.expectRevert(ERC4626Adapter.TargetVaultDepositFailed.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        targetVault.setForceZeroDeposit(false);
    }

    function test_Deposit_RevertIf_ZeroAmount() public {
        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.deposit(0, alice);
    }

    function test_Deposit_RevertIf_ZeroReceiver() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, address(0));
    }

    function test_Deposit_RevertIf_Paused() public {
        vault.pause();

        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
    }

    function test_FirstDeposit_RevertIf_TooSmall() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.FirstDepositTooSmall.selector, 1000, 999));
        vm.prank(alice);
        vault.deposit(999, alice);
    }

    function testFuzz_FirstDeposit_SuccessIf_MinimumMet(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        uint256 expectedShares = amount * 10 ** vault.OFFSET();

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), shares);
    }
}
