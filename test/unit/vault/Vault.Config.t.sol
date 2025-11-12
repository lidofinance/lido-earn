// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultConfigTest is VaultTestBase {
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
        uint16 maxFee = uint16(vault.MAX_REWARD_FEE_BASIS_POINTS());

        vm.expectEmit(true, true, false, true);
        emit Vault.RewardFeeUpdated(REWARD_FEE, maxFee);

        vault.setRewardFee(maxFee);

        assertEq(vault.rewardFee(), maxFee);
    }

    function test_SetRewardFee_RevertIf_ExceedsMaximum() public {
        uint16 invalidFee = uint16(vault.MAX_REWARD_FEE_BASIS_POINTS() + 1);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidFee.selector, invalidFee));
        vault.setRewardFee(invalidFee);
    }

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

    function testFuzz_SetRewardFee_WithinBounds(uint16 newFee) public {
        vm.assume(newFee <= vault.MAX_REWARD_FEE_BASIS_POINTS());

        vault.setRewardFee(newFee);

        assertEq(vault.rewardFee(), newFee);
    }

    function test_SetTreasury_Basic() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, true, false, true);
        emit Vault.TreasuryUpdated(treasury, newTreasury);

        vault.setTreasury(newTreasury);

        assertEq(vault.TREASURY(), newTreasury);
    }

    function test_SetTreasury_RevertIf_ZeroAddress() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.setTreasury(address(0));
    }

    function test_SetTreasury_RevertIf_SameAddress() public {
        vm.expectRevert(Vault.InvalidTreasuryAddress.selector);
        vault.setTreasury(treasury);
    }

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
