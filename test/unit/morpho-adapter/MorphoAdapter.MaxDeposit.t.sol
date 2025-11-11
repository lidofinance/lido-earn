// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./MorphoAdapterTestBase.sol";
import {Vault} from "src/Vault.sol";

contract MorphoAdapterMaxDepositTest is MorphoAdapterTestBase {
    function test_MaxDeposit_RespectsMorphoLimits() public view {
        uint256 vaultMaxDeposit = vault.maxDeposit(alice);
        uint256 morphoMaxDeposit = morpho.maxDeposit(address(vault));

        assertEq(vaultMaxDeposit, morphoMaxDeposit, "MaxDeposit should match Morpho limits");
    }

    function test_MaxDeposit_ReturnsZeroWhenPaused() public {
        vm.prank(address(this));
        vault.pause();

        uint256 vaultMaxDeposit = vault.maxDeposit(alice);

        assertEq(vaultMaxDeposit, 0, "MaxDeposit should be 0 when paused");
    }

    function test_MaxMint_RespectsMorphoLimits() public {
        morpho.setLiquidityCap(1_000_000e6);

        uint256 maxMint = vault.maxMint(alice);
        uint256 morphoMaxDeposit = morpho.maxDeposit(address(vault));
        uint256 expectedMaxMint = vault.convertToShares(morphoMaxDeposit);

        assertEq(maxMint, expectedMaxMint, "MaxMint should match converted Morpho limits");
    }

    function test_MaxMint_ReturnsZeroWhenPaused() public {
        vm.prank(address(this));
        vault.pause();

        uint256 maxMint = vault.maxMint(alice);

        assertEq(maxMint, 0, "MaxMint should be 0 when paused");
    }

    function test_Deposit_RevertIf_ExceedsMaxDeposit() public {
        morpho.setLiquidityCap(100_000e6);

        uint256 vaultMaxDeposit = vault.maxDeposit(alice);

        uint256 excessiveAmount = vaultMaxDeposit + 1e6;

        vm.expectRevert(
            abi.encodeWithSelector(Vault.ExceedsMaxDeposit.selector, excessiveAmount, vaultMaxDeposit)
        );
        vm.prank(alice);
        vault.deposit(excessiveAmount, alice);
    }

    function test_Mint_RevertIf_ExceedsMaxDeposit() public {
        morpho.setLiquidityCap(100_000e6);

        uint256 maxDep = vault.maxDeposit(alice);

        uint256 excessiveShares = vault.convertToShares(maxDep) + 1e6;

        vm.expectRevert();
        vm.prank(alice);
        vault.mint(excessiveShares, alice);
    }

    function test_Mint_ChecksMaxDepositAfterHarvest() public {
        morpho.setLiquidityCap(100_000e6);

        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        uint256 sharesBefore = vault.totalSupply();
        assertEq(sharesBefore, 50_000e6 * 10 ** vault.OFFSET());

        uint256 profit = 5_000e6;
        usdc.mint(address(morpho), profit);

        uint256 maxDep = vault.maxDeposit(bob);

        uint256 sharesToMint = vault.previewDeposit(maxDep);

        uint256 previewedAssets = vault.previewMint(sharesToMint);

        assertApproxEqAbs(previewedAssets, maxDep, 10, "PreviewMint should be accurate");

        vm.prank(bob);
        uint256 actualAssets = vault.mint(sharesToMint, bob);

        assertApproxEqAbs(actualAssets, previewedAssets, 10, "Actual mint should match preview");

        assertTrue(actualAssets <= maxDep + 10, "Should not exceed maxDeposit");

        uint256 totalAssetsFinal = vault.totalAssets();
        assertTrue(totalAssetsFinal <= 100_000e6, "Should not exceed Morpho cap");

        uint256 bobShares = vault.balanceOf(bob);
        assertEq(bobShares, sharesToMint, "Bob should receive requested shares");

        uint256 treasuryShares = vault.balanceOf(treasury);
        assertTrue(treasuryShares > 0, "Treasury should receive fee shares");
    }

    function test_MaxDeposit_UpdatesAfterDeposit() public {
        uint256 initialMaxDeposit = vault.maxDeposit(alice);

        uint256 depositAmount = 10_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 newMaxDeposit = vault.maxDeposit(alice);

        assertLe(newMaxDeposit, initialMaxDeposit, "MaxDeposit should not increase after deposit");
    }

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

    function test_Deposit_WithCap_UpdatesMaxDeposit() public {
        morpho.setLiquidityCap(100_000e6);

        uint256 initialMaxDeposit = vault.maxDeposit(alice);

        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 newMaxDeposit = vault.maxDeposit(alice);
        assertLt(newMaxDeposit, initialMaxDeposit, "MaxDeposit should decrease after deposit");
        assertEq(newMaxDeposit, initialMaxDeposit - 10_000e6, "MaxDeposit should decrease by deposit amount");
    }
}
