// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract VaultDepositTest is VaultTestBase {
    function test_Deposit_Basic() public {
        uint256 depositAmount = 10_000e6;
        uint256 expectedShares = depositAmount * 10 ** vault.OFFSET();

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalSupply(), shares);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_Deposit_EmitsEvent() public {
        uint256 depositAmount = 10_000e6;
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        vm.expectEmit(true, true, false, true);
        emit Deposited(alice, alice, depositAmount, expectedShares);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);
    }

    function test_Deposit_MultipleUsers() public {
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(50_000e6, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(30_000e6, bob);

        uint256 expectedAliceShares = 50_000e6 * 10 ** vault.OFFSET();
        uint256 expectedBobShares = 30_000e6 * 10 ** vault.OFFSET();

        assertEq(aliceShares, expectedAliceShares);
        assertEq(bobShares, expectedBobShares);
        assertEq(vault.totalSupply(), aliceShares + bobShares);
        assertEq(vault.totalAssets(), 80_000e6);
    }

    function test_Deposit_RevertIf_ZeroAmount() public {
        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.deposit(0, alice);
    }

    function test_Deposit_RevertIf_ZeroReceiver() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, address(0));
    }

    function test_Deposit_RevertIf_Paused() public {
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
    }

    function test_FirstDeposit_RevertIf_TooSmall() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.FirstDepositTooSmall.selector, 1000, 999));

        vm.prank(alice);
        vault.deposit(999, alice);
    }

    function test_FirstDeposit_SuccessIf_MinimumMet() public {
        uint256 depositAmount = 1000;
        uint256 expectedShares = depositAmount * 10 ** vault.OFFSET();

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_SecondDeposit_CanBeSmall() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 smallDeposit = 1;
        uint256 expectedShares = vault.previewDeposit(smallDeposit);

        vm.prank(bob);
        uint256 shares = vault.deposit(smallDeposit, bob);

        assertEq(shares, expectedShares);
    }

    function test_Mint_Basic() public {
        uint256 sharesToMint = 10_000e6;
        uint256 expectedAssets = vault.previewMint(sharesToMint);

        vm.prank(alice);
        uint256 assets = vault.mint(sharesToMint, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), sharesToMint);
        assertEq(vault.totalAssets(), assets);
    }

    function test_Mint_RevertIf_ZeroShares() public {
        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.mint(0, alice);
    }

    function test_Mint_RevertIf_ZeroReceiver() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.mint(10_000e6, address(0));
    }

    function test_Mint_RevertIf_FirstDepositTooSmall() public {
        uint256 sharesToMint = (vault.MIN_FIRST_DEPOSIT() - 1) * 10 ** vault.OFFSET();
        uint256 expectedAssets = vault.previewMint(sharesToMint);

        vm.expectRevert(
            abi.encodeWithSelector(Vault.FirstDepositTooSmall.selector, vault.MIN_FIRST_DEPOSIT(), expectedAssets)
        );

        vm.prank(alice);
        vault.mint(sharesToMint, alice);
    }

    function test_Mint_RevertIf_Paused() public {
        uint256 sharesToMint = vault.MIN_FIRST_DEPOSIT() * 10 ** vault.OFFSET();

        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.mint(sharesToMint, alice);
    }

    function test_PreviewDeposit_Accurate() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 previewedShares = vault.previewDeposit(10_000e6);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(10_000e6, bob);

        assertEq(previewedShares, actualShares);
    }

    function test_Offset_ProtectsAgainstInflationAttack() public {
        vm.prank(alice);
        vault.deposit(1000, alice);

        asset.mint(address(vault), 100_000e6);

        vm.prank(bob);
        uint256 victimShares = vault.deposit(10_000e6, bob);

        uint256 expectedShares = vault.previewDeposit(10_000e6);
        assertEq(victimShares, expectedShares);
    }
}
