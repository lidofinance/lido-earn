// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "test/unit/erc4626-adapter/ERC4626AdapterTestBase.sol";
import "forge-std/console.sol";

contract SolvencyTest is ERC4626AdapterTestBase {
    using Math for uint256;

    address[] public users;
    uint256 internal constant USER_COUNT = 256;
    uint256 internal constant EMERGENCY_TEST_USERS = 32;

    function setUp() public override {
        super.setUp();
        for (uint256 i = 0; i < USER_COUNT; i++) {
            address user = vm.addr(uint256(keccak256(abi.encodePacked("user", i))));
            users.push(user);
            _dealAndApprove(user, INITIAL_BALANCE);
        }
    }

    /// @notice Runs randomized deposit/withdraw cycles with periodic profits to ensure solvency holds.
    /// @dev Verifies total assets track net deposits plus profit and that users and treasury can fully redeem leaving zero balance.
    function test_Solvency_WithRandomCycles() public {
        uint256 numCycles = 100;
        uint256 totalProfit = 0;
        uint256 totalDeposited = 0;
        uint256 totalWithdrawnDuringCycles = 0;

        for (uint256 i = 0; i < numCycles; i++) {
            uint256 userIndex = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % users.length;
            address user = users[userIndex];
            uint256 action = uint256(keccak256(abi.encodePacked(user, i))) % 2;
            uint256 amount = (uint256(keccak256(abi.encodePacked(action, i))) % (INITIAL_BALANCE / 10)) + 1_000e6;

            if (action == 0) {
                if (usdc.balanceOf(user) >= amount) {
                    console.log("User:", user);
                    console.log("Allowance:", usdc.allowance(user, address(vault)));
                    vm.prank(user);
                    vault.deposit(amount, user);
                    totalDeposited += amount;
                }
            } else {
                uint256 userShares = vault.balanceOf(user);
                if (userShares > 0) {
                    uint256 sharesToWithdraw =
                        (userShares * (amount % vault.MAX_BASIS_POINTS())) / vault.MAX_BASIS_POINTS();
                    if (sharesToWithdraw > 0) {
                        uint256 assetsToWithdraw = vault.previewWithdraw(sharesToWithdraw);
                        if (vault.maxWithdraw(user) >= assetsToWithdraw) {
                            vm.prank(user);
                            vault.withdraw(assetsToWithdraw, user, user);
                            totalWithdrawnDuringCycles += assetsToWithdraw;
                        }
                    }
                }
            }

            if (i > 0 && i % 10 == 0) {
                uint256 profit = 10_000e6;
                usdc.mint(address(targetVault), profit);
                totalProfit += profit;
            }
        }

        uint256 netDeposited = totalDeposited - totalWithdrawnDuringCycles;
        uint256 assetsBeforeFinalWithdraw = vault.totalAssets();

        assertApproxEqAbs(assetsBeforeFinalWithdraw, netDeposited + totalProfit, 9);

        uint256 totalWithdrawnAtEnd = 0;
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 shares = vault.balanceOf(user);
            if (shares > 0) {
                vm.prank(user);
                totalWithdrawnAtEnd += vault.redeem(shares, user, user);
            }
        }

        uint256 treasuryShares = vault.balanceOf(treasury);
        uint256 treasuryWithdrawn = 0;
        if (treasuryShares > 0) {
            vm.prank(treasury);
            treasuryWithdrawn = vault.redeem(treasuryShares, treasury, treasury);
        }

        uint256 finalUserAssets = totalWithdrawnAtEnd;
        uint256 finalTreasuryAssets = treasuryWithdrawn;
        uint256 finalVaultAssets = usdc.balanceOf(address(vault));

        assertApproxEqAbs(finalUserAssets + finalTreasuryAssets, netDeposited + totalProfit, 2);

        // Vault must be completely empty
        assertEq(finalVaultAssets, 0);
    }

    /// @notice Exercises an end-to-end emergency withdraw + recovery cycle for many users.
    /// @dev Verifies recovery snapshots distribute funds pro-rata, treasury can claim, and vault ends with zero supply/balance.
    function test_EmergencySolvency_AllUsersRedeemVaultEmpty() public {
        uint256 totalDeposited = 0;
        for (uint256 i = 0; i < EMERGENCY_TEST_USERS; i++) {
            address user = users[i];
            uint256 amount = (i + 1) * 1_000e6;
            vm.prank(user);
            vault.deposit(amount, user);
            totalDeposited += amount;
        }

        uint256 accruedProfit = 5_000_000e6;
        usdc.mint(address(targetVault), accruedProfit);

        vm.prank(address(this));
        vault.emergencyWithdraw();

        vm.prank(address(this));
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 snapshotAssets = vault.recoveryAssets();
        uint256 snapshotSupply = vault.recoverySupply();
        assertGt(snapshotSupply, 0);
        assertApproxEqAbs(snapshotAssets, totalDeposited + accruedProfit, EMERGENCY_TEST_USERS + 1);

        uint256 totalDistributed = 0;
        for (uint256 i = 0; i < EMERGENCY_TEST_USERS; i++) {
            address user = users[i];
            uint256 userShares = vault.balanceOf(user);
            if (userShares == 0) continue;
            uint256 expectedAssets = userShares.mulDiv(snapshotAssets, snapshotSupply, Math.Rounding.Floor);
            if (expectedAssets == 0) continue;
            vm.prank(user);
            uint256 received = vault.emergencyRedeem(userShares, user, user);
            totalDistributed += received;
            assertEq(received, expectedAssets);
            assertEq(vault.balanceOf(user), 0);
        }

        uint256 treasuryShares = vault.balanceOf(treasury);
        uint256 treasuryDistributed = 0;

        if (treasuryShares > 0) {
            vm.prank(treasury);
            treasuryDistributed = vault.emergencyRedeem(treasuryShares, treasury, treasury);
        }

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 distributedWithTreasury = totalDistributed + treasuryDistributed;

        assertEq(distributedWithTreasury + vaultBalance, snapshotAssets);
        assertEq(vault.totalSupply(), 0);
        assertApproxEqAbs(
            distributedWithTreasury, totalDeposited + accruedProfit - vaultBalance, EMERGENCY_TEST_USERS + 1
        );

        uint256 netProfitForUsers = accruedProfit - treasuryDistributed;
        assertApproxEqAbs(totalDistributed, totalDeposited + netProfitForUsers - vaultBalance, EMERGENCY_TEST_USERS + 1);
    }
}
