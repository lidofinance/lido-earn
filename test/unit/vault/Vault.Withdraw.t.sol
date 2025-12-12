// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract VaultWithdrawTest is VaultTestBase {
    /// @notice Exercises standard withdraw happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
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

    /// @notice Ensures withdraw reverts when zero amount.
    /// @dev Verifies the revert protects against zero amount.
    function test_Withdraw_RevertIf_ZeroAmount() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidAssetsAmount.selector, 0, 0));
        vm.prank(alice);
        vault.withdraw(0, alice, alice);
    }

    /// @notice Ensures withdraw reverts when zero receiver.
    /// @dev Verifies the revert protects against zero receiver.
    function test_Withdraw_RevertIf_ZeroReceiver() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidReceiverAddress.selector, address(0)));
        vm.prank(alice);
        vault.withdraw(10_000e6, address(0), alice);
    }

    /// @notice Tests that withdraw does not burn all shares.
    /// @dev Validates that withdraw does not burn all shares.
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

    /// @notice Checks withdraw emits the expected event.
    /// @dev Verifies the emitted event data matches the scenario.
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

    /// @notice Ensures withdraw reverts when insufficient shares.
    /// @dev Verifies the revert protects against insufficient shares.
    function test_Withdraw_RevertIf_InsufficientShares() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 sharesRequested = vault.convertToShares(20_000e6);

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientShares.selector, sharesRequested, shares));
        vm.prank(alice);
        vault.withdraw(20_000e6, alice, alice);
    }

    /// @notice Tests that withdraw delegated with approval.
    /// @dev Validates that withdraw delegated with approval.
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

    /// @notice Tests that withdraw delegated revert if insufficient allowance.
    /// @dev Validates that withdraw delegated revert if insufficient allowance.
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

    /// @notice Tests that withdraw delegated revert if no approval.
    /// @dev Validates that withdraw delegated revert if no approval.
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

    /// @notice Tests that withdraw works when paused.
    /// @dev Validates that withdraw works when paused.
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

    /// @notice Tests that withdraw self does not require approval.
    /// @dev Validates that withdraw self does not require approval.
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

    /// @notice Tests that withdraw delegated with unlimited approval.
    /// @dev Validates that withdraw delegated with unlimited approval.
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

    /// @notice Tests that withdraw updates last total assets.
    /// @dev Validates that withdraw updates last total assets.
    function test_Withdraw_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        asset.mint(address(vault), 20_000e6);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(10_000e6, alice, alice);

        uint256 assetsAfter = vault.totalAssets();

        assertApproxEqAbs(
            sharesBurned, vault.previewWithdraw(10_000e6), 1, "SharesBurned should match preview within 1 wei"
        );
        assertEq(vault.lastTotalAssets(), assetsAfter);
        assertEq(totalAssetsBefore - assetsAfter, 10_000e6);
    }

    /// @notice Exercises standard redeem happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
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

    /// @notice Tests that redeem all shares.
    /// @dev Validates that redeem all shares.
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

    /// @notice Tests that redeem updates last total assets.
    /// @dev Validates that redeem updates last total assets.
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

    /// @notice Ensures redeem reverts when zero shares.
    /// @dev Verifies the revert protects against zero shares.
    function test_Redeem_RevertIf_ZeroShares() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidSharesAmount.selector, 0, 0));
        vm.prank(alice);
        vault.redeem(0, alice, alice);
    }

    /// @notice Ensures redeem reverts when zero receiver.
    /// @dev Verifies the revert protects against zero receiver.
    function test_Redeem_RevertIf_ZeroReceiver() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidReceiverAddress.selector, address(0)));
        vm.prank(alice);
        vault.redeem(shares / 2, address(0), alice);
    }

    /// @notice Ensures redeem reverts when no approval.
    /// @dev Verifies the revert protects against no approval.
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

    /// @notice Tests that redeem delegated with approval.
    /// @dev Validates that redeem delegated with approval.
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

    /// @notice Tests that redeem works when paused.
    /// @dev Validates that redeem works when paused.
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

    /// @notice Ensures redeem reverts when insufficient shares.
    /// @dev Verifies the revert protects against insufficient shares.
    function test_Redeem_RevertIf_InsufficientShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientShares.selector, shares + 1, shares));

        vm.prank(alice);
        vault.redeem(shares + 1, alice, alice);
    }

    /// @notice Tests that preview withdraw accurate.
    /// @dev Validates that preview withdraw accurate.
    function test_PreviewWithdraw_Accurate() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 previewedShares = vault.previewWithdraw(10_000e6);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(10_000e6, alice, alice);

        assertEq(previewedShares, actualShares);
    }

    /// @notice Tests that preview withdraw with pending fees.
    /// @dev Validates that preview withdraw with pending fees.
    function test_PreviewWithdraw_WithPendingFees() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 previewedShares = vault.previewWithdraw(50_000e6);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(50_000e6, alice, alice);

        assertEq(actualShares, previewedShares, "Preview should match actual shares burned");
    }

    /// @notice Tests that preview redeem with pending fees accurate.
    /// @dev Validates that preview redeem with pending fees accurate.
    function test_PreviewRedeem_WithPendingFees_Accurate() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 sharesToRedeem = vault.balanceOf(alice) / 2;
        uint256 previewedAssets = vault.previewRedeem(sharesToRedeem);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(sharesToRedeem, alice, alice);

        assertApproxEqAbs(actualAssets, previewedAssets, 2, "Preview should match actual assets received");
    }

    /// @notice Tests that max withdraw.
    /// @dev Validates that max withdraw.
    function test_MaxWithdraw() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);

        assertApproxEqAbs(maxWithdraw, 100_000e6, 2);
    }

    /// @notice Tests that max withdraw with pending fees should not revert.
    /// @dev Validates that max withdraw with pending fees should not revert.
    function test_MaxWithdraw_WithPendingFees_ShouldNotRevert() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6; // 10% profit
        asset.mint(address(vault), profit);

        uint256 maxWithdrawValue = vault.maxWithdraw(alice);

        vm.prank(alice);
        vault.withdraw(maxWithdrawValue, alice, alice);
    }

    /// @notice Fuzzes that max withdraw is actually withdrawable.
    /// @dev Validates that max withdraw is actually withdrawable.
    function testFuzz_MaxWithdraw_IsActuallyWithdrawable(uint96 depositAmount, uint96 profitAmount, uint16 rewardFeeBps)
        public
    {
        depositAmount = uint96(bound(depositAmount, 1001e6, 1_000_000e6));
        profitAmount = uint96(bound(profitAmount, 0, depositAmount));
        rewardFeeBps = uint16(bound(rewardFeeBps, 0, 2000));

        vm.assume(rewardFeeBps != vault.rewardFee());

        vault.setRewardFee(rewardFeeBps);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        if (profitAmount > 0) {
            asset.mint(address(vault), profitAmount);
        }

        uint256 maxWithdrawValue = vault.maxWithdraw(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 aliceAssetsBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(maxWithdrawValue, alice, alice);

        uint256 aliceSharesAfter = vault.balanceOf(alice);
        uint256 aliceAssetsAfter = asset.balanceOf(alice);

        assertEq(aliceAssetsAfter - aliceAssetsBefore, maxWithdrawValue);
        assertEq(aliceSharesBefore - aliceSharesAfter, sharesBurned);

        assertApproxEqAbs(vault.maxWithdraw(alice), 1, 2);

        if (aliceSharesAfter > 0) {
            uint256 remainingAssetValue = vault.convertToAssets(aliceSharesAfter);
            assertLe(remainingAssetValue, 1);
        }
    }

    /// @notice Tests that deposit withdraw rounding does not cause loss.
    /// @dev Validates that deposit withdraw rounding does not cause loss.
    function test_DepositWithdraw_RoundingDoesNotCauseLoss() public {
        vm.prank(alice);
        vault.deposit(1000, alice);

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(asset.balanceOf(alice), INITIAL_BALANCE);
    }

    /// @notice Tests that multiple deposits withdraws maintains accounting.
    /// @dev Validates that multiple deposits withdraws maintains accounting.
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

    /// @notice Tests that total assets.
    /// @dev Validates that total assets.
    function test_TotalAssets() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        uint256 vaultTotalAssets = vault.totalAssets();

        assertEq(vaultTotalAssets, 50_000e6);
    }

    /* ========== FUZZING TESTS ========== */

    // Fuzz test for withdraw after deposit
    /// @notice Fuzzes that withdraw success.
    /// @dev Validates that withdraw success.
    function testFuzz_Withdraw_Success(uint96 depositAmount, uint96 withdrawAmount) public {
        depositAmount = uint96(bound(depositAmount, 1000, type(uint96).max));
        withdrawAmount = uint96(bound(withdrawAmount, 1, depositAmount));

        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);

        assertEq(sharesBurned, expectedShares);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, withdrawAmount);
        assertEq(vault.balanceOf(alice), shares - sharesBurned);
    }

    /// @notice Fuzzes that redeem success.
    /// @dev Validates that redeem success.
    function testFuzz_Redeem_Success(uint96 depositAmount, uint96 sharesToRedeem) public {
        depositAmount = uint96(bound(depositAmount, 10_000e6, type(uint96).max));

        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        sharesToRedeem = uint96(bound(sharesToRedeem, shares / 100, shares));

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);

        // Если expectedAssets == 0 из-за округления, пропускаем тест
        if (expectedAssets == 0) return;

        vm.prank(alice);
        uint256 assets = vault.redeem(sharesToRedeem, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);

        assertEq(assets, expectedAssets);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, assets);
        assertEq(vault.balanceOf(alice), shares - sharesToRedeem);
    }

    /// @notice Fuzzes that withdraw with multiple users.
    /// @dev Validates that withdraw with multiple users.
    function testFuzz_Withdraw_WithMultipleUsers(uint96 deposit1, uint96 deposit2, uint96 withdraw1) public {
        deposit1 = uint96(bound(deposit1, 1000, type(uint96).max / 2));
        deposit2 = uint96(bound(deposit2, 1000, type(uint96).max / 2));

        if (deposit1 > INITIAL_BALANCE) {
            asset.mint(alice, deposit1 - INITIAL_BALANCE);
        }
        if (deposit2 > INITIAL_BALANCE) {
            asset.mint(bob, deposit2 - INITIAL_BALANCE);
        }

        vm.prank(alice);
        vault.deposit(deposit1, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(deposit2, bob);

        withdraw1 = uint96(bound(withdraw1, 1, deposit1));

        vm.prank(alice);
        vault.withdraw(withdraw1, alice, alice);

        assertEq(vault.balanceOf(bob), bobShares);
        assertEq(vault.totalAssets(), deposit1 + deposit2 - withdraw1);
    }

    /// @notice Fuzzes that withdraw rounding favors vault.
    /// @dev Validates that withdraw rounding favors vault.
    function testFuzz_Withdraw_RoundingFavorsVault(uint96 depositAmount, uint96 withdrawAmount) public {
        depositAmount = uint96(bound(depositAmount, 10_000e6, type(uint96).max / 2));

        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        withdrawAmount = uint96(bound(withdrawAmount, 100, depositAmount - 100));

        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);

        assertGe(actualShares, previewedShares);
        assertApproxEqAbs(actualShares, previewedShares, 2);
    }

    /// @notice Fuzzes that redeem rounding favors vault.
    /// @dev Validates that redeem rounding favors vault.
    function testFuzz_Redeem_RoundingFavorsVault(uint96 depositAmount, uint96 sharesToRedeem) public {
        depositAmount = uint96(bound(depositAmount, 10_000e6, type(uint96).max / 2));

        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        sharesToRedeem = uint96(bound(sharesToRedeem, shares / 1000, shares - (shares / 1000)));

        uint256 previewedAssets = vault.previewRedeem(sharesToRedeem);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(sharesToRedeem, alice, alice);

        assertLe(actualAssets, previewedAssets);
        assertApproxEqAbs(actualAssets, previewedAssets, 2);
    }
}
