// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MorphoAdapter} from "src/adapters/Morpho.sol";
import {MockMetaMorpho} from "test/mocks/MockMetaMorpho.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {RewardDistributor} from "src/RewardDistributor.sol";

/**
 * @title RewardDistributionHandler
 * @notice Handler for reward distribution invariant tests
 * @dev Executes vault operations and tracks reward distribution state
 */
contract RewardDistributionHandler is Test {
    using Math for uint256;

    MorphoAdapter public vault;
    MockERC20 public asset;
    MockMetaMorpho public morpho;
    RewardDistributor public rewardDistributor;

    address[] public actors;

    uint256 public treasurySharesBefore;
    uint256 public totalAssetsBefore;
    uint256 public lastTotalAssetsBefore;
    uint256 public totalSupplyBefore;

    mapping(address => uint256) public userSharesSnapshot;
    address public currentActor;

    uint256 public depositsCount;
    uint256 public withdrawsCount;
    uint256 public mintsCount;
    uint256 public redeemsCount;
    uint256 public treasuryMintsCount;
    uint256 public treasuryMintsWithoutProfit;

    uint256 public totalProfitHarvested;
    uint256 public totalExpectedTreasuryShares;

    constructor(
        MorphoAdapter _vault,
        MockERC20 _asset,
        MockMetaMorpho _morpho,
        RewardDistributor _rewardDistributor,
        address[] memory _actors
    ) {
        vault = _vault;
        asset = _asset;
        morpho = _morpho;
        rewardDistributor = _rewardDistributor;
        actors = _actors;

        for (uint256 i = 0; i < actors.length; i++) {
            asset.mint(actors[i], 1_000_000e6);
            vm.prank(actors[i]);
            asset.approve(address(vault), type(uint256).max);
        }
    }

    modifier captureState() {
        treasurySharesBefore = vault.balanceOf(address(rewardDistributor));
        totalAssetsBefore = vault.totalAssets();
        lastTotalAssetsBefore = vault.lastTotalAssets();
        totalSupplyBefore = vault.totalSupply();

        for (uint256 i = 0; i < actors.length; i++) {
            userSharesSnapshot[actors[i]] = vault.balanceOf(actors[i]);
        }

        _;
        _checkInvariant();
    }

    function _checkInvariant() internal {
        uint256 treasurySharesAfter = vault.balanceOf(address(rewardDistributor));
        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertTrue(
            treasurySharesAfter >= treasurySharesBefore, "INVARIANT VIOLATION: Treasury shares decreased (burned)"
        );

        bool hadProfit = totalAssetsBefore > lastTotalAssetsBefore;
        bool treasurySharesIncreased = treasurySharesAfter > treasurySharesBefore;

        if (treasurySharesIncreased) {
            treasuryMintsCount++;

            if (!hadProfit) {
                treasuryMintsWithoutProfit++;
                emit log_named_uint(
                    "Treasury shares minted WITHOUT profit!", treasurySharesAfter - treasurySharesBefore
                );
                emit log_named_uint("totalAssetsBefore", totalAssetsBefore);
                emit log_named_uint("lastTotalAssetsBefore", lastTotalAssetsBefore);
            }

            assertTrue(hadProfit, "INVARIANT VIOLATION: Treasury shares minted without profit");
        }

        if (hadProfit && lastTotalAssetsAfter > lastTotalAssetsBefore) {
            uint256 profit = totalAssetsBefore - lastTotalAssetsBefore;
            uint256 supply = totalSupplyBefore;

            totalProfitHarvested += profit;

            if (supply > 0 && profit > 0 && totalAssetsBefore > 0) {
                uint256 feeAmount = profit.mulDiv(vault.rewardFee(), vault.MAX_BASIS_POINTS(), Math.Rounding.Ceil);

                if (feeAmount > 0 && feeAmount < totalAssetsBefore) {
                    uint256 expectedTreasuryShares = (feeAmount * supply) / (totalAssetsBefore - feeAmount);

                    totalExpectedTreasuryShares += expectedTreasuryShares;

                    if (expectedTreasuryShares > 0) {
                        assertTrue(
                            treasurySharesIncreased,
                            "INVARIANT VIOLATION: Profit harvested but treasury received no shares"
                        );

                        uint256 actualSharesMinted = treasurySharesAfter - treasurySharesBefore;

                        assertApproxEqAbs(
                            actualSharesMinted,
                            expectedTreasuryShares,
                            2,
                            "INVARIANT VIOLATION: Treasury shares minted amount incorrect"
                        );
                    }
                }
            }

            for (uint256 i = 0; i < actors.length; i++) {
                if (actors[i] == currentActor) {
                    continue;
                }

                uint256 userSharesBefore = userSharesSnapshot[actors[i]];
                uint256 userSharesAfter = vault.balanceOf(actors[i]);

                assertTrue(
                    userSharesAfter == userSharesBefore, "INVARIANT VIOLATION: User shares changed during harvest"
                );
            }
        }
    }

    function deposit(uint256 actorSeed, uint256 amount) external captureState {
        amount = bound(amount, 1000, 100_000e6);

        address actor = actors[actorSeed % actors.length];
        currentActor = actor;

        uint256 balance = asset.balanceOf(actor);
        if (balance < amount) {
            asset.mint(actor, amount - balance);
        }

        vm.startPrank(actor);
        asset.approve(address(vault), amount);

        try vault.deposit(amount, actor) {
            depositsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Deposit failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external captureState {
        address actor = actors[actorSeed % actors.length];
        currentActor = actor;

        uint256 maxWithdraw = vault.maxWithdraw(actor);
        if (maxWithdraw == 0) return;

        amount = bound(amount, 1, maxWithdraw);

        vm.startPrank(actor);
        try vault.withdraw(amount, actor, actor) {
            withdrawsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Withdraw failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function mint(uint256 actorSeed, uint256 shares) external captureState {
        shares = bound(shares, 1000, 100_000e6);

        address actor = actors[actorSeed % actors.length];
        currentActor = actor;

        uint256 assetsRequired = vault.previewMint(shares);
        uint256 balance = asset.balanceOf(actor);

        if (balance < assetsRequired) {
            asset.mint(actor, assetsRequired - balance);
        }

        vm.startPrank(actor);
        asset.approve(address(vault), assetsRequired);

        try vault.mint(shares, actor) {
            mintsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Mint failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 shares) external captureState {
        address actor = actors[actorSeed % actors.length];
        currentActor = actor;

        uint256 maxRedeem = vault.balanceOf(actor);
        if (maxRedeem == 0) return;

        shares = bound(shares, 1, maxRedeem);

        vm.startPrank(actor);
        try vault.redeem(shares, actor, actor) {
            redeemsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Redeem failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function addRewards(uint256 amount) external captureState {
        currentActor = address(0);
        amount = bound(amount, 0, 10_000e6);

        if (amount > 0) {
            asset.mint(address(morpho), amount);
        }
    }
}
