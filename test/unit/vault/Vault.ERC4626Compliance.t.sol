// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";

/**
 * @title VaultERC4626ComplianceTest
 * @notice Comprehensive tests for ERC4626 standard compliance
 * @dev Tests verify that preview functions, max functions, convert functions, and rounding
 *      all behave according to ERC4626 specification
 */
contract VaultERC4626ComplianceTest is VaultTestBase {
    uint256 constant FIRST_DEPOSIT = 100_000e6;
    uint256 constant SECOND_DEPOSIT = 50_000e6;

    function setUp() public override {
        super.setUp();

        // Setup: Alice makes first deposit to establish vault state
        vm.prank(alice);
        vault.deposit(FIRST_DEPOSIT, alice);
    }

    /* ========== PREVIEW FUNCTIONS TESTS ========== */

    /// @notice Test that previewDeposit matches actual deposit shares received
    function test_PreviewDeposit_MatchesActualDeposit() public {
        uint256 depositAmount = SECOND_DEPOSIT;

        // Get preview
        uint256 previewedShares = vault.previewDeposit(depositAmount);

        // Execute actual deposit
        vm.prank(bob);
        uint256 actualShares = vault.deposit(depositAmount, bob);

        // Preview should exactly match actual shares received
        assertEq(previewedShares, actualShares, "PreviewDeposit should match actual shares");
    }

    /// @notice Test that previewMint matches actual mint assets required
    function test_PreviewMint_MatchesActualMint() public {
        uint256 sharesToMint = 50_000e6 * 10 ** vault.OFFSET();

        // Get preview
        uint256 previewedAssets = vault.previewMint(sharesToMint);

        // Execute actual mint
        vm.prank(bob);
        uint256 actualAssets = vault.mint(sharesToMint, bob);

        // Preview should match actual assets required (allow ±1 wei for rounding)
        assertApproxEqAbs(previewedAssets, actualAssets, 1, "PreviewMint should match actual assets");
    }

    /// @notice Test that previewWithdraw matches actual withdraw shares burned
    function test_PreviewWithdraw_MatchesActualWithdraw() public {
        uint256 withdrawAmount = 30_000e6;

        // Get preview
        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);

        // Execute actual withdraw
        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);

        // Preview should match actual shares burned (allow ±1 wei for rounding)
        assertApproxEqAbs(previewedShares, actualShares, 1, "PreviewWithdraw should match actual shares");
    }

    /// @notice Test that previewRedeem matches actual redeem assets received
    function test_PreviewRedeem_MatchesActualRedeem() public {
        uint256 sharesToRedeem = 30_000e6 * 10 ** vault.OFFSET();

        // Get preview
        uint256 previewedAssets = vault.previewRedeem(sharesToRedeem);

        // Execute actual redeem
        vm.prank(alice);
        uint256 actualAssets = vault.redeem(sharesToRedeem, alice, alice);

        // Preview should match actual assets received (allow ±1 wei for rounding)
        assertApproxEqAbs(previewedAssets, actualAssets, 1, "PreviewRedeem should match actual assets");
    }

    /* ========== MAX FUNCTIONS TESTS ========== */

    /// @notice Test that maxDeposit returns max uint256 in normal conditions
    /// @dev Note: ERC4626 standard maxDeposit doesn't enforce pause state.
    ///      Pause protection is enforced by deposit() function's whenNotPaused modifier.
    function test_MaxDeposit_ReturnsMaxUint256() public view {
        uint256 maxDeposit = vault.maxDeposit(alice);

        assertEq(maxDeposit, type(uint256).max, "MaxDeposit should be max uint256");
    }

    /// @notice Test that maxMint returns max uint256 in normal conditions
    /// @dev Note: ERC4626 standard maxMint doesn't enforce pause state.
    ///      Pause protection is enforced by mint() function's whenNotPaused modifier.
    function test_MaxMint_ReturnsMaxUint256() public view {
        uint256 maxMint = vault.maxMint(alice);

        assertEq(maxMint, type(uint256).max, "MaxMint should be max uint256");
    }

    /// @notice Test that maxWithdraw returns correct amount for user's shares
    function test_MaxWithdraw_ReturnsCorrectAmount() public view {
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxWithdraw = vault.maxWithdraw(alice);

        // maxWithdraw returns slightly less (1 wei) than convertToAssets to account for rounding
        // This ensures withdraw(maxWithdraw) will never revert due to insufficient shares
        uint256 expectedAssets = vault.convertToAssets(aliceShares);
        assertApproxEqAbs(maxWithdraw, expectedAssets, 1, "MaxWithdraw should be close to convertToAssets");
    }

    /// @notice Test that maxRedeem returns user's full share balance
    function test_MaxRedeem_ReturnsShareBalance() public view {
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxRedeem = vault.maxRedeem(alice);

        assertEq(maxRedeem, aliceShares, "MaxRedeem should return full share balance");
    }

    /* ========== CONVERT FUNCTIONS TESTS ========== */

    /// @notice Test that convertToShares rounds down (favors vault)
    function test_ConvertToShares_RoundsDown() public {
        // Add a small profit to create non-round conversion ratio
        asset.mint(address(vault), 7);

        uint256 assets = 10_000e6 + 3; // Amount that won't divide evenly
        uint256 shares = vault.convertToShares(assets);

        // Convert back to assets
        uint256 assetsBack = vault.convertToAssets(shares);

        // Due to rounding down, assets back should be <= original assets
        assertLe(assetsBack, assets, "ConvertToShares should round down");
    }

    /// @notice Test that convertToAssets rounds down (favors vault)
    function test_ConvertToAssets_RoundsDown() public {
        // Add a small profit to create non-round conversion ratio
        asset.mint(address(vault), 7);

        uint256 shares = 10_000e6 * 10 ** vault.OFFSET() + 3; // Amount that won't divide evenly
        uint256 assets = vault.convertToAssets(shares);

        // Convert back to shares
        uint256 sharesBack = vault.convertToShares(assets);

        // Due to rounding down, shares back should be <= original shares
        assertLe(sharesBack, shares, "ConvertToAssets should round down");
    }

    /// @notice Test that convertToShares works correctly with zero assets
    function test_ConvertToShares_WithZeroAssets() public view {
        uint256 shares = vault.convertToShares(0);

        assertEq(shares, 0, "Converting 0 assets should return 0 shares");
    }

    /// @notice Test that convertToAssets works correctly with zero shares
    function test_ConvertToAssets_WithZeroShares() public view {
        uint256 assets = vault.convertToAssets(0);

        assertEq(assets, 0, "Converting 0 shares should return 0 assets");
    }

    /* ========== ASSET/SHARE RATIO TESTS ========== */

    /// @notice Test that deposit returns shares matching preview
    function test_Deposit_SharesMatchPreview() public {
        uint256 depositAmount = 25_000e6;

        uint256 previewedShares = vault.previewDeposit(depositAmount);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(depositAmount, bob);

        assertEq(actualShares, previewedShares, "Deposit shares should match preview");
    }

    /// @notice Test that mint requires assets matching preview
    function test_Mint_AssetsMatchPreview() public {
        uint256 sharesToMint = 25_000e6 * 10 ** vault.OFFSET();

        uint256 previewedAssets = vault.previewMint(sharesToMint);
        uint256 bobAssetsBefore = asset.balanceOf(bob);

        vm.prank(bob);
        vault.mint(sharesToMint, bob);

        uint256 bobAssetsAfter = asset.balanceOf(bob);
        uint256 actualAssetsSpent = bobAssetsBefore - bobAssetsAfter;

        // Allow ±1 wei difference for rounding
        assertApproxEqAbs(actualAssetsSpent, previewedAssets, 1, "Mint assets should match preview");
    }

    /// @notice Test that withdraw burns shares matching preview
    function test_Withdraw_SharesMatchPreview() public {
        uint256 withdrawAmount = 25_000e6;

        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceSharesAfter = vault.balanceOf(alice);
        uint256 actualSharesBurned = aliceSharesBefore - aliceSharesAfter;

        // Allow ±1 wei difference for rounding
        assertApproxEqAbs(actualSharesBurned, previewedShares, 1, "Withdraw shares should match preview");
    }

    /// @notice Test that redeem returns assets matching preview
    function test_Redeem_AssetsMatchPreview() public {
        uint256 sharesToRedeem = 25_000e6 * 10 ** vault.OFFSET();

        uint256 previewedAssets = vault.previewRedeem(sharesToRedeem);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(sharesToRedeem, alice, alice);

        // Allow ±1 wei difference for rounding
        assertApproxEqAbs(actualAssets, previewedAssets, 1, "Redeem assets should match preview");
    }

    /* ========== ROUNDING PROTECTION TESTS ========== */

    /// @notice Test that deposit rounding favors the vault (user receives fewer shares)
    function test_Deposit_RoundingFavorsVault() public {
        // Create a scenario where rounding matters by adding profit
        asset.mint(address(vault), 3);

        uint256 depositAmount = 1e6 + 1; // Small amount to trigger rounding
        uint256 shares = vault.previewDeposit(depositAmount);

        // Convert shares back to assets
        uint256 assetsForShares = vault.convertToAssets(shares);

        // Due to rounding down in convertToShares, user should get slightly fewer shares
        // than would give them back their exact deposit
        assertLe(assetsForShares, depositAmount, "Deposit rounding should favor vault");
    }

    /// @notice Test that mint rounding favors the vault (user pays more assets)
    function test_Mint_RoundingFavorsVault() public {
        // Create a scenario where rounding matters by adding profit
        asset.mint(address(vault), 3);

        uint256 sharesToMint = 1e6 + 1; // Small amount to trigger rounding
        uint256 assets = vault.previewMint(sharesToMint);

        // Convert assets to shares
        uint256 sharesForAssets = vault.convertToShares(assets);

        // Due to rounding, user should get equal or fewer shares for their assets
        assertGe(sharesForAssets, sharesToMint, "Mint rounding should favor vault");
    }

    /// @notice Test that withdraw rounding favors the vault (user burns more shares)
    function test_Withdraw_RoundingFavorsVault() public {
        // Create a scenario where rounding matters by adding profit
        asset.mint(address(vault), 3);

        uint256 withdrawAmount = 1e6 + 1; // Small amount to trigger rounding
        uint256 shares = vault.previewWithdraw(withdrawAmount);

        // Convert shares back to assets
        uint256 assetsForShares = vault.convertToAssets(shares);

        // Due to rounding up in previewWithdraw, user should burn slightly more shares
        // than the assets they receive are worth
        assertGe(assetsForShares, withdrawAmount, "Withdraw rounding should favor vault");
    }

    /// @notice Test that redeem rounding favors the vault (user receives fewer assets)
    function test_Redeem_RoundingFavorsVault() public {
        // Create a scenario where rounding matters by adding profit
        asset.mint(address(vault), 3);

        uint256 sharesToRedeem = 1e6 + 1; // Small amount to trigger rounding
        uint256 assets = vault.previewRedeem(sharesToRedeem);

        // Convert assets to shares
        uint256 sharesForAssets = vault.convertToShares(assets);

        // Due to rounding down in convertToAssets, user should receive assets worth
        // slightly less than the shares they burned
        assertLe(sharesForAssets, sharesToRedeem, "Redeem rounding should favor vault");
    }

    /* ========== FUZZ TESTS ========== */

    /// @notice Fuzz test: preview functions should always match actual operations
    function testFuzz_PreviewDeposit_AlwaysMatchesActual(uint96 depositAmount) public {
        // Bound to reasonable range (avoid first deposit minimum, avoid overflow)
        depositAmount = uint96(bound(depositAmount, 10_000e6, 500_000e6));

        _dealAndApprove(bob, depositAmount);

        uint256 previewedShares = vault.previewDeposit(depositAmount);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(depositAmount, bob);

        assertEq(previewedShares, actualShares, "Fuzzed previewDeposit should match actual");
    }

    /// @notice Fuzz test: convertToShares followed by convertToAssets should round down
    function testFuzz_Convert_RoundsDown(uint96 assets) public {
        // Bound to reasonable range
        assets = uint96(bound(assets, 1e6, 1_000_000e6));

        // Add some profit to create non-trivial conversion ratio
        asset.mint(address(vault), 100e6);

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        // Due to double rounding down, assetsBack <= original assets
        assertLe(assetsBack, assets, "Fuzzed convert should round down");
    }

    /// @notice Fuzz test: maxDeposit should always return max uint256 for any valid user
    /// @dev Note: ERC4626 standard doesn't require maxDeposit to consider pause state
    function testFuzz_MaxDeposit_AlwaysMaxUint256(address user) public {
        // Filter invalid addresses
        vm.assume(user != address(0));

        // MaxDeposit should be max uint256 regardless of pause state
        assertEq(vault.maxDeposit(user), type(uint256).max, "MaxDeposit should be max uint256");

        // Even when paused (pause is enforced by deposit() modifier, not maxDeposit())
        vault.pause();
        assertEq(vault.maxDeposit(user), type(uint256).max, "MaxDeposit should still be max when paused");
    }

    /// @notice Fuzz test: withdraw and redeem should give consistent results
    function testFuzz_WithdrawRedeem_Consistency(uint96 withdrawAmount) public view {
        // Bound to available liquidity (alice has FIRST_DEPOSIT deposited)
        withdrawAmount = uint96(bound(withdrawAmount, 1e6, FIRST_DEPOSIT - 1e6));

        // Get how many shares needed for withdraw
        uint256 sharesForWithdraw = vault.previewWithdraw(withdrawAmount);

        // Get how many assets we'd get for redeeming those shares
        uint256 assetsFromRedeem = vault.previewRedeem(sharesForWithdraw);

        // Assets from redeeming the required shares should be >= withdraw amount
        // (May be slightly more due to rounding in favor of vault)
        assertGe(assetsFromRedeem, withdrawAmount, "Redeem should be consistent with withdraw");
    }
}
