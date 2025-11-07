// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract VaultPausableTest is VaultTestBase {
    function test_Pause_Basic() public {
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_Pause_RevertIf_NotPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.PAUSER_ROLE())
        );
        vm.prank(alice);
        vault.pause();
    }

    function test_Pause_WithPauserRole() public {
        address pauser = makeAddr("pauser");
        vault.grantRole(vault.PAUSER_ROLE(), pauser);

        vm.prank(pauser);
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_Unpause_Basic() public {
        vault.pause();
        assertTrue(vault.paused());

        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_Unpause_RevertIf_NotPauser() public {
        vault.pause();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.PAUSER_ROLE())
        );
        vm.prank(alice);
        vault.unpause();
    }

    function test_Pause_BlocksDeposit() public {
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
    }

    function test_Pause_BlocksMint() public {
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.mint(10_000e6, alice);
    }

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

    function test_Unpause_AllowsOperations() public {
        vault.pause();
        vault.unpause();

        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        uint256 expectedShares = 10_000e6 * 10 ** vault.OFFSET();
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(shares, expectedShares);
    }

    function test_Pause_DoesNotBlockViews() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100_000e6, alice);

        vault.pause();

        assertEq(vault.totalAssets(), 100_000e6);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.maxWithdraw(alice), 100_000e6);
    }

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
