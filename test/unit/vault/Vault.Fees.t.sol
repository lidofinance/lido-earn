// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultFeesTest is VaultTestBase {
    /* ========== SET REWARD FEE TESTS ========== */

    function test_SetRewardFee_Basic() public {
        uint16 newFee = 1000;

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    function test_SetRewardFee_ToZero() public {
        uint16 newFee = 0;

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), 0);
    }

    function test_SetRewardFee_ToMaximum() public {
        uint16 newFee = 2000;

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), 2000);
    }

    function test_SetRewardFee_RevertIf_ExceedsMaximum() public {
        uint16 invalidFee = 2001;

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidFee.selector, invalidFee));
        vault.setRewardFee(invalidFee);
    }

    function test_SetRewardFee_RevertIf_NotFeeManager() public {
        uint16 newFee = 1000;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.FEE_MANAGER_ROLE()
            )
        );
        vm.prank(alice);
        vault.setRewardFee(newFee);
    }

    function test_SetRewardFee_HarvestsFeesBeforeChange() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        assertEq(treasurySharesBefore, 0);

        uint256 expectedShares = _calculateExpectedFeeShares(profit);

        vault.setRewardFee(1000);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, expectedShares);
    }

    function test_SetRewardFee_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();
        assertEq(lastTotalAssetsBefore, 100_000e6);

        asset.mint(address(vault), 10_000e6);

        vault.setRewardFee(1000);

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertEq(lastTotalAssetsAfter, vault.totalAssets());
        assertEq(lastTotalAssetsAfter, 110_000e6);
    }

    function test_SetRewardFee_WithFeeManagerRole() public {
        address feeManager = makeAddr("feeManager");

        vault.grantRole(vault.FEE_MANAGER_ROLE(), feeManager);

        uint16 newFee = 1500;

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vm.prank(feeManager);
        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    function test_SetRewardFee_MultipleChanges() public {
        vault.setRewardFee(1000);
        assertEq(vault.rewardFee(), 1000);

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(1000, 1500);

        vault.setRewardFee(1500);
        assertEq(vault.rewardFee(), 1500);

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(1500, REWARD_FEE);

        vault.setRewardFee(REWARD_FEE);
        assertEq(vault.rewardFee(), REWARD_FEE);
    }

    /* ========== HARVEST FEES TESTS ========== */

    function test_HarvestFees_WithProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 initialTreasuryShares = vault.balanceOf(treasury);
        assertEq(initialTreasuryShares, 0);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 expectedShares = _calculateExpectedFeeShares(profit);
        uint256 expectedFeeAmount = (profit * REWARD_FEE) / vault.MAX_BASIS_POINTS();

        vm.expectEmit(false, false, false, true);
        emit Vault.FeesHarvested(profit, expectedFeeAmount, expectedShares);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, expectedShares);
    }

    function test_HarvestFees_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        vm.recordLogs();
        vault.harvestFees();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundFeesHarvestedEvent = false;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("FeesHarvested(uint256,uint256,uint256)")) {
                foundFeesHarvestedEvent = true;
                break;
            }
        }

        assertTrue(foundFeesHarvestedEvent);
    }

    function test_HarvestFees_NoProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertEq(treasurySharesAfter, treasurySharesBefore);
        assertEq(lastTotalAssetsAfter, lastTotalAssetsBefore);
    }

    function test_HarvestFees_WithLoss() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vm.prank(address(vault));
        asset.transfer(address(1), 5_000e6);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, treasurySharesBefore);
    }

    function test_HarvestFees_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        asset.mint(address(vault), 10_000e6);

        uint256 totalAssetsBefore = vault.totalAssets();

        vault.harvestFees();

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertEq(lastTotalAssetsAfter, totalAssetsBefore);
    }

    function test_HarvestFees_WhenTotalSupplyIsZero() public {
        assertEq(vault.totalSupply(), 0);

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();

        vault.harvestFees();

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertEq(lastTotalAssetsAfter, lastTotalAssetsBefore);
    }

    function test_HarvestFees_WhenTotalAssetsIsZero() public {
        assertEq(vault.totalAssets(), 0);

        vault.harvestFees();

        assertEq(vault.lastTotalAssets(), 0);
    }

    function test_HarvestFees_MultipleHarvests() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 firstProfit = 5_000e6;
        asset.mint(address(vault), firstProfit);

        uint256 expectedFirstShares = _calculateExpectedFeeShares(firstProfit);

        vault.harvestFees();
        uint256 treasurySharesAfterFirst = vault.balanceOf(treasury);

        assertEq(treasurySharesAfterFirst, expectedFirstShares);

        uint256 secondProfit = 3_000e6;
        asset.mint(address(vault), secondProfit);

        uint256 expectedSecondShares = _calculateExpectedFeeShares(secondProfit);

        vault.harvestFees();
        uint256 treasurySharesAfterSecond = vault.balanceOf(treasury);

        assertEq(treasurySharesAfterSecond, expectedFirstShares + expectedSecondShares);
    }

    function test_HarvestFees_CalledAutomaticallyOnDeposit() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        assertEq(treasurySharesBefore, 0);

        uint256 expectedShares = _calculateExpectedFeeShares(profit);

        vm.prank(bob);
        vault.deposit(50_000e6, bob);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, expectedShares);
    }

    function test_HarvestFees_CalledAutomaticallyOnWithdraw() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        assertEq(treasurySharesBefore, 0);

        uint256 expectedShares = _calculateExpectedFeeShares(profit);

        vm.prank(alice);
        vault.withdraw(10_000e6, alice, alice);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, expectedShares);
    }

    function test_HarvestFees_CalledAutomaticallyOnMint() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        assertEq(treasurySharesBefore, 0);

        uint256 profit = 3_000e6;
        asset.mint(address(vault), profit);

        uint256 expectedShares = _calculateExpectedFeeShares(profit);
        uint256 sharesToMint = vault.convertToShares(5_000e6);

        vm.prank(bob);
        vault.mint(sharesToMint, bob);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, expectedShares);
    }

    function test_HarvestFees_CalledAutomaticallyOnRedeem() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        assertEq(treasurySharesBefore, 0);

        uint256 expectedShares = _calculateExpectedFeeShares(profit);

        uint256 aliceShares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(aliceShares / 10, alice, alice);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, expectedShares);
    }

    function test_HarvestFees_CalculatesCorrectFeeAmount() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 expectedFeeAmount = (profit * REWARD_FEE) / vault.MAX_BASIS_POINTS();

        vault.harvestFees();

        uint256 treasuryShares = vault.balanceOf(treasury);
        uint256 treasuryAssets = vault.convertToAssets(treasuryShares);

        assertApproxEqAbs(treasuryAssets, expectedFeeAmount, 2);
    }

    function test_HarvestFees_WithZeroFee() public {
        vault.setRewardFee(0);

        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        asset.mint(address(vault), 10_000e6);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertEq(treasurySharesAfter, treasurySharesBefore);
    }

    function test_HarvestFees_WithMaxFee() public {
        vault.setRewardFee(2000);

        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 expectedFeeAmount = (profit * 2000) / vault.MAX_BASIS_POINTS();

        vault.harvestFees();

        uint256 treasuryShares = vault.balanceOf(treasury);
        uint256 treasuryAssets = vault.convertToAssets(treasuryShares);

        assertApproxEqAbs(treasuryAssets, expectedFeeAmount, 2);
    }

    function test_GetPendingFees_WithProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 pendingFees = vault.getPendingFees();
        uint256 expectedFeeAmount = (profit * REWARD_FEE) / vault.MAX_BASIS_POINTS();

        assertApproxEqAbs(pendingFees, expectedFeeAmount, 1);
    }

    function test_GetPendingFees_NoProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 pendingFees = vault.getPendingFees();

        assertEq(pendingFees, 0);
    }

    function test_GetPendingFees_WithLoss() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vm.prank(address(vault));
        asset.transfer(address(1), 5_000e6);

        uint256 pendingFees = vault.getPendingFees();

        assertEq(pendingFees, 0);
    }

    function test_GetPendingFees_AfterHarvest() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 pendingFeesBefore = vault.getPendingFees();
        uint256 expectedFeeAmount = (profit * REWARD_FEE) / vault.MAX_BASIS_POINTS();
        assertApproxEqAbs(pendingFeesBefore, expectedFeeAmount, 1);

        vault.harvestFees();

        uint256 pendingFeesAfter = vault.getPendingFees();
        assertEq(pendingFeesAfter, 0);
    }
}
