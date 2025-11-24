// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract VaultPausableTest is VaultTestBase {
    /// @notice Exercises standard pause happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
    function test_Pause_Basic() public {
        vault.pause();

        assertTrue(vault.paused());
    }

    /// @notice Ensures pause reverts when not pauser.
    /// @dev Verifies the revert protects against not pauser.
    function test_Pause_RevertIf_NotPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.PAUSER_ROLE())
        );
        vm.prank(alice);
        vault.pause();
    }

    /// @notice Tests that pause with pauser role.
    /// @dev Validates that pause with pauser role.
    function test_Pause_WithPauserRole() public {
        address pauser = makeAddr("pauser");
        vault.grantRole(vault.PAUSER_ROLE(), pauser);

        vm.prank(pauser);
        vault.pause();

        assertTrue(vault.paused());
    }

    /// @notice Exercises standard unpause happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
    function test_Unpause_Basic() public {
        vault.pause();
        assertTrue(vault.paused());

        vault.unpause();
        assertFalse(vault.paused());
    }

    /// @notice Ensures pause reverts when already paused.
    /// @dev Verifies the revert protects against already paused.
    function test_Pause_RevertIf_AlreadyPaused() public {
        vault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.pause();
    }

    /// @notice Ensures unpause reverts when not paused.
    /// @dev Verifies the revert protects against not paused.
    function test_Unpause_RevertIf_NotPaused() public {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vault.unpause();
    }

    /// @notice Ensures unpause reverts when not pauser.
    /// @dev Verifies the revert protects against not pauser.
    function test_Unpause_RevertIf_NotPauser() public {
        vault.pause();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.PAUSER_ROLE())
        );
        vm.prank(alice);
        vault.unpause();
    }

    /// @notice Tests that pause blocks deposit.
    /// @dev Validates that pause blocks deposit.
    function test_Pause_BlocksDeposit() public {
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
    }

    /// @notice Tests that pause blocks mint.
    /// @dev Validates that pause blocks mint.
    function test_Pause_BlocksMint() public {
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.mint(10_000e6, alice);
    }

    /// @notice Tests that pause allows withdraw.
    /// @dev Validates that pause allows withdraw.
    function test_Pause_AllowsWithdraw() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vault.pause();

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(10_000e6, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 10_000e6);
    }

    /// @notice Tests that pause allows redeem.
    /// @dev Validates that pause allows redeem.
    function test_Pause_AllowsRedeem() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100_000e6, alice);

        vault.pause();

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares / 10, alice, alice);

        uint256 aliceBalanceAfter = asset.balanceOf(alice);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, assets);
        assertGt(assets, 0);
    }

    /// @notice Tests that unpause allows operations.
    /// @dev Validates that unpause allows operations.
    function test_Unpause_AllowsOperations() public {
        vault.pause();
        vault.unpause();

        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        uint256 expectedShares = 10_000e6 * 10 ** vault.OFFSET();
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(shares, expectedShares);
    }

    /// @notice Tests that pause does not block views.
    /// @dev Validates that pause does not block views.
    function test_Pause_DoesNotBlockViews() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100_000e6, alice);

        vault.pause();

        assertEq(vault.totalAssets(), 100_000e6);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.previewWithdraw(10_000e6), vault.convertToShares(10_000e6));
    }

    /// @notice Tests that pause does not block preview deposit.
    /// @dev Validates that pause does not block preview deposit.
    function test_Pause_DoesNotBlockPreviewDeposit() public {
        vault.pause();
        uint256 previewShares = vault.previewDeposit(10_000e6);
        assertGt(previewShares, 0);
    }

    /// @notice Tests that max deposit positive when unpaused.
    /// @dev Validates that max deposit positive when unpaused.
    function test_MaxDepositPositiveWhenUnpaused() public view {
        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    /// @notice Tests that pause multiple times different pausers.
    /// @dev Validates that pause multiple times different pausers.
    function test_Pause_MultipleTimesDifferentPausers() public {
        address pauser1 = makeAddr("pauser1");
        address pauser2 = makeAddr("pauser2");

        vault.grantRole(vault.PAUSER_ROLE(), pauser1);
        vault.grantRole(vault.PAUSER_ROLE(), pauser2);

        vm.prank(pauser1);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(pauser2);
        vault.unpause();
        assertFalse(vault.paused());

        vm.prank(pauser2);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(pauser1);
        vault.unpause();
        assertFalse(vault.paused());
    }
}
