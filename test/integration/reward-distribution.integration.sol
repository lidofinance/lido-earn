// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MorphoVault} from "src/vaults/MorphoVault.sol";
import {MockMetaMorpho} from "test/mocks/MockMetaMorpho.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract RewardDistributionIntegrationTest is Test {
    MorphoVault public vault;
    MockMetaMorpho public morpho;
    MockERC20 public usdc;

    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 constant INITIAL_BALANCE = 1_000_000e6;
    uint16 constant REWARD_FEE = 500;
    uint8 constant OFFSET = 6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);

        morpho = new MockMetaMorpho(
            IERC20(address(usdc)),
            "Mock Morpho USDC",
            "mUSDC",
            OFFSET
        );

        vault = new MorphoVault(
            address(usdc),
            address(morpho),
            treasury,
            REWARD_FEE,
            OFFSET,
            "Morpho USDC Vault",
            "mvUSDC"
        );

        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(charlie, INITIAL_BALANCE);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(charlie);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _getSharePrice() internal view returns (uint256) {
        return vault.convertToAssets(10 ** OFFSET);
    }

    function _addRewardsByBasisPoints(uint256 basisPoints) internal {
        uint256 currentBalance = usdc.balanceOf(address(morpho));
        uint256 yieldAmount = (currentBalance * basisPoints) / 10000;
        usdc.mint(address(morpho), yieldAmount);
    }

    function _addRewardsByAmount(uint256 amount) internal {
        usdc.mint(address(morpho), amount);
    }

    function test_RewardDistribution_HappyPath() public {
        uint256 vaultBalanceBefore = vault.totalAssets();
        uint256 vaultBalanceAfter;

        // Alice deposit
        {
            assertEq(vaultBalanceBefore, 0);

            uint256 aliceSharesBefore = vault.balanceOf(address(alice));
            uint256 aliceBalanceBefore = vault.convertToAssets(
                aliceSharesBefore
            );
            uint256 treasurySharesBefore = vault.balanceOf(treasury);

            uint256 deposit = 10_000e6;
            uint256 expectedSharesDiff = vault.convertToShares(deposit);

            vm.prank(alice);
            vault.deposit(deposit, address(alice));

            vaultBalanceAfter = vault.totalAssets();
            uint256 aliceSharesAfter = vault.balanceOf(address(alice));
            uint256 treasurySharesAfter = vault.balanceOf(treasury);

            assertEq(aliceSharesBefore + expectedSharesDiff, aliceSharesAfter);
            assertEq(vaultBalanceBefore + deposit, vaultBalanceAfter);
            assertEq(
                aliceBalanceBefore + deposit,
                vault.convertToAssets(aliceSharesAfter)
            );
            // No treasury changes on first deposit (no rewards yet)
            assertEq(treasurySharesBefore, treasurySharesAfter);
        }

        // First rewards distribution (0.1%)
        {
            vaultBalanceBefore = vault.totalAssets();

            uint256 aliceShares = vault.balanceOf(address(alice));
            uint256 aliceBalanceBefore = vault.convertToAssets(aliceShares);
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 rewardsAmount = (vaultBalanceBefore * 10) / 10000;

            _addRewardsByAmount(rewardsAmount);

            uint256 aliceBalanceAfter = vault.convertToAssets(aliceShares);
            uint256 treasurySharesAfter = vault.balanceOf(treasury);

            assertEq(aliceShares, vault.balanceOf(address(alice)));
            assertApproxEqAbs(
                aliceBalanceBefore + rewardsAmount,
                aliceBalanceAfter,
                2
            );
            // Treasury should not change yet (no _harvestFees() called)
            assertEq(treasurySharesBefore, treasurySharesAfter);
        }

        // Bob deposit
        {
            vaultBalanceBefore = vault.totalAssets();
            uint256 bobSharesBefore = vault.balanceOf(address(bob));
            uint256 bobBalanceBefore = vault.convertToAssets(bobSharesBefore);
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 totalSupplyBefore = vault.totalSupply();

            uint256 lastAssets = vault.lastTotalAssets();
            uint256 profit = vaultBalanceBefore - lastAssets;
            uint256 expectedFeeAmount = (profit * 500) / 10000;
            uint256 expectedTreasuryShares = (expectedFeeAmount *
                totalSupplyBefore) / (vaultBalanceBefore - expectedFeeAmount);

            uint256 deposit = 5_000e6;

            vm.prank(bob);
            uint256 actualShares = vault.deposit(deposit, address(bob));

            uint256 bobSharesAfter = vault.balanceOf(address(bob));
            uint256 treasurySharesAfter = vault.balanceOf(treasury);
            vaultBalanceAfter = vault.totalAssets();

            assertEq(bobSharesBefore + actualShares, bobSharesAfter);
            assertEq(vaultBalanceBefore + deposit, vaultBalanceAfter);
            assertApproxEqAbs(
                bobBalanceBefore + deposit,
                vault.convertToAssets(bobSharesAfter),
                2
            );
            assertEq(
                treasurySharesAfter,
                treasurySharesBefore + expectedTreasuryShares
            );
        }

        // Second rewards distribution (0.1%)
        {
            vaultBalanceBefore = vault.totalAssets();

            uint256 aliceShares = vault.balanceOf(address(alice));
            uint256 bobShares = vault.balanceOf(address(bob));
            uint256 aliceBalanceBefore = vault.convertToAssets(aliceShares);
            uint256 bobBalanceBefore = vault.convertToAssets(bobShares);
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 rewardsAmount = (vaultBalanceBefore * 10) / 10000;

            _addRewardsByAmount(rewardsAmount);

            uint256 aliceBalanceAfter = vault.convertToAssets(aliceShares);
            uint256 bobBalanceAfter = vault.convertToAssets(bobShares);
            uint256 treasurySharesAfter = vault.balanceOf(treasury);

            assertEq(aliceShares, vault.balanceOf(address(alice)));
            assertEq(bobShares, vault.balanceOf(address(bob)));

            assertApproxEqAbs(
                aliceBalanceBefore +
                    (rewardsAmount * aliceBalanceBefore) /
                    vaultBalanceBefore,
                aliceBalanceAfter,
                2
            );
            assertApproxEqAbs(
                bobBalanceBefore +
                    (rewardsAmount * bobBalanceBefore) /
                    vaultBalanceBefore,
                bobBalanceAfter,
                2
            );
            // Treasury shares don't change (no _harvestFees() called)
            assertEq(treasurySharesBefore, treasurySharesAfter);
        }

        // Charlie deposit
        {
            vaultBalanceBefore = vault.totalAssets();
            uint256 charlieSharesBefore = vault.balanceOf(address(charlie));
            uint256 charlieBalanceBefore = vault.convertToAssets(
                charlieSharesBefore
            );
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 totalSupplyBefore = vault.totalSupply();

            uint256 lastAssets = vault.lastTotalAssets();
            uint256 profit = vaultBalanceBefore - lastAssets;
            uint256 expectedFeeAmount = (profit * 500) / 10000;
            uint256 expectedTreasuryShares = (expectedFeeAmount *
                totalSupplyBefore) / (vaultBalanceBefore - expectedFeeAmount);

            uint256 deposit = 7_500e6;

            vm.prank(charlie);
            uint256 actualShares = vault.deposit(deposit, address(charlie));

            uint256 charlieSharesAfter = vault.balanceOf(address(charlie));
            uint256 treasurySharesAfter = vault.balanceOf(treasury);
            vaultBalanceAfter = vault.totalAssets();

            assertEq(charlieSharesBefore + actualShares, charlieSharesAfter);
            assertEq(vaultBalanceBefore + deposit, vaultBalanceAfter);
            assertApproxEqAbs(
                charlieBalanceBefore + deposit,
                vault.convertToAssets(charlieSharesAfter),
                2
            );
            assertEq(
                treasurySharesAfter,
                treasurySharesBefore + expectedTreasuryShares
            );
        }

        // Third rewards distribution (0.2%)
        {
            vaultBalanceBefore = vault.totalAssets();

            uint256 aliceShares = vault.balanceOf(address(alice));
            uint256 bobShares = vault.balanceOf(address(bob));
            uint256 charlieShares = vault.balanceOf(address(charlie));
            uint256 aliceBalanceBefore = vault.convertToAssets(aliceShares);
            uint256 bobBalanceBefore = vault.convertToAssets(bobShares);
            uint256 charlieBalanceBefore = vault.convertToAssets(charlieShares);
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 rewardsAmount = (vaultBalanceBefore * 20) / 10000;

            _addRewardsByAmount(rewardsAmount);

            uint256 aliceBalanceAfter = vault.convertToAssets(aliceShares);
            uint256 bobBalanceAfter = vault.convertToAssets(bobShares);
            uint256 charlieBalanceAfter = vault.convertToAssets(charlieShares);
            uint256 treasurySharesAfter = vault.balanceOf(treasury);

            assertEq(aliceShares, vault.balanceOf(address(alice)));
            assertEq(bobShares, vault.balanceOf(address(bob)));
            assertEq(charlieShares, vault.balanceOf(address(charlie)));
            // Treasury shares don't change (no _harvestFees() called)
            assertEq(treasurySharesBefore, treasurySharesAfter);

            assertApproxEqAbs(
                aliceBalanceBefore +
                    (rewardsAmount * aliceBalanceBefore) /
                    vaultBalanceBefore,
                aliceBalanceAfter,
                2
            );
            assertApproxEqAbs(
                bobBalanceBefore +
                    (rewardsAmount * bobBalanceBefore) /
                    vaultBalanceBefore,
                bobBalanceAfter,
                2
            );
            assertApproxEqAbs(
                charlieBalanceBefore +
                    (rewardsAmount * charlieBalanceBefore) /
                    vaultBalanceBefore,
                charlieBalanceAfter,
                2
            );
        }

        // Alice withdraws all
        {
            uint256 aliceShares = vault.balanceOf(address(alice));
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 totalSupplyBefore = vault.totalSupply();
            uint256 totalAssetsBefore = vault.totalAssets();

            uint256 lastAssets = vault.lastTotalAssets();
            uint256 profit = totalAssetsBefore - lastAssets;
            uint256 expectedAdditionalTreasuryShares = 0;
            if (profit > 0) {
                uint256 expectedFeeAmount = (profit * 500) / 10000;
                expectedAdditionalTreasuryShares =
                    (expectedFeeAmount * totalSupplyBefore) /
                    (totalAssetsBefore - expectedFeeAmount);
            }

            uint256 aliceUsdcBefore = usdc.balanceOf(address(alice));

            vm.prank(alice);
            uint256 aliceActualAssets = vault.redeem(
                aliceShares,
                address(alice),
                address(alice)
            );

            uint256 aliceUsdcAfter = usdc.balanceOf(address(alice));
            uint256 treasurySharesAfter = vault.balanceOf(treasury);

            assertEq(vault.balanceOf(address(alice)), 0);
            assertEq(aliceUsdcAfter - aliceUsdcBefore, aliceActualAssets);

            uint256 expectedTotalTreasuryShares = treasurySharesBefore +
                expectedAdditionalTreasuryShares;
            assertEq(treasurySharesAfter, expectedTotalTreasuryShares);
        }

        // Bob withdraws all
        {
            uint256 bobShares = vault.balanceOf(address(bob));
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 bobUsdcBefore = usdc.balanceOf(address(bob));

            vm.prank(bob);
            uint256 bobActualAssets = vault.redeem(
                bobShares,
                address(bob),
                address(bob)
            );

            uint256 bobUsdcAfter = usdc.balanceOf(address(bob));
            uint256 treasurySharesAfter = vault.balanceOf(treasury);

            assertEq(vault.balanceOf(address(bob)), 0);
            assertEq(bobUsdcAfter - bobUsdcBefore, bobActualAssets);

            assertEq(treasurySharesAfter, treasurySharesBefore);
        }

        // Charlie withdraws all
        {
            uint256 charlieShares = vault.balanceOf(address(charlie));
            uint256 treasurySharesBefore = vault.balanceOf(treasury);
            uint256 charlieUsdcBefore = usdc.balanceOf(address(charlie));

            vm.prank(charlie);
            uint256 charlieActualAssets = vault.redeem(
                charlieShares,
                address(charlie),
                address(charlie)
            );

            uint256 charlieUsdcAfter = usdc.balanceOf(address(charlie));
            uint256 treasurySharesAfter = vault.balanceOf(treasury);

            assertEq(vault.balanceOf(address(charlie)), 0);
            assertEq(charlieUsdcAfter - charlieUsdcBefore, charlieActualAssets);

            assertEq(treasurySharesAfter, treasurySharesBefore);

            assertEq(vault.totalSupply(), treasurySharesAfter);
            uint256 treasuryAssets = vault.convertToAssets(treasurySharesAfter);
            assertApproxEqAbs(vault.totalAssets(), treasuryAssets, 2);
        }
    }
}
