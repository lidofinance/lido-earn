// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ERC4626AdapterTestBase.sol";
import {Vault} from "src/Vault.sol";

contract ERC4626AdapterMaxDepositTest is ERC4626AdapterTestBase {
    /// @notice Tests that max deposit respects target vault limits.
    /// @dev Validates that max deposit respects target vault limits.
    function test_MaxDeposit_RespectsTargetVaultLimits() public view {
        uint256 vaultMaxDeposit = vault.maxDeposit(alice);
        uint256 targetMaxDeposit = targetVault.maxDeposit(address(vault));

        assertEq(vaultMaxDeposit, targetMaxDeposit, "MaxDeposit should match target vault limits");
    }

    /// @notice Tests that max deposit returns zero when paused.
    /// @dev Validates that max deposit returns zero when paused.
    function test_MaxDeposit_ReturnsZeroWhenPaused() public {
        vm.prank(address(this));
        vault.pause();

        uint256 vaultMaxDeposit = vault.maxDeposit(alice);

        assertEq(vaultMaxDeposit, 0, "MaxDeposit should be 0 when paused");
    }

    /// @notice Tests that max deposit returns zero when emergency mode is active.
    /// @dev Emergency mode blocks new exposure even if the vault is not formally paused.
    function test_MaxDeposit_ReturnsZeroInEmergencyMode() public {
        vm.prank(address(this));
        vault.activateEmergencyMode();

        uint256 vaultMaxDeposit = vault.maxDeposit(alice);

        assertEq(vaultMaxDeposit, 0, "MaxDeposit should be 0 during emergency mode");
    }

    function test_MaxMint_ReturnsMaxUint_WhenTargetVaultUnlimited() public view {
        // Verify target vault has unlimited capacity
        uint256 targetMaxDeposit = targetVault.maxDeposit(address(vault));
        assertEq(targetMaxDeposit, type(uint256).max, "Target should be unlimited");

        // Verify adapter propagates unlimited capacity
        uint256 adapterMaxMint = vault.maxMint(alice);
        assertEq(adapterMaxMint, type(uint256).max, "Should return max uint");
      }

    /// @notice Tests that max mint respects target vault limits.
    /// @dev Validates that max mint respects target vault limits.
    function test_MaxMint_RespectsTargetVaultLimits() public {
        targetVault.setLiquidityCap(1_000_000e6);

        uint256 maxMint = vault.maxMint(alice);
        uint256 targetMaxDeposit = targetVault.maxDeposit(address(vault));
        uint256 expectedMaxMint = vault.convertToShares(targetMaxDeposit);

        assertEq(maxMint, expectedMaxMint, "MaxMint should match converted target limits");
    }

    /// @notice Tests that max mint returns zero when paused.
    /// @dev Validates that max mint returns zero when paused.
    function test_MaxMint_ReturnsZeroWhenPaused() public {
        vm.prank(address(this));
        vault.pause();

        uint256 maxMint = vault.maxMint(alice);

        assertEq(maxMint, 0, "MaxMint should be 0 when paused");
    }

    /// @notice Tests that max mint returns zero when emergency mode is active.
    /// @dev Ensures integrations see zero capacity once emergency mode triggers.
    function test_MaxMint_ReturnsZeroInEmergencyMode() public {
        vm.prank(address(this));
        vault.activateEmergencyMode();

        uint256 maxMint = vault.maxMint(alice);

        assertEq(maxMint, 0, "MaxMint should be 0 during emergency mode");
    }

    /// @notice Ensures deposit reverts when exceeds max deposit.
    /// @dev Verifies the revert protects against exceeds max deposit.
    function test_Deposit_RevertIf_ExceedsMaxDeposit() public {
        targetVault.setLiquidityCap(100_000e6);

        uint256 vaultMaxDeposit = vault.maxDeposit(alice);

        uint256 excessiveAmount = vaultMaxDeposit + 1e6;

        vm.expectRevert(abi.encodeWithSelector(Vault.ExceedsMaxDeposit.selector, excessiveAmount, vaultMaxDeposit));
        vm.prank(alice);
        vault.deposit(excessiveAmount, alice);
    }

    /// @notice Ensures mint reverts when exceeds max deposit.
    /// @dev Verifies the revert protects against exceeds max deposit.
    function test_Mint_RevertIf_ExceedsMaxDeposit() public {
        targetVault.setLiquidityCap(100_000e6);

        uint256 maxDep = vault.maxDeposit(alice);

        uint256 excessiveShares = vault.convertToShares(maxDep) + 1e6;

        vm.expectRevert();
        vm.prank(alice);
        vault.mint(excessiveShares, alice);
    }

    /// @notice Tests that mint checks max deposit after harvest.
    /// @dev Validates that mint checks max deposit after harvest.
    function test_Mint_ChecksMaxDepositAfterHarvest() public {
        targetVault.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        uint256 sharesBefore = vault.totalSupply();
        assertEq(sharesBefore, 50_000e6 * 10 ** vault.OFFSET());

        uint256 profit = 5_000e6;
        usdc.mint(address(targetVault), profit);

        uint256 maxDep = vault.maxDeposit(bob);

        uint256 sharesToMint = vault.previewDeposit(maxDep);

        uint256 previewedAssets = vault.previewMint(sharesToMint);

        assertApproxEqAbs(previewedAssets, maxDep, 10, "PreviewMint should be accurate");

        vm.prank(bob);
        uint256 actualAssets = vault.mint(sharesToMint, bob);

        assertApproxEqAbs(actualAssets, previewedAssets, 10, "Actual mint should match preview");

        assertTrue(actualAssets <= maxDep + 10, "Should not exceed maxDeposit");

        uint256 totalAssetsFinal = vault.totalAssets();
        assertTrue(totalAssetsFinal <= 100_000e6, "Should not exceed target vault cap");

        uint256 bobShares = vault.balanceOf(bob);
        assertEq(bobShares, sharesToMint, "Bob should receive requested shares");

        uint256 treasuryShares = vault.balanceOf(treasury);
        assertTrue(treasuryShares > 0, "Treasury should receive fee shares");
    }

    /// @notice Tests that max deposit updates after deposit.
    /// @dev Validates that max deposit updates after deposit.
    function test_MaxDeposit_UpdatesAfterDeposit() public {
        uint256 initialMaxDeposit = vault.maxDeposit(alice);

        uint256 depositAmount = 10_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 newMaxDeposit = vault.maxDeposit(alice);

        assertLe(newMaxDeposit, initialMaxDeposit, "MaxDeposit should not increase after deposit");
    }

    /// @notice Fuzzes that max deposit updates after deposit.
    /// @dev Validates that max deposit updates after deposit.
    function testFuzz_MaxDeposit_UpdatesAfterDeposit(uint96 depositAmount) public {
        uint256 initialMaxDeposit = vault.maxDeposit(alice);
        uint256 minDeposit = 1;
        // Если maxDeposit меньше minDeposit, пропускаем тест
        vm.assume(initialMaxDeposit >= minDeposit);
        // Ограничиваем верхнюю границу для избежания проблем с bound
        uint256 maxBound = initialMaxDeposit > type(uint96).max ? type(uint96).max : initialMaxDeposit;
        uint256 deposit = bound(uint256(depositAmount), minDeposit, maxBound);
        usdc.mint(alice, deposit);

        vm.prank(alice);
        vault.deposit(deposit, alice);

        uint256 newMaxDeposit = vault.maxDeposit(alice);

        assertLe(newMaxDeposit, initialMaxDeposit, "MaxDeposit should not increase after deposit");
    }

    /// @notice Tests that max deposit multiple deposits approaching cap.
    /// @dev Validates that max deposit multiple deposits approaching cap.
    function test_MaxDeposit_MultipleDepositsApproachingCap() public {
        uint256 maxDeposit = vault.maxDeposit(alice);

        if (maxDeposit < type(uint256).max / 2) {
            uint256 halfCap = maxDeposit / 2;

            vm.prank(alice);
            vault.deposit(halfCap, alice);

            uint256 remainingCap = vault.maxDeposit(alice);

            vm.prank(bob);
            vault.deposit(remainingCap, bob);

            uint256 finalMaxDeposit = vault.maxDeposit(alice);
            assertLe(finalMaxDeposit, maxDeposit / 1000, "MaxDeposit should be nearly exhausted");
        }
    }

    /// @notice Tests that deposit with cap updates max deposit.
    /// @dev Validates that deposit with cap updates max deposit.
    function test_Deposit_WithCap_UpdatesMaxDeposit() public {
        targetVault.setLiquidityCap(100_000e6);

        uint256 initialMaxDeposit = vault.maxDeposit(alice);

        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 newMaxDeposit = vault.maxDeposit(alice);
        assertLt(newMaxDeposit, initialMaxDeposit, "MaxDeposit should decrease after deposit");
        assertEq(newMaxDeposit, initialMaxDeposit - 10_000e6, "MaxDeposit should decrease by deposit amount");
    }

    /// @notice Fuzzes that deposit with cap updates max deposit.
    /// @dev Validates that deposit with cap updates max deposit.
    function testFuzz_Deposit_WithCap_UpdatesMaxDeposit(uint96 capAmount, uint96 depositAmount) public {
        uint256 cap = bound(uint256(capAmount), 1 * 2, type(uint96).max);
        uint256 deposit = bound(uint256(depositAmount), 1, cap / 2); // deposit должен быть меньше половины cap для теста
        usdc.mint(alice, deposit);

        targetVault.setLiquidityCap(cap);

        uint256 initialMaxDeposit = vault.maxDeposit(alice);

        vm.prank(alice);
        vault.deposit(deposit, alice);

        uint256 newMaxDeposit = vault.maxDeposit(alice);
        assertLt(newMaxDeposit, initialMaxDeposit, "MaxDeposit should decrease after deposit");
        assertEq(newMaxDeposit, initialMaxDeposit - deposit, "MaxDeposit should decrease by deposit amount");
    }

    /// @notice Tests deposit with pending fees - harvest happens before checking cap
    /// @dev Verifies that deposit() harvests fees BEFORE checking maxDeposit,
    ///      so the fee dilution is already applied when cap check happens
    function test_Deposit_WithFeeDilution_StaysWithinCap() public {
        targetVault.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(90_000e6, alice);

        uint256 profit = 5_000e6;
        usdc.mint(address(targetVault), profit);

        uint256 maxDepositBefore = vault.maxDeposit(bob);
        assertEq(maxDepositBefore, 5_000e6, "maxDeposit should be exactly 5,000 USDC");

        uint256 depositAmount = 4_900e6;
        uint256 previewedShares = vault.previewDeposit(depositAmount);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(depositAmount, bob);

        uint256 actualAssetsWorth = vault.convertToAssets(actualShares);
        uint256 previewedAssetsWorth = vault.convertToAssets(previewedShares);

        assertApproxEqAbs(actualAssetsWorth, previewedAssetsWorth, 2, "Actual should match preview in asset terms");

        uint256 totalAssetsAfter = vault.totalAssets();
        assertLe(totalAssetsAfter, 100_000e6, "Should not exceed target vault cap");
    }

    /// @notice Tests that deposit reverts when target vault exceeds cap due to profits
    /// @dev When totalAssets > liquidityCap, maxDeposit returns 0, blocking new deposits
    function test_Deposit_WithLargeFeeDilution_MaxDepositBecomesZero() public {
        targetVault.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(95_000e6, alice);

        uint256 profit = 47_500e6;
        usdc.mint(address(targetVault), profit);

        uint256 maxDep = vault.maxDeposit(bob);
        assertEq(maxDep, 0, "maxDeposit should be 0 when totalAssets exceeds cap");

        vm.expectRevert(abi.encodeWithSelector(Vault.ExceedsMaxDeposit.selector, 1000e6, 0));
        vm.prank(bob);
        vault.deposit(1000e6, bob);
    }

    /// @notice Tests the critical difference between convertToAssets and previewDeposit with pending fees
    /// @dev Demonstrates that:
    ///      - convertToAssets: snapshot function, doesn't account for harvest
    ///      - previewDeposit: simulation function, accounts for harvest and fee dilution
    ///      This difference is crucial for understanding share calculations with pending fees
    function test_Deposit_ConvertToAssetsVsPreviewDeposit_WithPendingFees() public {
        targetVault.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(80_000e6, alice);

        uint256 profit = 10_000e6;
        usdc.mint(address(targetVault), profit);

        uint256 maxDep = vault.maxDeposit(bob);
        assertEq(maxDep, 10_000e6, "maxDeposit should be exactly 10,000 USDC");

        uint256 assetsAmount = 9_000e6;

        uint256 sharesFromConvert = vault.convertToShares(assetsAmount);
        uint256 sharesFromPreview = vault.previewDeposit(assetsAmount);

        assertGt(sharesFromPreview, sharesFromConvert, "Preview should return more shares due to fee share minting");

        vm.prank(bob);
        uint256 actualShares = vault.deposit(assetsAmount, bob);

        uint256 actualAssetsWorth = vault.convertToAssets(actualShares);
        uint256 previewedAssetsWorth = vault.convertToAssets(sharesFromPreview);

        assertApproxEqAbs(actualAssetsWorth, previewedAssetsWorth, 2, "Actual should match preview in asset terms");
        assertLe(vault.totalAssets(), 100_000e6, "Should not exceed target vault cap");
    }

    /// @notice Tests that mint with fee dilution stays within cap.
    /// @dev Validates that mint with fee dilution stays within cap.
    function test_Mint_WithFeeDilution_StaysWithinCap() public {
        targetVault.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(90_000e6, alice);

        uint256 profit = 5_000e6;
        usdc.mint(address(targetVault), profit);

        uint256 maxDepositBefore = vault.maxDeposit(bob);
        assertEq(maxDepositBefore, 5_000e6, "maxDeposit should be exactly 5,000 USDC");

        uint256 sharesToMint = vault.convertToShares(4_900e6);
        uint256 previewedAssets = vault.previewMint(sharesToMint);

        vm.prank(bob);
        uint256 actualAssets = vault.mint(sharesToMint, bob);

        assertApproxEqAbs(actualAssets, previewedAssets, 2, "Actual should match preview");

        uint256 totalAssetsAfter = vault.totalAssets();
        assertLe(totalAssetsAfter, 100_000e6, "Should not exceed target vault cap");
    }

    /// @notice Tests that maxDeposit returns 0 when target vault already exceeds cap due to profits
    /// @dev When totalAssets > liquidityCap, the target vault returns maxDeposit = 0, blocking new deposits
    function test_Mint_WithLargeFeeDilution_MaxDepositBecomesZero() public {
        targetVault.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(95_000e6, alice);

        uint256 profit = 47_500e6;
        usdc.mint(address(targetVault), profit);

        uint256 maxDep = vault.maxDeposit(bob);
        assertEq(maxDep, 0, "maxDeposit should be 0 when totalAssets exceeds cap");

        vm.expectRevert(abi.encodeWithSelector(Vault.ExceedsMaxDeposit.selector, 1000e6, 0));
        vm.prank(bob);
        vault.deposit(1000e6, bob);

        uint256 sharesToMint = 1000e6 * 10 ** vault.OFFSET();
        vm.expectRevert();
        vm.prank(bob);
        vault.mint(sharesToMint, bob);
    }

    /// @notice Tests the critical difference between convertToShares and previewMint with pending fees
    /// @dev Demonstrates that:
    ///      - convertToShares: snapshot function, doesn't account for harvest
    ///      - previewMint: simulation function, accounts for harvest and fee dilution
    ///      This difference is crucial for understanding cap checks and user expectations
    function test_Mint_ConvertToSharesVsPreviewMint_WithPendingFees() public {
        targetVault.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(80_000e6, alice);

        uint256 profit = 10_000e6;
        usdc.mint(address(targetVault), profit);

        uint256 maxDep = vault.maxDeposit(bob);
        assertEq(maxDep, 10_000e6, "maxDeposit should be exactly 10,000 USDC");

        uint256 assetsAmount = 9_000e6;

        uint256 sharesFromConvert = vault.convertToShares(assetsAmount);
        uint256 sharesFromPreview = vault.previewDeposit(assetsAmount);

        assertGt(sharesFromPreview, sharesFromConvert, "Preview should return more shares due to fee share minting");

        uint256 sharesToMint = sharesFromConvert;
        uint256 assetsFromPreviewMint = vault.previewMint(sharesToMint);

        assertLt(assetsFromPreviewMint, assetsAmount, "PreviewMint should require fewer assets after harvest");

        vm.prank(bob);
        uint256 actualAssets = vault.mint(sharesToMint, bob);

        assertApproxEqAbs(actualAssets, assetsFromPreviewMint, 2, "Actual should match preview");
        assertLe(vault.totalAssets(), 100_000e6, "Should not exceed target vault cap");
    }
}
