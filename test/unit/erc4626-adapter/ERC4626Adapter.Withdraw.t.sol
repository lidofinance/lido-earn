// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "src/Vault.sol";
import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterWithdrawTest is ERC4626AdapterTestBase {
    /// @notice Fuzzes that withdraw leaves positive shares.
    /// @dev Validates that withdraw leaves positive shares.
    function testFuzz_Withdraw_LeavesPositiveShares(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 2, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets - 1);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        uint256 initialShares = vault.deposit(depositAssets, alice);

        uint256 sharesBurned = vault.previewWithdraw(withdrawAssets);

        vm.prank(alice);
        vault.withdraw(withdrawAssets, alice, alice);

        uint256 remainingShares = vault.balanceOf(alice);

        assertGt(remainingShares, 0);
        assertEq(initialShares, sharesBurned + remainingShares);
    }

    /// @notice Fuzzes withdraw emits the expected event.
    /// @dev Verifies the emitted event data matches the scenario.
    function testFuzz_Withdraw_EmitsEvent(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        vm.expectEmit(true, true, true, false);
        emit Withdrawn(alice, alice, alice, withdrawAssets, 0);

        vm.prank(alice);
        vault.withdraw(withdrawAssets, alice, alice);
    }

    /// @notice Fuzzes that withdraw reverts when insufficient shares.
    /// @dev Verifies the revert protects against insufficient shares.
    function testFuzz_Withdraw_RevertIf_InsufficientShares(uint96 depositAmount, uint96 requestedAssets) public {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max - 1);
        uint256 requestAssets = bound(uint256(requestedAssets), depositAssets + 1, type(uint96).max);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 sharesRequested = vault.convertToShares(requestAssets);

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientShares.selector, sharesRequested, shares));
        vm.prank(alice);
        vault.withdraw(requestAssets, alice, alice);
    }

    /// @notice Fuzzes that withdraw reverts when insufficient liquidity.
    /// @dev Verifies the revert protects against insufficient liquidity.
    function testFuzz_Withdraw_RevertIf_InsufficientLiquidity(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 10, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 10, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        uint256 cap = withdrawAssets - 1;
        targetVault.setLiquidityCap(cap);

        vm.expectRevert(abi.encodeWithSelector(ERC4626Adapter.TargetVaultInsufficientLiquidity.selector, withdrawAssets, cap));

        vm.prank(alice);
        vault.withdraw(withdrawAssets, alice, alice);
    }

    /// @notice Fuzzes that redeem all shares.
    /// @dev Validates that redeem all shares.
    function testFuzz_Redeem_AllShares(uint96 depositAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        uint256 totalShares = vault.deposit(depositAssets, alice);

        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(totalShares, alice, alice);
        uint256 expectedAssets = vault.previewRedeem(totalShares);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), 0);
        assertApproxEqAbs(usdc.balanceOf(alice) - balanceBefore, assets, 2);
    }

    /// @notice Fuzzes that withdraw delegated with approval.
    /// @dev Validates that withdraw delegated with approval.
    function testFuzz_Withdraw_DelegatedWithApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        uint256 requiredShares = vault.previewWithdraw(withdrawAssets);

        vm.prank(alice);
        vault.approve(bob, requiredShares);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(withdrawAssets, bob, alice);

        uint256 bobUsdcAfter = usdc.balanceOf(bob);
        uint256 aliceSharesAfter = vault.balanceOf(alice);

        assertEq(sharesBurned, requiredShares);
        assertEq(aliceSharesAfter, aliceSharesBefore - sharesBurned);
        assertApproxEqAbs(bobUsdcAfter - bobUsdcBefore, withdrawAssets, 2);
        assertEq(vault.allowance(alice, bob), 0);
    }

    /// @notice Fuzzes that withdraw delegated revert if insufficient allowance.
    /// @dev Validates that withdraw delegated revert if insufficient allowance.
    function testFuzz_Withdraw_DelegatedRevertIf_InsufficientAllowance(uint96 depositAmount, uint96 withdrawAmount)
        public
    {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        uint256 requiredShares = vault.previewWithdraw(withdrawAssets);

        vm.prank(alice);
        vault.approve(bob, requiredShares - 1);

        vm.expectRevert();
        vm.prank(bob);
        vault.withdraw(withdrawAssets, bob, alice);
    }

    /// @notice Fuzzes that withdraw delegated revert if no approval.
    /// @dev Validates that withdraw delegated revert if no approval.
    function testFuzz_Withdraw_DelegatedRevertIf_NoApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        vm.expectRevert();
        vm.prank(bob);
        vault.withdraw(withdrawAssets, bob, alice);
    }

    /// @notice Fuzzes that withdraw self does not require approval.
    /// @dev Validates that withdraw self does not require approval.
    function testFuzz_Withdraw_SelfDoesNotRequireApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        uint256 expectedShares = vault.previewWithdraw(withdrawAssets);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAssets, alice, alice);

        uint256 aliceUsdcAfter = usdc.balanceOf(alice);

        assertEq(sharesBurned, expectedShares);
        assertApproxEqAbs(aliceUsdcAfter - aliceUsdcBefore, withdrawAssets, 2);
    }

    /// @notice Fuzzes that withdraw delegated with unlimited approval.
    /// @dev Validates that withdraw delegated with unlimited approval.
    function testFuzz_Withdraw_DelegatedWithUnlimitedApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), 1, type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        vm.prank(alice);
        vault.approve(bob, type(uint256).max);

        uint256 expectedShares = vault.previewWithdraw(withdrawAssets);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(withdrawAssets, bob, alice);

        uint256 bobUsdcAfter = usdc.balanceOf(bob);

        assertEq(sharesBurned, expectedShares);
        assertApproxEqAbs(bobUsdcAfter - bobUsdcBefore, withdrawAssets, 2);
        assertEq(vault.allowance(alice, bob), type(uint256).max);
    }
}
