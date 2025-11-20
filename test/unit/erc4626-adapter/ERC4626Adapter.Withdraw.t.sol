// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "src/Vault.sol";
import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterWithdrawTest is ERC4626AdapterTestBase {
    function testFuzz_Withdraw_LeavesPositiveShares(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_Withdraw_EmitsEvent(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        vm.expectEmit(true, true, true, false);
        emit Withdrawn(alice, alice, alice, withdrawAssets, 0);

        vm.prank(alice);
        vault.withdraw(withdrawAssets, alice, alice);
    }

    function testFuzz_Withdraw_RevertIf_InsufficientShares(uint96 depositAmount, uint96 requestedAssets) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max - 1);
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

    function testFuzz_Withdraw_RevertIf_InsufficientLiquidity(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 2, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        uint256 cap = withdrawAssets - 1;
        targetVault.setLiquidityCap(cap);

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, withdrawAssets, cap));

        vm.prank(alice);
        vault.withdraw(withdrawAssets, alice, alice);
    }

    function testFuzz_Redeem_AllShares(uint96 depositAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_Withdraw_DelegatedWithApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_Withdraw_DelegatedRevertIf_InsufficientAllowance(uint96 depositAmount, uint96 withdrawAmount)
        public
    {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_Withdraw_DelegatedRevertIf_NoApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        uint256 withdrawAssets = bound(uint256(withdrawAmount), 1, depositAssets);
        usdc.mint(alice, depositAssets);

        vm.prank(alice);
        vault.deposit(depositAssets, alice);

        vm.expectRevert();
        vm.prank(bob);
        vault.withdraw(withdrawAssets, bob, alice);
    }

    function testFuzz_Withdraw_SelfDoesNotRequireApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_Withdraw_DelegatedWithUnlimitedApproval(uint96 depositAmount, uint96 withdrawAmount) public {
        uint256 depositAssets = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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
