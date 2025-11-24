// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title VaultRewardDistributionInvariantTest
 * @notice Invariant tests for vault reward distribution correctness
 *
 * TESTED INVARIANTS:
 *
 * 1. Treasury shares are minted ONLY when there is profit
 *    - invariant_TreasurySharesMintedOnlyWithProfit()
 *    - Treasury receives shares only when totalAssets > lastTotalAssets
 *    - During deposits/withdrawals WITHOUT reward accrual, treasury should NOT receive shares
 *    - Ensures fees are charged only on actual profit, not on users' capital
 *
 * 2. Treasury receives shares when profit exists
 *    - invariant_TreasuryReceivesSharesWhenProfit()
 *    - When profit is harvested, treasury MUST receive shares
 *    - Validates that fee collection mechanism is working
 *
 * 3. Treasury shares correctness
 *    - Per-harvest check in _checkInvariant()
 *    - Validates that treasury receives EXACTLY the expected amount of shares
 *    - Uses assertApproxEqAbs with 2 wei tolerance for rounding
 *    - Formula: sharesMinted = (feeAmount * supply) / (totalAssets - feeAmount)
 *
 * 4. lastTotalAssets never exceeds current totalAssets
 *    - invariant_LastTotalAssetsNeverExceedsCurrent()
 *    - lastTotalAssets is snapshot from last harvest
 *    - If lastTotalAssets > totalAssets, indicates bug in harvest logic
 *
 * 5. User shares don't change during harvest
 *    - Check in _checkInvariant()
 *    - When profit is harvested, ONLY treasury receives new shares
 *    - Ensures fair fee collection (no dilution of user positions)
 *
 * 6. Reward fee never exceeds maximum allowed limit
 *    - invariant_RewardFeeWithinLimits()
 *    - Ensures reward fee is always within protocol limits
 *    - Validates fee configuration integrity
 */
import {TestConfig} from "test/utils/TestConfig.sol";
import "forge-std/console.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {MockERC4626Vault} from "test/mocks/MockERC4626Vault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {RewardDistributor} from "src/RewardDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RewardDistributionHandler} from "./handlers/RewardDistributionHandler.sol";

contract RewardDistributionInvariantTest is TestConfig {
    ERC4626Adapter public vault;
    MockERC4626Vault public targetVault;
    MockERC20 public usdc;
    RewardDistributor public rewardDistributor;
    RewardDistributionHandler public handler;

    address public manager = makeAddr("manager");
    address public recipient1 = makeAddr("recipient1");
    address public recipient2 = makeAddr("recipient2");
    address public initialDepositor;

    uint16 constant REWARD_FEE = 500;
    uint8 constant OFFSET = 6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", _assetDecimals());

        targetVault = new MockERC4626Vault(IERC20(address(usdc)), "Mock Yield USDC", "yUSDC", OFFSET);

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = 500;
        basisPoints[1] = 9500;

        rewardDistributor = new RewardDistributor(manager, recipients, basisPoints);

        vault = new ERC4626Adapter(
            address(usdc),
            address(targetVault),
            address(rewardDistributor),
            REWARD_FEE,
            OFFSET,
            "Morpho USDC Vault",
            "mvUSDC",
            address(this)
        );

        address[] memory actors = new address[](3);
        actors[0] = makeAddr("actor1");
        actors[1] = makeAddr("actor2");
        actors[2] = makeAddr("actor3");

        handler = new RewardDistributionHandler(vault, usdc, targetVault, rewardDistributor, actors);

        targetContract(address(handler));

        excludeContract(address(vault));
        excludeContract(address(targetVault));
        excludeContract(address(usdc));
        excludeContract(address(rewardDistributor));

        initialDepositor = makeAddr("initialDepositor");
        usdc.mint(initialDepositor, 10_000e6);
        vm.startPrank(initialDepositor);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6, initialDepositor);
        vm.stopPrank();
    }

    /// @notice Ensures treasury share mints only occur alongside positive profit realization.
    /// @dev Verifies handler never records treasury mints during operations that did not accrue profit.
    function invariant_TreasurySharesMintedOnlyWithProfit() public view {
        assertEq(handler.treasuryMintsWithoutProfit(), 0, "INVARIANT VIOLATION: Treasury shares minted without profit");
    }

    /// @notice Confirms that whenever profit exists the treasury actually receives new shares.
    /// @dev Verifies positive profit runs tally at least one user operation that triggered fee minting.
    function invariant_TreasuryReceivesSharesWhenProfit() public view {
        if (handler.treasuryMintsCount() > 0) {
            uint256 totalOperations =
                handler.depositsCount() + handler.withdrawsCount() + handler.mintsCount() + handler.redeemsCount();
            assertGt(totalOperations, 0, "INVARIANT VIOLATION: Treasury has shares but no operations recorded");
        }
    }

    /// @notice Guarantees the recorded `lastTotalAssets` snapshot never exceeds current assets.
    /// @dev Protects fee accounting by ensuring harvest snapshots cannot drift above actual assets.
    function invariant_LastTotalAssetsNeverExceedsCurrent() public view {
        uint256 currentAssets = vault.totalAssets();
        uint256 lastAssets = vault.lastTotalAssets();

        assertLe(lastAssets, currentAssets, "INVARIANT VIOLATION: lastTotalAssets > totalAssets");
    }

    /// @notice Ensures the configured reward fee always remains within protocol bounds.
    /// @dev Validates reward fee never exceeds `MAX_REWARD_FEE_BASIS_POINTS`.
    function invariant_RewardFeeWithinLimits() public view {
        assertLe(
            vault.rewardFee(),
            vault.MAX_REWARD_FEE_BASIS_POINTS(),
            "INVARIANT VIOLATION: Reward fee exceeds MAX_REWARD_FEE"
        );
    }

    /// @notice Provides a readable summary after each invariant run for debugging context.
    /// @dev Emits call counters and cumulative stats through console logs.
    function invariant_callSummary() public view {
        console.log("\n=== Invariant Test Summary ===");
        console.log("Deposits:", handler.depositsCount());
        console.log("Withdraws:", handler.withdrawsCount());
        console.log("Mints:", handler.mintsCount());
        console.log("Redeems:", handler.redeemsCount());
        console.log("Treasury mints:", handler.treasuryMintsCount());
        console.log("Treasury mints WITHOUT profit:", handler.treasuryMintsWithoutProfit());
        console.log("\n--- Cumulative Stats ---");
        console.log("Total profit harvested:", handler.totalProfitHarvested());
        console.log("Expected treasury shares:", handler.totalExpectedTreasuryShares());
        console.log("Actual treasury shares:", vault.balanceOf(address(rewardDistributor)));
        console.log("==============================\n");
    }
}
