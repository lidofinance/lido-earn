// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ERC4626AdapterTestBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ERC4626AdapterMaxRedeemTest is ERC4626AdapterTestBase {
    using Math for uint256;

    /* ========== NORMAL MODE TESTS ========== */

    /// @notice Tests that maxRedeem returns user balance when target vault has full liquidity
    /// @dev When target vault liquidity >= user position value, user can redeem all shares
    function test_MaxRedeem_ReturnsUserBalanceWithFullLiquidity() public {
        // Setup: Alice deposits 100k USDC
        uint256 depositAmount = 100_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertEq(maxRedeemable, aliceShares, "MaxRedeem should equal user balance with full liquidity");
    }

    /// @notice Tests that maxRedeem respects target vault liquidity limits
    /// @dev When target vault has limited liquidity, maxRedeem is capped by available assets
    function test_MaxRedeem_RespectsTargetVaultLiquidityLimits() public {
        // Setup: Alice deposits 100k USDC
        uint256 depositAmount = 100_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceShares = vault.balanceOf(alice);

        // Simulate limited liquidity in target vault (50k available)
        uint256 limitedLiquidity = 50_000e6;
        targetVault.setLiquidityCap(limitedLiquidity);

        uint256 maxRedeemable = vault.maxRedeem(alice);
        uint256 expectedMaxShares = vault.convertToShares(limitedLiquidity);

        assertLe(maxRedeemable, aliceShares, "MaxRedeem should be less than user balance");
        assertApproxEqAbs(maxRedeemable, expectedMaxShares, 1, "MaxRedeem should match liquidity-limited shares");
    }

    /// @notice Tests that maxRedeem returns zero when user has no shares
    /// @dev Edge case: user with no position should get maxRedeem = 0
    function test_MaxRedeem_ReturnsZeroWhenUserHasNoShares() public view {
        uint256 maxRedeemable = vault.maxRedeem(alice);
        assertEq(maxRedeemable, 0, "MaxRedeem should be 0 for user with no shares");
    }

    /// @notice Tests that maxRedeem returns zero when target vault has no liquidity
    /// @dev Even if user has shares, maxRedeem is 0 when target vault liquidity is 0
    function test_MaxRedeem_ReturnsZeroWhenTargetVaultHasNoLiquidity() public {
        // Setup: Alice deposits 100k USDC
        uint256 depositAmount = 100_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Simulate no liquidity in target vault
        targetVault.setLiquidityCap(0);

        uint256 maxRedeemable = vault.maxRedeem(alice);
        assertEq(maxRedeemable, 0, "MaxRedeem should be 0 when target vault has no liquidity");
    }

    /// @notice Tests maxRedeem for multiple users with different balances
    /// @dev Verifies that maxRedeem is calculated independently for each user
    function test_MaxRedeem_MultipleUsersWithDifferentBalances() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Bob deposits 50k USDC
        vm.prank(bob);
        vault.deposit(50_000e6, bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        uint256 aliceMaxRedeem = vault.maxRedeem(alice);
        uint256 bobMaxRedeem = vault.maxRedeem(bob);

        assertEq(aliceMaxRedeem, aliceShares, "Alice maxRedeem should equal her balance");
        assertEq(bobMaxRedeem, bobShares, "Bob maxRedeem should equal his balance");
        assertGt(aliceMaxRedeem, bobMaxRedeem, "Alice should have higher maxRedeem than Bob");
    }

    /// @notice Tests maxRedeem with partial target vault liquidity across multiple users
    /// @dev When liquidity is limited, both users are proportionally constrained
    function test_MaxRedeem_MultipleUsersWithPartialLiquidity() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Bob deposits 50k USDC
        vm.prank(bob);
        vault.deposit(50_000e6, bob);

        // Simulate limited liquidity (40k available out of 150k total)
        // This ensures both users are constrained (40k < 50k < 100k)
        targetVault.setLiquidityCap(40_000e6);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        uint256 aliceMaxRedeem = vault.maxRedeem(alice);
        uint256 bobMaxRedeem = vault.maxRedeem(bob);

        // Both should be limited by available liquidity
        assertLt(aliceMaxRedeem, aliceShares, "Alice maxRedeem should be limited");
        assertLt(bobMaxRedeem, bobShares, "Bob maxRedeem should be limited");

        // Both have the same liquidity constraint
        uint256 expectedMaxShares = vault.convertToShares(40_000e6);
        assertApproxEqAbs(aliceMaxRedeem, expectedMaxShares, 1, "Alice should be limited by liquidity cap");
        assertApproxEqAbs(bobMaxRedeem, expectedMaxShares, 1, "Bob should be limited by liquidity cap");
    }

    /// @notice Tests maxRedeem after successful redemption updates correctly
    /// @dev After one user redeems, maxRedeem for other users should update
    function test_MaxRedeem_UpdatesAfterRedemption() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Bob deposits 50k USDC
        vm.prank(bob);
        vault.deposit(50_000e6, bob);

        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Alice redeems half her shares
        uint256 redeemAmount = aliceSharesBefore / 2;
        vm.prank(alice);
        vault.redeem(redeemAmount, alice, alice);

        uint256 aliceSharesAfter = vault.balanceOf(alice);
        uint256 aliceMaxRedeemAfter = vault.maxRedeem(alice);

        assertEq(aliceSharesAfter, aliceSharesBefore - redeemAmount, "Alice shares should decrease");
        assertEq(aliceMaxRedeemAfter, aliceSharesAfter, "Alice maxRedeem should equal new balance");
    }

    /// @notice Tests maxRedeem accounts for pending fee dilution
    /// @dev When there are pending fees, maxRedeem should consider the dilution effect
    function test_MaxRedeem_AccountsForPendingFees() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Generate profit in target vault (10k USDC profit)
        uint256 profit = 10_000e6;
        usdc.mint(address(targetVault), profit);

        // maxRedeem should still return alice's share count
        // (fees haven't been harvested yet, but maxRedeem uses current balances)
        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertEq(maxRedeemable, aliceSharesBefore, "MaxRedeem should equal user balance before harvest");
    }

    /// @notice Tests maxRedeem with very small amounts (rounding edge case)
    /// @dev Verifies correct behavior with minimal share amounts
    function test_MaxRedeem_WithVerySmallAmounts() public {
        // Alice makes minimum deposit
        uint256 minDeposit = vault.MIN_FIRST_DEPOSIT();
        vm.prank(alice);
        vault.deposit(minDeposit, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertGt(aliceShares, 0, "Alice should have shares");
        assertEq(maxRedeemable, aliceShares, "MaxRedeem should equal balance even for small amounts");
    }

    /// @notice Tests maxRedeem with very large amounts
    /// @dev Verifies correct behavior with maximum practical share amounts
    function test_MaxRedeem_WithVeryLargeAmounts() public {
        // Set large cap
        targetVault.setLiquidityCap(type(uint96).max);

        // Alice deposits large amount
        uint256 largeAmount = 1_000_000_000e6; // 1 billion USDC
        usdc.mint(alice, largeAmount);
        vm.prank(alice);
        vault.deposit(largeAmount, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertEq(maxRedeemable, aliceShares, "MaxRedeem should equal balance for large amounts");
    }

    /// @notice Tests maxRedeem conversion accuracy with _convertToShares
    /// @dev Ensures maxRedeem properly uses _convertToShares with Floor rounding
    function test_MaxRedeem_ConversionAccuracy() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Limit target vault liquidity to 50k
        uint256 limitedLiquidity = 50_000e6;
        targetVault.setLiquidityCap(limitedLiquidity);

        uint256 maxRedeemable = vault.maxRedeem(alice);

        // Manually calculate expected shares using Floor rounding
        uint256 expectedShares = vault.convertToShares(limitedLiquidity);

        assertEq(maxRedeemable, expectedShares, "MaxRedeem should use correct Floor rounding");
    }

    /* ========== RECOVERY MODE TESTS ========== */

    /// @notice Tests that maxRedeem returns all user shares when recovery mode is active
    /// @dev In recovery mode, users can redeem all shares regardless of target vault liquidity
    function test_MaxRedeem_ReturnsAllSharesInRecoveryMode() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 aliceShares = vault.balanceOf(alice);

        // Trigger emergency and activate recovery
        vault.emergencyWithdraw();
        uint256 recoveredAmount = usdc.balanceOf(address(vault));
        vault.activateRecovery(recoveredAmount);

        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertEq(maxRedeemable, aliceShares, "MaxRedeem should return all shares in recovery mode");
    }

    /// @notice Tests that maxRedeem returns zero when user has no shares in recovery mode
    /// @dev Edge case: user with no position should get maxRedeem = 0 even in recovery mode
    function test_MaxRedeem_ReturnsZeroWhenNoSharesInRecoveryMode() public {
        // Alice deposits to initialize vault
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Trigger emergency and activate recovery
        vault.emergencyWithdraw();
        uint256 recoveredAmount = usdc.balanceOf(address(vault));
        vault.activateRecovery(recoveredAmount);

        // Check Bob's maxRedeem (Bob has no shares)
        uint256 maxRedeemable = vault.maxRedeem(bob);

        assertEq(maxRedeemable, 0, "MaxRedeem should be 0 for user with no shares in recovery mode");
    }

    /// @notice Tests that recovery mode ignores target vault liquidity limits
    /// @dev Even with zero target vault liquidity, users can redeem in recovery mode
    function test_MaxRedeem_IgnoresTargetVaultLiquidityInRecoveryMode() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 aliceShares = vault.balanceOf(alice);

        // Trigger emergency and activate recovery
        vault.emergencyWithdraw();
        uint256 recoveredAmount = usdc.balanceOf(address(vault));
        vault.activateRecovery(recoveredAmount);

        // Simulate target vault having zero liquidity (shouldn't matter in recovery)
        targetVault.setLiquidityCap(0);

        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertEq(maxRedeemable, aliceShares, "MaxRedeem should ignore target vault liquidity in recovery mode");
    }

    /// @notice Tests maxRedeem for multiple users in recovery mode
    /// @dev Each user should be able to redeem their full balance in recovery mode
    function test_MaxRedeem_MultipleUsersInRecoveryMode() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Bob deposits 50k USDC
        vm.prank(bob);
        vault.deposit(50_000e6, bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        // Trigger emergency and activate recovery
        vault.emergencyWithdraw();
        uint256 recoveredAmount = usdc.balanceOf(address(vault));
        vault.activateRecovery(recoveredAmount);

        uint256 aliceMaxRedeem = vault.maxRedeem(alice);
        uint256 bobMaxRedeem = vault.maxRedeem(bob);

        assertEq(aliceMaxRedeem, aliceShares, "Alice should be able to redeem all shares");
        assertEq(bobMaxRedeem, bobShares, "Bob should be able to redeem all shares");
    }

    /// @notice Tests transition from normal mode to recovery mode
    /// @dev maxRedeem behavior should change when recovery mode is activated
    function test_MaxRedeem_TransitionToRecoveryMode() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Simulate limited target vault liquidity
        targetVault.setLiquidityCap(50_000e6);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxRedeemBefore = vault.maxRedeem(alice);

        // MaxRedeem should be limited before recovery mode
        assertLt(maxRedeemBefore, aliceShares, "MaxRedeem should be limited before recovery");

        // Trigger emergency and activate recovery
        vault.emergencyWithdraw();
        uint256 recoveredAmount = usdc.balanceOf(address(vault));
        vault.activateRecovery(recoveredAmount);

        uint256 maxRedeemAfter = vault.maxRedeem(alice);

        // MaxRedeem should return all shares in recovery mode
        assertEq(maxRedeemAfter, aliceShares, "MaxRedeem should return all shares after recovery activation");
        assertGt(maxRedeemAfter, maxRedeemBefore, "MaxRedeem should increase after recovery activation");
    }

    /* ========== FUZZ TESTS ========== */

    /// @notice Fuzz test: maxRedeem with different user balances
    /// @dev Verifies maxRedeem correctness across various deposit amounts
    function testFuzz_MaxRedeem_WithDifferentUserBalances(uint96 depositAmount) public {
        uint256 deposit = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, deposit);

        vm.prank(alice);
        vault.deposit(deposit, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertEq(maxRedeemable, aliceShares, "MaxRedeem should equal user balance");
    }

    /// @notice Fuzz test: maxRedeem with different liquidity levels
    /// @dev Verifies maxRedeem respects various target vault liquidity constraints
    function testFuzz_MaxRedeem_WithDifferentLiquidityLevels(uint96 liquidityCap) public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 cap = bound(uint256(liquidityCap), 0, 100_000e6);
        targetVault.setLiquidityCap(cap);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 maxRedeemable = vault.maxRedeem(alice);

        if (cap == 0) {
            assertEq(maxRedeemable, 0, "MaxRedeem should be 0 when no liquidity");
        } else {
            uint256 expectedMaxShares = vault.convertToShares(cap);
            uint256 expectedMaxRedeem = Math.min(aliceShares, expectedMaxShares);
            assertApproxEqAbs(maxRedeemable, expectedMaxRedeem, 1, "MaxRedeem should respect liquidity cap");
        }
    }

    /// @notice Fuzz test: maxRedeem with random profits affecting conversion
    /// @dev Verifies maxRedeem handles fee dilution correctly with various profit amounts
    function testFuzz_MaxRedeem_WithProfits(uint96 profitAmount) public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Generate random profit
        uint256 profit = bound(uint256(profitAmount), 0, 1_000_000e6);
        usdc.mint(address(targetVault), profit);

        uint256 maxRedeemable = vault.maxRedeem(alice);

        // MaxRedeem should still return alice's current share balance
        assertEq(maxRedeemable, aliceSharesBefore, "MaxRedeem should equal user balance with profit");
    }

    /// @notice Fuzz test: maxRedeem in recovery mode with different balances
    /// @dev Verifies recovery mode always returns full balance regardless of amount
    function testFuzz_MaxRedeem_InRecoveryModeWithDifferentBalances(uint96 depositAmount) public {
        uint256 deposit = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, deposit);

        vm.prank(alice);
        vault.deposit(deposit, alice);

        uint256 aliceShares = vault.balanceOf(alice);

        // Trigger emergency and activate recovery
        vault.emergencyWithdraw();
        uint256 recoveredAmount = usdc.balanceOf(address(vault));
        vault.activateRecovery(recoveredAmount);

        uint256 maxRedeemable = vault.maxRedeem(alice);

        assertEq(maxRedeemable, aliceShares, "MaxRedeem should always return full balance in recovery mode");
    }

    /// @notice Fuzz test: maxRedeem with multiple users and varying liquidity
    /// @dev Tests complex scenario with two users and random liquidity constraint
    function testFuzz_MaxRedeem_MultipleUsersWithVaryingLiquidity(
        uint96 aliceDeposit,
        uint96 bobDeposit,
        uint96 liquidityCap
    ) public {
        uint256 aliceAmount = bound(uint256(aliceDeposit), vault.MIN_FIRST_DEPOSIT(), type(uint88).max);
        uint256 bobAmount = bound(uint256(bobDeposit), vault.MIN_FIRST_DEPOSIT(), type(uint88).max);

        usdc.mint(alice, aliceAmount);
        vm.prank(alice);
        vault.deposit(aliceAmount, alice);

        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        vault.deposit(bobAmount, bob);

        uint256 totalDeposited = aliceAmount + bobAmount;
        uint256 cap = bound(uint256(liquidityCap), 0, totalDeposited);
        targetVault.setLiquidityCap(cap);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        uint256 aliceMaxRedeem = vault.maxRedeem(alice);
        uint256 bobMaxRedeem = vault.maxRedeem(bob);

        // Both should be <= their balances
        assertLe(aliceMaxRedeem, aliceShares, "Alice maxRedeem should not exceed balance");
        assertLe(bobMaxRedeem, bobShares, "Bob maxRedeem should not exceed balance");

        if (cap > 0) {
            uint256 liquidityShares = vault.convertToShares(cap);
            assertLe(aliceMaxRedeem, liquidityShares, "Alice maxRedeem should respect liquidity");
            assertLe(bobMaxRedeem, liquidityShares, "Bob maxRedeem should respect liquidity");
        } else {
            assertEq(aliceMaxRedeem, 0, "Alice maxRedeem should be 0 with no liquidity");
            assertEq(bobMaxRedeem, 0, "Bob maxRedeem should be 0 with no liquidity");
        }
    }

    /* ========== INTEGRATION WITH REDEEM TESTS ========== */

    /// @notice Tests that actual redeem respects maxRedeem limit
    /// @dev Attempting to redeem more than maxRedeem should fail
    function test_Redeem_RespectsMaxRedeemLimit() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Limit target vault liquidity
        targetVault.setLiquidityCap(50_000e6);

        uint256 maxRedeemable = vault.maxRedeem(alice);
        uint256 aliceShares = vault.balanceOf(alice);

        // Try to redeem more than maxRedeem (should revert due to liquidity)
        vm.expectRevert();
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        // Redeem exactly maxRedeem (should succeed)
        vm.prank(alice);
        vault.redeem(maxRedeemable, alice, alice);
    }

    /// @notice Tests that maxRedeem accurately predicts successful redeem amount
    /// @dev If maxRedeem returns N shares, redeeming N shares should succeed
    function test_Redeem_SucceedsWithMaxRedeemAmount() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Limit target vault liquidity
        targetVault.setLiquidityCap(70_000e6);

        uint256 maxRedeemable = vault.maxRedeem(alice);

        // Redeem exactly maxRedeem amount (should succeed)
        vm.prank(alice);
        uint256 assetsReceived = vault.redeem(maxRedeemable, alice, alice);

        assertGt(assetsReceived, 0, "Should receive assets from redemption");
    }

    /// @notice Tests maxRedeem with zero total supply edge case
    /// @dev When vault is empty, maxRedeem should return 0
    function test_MaxRedeem_WithZeroTotalSupply() public view {
        // Vault is empty initially
        uint256 maxRedeemable = vault.maxRedeem(alice);
        assertEq(maxRedeemable, 0, "MaxRedeem should be 0 when total supply is 0");
    }

    /// @notice Tests maxRedeem after all users redeem (vault becomes empty)
    /// @dev After complete redemption, maxRedeem should be 0
    function test_MaxRedeem_AfterCompleteRedemption() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 aliceShares = vault.balanceOf(alice);

        // Alice redeems all shares
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        uint256 maxRedeemableAfter = vault.maxRedeem(alice);
        assertEq(maxRedeemableAfter, 0, "MaxRedeem should be 0 after complete redemption");
    }

    /// @notice Tests maxRedeem is non-decreasing when liquidity increases
    /// @dev As target vault liquidity increases, maxRedeem should not decrease
    function test_MaxRedeem_NonDecreasingWithLiquidityIncrease() public {
        // Alice deposits 100k USDC
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Start with limited liquidity
        targetVault.setLiquidityCap(30_000e6);
        uint256 maxRedeem1 = vault.maxRedeem(alice);

        // Increase liquidity
        targetVault.setLiquidityCap(60_000e6);
        uint256 maxRedeem2 = vault.maxRedeem(alice);

        // Increase liquidity further
        targetVault.setLiquidityCap(100_000e6);
        uint256 maxRedeem3 = vault.maxRedeem(alice);

        assertLe(maxRedeem1, maxRedeem2, "MaxRedeem should not decrease when liquidity increases");
        assertLe(maxRedeem2, maxRedeem3, "MaxRedeem should not decrease when liquidity increases further");
    }
}
