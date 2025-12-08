// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "test/unit/erc4626-adapter/ERC4626AdapterTestBase.sol";
import "forge-std/console.sol";

/**
 * @title DonationTest
 * @notice Integration tests for donation scenarios where external parties donate target vault shares
 * @dev Tests the flow where someone deposits directly into target vault and transfers shares to our vault
 */
contract DonationTest is ERC4626AdapterTestBase {
    using Math for uint256;

    address public user1;
    address public user2;
    address public user3;
    address public donor;

    function setUp() public override {
        super.setUp();

        // Create 3 users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        donor = makeAddr("donor");

        // Give users and donor initial balances
        _dealAndApprove(user1, 100_000e6);
        _dealAndApprove(user2, 150_000e6);
        _dealAndApprove(user3, 200_000e6);
        _dealAndApprove(donor, 500_000e6);
    }

    /**
     * @notice Tests that donated target vault shares are properly accounted as profit and trigger fee harvest
     * @dev Scenario:
     *      1. Three users deposit into vault
     *      2. Target vault generates profit (simulated by minting assets to target vault)
     *      3. External donor deposits directly into target vault and transfers shares to our vault
     *      4. harvestFees is called
     *      5. Treasury receives fee shares proportional to the total profit (including donation)
     */
    function test_Donation_SharesDonatedToVault() public {
        // ========== STEP 1: Users deposit ==========
        uint256 user1Deposit = 50_000e6;
        uint256 user2Deposit = 100_000e6;
        uint256 user3Deposit = 150_000e6;

        vm.prank(user1);
        vault.deposit(user1Deposit, user1);

        vm.prank(user2);
        vault.deposit(user2Deposit, user2);

        vm.prank(user3);
        vault.deposit(user3Deposit, user3);

        uint256 totalDeposited = user1Deposit + user2Deposit + user3Deposit;

        // Verify initial state
        assertEq(vault.totalAssets(), totalDeposited, "Total assets should equal deposits");
        assertEq(vault.balanceOf(treasury), 0, "Treasury should have no shares initially");

        // ========== STEP 2: Target vault generates profit ==========
        uint256 targetVaultProfit = 30_000e6;
        usdc.mint(address(targetVault), targetVaultProfit);

        // Total assets should increase by profit
        uint256 expectedAssetsAfterProfit = totalDeposited + targetVaultProfit;
        assertApproxEqAbs(
            vault.totalAssets(), expectedAssetsAfterProfit, 1, "Total assets should include target vault profit"
        );

        // ========== STEP 3: Donor donates target vault shares ==========
        // Donor deposits directly into target vault
        uint256 donorDepositAmount = 100_000e6;

        vm.startPrank(donor);
        usdc.approve(address(targetVault), donorDepositAmount);
        uint256 donorShares = targetVault.deposit(donorDepositAmount, donor);

        // Donor transfers their target vault shares to our vault
        targetVault.transfer(address(vault), donorShares);
        vm.stopPrank();

        // ========== STEP 4: Check total assets increased ==========
        // Total assets should now include the donated shares value
        uint256 donatedSharesValue = targetVault.convertToAssets(donorShares);
        uint256 expectedAssetsAfterDonation = expectedAssetsAfterProfit + donatedSharesValue;

        assertApproxEqAbs(
            vault.totalAssets(),
            expectedAssetsAfterDonation,
            1,
            "Total assets should include donated shares value"
        );

        // ========== STEP 5: Harvest fees ==========
        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        uint256 totalSupplyBefore = vault.totalSupply();

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        uint256 totalSupplyAfter = vault.totalSupply();

        // ========== STEP 6: Verify treasury received fee shares ==========
        uint256 feeSharesMinted = treasurySharesAfter - treasurySharesBefore;

        // Treasury should have received fee shares
        assertGt(feeSharesMinted, 0, "Treasury should receive fee shares from profit");

        // Total supply should have increased by fee shares
        assertEq(totalSupplyAfter, totalSupplyBefore + feeSharesMinted, "Total supply should increase by fee shares");

        // Verify fee shares represent reasonable proportion of total profit
        // With 5% fee (500 bps), fee shares should be roughly 5% of profit in share terms
        uint256 totalProfit = targetVaultProfit + donatedSharesValue;
        uint256 expectedFeeValue = (totalProfit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();
        uint256 actualFeeValue = vault.convertToAssets(feeSharesMinted);

        // Fee value should be close to expected (allowing for rounding)
        assertApproxEqAbs(actualFeeValue, expectedFeeValue, 2, "Fee value should be ~5% of total profit");

        // ========== STEP 7: Verify all users can withdraw their proportional share ==========

        // Calculate expected values
        uint256 feeAmount = (totalProfit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();
        uint256 netProfitForUsers = totalProfit - feeAmount;

        // User1 should get: deposit + (deposit/totalDeposited * netProfit)
        uint256 user1ExpectedProfit = (user1Deposit * netProfitForUsers) / totalDeposited;
        uint256 user1Expected = user1Deposit + user1ExpectedProfit;

        uint256 user1Shares = vault.balanceOf(user1);
        vm.prank(user1);
        uint256 user1Assets = vault.redeem(user1Shares, user1, user1);

        assertApproxEqAbs(user1Assets, user1Expected, 2, "User1 should get deposit + proportional profit");

        // User2 should get: deposit + (deposit/totalDeposited * netProfit)
        uint256 user2ExpectedProfit = (user2Deposit * netProfitForUsers) / totalDeposited;
        uint256 user2Expected = user2Deposit + user2ExpectedProfit;

        uint256 user2Shares = vault.balanceOf(user2);
        vm.prank(user2);
        uint256 user2Assets = vault.redeem(user2Shares, user2, user2);

        assertApproxEqAbs(user2Assets, user2Expected, 2, "User2 should get deposit + proportional profit");

        // User3 should get: deposit + (deposit/totalDeposited * netProfit)
        uint256 user3ExpectedProfit = (user3Deposit * netProfitForUsers) / totalDeposited;
        uint256 user3Expected = user3Deposit + user3ExpectedProfit;

        uint256 user3Shares = vault.balanceOf(user3);
        vm.prank(user3);
        uint256 user3Assets = vault.redeem(user3Shares, user3, user3);

        assertApproxEqAbs(user3Assets, user3Expected, 2, "User3 should get deposit + proportional profit");

        // Treasury should be able to redeem their fee shares
        uint256 treasuryShares = vault.balanceOf(treasury);
        vm.prank(treasury);
        uint256 treasuryAssets = vault.redeem(treasuryShares, treasury, treasury);

        assertApproxEqAbs(treasuryAssets, feeAmount, 2, "Treasury should receive fee amount");

        // Verify solvency: all withdrawals should equal total assets that were in vault
        uint256 totalWithdrawn = user1Assets + user2Assets + user3Assets + treasuryAssets;
        uint256 expectedTotal = totalDeposited + totalProfit;

        assertApproxEqAbs(totalWithdrawn, expectedTotal, 10, "Total withdrawn should equal deposits + profit");

        console.log("=== DEPOSITS ===");
        console.log("User1 deposit:", user1Deposit);
        console.log("User2 deposit:", user2Deposit);
        console.log("User3 deposit:", user3Deposit);
        console.log("Total deposited:", totalDeposited);
        console.log("");
        console.log("=== PROFIT ===");
        console.log("Target vault profit:", targetVaultProfit);
        console.log("Donated value:", donatedSharesValue);
        console.log("Total profit:", totalProfit);
        console.log("Fee amount (5%):", feeAmount);
        console.log("Net profit for users:", netProfitForUsers);
        console.log("");
        console.log("=== WITHDRAWALS ===");
        console.log("User1 withdrew:", user1Assets);
        console.log("User1 expected:", user1Expected);
        console.log("User1 profit:", user1Assets - user1Deposit);
        console.log("User2 withdrew:", user2Assets);
        console.log("User2 expected:", user2Expected);
        console.log("User2 profit:", user2Assets - user2Deposit);
        console.log("User3 withdrew:", user3Assets);
        console.log("User3 expected:", user3Expected);
        console.log("User3 profit:", user3Assets - user3Deposit);
        console.log("Treasury withdrew:", treasuryAssets);
        console.log("Treasury expected:", feeAmount);
        console.log("");
        console.log("=== SOLVENCY ===");
        console.log("Total withdrawn:", totalWithdrawn);
        console.log("Expected total:", expectedTotal);
        console.log("Vault remaining:", vault.totalAssets());
    }
}
