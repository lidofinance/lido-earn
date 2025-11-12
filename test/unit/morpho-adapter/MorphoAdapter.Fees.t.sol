// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vm} from "forge-std/Vm.sol";
import {Vault} from "src/Vault.sol";
import "./MorphoAdapterTestBase.sol";

contract MorphoAdapterFeesTest is MorphoAdapterTestBase {
    /* ========== SET REWARD FEE TESTS ========== */

    function test_SetRewardFee_Basic() public {
        uint16 newFee = 1000;

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    function test_SetRewardFee_ToZero() public {
        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, 0);

        vault.setRewardFee(0);

        assertEq(vault.rewardFee(), 0);
    }

    function test_SetRewardFee_ToMaximum() public {
        uint16 newFee = uint16(vault.MAX_REWARD_FEE_BASIS_POINTS());

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    function test_SetRewardFee_RevertIf_ExceedsMaximum() public {
        uint16 invalidFee = uint16(vault.MAX_REWARD_FEE_BASIS_POINTS() + 1);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidFee.selector, invalidFee));
        vault.setRewardFee(invalidFee);
    }

    function test_SetRewardFee_RevertIf_NotFeeManager() public {
        uint16 newFee = 1000;

        vm.expectRevert();
        vm.prank(alice);
        vault.setRewardFee(newFee);
    }

    function test_SetRewardFee_HarvestsFeesBeforeChange() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 10_000e6);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vault.setRewardFee(1000);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertGt(treasurySharesAfter, treasurySharesBefore);
    }

    function test_SetRewardFee_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 10_000e6);

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();

        vault.setRewardFee(1000);

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertGt(lastTotalAssetsAfter, lastTotalAssetsBefore);
        assertApproxEqAbs(lastTotalAssetsAfter, vault.totalAssets(), 1);
    }

    function test_SetRewardFee_WithFeeManagerRole() public {
        address feeManager = makeAddr("feeManager");
        vault.grantRole(vault.MANAGER_ROLE(), feeManager);

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

        uint256 profit = 10_000e6;
        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + profit);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertGt(treasurySharesAfter, initialTreasuryShares);
    }

    function test_HarvestFees_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + profit);

        vm.recordLogs();
        vault.harvestFees();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("FeesHarvested(uint256,uint256,uint256)")) {
                found = true;
                break;
            }
        }

        assertTrue(found);
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

        uint256 currentBalance = usdc.balanceOf(address(morpho));
        deal(address(usdc), address(morpho), currentBalance - 5_000e6);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        assertEq(treasurySharesAfter, treasurySharesBefore);
    }

    function test_HarvestFees_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 10_000e6);

        uint256 totalAssetsBefore = vault.totalAssets();

        vault.harvestFees();

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertApproxEqAbs(lastTotalAssetsAfter, totalAssetsBefore, 1);
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

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 5_000e6);
        vault.harvestFees();
        uint256 treasurySharesAfterFirst = vault.balanceOf(treasury);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 3_000e6);
        vault.harvestFees();
        uint256 treasurySharesAfterSecond = vault.balanceOf(treasury);

        assertGt(treasurySharesAfterFirst, 0);
        assertGt(treasurySharesAfterSecond, treasurySharesAfterFirst);
    }

    function test_HarvestFees_CalledAutomaticallyOnDeposit() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 10_000e6);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vm.prank(bob);
        vault.deposit(50_000e6, bob);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertGt(treasurySharesAfter, treasurySharesBefore);
    }

    function test_HarvestFees_CalledAutomaticallyOnWithdraw() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 10_000e6);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vm.prank(alice);
        vault.withdraw(50_000e6, alice, alice);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        assertGt(treasurySharesAfter, treasurySharesBefore);
    }

    /* ========== PENDING FEES TESTS ========== */

    function test_GetPendingFees_WithProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + profit);

        uint256 expectedFeeAmount = (profit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();

        uint256 pendingFees = vault.getPendingFees();
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

        uint256 currentBalance = usdc.balanceOf(address(morpho));
        deal(address(usdc), address(morpho), currentBalance - 5_000e6);

        uint256 pendingFees = vault.getPendingFees();
        assertEq(pendingFees, 0);
    }

    function test_GetPendingFees_AfterHarvest() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 10_000e6);

        uint256 pendingFeesBefore = vault.getPendingFees();
        assertGt(pendingFeesBefore, 0);

        vault.harvestFees();

        uint256 pendingFeesAfter = vault.getPendingFees();
        assertEq(pendingFeesAfter, 0);
    }
}
