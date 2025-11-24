// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "src/Vault.sol";
import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterDepositTest is ERC4626AdapterTestBase {
    /// @notice Fuzzes deposit emits the expected event.
    /// @dev Verifies the emitted event data matches the scenario.
    function testFuzz_Deposit_EmitsEvent(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(true, true, false, true);
        emit Deposited(alice, alice, amount, expectedShares);

        vm.prank(alice);
        vault.deposit(amount, alice);
    }

    /// @notice Fuzzes deposit with multiple users.
    /// @dev Verifies accounting remains correct across participants.
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

    /// @notice Fuzzes that deposit updates target vault balance.
    /// @dev Validates that deposit updates target vault balance.
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

    /// @notice Ensures deposit reverts when target vault returns zero shares.
    /// @dev Verifies the revert protects against target vault returns zero shares.
    function test_Deposit_RevertIf_TargetVaultReturnsZeroShares() public {
        targetVault.setForceZeroDeposit(true);

        vm.expectRevert(ERC4626Adapter.TargetVaultDepositFailed.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        targetVault.setForceZeroDeposit(false);
    }

    /// @notice Ensures deposit reverts when zero amount.
    /// @dev Verifies the revert protects against zero amount.
    function test_Deposit_RevertIf_ZeroAmount() public {
        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.deposit(0, alice);
    }

    /// @notice Ensures deposit reverts when zero receiver.
    /// @dev Verifies the revert protects against zero receiver.
    function test_Deposit_RevertIf_ZeroReceiver() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, address(0));
    }

    /// @notice Ensures deposit reverts when paused.
    /// @dev Verifies the revert protects against paused.
    function test_Deposit_RevertIf_Paused() public {
        vault.pause();

        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
    }

    /// @notice Ensures first deposit reverts when too small.
    /// @dev Verifies the revert protects against too small.
    function test_FirstDeposit_RevertIf_TooSmall() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.FirstDepositTooSmall.selector, 1000, 999));
        vm.prank(alice);
        vault.deposit(999, alice);
    }

    /// @notice Fuzzes that first deposit success if minimum met.
    /// @dev Validates that first deposit success if minimum met.
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
