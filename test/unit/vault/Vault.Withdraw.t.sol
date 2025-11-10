// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract VaultWithdrawTest is VaultTestBase {
    function test_Withdraw_Basic() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);

        assertEq(shares, expectedShares);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, withdrawAmount);
    }

    function test_Withdraw_RevertIf_ZeroAmount() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.withdraw(0, alice, alice);
    }

    function test_Withdraw_RevertIf_ZeroReceiver() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.withdraw(10_000e6, address(0), alice);
    }

    function test_Withdraw_DoesNotBurnAllShares() public {
        vm.prank(alice);
        uint256 initialShares = vault.deposit(50_000e6, alice);

        uint256 withdrawAmount = 5_000e6;
        uint256 sharesBurned = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        uint256 remainingShares = vault.balanceOf(alice);
        uint256 expectedRemainingShares = initialShares - sharesBurned;

        assertEq(remainingShares, expectedRemainingShares);
        assertApproxEqRel(remainingShares, (initialShares * 9) / 10, 2);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(alice, alice, alice, withdrawAmount, expectedShares);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
    }

    function test_Withdraw_RevertIf_InsufficientShares() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 sharesRequested = vault.convertToShares(20_000e6);

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientShares.selector, sharesRequested, shares));
        vm.prank(alice);
        vault.withdraw(20_000e6, alice, alice);
    }

    function test_Withdraw_RevertIf_ProtocolReturnsLessAssets() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        vault.setForcedShortfall(1);

        uint256 withdrawAmount = 10_000e6;
        uint256 returnedAmount = withdrawAmount - 1;

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, withdrawAmount, returnedAmount));
        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
    }

    function test_Withdraw_DelegatedWithApproval() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 requiredShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.approve(bob, requiredShares);

        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, bob, alice);

        uint256 bobAssetAfter = asset.balanceOf(bob);
        uint256 aliceSharesAfter = vault.balanceOf(alice);

        assertEq(sharesBurned, requiredShares);
        assertEq(aliceSharesAfter, aliceSharesBefore - sharesBurned);
        assertEq(bobAssetAfter - bobAssetBefore, withdrawAmount);
        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_Withdraw_DelegatedRevertIf_InsufficientAllowance() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 requiredShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.approve(bob, requiredShares - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, bob, requiredShares - 1, requiredShares
            )
        );
        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, alice);
    }

    function test_Withdraw_DelegatedRevertIf_NoApproval() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 requiredShares = vault.previewWithdraw(withdrawAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, requiredShares)
        );
        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, alice);
    }

    function test_Withdraw_WorksWhenPaused() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.pause();

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(5_000e6, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 5_000e6);
    }

    function test_Withdraw_SelfDoesNotRequireApproval() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        uint256 aliceAssetBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceAssetAfter = asset.balanceOf(alice);

        assertEq(sharesBurned, expectedShares);
        assertEq(aliceAssetAfter - aliceAssetBefore, withdrawAmount);
    }

    function test_Withdraw_DelegatedWithUnlimitedApproval() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vm.prank(alice);
        vault.approve(bob, type(uint256).max);

        uint256 withdrawAmount = 10_000e6;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        uint256 bobAssetBefore = asset.balanceOf(bob);

        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, bob, alice);

        uint256 bobAssetAfter = asset.balanceOf(bob);

        assertEq(sharesBurned, expectedShares);
        assertEq(bobAssetAfter - bobAssetBefore, withdrawAmount);
        assertEq(vault.allowance(alice, bob), type(uint256).max);
    }

    function test_Withdraw_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        asset.mint(address(vault), 20_000e6);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(10_000e6, alice, alice);

        uint256 assetsAfter = vault.totalAssets();

        assertEq(sharesBurned, vault.previewWithdraw(10_000e6));
        assertEq(vault.lastTotalAssets(), assetsAfter);
        assertEq(totalAssetsBefore - assetsAfter, 10_000e6);
    }

    function test_Redeem_Basic() public {
        vm.prank(alice);
        uint256 totalShares = vault.deposit(100_000e6, alice);

        uint256 sharesToRedeem = totalShares / 10;
        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(sharesToRedeem, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);

        assertEq(assets, expectedAssets);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, assets);
        assertEq(vault.balanceOf(alice), totalShares - sharesToRedeem);
    }

    function test_Redeem_AllShares() public {
        vm.prank(alice);
        uint256 totalShares = vault.deposit(100_000e6, alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(totalShares, alice, alice);
        uint256 expectedAssets = vault.previewRedeem(totalShares);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(asset.balanceOf(alice), INITIAL_BALANCE);
    }

    function test_Redeem_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        uint256 totalShares = vault.deposit(100_000e6, alice);

        asset.mint(address(vault), 20_000e6);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 sharesToRedeem = totalShares / 4;

        vm.prank(alice);
        uint256 assetsRedeemed = vault.redeem(sharesToRedeem, alice, alice);

        assertEq(vault.lastTotalAssets(), vault.totalAssets());
        assertEq(vault.totalAssets(), totalAssetsBefore - assetsRedeemed);
    }

    function test_Redeem_RevertIf_ZeroShares() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.redeem(0, alice, alice);
    }

    function test_Redeem_RevertIf_ZeroReceiver() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.redeem(shares / 2, address(0), alice);
    }

    function test_Redeem_RevertIf_NoApproval() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        uint256 sharesToRedeem = shares / 10;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, sharesToRedeem)
        );
        vm.prank(bob);
        vault.redeem(sharesToRedeem, bob, alice);
    }

    function test_Redeem_DelegatedWithApproval() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100_000e6, alice);

        uint256 sharesToRedeem = shares / 10;
        vm.prank(alice);
        vault.approve(bob, sharesToRedeem);

        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(bob);
        uint256 assets = vault.redeem(sharesToRedeem, bob, alice);

        assertEq(assets, vault.previewRedeem(sharesToRedeem));
        assertEq(vault.balanceOf(alice), aliceSharesBefore - sharesToRedeem);
        assertEq(vault.allowance(alice, bob), 0);
        assertEq(asset.balanceOf(bob) - bobAssetBefore, assets);
    }

    function test_Redeem_WorksWhenPaused() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        vault.pause();

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares / 10, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, assets);
        assertGt(assets, 0);
    }

    function test_Redeem_RevertIf_InsufficientShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientShares.selector, shares + 1, shares));

        vm.prank(alice);
        vault.redeem(shares + 1, alice, alice);
    }

    function test_PreviewWithdraw_Accurate() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 previewedShares = vault.previewWithdraw(10_000e6);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(10_000e6, alice, alice);

        assertEq(previewedShares, actualShares);
    }

    function test_MaxWithdraw() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);

        assertEq(maxWithdraw, 100_000e6);
    }

    function test_DepositWithdraw_RoundingDoesNotCauseLoss() public {
        vm.prank(alice);
        vault.deposit(1000, alice);

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(asset.balanceOf(alice), INITIAL_BALANCE);
    }

    function test_MultipleDepositsWithdraws_MaintainsAccounting() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            vault.deposit(10_000e6, alice);
        }

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            vault.withdraw(10_000e6, alice, alice);
        }

        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        assertEq(assets, 20_000e6);
    }

    function test_TotalAssets() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        uint256 vaultTotalAssets = vault.totalAssets();

        assertEq(vaultTotalAssets, 50_000e6);
    }

    /* ========== FUZZING TESTS ========== */

    // Fuzz test for withdraw after deposit
    function testFuzz_Withdraw_Success(uint96 depositAmount, uint96 withdrawAmount) public {
        // Bound depositAmount
        depositAmount = uint96(bound(depositAmount, 1000, type(uint96).max));

        // Withdraw must be <= deposit
        vm.assume(withdrawAmount <= depositAmount);
        vm.assume(withdrawAmount > 0);

        // Mint additional tokens to alice if needed
        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        // Deposit first
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        // Withdraw
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);

        // Verify shares burned correctly
        assertEq(sharesBurned, expectedShares);

        // Verify balance changed correctly
        assertEq(aliceBalanceAfter - aliceBalanceBefore, withdrawAmount);

        // Verify remaining shares
        assertEq(vault.balanceOf(alice), shares - sharesBurned);
    }

    // Fuzz test for redeem after deposit
    function testFuzz_Redeem_Success(uint96 depositAmount, uint96 sharesToRedeem) public {
        // Bound depositAmount to ensure meaningful shares
        depositAmount = uint96(bound(depositAmount, 10_000e6, type(uint96).max));

        // Mint additional tokens to alice if needed
        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        // Deposit first
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Shares to redeem must be at least 1% of shares to avoid zero asset rounding
        sharesToRedeem = uint96(bound(sharesToRedeem, shares / 100, shares));

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);

        // Skip if redeem would result in 0 assets
        vm.assume(expectedAssets > 0);

        // Redeem
        vm.prank(alice);
        uint256 assets = vault.redeem(sharesToRedeem, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);

        // Verify assets received correctly
        assertEq(assets, expectedAssets);

        // Verify balance changed correctly
        assertEq(aliceBalanceAfter - aliceBalanceBefore, assets);

        // Verify remaining shares
        assertEq(vault.balanceOf(alice), shares - sharesToRedeem);
    }

    // Fuzz test for multiple users depositing and one withdrawing
    function testFuzz_Withdraw_WithMultipleUsers(uint96 deposit1, uint96 deposit2, uint96 withdraw1) public {
        // Bound deposits
        deposit1 = uint96(bound(deposit1, 1000, type(uint96).max / 2));
        deposit2 = uint96(bound(deposit2, 1000, type(uint96).max / 2));

        // Mint additional tokens if needed
        if (deposit1 > INITIAL_BALANCE) {
            asset.mint(alice, deposit1 - INITIAL_BALANCE);
        }
        if (deposit2 > INITIAL_BALANCE) {
            asset.mint(bob, deposit2 - INITIAL_BALANCE);
        }

        // Both users deposit
        vm.prank(alice);
        vault.deposit(deposit1, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(deposit2, bob);

        // Alice withdraws part of her deposit
        vm.assume(withdraw1 <= deposit1);
        vm.assume(withdraw1 > 0);

        vm.prank(alice);
        vault.withdraw(withdraw1, alice, alice);

        // Verify Bob's shares weren't affected
        assertEq(vault.balanceOf(bob), bobShares);

        // Verify total assets decreased by withdraw amount
        assertEq(vault.totalAssets(), deposit1 + deposit2 - withdraw1);
    }

    // Fuzz test that rounding favors the vault on withdraw
    function testFuzz_Withdraw_RoundingFavorsVault(uint96 depositAmount, uint96 withdrawAmount) public {
        // Bound depositAmount
        depositAmount = uint96(bound(depositAmount, 10_000e6, type(uint96).max / 2));

        // Mint additional tokens if needed
        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Withdraw must be less than deposit
        withdrawAmount = uint96(bound(withdrawAmount, 100, depositAmount - 100));

        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);

        // User should burn more than or equal to previewed shares (rounding favors vault)
        assertGe(actualShares, previewedShares);

        // Should be very close (allow small rounding difference)
        assertApproxEqAbs(actualShares, previewedShares, 2);
    }

    // Fuzz test that rounding favors the vault on redeem
    function testFuzz_Redeem_RoundingFavorsVault(uint96 depositAmount, uint96 sharesToRedeem) public {
        // Bound depositAmount
        depositAmount = uint96(bound(depositAmount, 10_000e6, type(uint96).max / 2));

        // Mint additional tokens if needed
        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Shares to redeem must be meaningful portion of shares
        sharesToRedeem = uint96(bound(sharesToRedeem, shares / 1000, shares - (shares / 1000)));

        uint256 previewedAssets = vault.previewRedeem(sharesToRedeem);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(sharesToRedeem, alice, alice);

        // User should receive less than or equal to previewed assets (rounding favors vault)
        assertLe(actualAssets, previewedAssets);

        // Should be very close (allow small rounding difference)
        assertApproxEqAbs(actualAssets, previewedAssets, 2);
    }

    /* ========== COVERAGE TESTS FOR EDGE CASES ========== */

    /// @dev Coverage: Vault.sol line 169 - if (sharesBurned == 0) revert ZeroAmount();
    /// @notice Tests that withdraw reverts when previewWithdraw returns 0 shares
    function test_Withdraw_RevertIf_SharesBurnedIsZero() public {
        // Setup: Make a deposit first
        vm.prank(alice);
        vault.deposit(10000, alice);

        // Force previewWithdraw to return 0
        MockVault(address(vault)).setForceZeroPreviewWithdraw(true);

        // Try to withdraw - should revert with ZeroAmount
        vm.startPrank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.withdraw(5000, alice, alice);
        vm.stopPrank();
    }
}
