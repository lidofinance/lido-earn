// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {MockVault} from "test/mocks/MockVault.sol";
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
        // Alice deposits tiny amount: 1000 assets
        vm.prank(alice);
        vault.deposit(1000, alice);
        // Alice gets 1000 * 10^OFFSET shares (with OFFSET=6: 1,000,000,000 shares)

        // Attacker donates 100M to inflate share price
        asset.mint(address(vault), 100_000e6);
        // Now totalAssets = 1000 + 100_000e6 = 100,000,001,000
        // totalSupply = 1,000,000,000 shares
        // Share price = 100,000,001,000 / 1,000,000,000 = ~100 per share

        // Before Bob deposits, calculate expected values:
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Expected: 100,000,001,000 assets, 1,000,000,000 shares
        assertEq(totalAssetsBefore, 100_000_001_000);
        assertEq(totalSupplyBefore, 1_000_000_000);

        // Bob deposits 10M
        // Harvest will occur:
        // - lastTotalAssets was 1000 (from Alice's deposit)
        // - currentTotal is 100,000,001,000
        // - profit = 100,000,001,000 - 1000 = 100,000,000,000
        uint256 profit = totalAssetsBefore - 1000;
        assertEq(profit, 100_000_000_000);

        // Fee = profit * 500 / 10000 = 100B * 0.05 = 5B
        uint256 feeAmount = (profit * 500) / 10_000;
        assertEq(feeAmount, 5_000_000_000);

        // Fee shares = feeAmount * supply / (totalAssets - feeAmount)
        // = 5B * 1B / (100B - 5B) = 5B * 1B / 95B
        uint256 expectedFeeShares = (feeAmount * totalSupplyBefore) / (totalAssetsBefore - feeAmount);
        // = 5_000_000_000 * 1_000_000_000 / 95_000_001_000
        // = 5_000_000_000_000_000_000 / 95_000_001_000
        // = 52_631_578 (floor division)

        // After harvest:
        // - totalSupply = 1B + 52.6M = 1,052,631,578
        // - totalAssets = 100B (Bob's assets NOT yet transferred)
        uint256 supplyAfterHarvest = totalSupplyBefore + expectedFeeShares;

        // Bob's deposit: 10M assets
        // Conversion happens BEFORE transferFrom (line 231 before line 234)
        // ERC4626 _convertToShares with offset:
        // shares = assets * (supply + 10^offset) / (totalAssets + 1)
        // offset = 6, so 10^offset = 1,000,000

        uint256 offset = 10 ** vault.OFFSET();
        uint256 expectedBobShares = (10_000e6 * (supplyAfterHarvest + offset)) / (totalAssetsBefore + 1);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(10_000e6, bob);

        assertEq(bobShares, expectedBobShares, "Bob should get exactly calculated shares");
    }

    /* ========== FUZZING TESTS ========== */

    // Fuzz test for successful deposit with various amounts
    function testFuzz_Deposit_Success(uint96 depositAmount) public {
        // Bound depositAmount to avoid minFirstDeposit issues and overflow
        depositAmount = uint96(bound(depositAmount, 1000, type(uint96).max));

        // Mint additional tokens to alice if needed
        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(alice, depositAmount - INITIAL_BALANCE);
        }

        uint256 expectedShares = vault.previewDeposit(depositAmount);
        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Verify shares were issued correctly
        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), shares);

        // Verify balance changed correctly
        assertEq(aliceBalanceBefore - asset.balanceOf(alice), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
    }

    // Fuzz test for successful mint with various share amounts
    function testFuzz_Mint_Success(uint96 sharesToMint) public {
        // Bound sharesToMint to avoid minFirstDeposit issues
        sharesToMint = uint96(bound(sharesToMint, 1000 * 10 ** vault.OFFSET(), type(uint96).max));

        uint256 expectedAssets = vault.previewMint(sharesToMint);

        // Mint additional tokens to alice if needed
        if (expectedAssets > INITIAL_BALANCE) {
            asset.mint(alice, expectedAssets - INITIAL_BALANCE);
        }

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.mint(sharesToMint, alice);

        // Verify assets were taken correctly
        assertEq(assets, expectedAssets);

        // Verify shares were issued
        assertEq(vault.balanceOf(alice), sharesToMint);

        // Verify balance changed correctly
        assertEq(aliceBalanceBefore - asset.balanceOf(alice), assets);
    }

    // Fuzz test for two sequential deposits with different users
    function testFuzz_Deposit_WithExistingDeposits(uint96 firstDeposit, uint96 secondDeposit) public {
        // Bound both deposits
        firstDeposit = uint96(bound(firstDeposit, 1000, type(uint96).max / 2));
        secondDeposit = uint96(bound(secondDeposit, 1000, type(uint96).max / 2));

        // Mint additional tokens if needed
        if (firstDeposit > INITIAL_BALANCE) {
            asset.mint(alice, firstDeposit - INITIAL_BALANCE);
        }
        if (secondDeposit > INITIAL_BALANCE) {
            asset.mint(bob, secondDeposit - INITIAL_BALANCE);
        }

        // First deposit by alice
        vm.prank(alice);
        vault.deposit(firstDeposit, alice);

        // Calculate share price after first deposit
        uint256 sharePriceAfterFirst = (vault.totalAssets() * 1e18) / vault.totalSupply();

        // Second deposit by bob
        uint256 expectedBobShares = vault.previewDeposit(secondDeposit);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(secondDeposit, bob);

        // Calculate share price after second deposit
        uint256 sharePriceAfterSecond = (vault.totalAssets() * 1e18) / vault.totalSupply();

        // Verify shares were issued correctly
        assertEq(bobShares, expectedBobShares);

        // Verify share price doesn't change unexpectedly (allow for rounding)
        assertApproxEqAbs(sharePriceAfterFirst, sharePriceAfterSecond, 10);

        // Verify total accounting is correct
        assertEq(vault.totalAssets(), firstDeposit + secondDeposit);
    }

    // Fuzz test that rounding always favors the vault on deposit
    function testFuzz_Deposit_RoundingFavorsVault(uint96 depositAmount) public {
        // Bound depositAmount
        depositAmount = uint96(bound(depositAmount, 1000, type(uint96).max / 2));

        // Create an existing position to enable rounding effects
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Mint additional tokens to bob
        if (depositAmount > INITIAL_BALANCE) {
            asset.mint(bob, depositAmount - INITIAL_BALANCE);
        }

        // Preview shares (rounds down per ERC4626)
        uint256 previewedShares = vault.previewDeposit(depositAmount);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(depositAmount, bob);

        // User should receive less than or equal to previewed shares (rounding favors vault)
        assertLe(actualShares, previewedShares);

        // Should be very close (within 1 wei for rounding)
        assertApproxEqAbs(actualShares, previewedShares, 1);
    }

    // Fuzz test that rounding favors the vault on mint
    function testFuzz_Mint_RoundingFavorsVault(uint96 sharesToMint) public {
        // Bound sharesToMint
        sharesToMint = uint96(bound(sharesToMint, 1000 * 10 ** vault.OFFSET(), type(uint96).max / 2));

        // Create an existing position to enable rounding effects
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 previewedAssets = vault.previewMint(sharesToMint);

        // Mint additional tokens to bob if needed
        if (previewedAssets > INITIAL_BALANCE) {
            asset.mint(bob, previewedAssets - INITIAL_BALANCE);
        }

        vm.prank(bob);
        uint256 actualAssets = vault.mint(sharesToMint, bob);

        // User should pay more than or equal to previewed assets (rounding favors vault)
        assertGe(actualAssets, previewedAssets);

        // Should be very close (within 1 wei for rounding)
        assertApproxEqAbs(actualAssets, previewedAssets, 1);
    }

    /* ========== COVERAGE TESTS FOR EDGE CASES ========== */

    /// @dev Coverage: Vault.sol line 116 - if (protocolSharesReceived == 0) revert ZeroAmount();
    /// @notice Tests that deposit reverts when _depositToProtocol returns 0 shares
    function test_Deposit_RevertIf_ProtocolSharesIsZero() public {
        // Force _depositToProtocol to return 0 shares
        MockVault(address(vault)).setForceZeroProtocolShares(true);

        // Try to deposit - should revert with ZeroAmount
        vm.startPrank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.deposit(10000, alice);
        vm.stopPrank();
    }

    /// @dev Coverage: Vault.sol line 148 - if (protocolSharesReceived == 0) revert ZeroAmount();
    /// @notice Tests that mint reverts when _depositToProtocol returns 0 shares
    function test_Mint_RevertIf_ProtocolSharesIsZero() public {
        // Setup: Make a first deposit to pass MIN_FIRST_DEPOSIT check
        vm.prank(alice);
        vault.deposit(10000, alice);

        // Force _depositToProtocol to return 0 shares
        MockVault(address(vault)).setForceZeroProtocolShares(true);

        // Try to mint - should revert with ZeroAmount
        vm.startPrank(bob);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.mint(10000, bob);
        vm.stopPrank();
    }
}
