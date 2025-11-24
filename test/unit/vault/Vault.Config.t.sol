// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultConfigTest is VaultTestBase {
    /// @notice Exercises standard set reward fee happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
    function test_SetRewardFee_Basic() public {
        uint16 newFee = 1000;

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
        uint16 maxFee = uint16(vault.MAX_REWARD_FEE_BASIS_POINTS());

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, maxFee);

        vault.setRewardFee(maxFee);

        assertEq(vault.rewardFee(), maxFee);
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
        uint16 newFee = 1500;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.MANAGER_ROLE()
            )
        );
        vm.prank(alice);
        vault.setRewardFee(newFee);
    }

    /// @notice Tests that set reward fee harvests fees before change.
    /// @dev Validates that set reward fee harvests fees before change.
    function test_SetRewardFee_HarvestsFeesBeforeChange() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 profit = 10_000e6;
        asset.mint(address(vault), profit);

        uint256 expectedShares = _calculateExpectedFeeShares(profit);
        assertEq(vault.balanceOf(treasury), 0);

        vault.setRewardFee(1000);

        assertEq(vault.balanceOf(treasury), expectedShares);
    }

    /// @notice Tests that set reward fee updates last total assets.
    /// @dev Validates that set reward fee updates last total assets.
    function test_SetRewardFee_UpdatesLastTotalAssets() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 lastAssetsBefore = vault.lastTotalAssets();
        assertEq(lastAssetsBefore, 100_000e6);

        asset.mint(address(vault), 10_000e6);

        vault.setRewardFee(1000);

        uint256 lastAssetsAfter = vault.lastTotalAssets();
        assertEq(lastAssetsAfter, vault.totalAssets());
        assertEq(lastAssetsAfter, 110_000e6);
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

    /// @notice Fuzzes that set reward fee within bounds.
    /// @dev Validates that set reward fee within bounds.
    function testFuzz_SetRewardFee_WithinBounds(uint16 newFee) public {
        newFee = uint16(bound(uint256(newFee), 0, vault.MAX_REWARD_FEE_BASIS_POINTS()));

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    /// @notice Exercises standard set treasury happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
    function test_SetTreasury_Basic() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, true, false, true);
        emit Vault.TreasuryUpdated(treasury, newTreasury);

        vault.setTreasury(newTreasury);

        assertEq(vault.TREASURY(), newTreasury);
    }

    /// @notice Ensures set treasury reverts when zero address.
    /// @dev Verifies the revert protects against zero address.
    function test_SetTreasury_RevertIf_ZeroAddress() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.setTreasury(address(0));
    }

    /// @notice Ensures set treasury reverts when same address.
    /// @dev Verifies the revert protects against same address.
    function test_SetTreasury_RevertIf_SameAddress() public {
        vm.expectRevert(Vault.InvalidTreasuryAddress.selector);
        vault.setTreasury(treasury);
    }

    /// @notice Ensures set treasury reverts when not fee manager.
    /// @dev Verifies the revert protects against not fee manager.
    function test_SetTreasury_RevertIf_NotFeeManager() public {
        address newTreasury = makeAddr("newTreasury");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.MANAGER_ROLE()
            )
        );
        vm.prank(alice);
        vault.setTreasury(newTreasury);
    }

    /// @notice Tests that set treasury does not transfer existing shares.
    /// @dev Validates that set treasury does not transfer existing shares.
    function test_SetTreasury_DoesNotTransferExistingShares() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        asset.mint(address(vault), 10_000e6);
        vault.harvestFees();

        uint256 oldTreasuryShares = vault.balanceOf(treasury);
        assertGt(oldTreasuryShares, 0);

        address newTreasury = makeAddr("newTreasury");
        vault.setTreasury(newTreasury);

        assertEq(vault.balanceOf(treasury), oldTreasuryShares);
        assertEq(vault.balanceOf(newTreasury), 0);

        asset.mint(address(vault), 5_000e6);
        vault.harvestFees();
        assertGt(vault.balanceOf(newTreasury), 0);
    }
}
