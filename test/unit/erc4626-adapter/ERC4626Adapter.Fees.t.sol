// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vm} from "forge-std/Vm.sol";
import {Vault} from "src/Vault.sol";
import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterFeesTest is ERC4626AdapterTestBase {
    /* ========== SET REWARD FEE TESTS ========== */

    /// @notice Exercises standard set reward fee happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
    function test_SetRewardFee_Basic() public {
        uint16 newFee = 1000;

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    /// @notice Fuzzes that set reward fee valid range.
    /// @dev Validates that set reward fee valid range.
    function testFuzz_SetRewardFee_ValidRange(uint16 newFee) public {
        newFee = uint16(bound(uint256(newFee), 0, vault.MAX_REWARD_FEE_BASIS_POINTS()));

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    /// @notice Tests that set reward fee to zero.
    /// @dev Validates that set reward fee to zero.
    function test_SetRewardFee_ToZero() public {
        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, 0);

        vault.setRewardFee(0);

        assertEq(vault.rewardFee(), 0);
    }

    /// @notice Tests that set reward fee to maximum.
    /// @dev Validates that set reward fee to maximum.
    function test_SetRewardFee_ToMaximum() public {
        uint16 newFee = uint16(vault.MAX_REWARD_FEE_BASIS_POINTS());

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, newFee);

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    /// @notice Ensures set reward fee reverts when exceeds maximum.
    /// @dev Verifies the revert protects against exceeds maximum.
    function test_SetRewardFee_RevertIf_ExceedsMaximum() public {
        uint16 invalidFee = uint16(vault.MAX_REWARD_FEE_BASIS_POINTS() + 1);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidFee.selector, invalidFee));
        vault.setRewardFee(invalidFee);
    }

    /// @notice Ensures set reward fee reverts when not fee manager.
    /// @dev Verifies the revert protects against not fee manager.
    function test_SetRewardFee_RevertIf_NotFeeManager() public {
        uint16 newFee = 1000;

        vm.expectRevert();
        vm.prank(alice);
        vault.setRewardFee(newFee);
    }

    /// @notice Tests that set reward fee harvests fees before change.
    /// @dev Validates that set reward fee harvests fees before change.
    function test_SetRewardFee_HarvestsFeesBeforeChange() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 10_000e6);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vault.setRewardFee(1000);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertGt(treasurySharesAfter, treasurySharesBefore);
    }

    /// @notice Tests that set reward fee updates last total assets.
    /// @dev Validates that set reward fee updates last total assets.
    function test_SetRewardFee_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 10_000e6);

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();

        vault.setRewardFee(1000);

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertGt(lastTotalAssetsAfter, lastTotalAssetsBefore);
        assertApproxEqAbs(lastTotalAssetsAfter, vault.totalAssets(), 1);
    }

    /// @notice Tests that set reward fee with fee manager role.
    /// @dev Validates that set reward fee with fee manager role.
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

    /// @notice Tests that set reward fee multiple changes.
    /// @dev Validates that set reward fee multiple changes.
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

    /// @notice Tests that harvest fees with profit.
    /// @dev Validates that harvest fees with profit.
    function test_HarvestFees_WithProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 initialTreasuryShares = vault.balanceOf(treasury);

        uint256 profit = 10_000e6;
        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + profit);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertGt(treasurySharesAfter, initialTreasuryShares);
    }

    /// @notice Fuzzes that harvest fees with profit.
    /// @dev Validates that harvest fees with profit.
    function testFuzz_HarvestFees_WithProfit(uint96 depositAmount, uint96 profitAmount) public {
        uint256 deposit = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        uint256 profit = bound(uint256(profitAmount), 100, type(uint96).max / 2); // Минимальный профит 100, max /2 для избежания overflow
        usdc.mint(alice, deposit);

        vm.prank(alice);
        vault.deposit(deposit, alice);

        uint256 initialTreasuryShares = vault.balanceOf(treasury);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + profit);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertGt(treasurySharesAfter, initialTreasuryShares);
    }

    /// @notice Checks harvest fees emits the expected event.
    /// @dev Verifies the emitted event data matches the scenario.
    function test_HarvestFees_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + profit);

        vm.recordLogs();
        vault.harvestFees();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("FeesHarvested(uint256)")) {
                found = true;
                break;
            }
        }

        assertTrue(found);
    }

    /// @notice Tests that harvest fees no profit.
    /// @dev Validates that harvest fees no profit.
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

    /// @notice Tests that harvest fees with loss.
    /// @dev Validates that harvest fees with loss.
    function test_HarvestFees_WithLoss() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        uint256 currentBalance = usdc.balanceOf(address(targetVault));
        deal(address(usdc), address(targetVault), currentBalance - 5_000e6);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        assertEq(treasurySharesAfter, treasurySharesBefore);
    }

    /// @notice Tests that harvest fees updates last total assets.
    /// @dev Validates that harvest fees updates last total assets.
    function test_HarvestFees_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 10_000e6);

        uint256 totalAssetsBefore = vault.totalAssets();

        vault.harvestFees();

        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertApproxEqAbs(lastTotalAssetsAfter, totalAssetsBefore, 1);
    }

    /// @notice Tests that harvest fees when total supply is zero.
    /// @dev Validates that harvest fees when total supply is zero.
    function test_HarvestFees_WhenTotalSupplyIsZero() public {
        assertEq(vault.totalSupply(), 0);

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();
        vault.harvestFees();
        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertEq(lastTotalAssetsAfter, lastTotalAssetsBefore);
    }

    /// @notice Tests that harvest fees when total assets is zero.
    /// @dev Validates that harvest fees when total assets is zero.
    function test_HarvestFees_WhenTotalAssetsIsZero() public {
        assertEq(vault.totalAssets(), 0);
        vault.harvestFees();
        assertEq(vault.lastTotalAssets(), 0);
    }

    /// @notice Tests that harvest fees multiple harvests.
    /// @dev Validates that harvest fees multiple harvests.
    function test_HarvestFees_MultipleHarvests() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 5_000e6);
        vault.harvestFees();
        uint256 treasurySharesAfterFirst = vault.balanceOf(treasury);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 3_000e6);
        vault.harvestFees();
        uint256 treasurySharesAfterSecond = vault.balanceOf(treasury);

        assertGt(treasurySharesAfterFirst, 0);
        assertGt(treasurySharesAfterSecond, treasurySharesAfterFirst);
    }

    /// @notice Tests that harvest fees called automatically on deposit.
    /// @dev Validates that harvest fees called automatically on deposit.
    function test_HarvestFees_CalledAutomaticallyOnDeposit() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 10_000e6);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vm.prank(bob);
        vault.deposit(50_000e6, bob);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);

        assertGt(treasurySharesAfter, treasurySharesBefore);
    }

    /// @notice Tests that harvest fees called automatically on withdraw.
    /// @dev Validates that harvest fees called automatically on withdraw.
    function test_HarvestFees_CalledAutomaticallyOnWithdraw() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 10_000e6);

        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vm.prank(alice);
        vault.withdraw(50_000e6, alice, alice);

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        assertGt(treasurySharesAfter, treasurySharesBefore);
    }

    /* ========== PENDING FEES TESTS ========== */

    /// @notice Tests that get pending fees with profit.
    /// @dev Validates that get pending fees with profit.
    function test_GetPendingFees_WithProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + profit);

        uint256 expectedFeeAmount = (profit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();

        uint256 pendingFees = vault.getPendingFees();
        assertApproxEqAbs(pendingFees, expectedFeeAmount, 1);
    }

    /// @notice Fuzzes that get pending fees with profit.
    /// @dev Validates that get pending fees with profit.
    function testFuzz_GetPendingFees_WithProfit(uint96 depositAmount, uint96 profitAmount) public {
        uint256 deposit = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        uint256 profit = bound(uint256(profitAmount), 100, type(uint96).max / 2); // Минимальный профит 100 для точных вычислений
        usdc.mint(alice, deposit);

        vm.prank(alice);
        vault.deposit(deposit, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + profit);

        uint256 expectedFeeAmount = (profit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();

        uint256 pendingFees = vault.getPendingFees();
        // Используем больше tolerance для фаззинг тестов из-за rounding в разных местах
        assertApproxEqAbs(pendingFees, expectedFeeAmount, expectedFeeAmount / 1000 + 10);
    }

    /// @notice Tests that get pending fees no profit.
    /// @dev Validates that get pending fees no profit.
    function test_GetPendingFees_NoProfit() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 pendingFees = vault.getPendingFees();
        assertEq(pendingFees, 0);
    }

    /// @notice Tests that get pending fees with loss.
    /// @dev Validates that get pending fees with loss.
    function test_GetPendingFees_WithLoss() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 currentBalance = usdc.balanceOf(address(targetVault));
        deal(address(usdc), address(targetVault), currentBalance - 5_000e6);

        uint256 pendingFees = vault.getPendingFees();
        assertEq(pendingFees, 0);
    }

    /// @notice Tests that get pending fees after harvest.
    /// @dev Validates that get pending fees after harvest.
    function test_GetPendingFees_AfterHarvest() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 10_000e6);

        uint256 pendingFeesBefore = vault.getPendingFees();
        assertGt(pendingFeesBefore, 0);

        vault.harvestFees();

        uint256 pendingFeesAfter = vault.getPendingFees();
        assertEq(pendingFeesAfter, 0);
    }
}
