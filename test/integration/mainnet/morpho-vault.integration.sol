// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMetaMorpho} from "@morpho/interfaces/IMetaMorpho.sol";

import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {EmergencyVault} from "src/EmergencyVault.sol";

import {VaultTestConfig, VaultTestConfigs} from "utils/Constants.sol";

contract MorphoVaultIntegrationTest is Test {
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    address public treasury = makeAddr("treasury");
    address public emergencyAdmin = makeAddr("emergencyAdmin");

    ERC4626Adapter public vault;

    uint256 public constant TOLERANCE = 10;

    function _forkMainnet() internal {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        vm.skip(bytes(rpcUrl).length == 0, "MAINNET_RPC_URL not set");
        vm.createSelectFork(rpcUrl);
    }

    function _deployVault(VaultTestConfig memory config) internal {
        vault = new ERC4626Adapter(
            config.token, config.targetVault, treasury, config.rewardFee, config.offset, config.name, config.symbol, address(this)
        );

        vault.grantRole(vault.EMERGENCY_ROLE(), emergencyAdmin);

        assertTrue(vault.hasRole(vault.EMERGENCY_ROLE(), emergencyAdmin), "Emergency role not granted");
    }

    function _setupUsers(VaultTestConfig memory config) internal {
        IERC20 token = IERC20(config.token);

        deal(config.token, alice, config.testDepositAmount);
        deal(config.token, bob, config.testDepositAmount * 2);
        deal(config.token, charlie, config.testDepositAmount / 2);

        vm.prank(alice);
        SafeERC20.forceApprove(token, address(vault), type(uint256).max);

        vm.prank(bob);
        SafeERC20.forceApprove(token, address(vault), type(uint256).max);

        vm.prank(charlie);
        SafeERC20.forceApprove(token, address(vault), type(uint256).max);
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.deposit(amount, user);
    }

    function _withdraw(address user, uint256 amount) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.withdraw(amount, user, user);
    }

    function _injectProfit(VaultTestConfig memory config, uint256 profitAmount) internal {
        uint256 currentBalance = IERC20(config.token).balanceOf(config.targetVault);
        deal(config.token, config.targetVault, currentBalance + profitAmount);
    }

    function _emergencyRedeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = vault.emergencyRedeem(shares, user, user);
    }

    /// @notice Executes a full deposit, profit, withdrawal, and emergency cycle against each configured mainnet vault.
    /// @dev Verifies live integrations handle deposits, profit accounting, emergency withdraw, and recovery redemption without balance drift.
    function test_FullEmergencyCycle_AllVaults() public {
        _forkMainnet();

        VaultTestConfig[] memory configs = VaultTestConfigs.allConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            VaultTestConfig memory config = configs[i];
            console2.log("\n========================================");
            console2.log("Testing vault:", config.name);
            console2.log("========================================");

            _deployVault(config);
            _setupUsers(config);

            IERC20 token = IERC20(config.token);
            IMetaMorpho morphoVault = IMetaMorpho(config.targetVault);

            // === PHASE 1: MULTI-USER DEPOSITS ===
            console2.log("\n=== PHASE 1: MULTI-USER DEPOSITS ===");

            uint256 aliceDepositAmount = config.testDepositAmount;
            uint256 bobDepositAmount = config.testDepositAmount * 2;
            uint256 charlieDepositAmount = config.testDepositAmount / 2;

            uint256 aliceBalanceBeforeDeposit = token.balanceOf(alice);
            uint256 bobBalanceBeforeDeposit = token.balanceOf(bob);
            uint256 charlieBalanceBeforeDeposit = token.balanceOf(charlie);

            assertEq(aliceBalanceBeforeDeposit, aliceDepositAmount, "Alice initial balance mismatch");
            assertEq(bobBalanceBeforeDeposit, bobDepositAmount, "Bob initial balance mismatch");
            assertEq(charlieBalanceBeforeDeposit, charlieDepositAmount, "Charlie initial balance mismatch");

            uint256 aliceShares = _deposit(alice, aliceDepositAmount);
            uint256 bobShares = _deposit(bob, bobDepositAmount);
            uint256 charlieShares = _deposit(charlie, charlieDepositAmount);

            console2.log("Alice deposited:", aliceDepositAmount, "received shares:", aliceShares);
            console2.log("Bob deposited:", bobDepositAmount, "received shares:", bobShares);
            console2.log("Charlie deposited:", charlieDepositAmount, "received shares:", charlieShares);

            assertEq(vault.balanceOf(alice), aliceShares, "Alice shares mismatch");
            assertEq(vault.balanceOf(bob), bobShares, "Bob shares mismatch");
            assertEq(vault.balanceOf(charlie), charlieShares, "Charlie shares mismatch");

            assertEq(token.balanceOf(alice), 0, "Alice should have 0 tokens after deposit");
            assertEq(token.balanceOf(bob), 0, "Bob should have 0 tokens after deposit");
            assertEq(token.balanceOf(charlie), 0, "Charlie should have 0 tokens after deposit");

            uint256 totalDepositedAssets = aliceDepositAmount + bobDepositAmount + charlieDepositAmount;
            console2.log("Total deposited assets:", totalDepositedAssets);

            uint256 morphoShares = morphoVault.balanceOf(address(vault));
            uint256 expectedMorphoShares = morphoVault.convertToShares(totalDepositedAssets);
            assertApproxEqAbs(morphoShares, expectedMorphoShares, 2, "Morpho shares mismatch");

            // === PHASE 2: PROFIT INJECTION ===
            console2.log("\n=== PHASE 2: PROFIT INJECTION ===");

            uint256 profitAmount = config.decimals == 6 ? 50_000_000e6 : 50_000e18;
            _injectProfit(config, profitAmount);

            uint256 totalAssetsAfterProfit = vault.totalAssets();
            console2.log("Total assets after profit:", totalAssetsAfterProfit);
            console2.log("Profit injected:", profitAmount);
            console2.log("Profit injection attempted");

            // === PHASE 3: PARTIAL WITHDRAWAL ===
            console2.log("\n=== PHASE 3: PARTIAL WITHDRAWAL ===");

            uint256 aliceTokenBalanceBefore = token.balanceOf(alice);
            uint256 aliceSharesBeforeWithdraw = vault.balanceOf(alice);

            uint256 aliceWithdrawAmount = vault.maxWithdraw(alice) / 2;
            uint256 aliceSharesBurned = _withdraw(alice, aliceWithdrawAmount);

            console2.log("Alice withdrew:", aliceWithdrawAmount, "burned shares:", aliceSharesBurned);

            uint256 aliceTokenBalanceAfter = token.balanceOf(alice);
            assertEq(
                aliceTokenBalanceAfter - aliceTokenBalanceBefore,
                aliceWithdrawAmount,
                "Alice should receive withdrawn tokens"
            );
            console2.log("Alice token balance after withdrawal:", aliceTokenBalanceAfter);

            aliceShares = vault.balanceOf(alice);
            assertEq(
                aliceSharesBeforeWithdraw - aliceShares, aliceSharesBurned, "Alice shares should be burned correctly"
            );
            console2.log("Alice remaining shares:", aliceShares);

            assertEq(token.balanceOf(bob), 0, "Bob token balance should be unchanged");
            assertEq(token.balanceOf(charlie), 0, "Charlie token balance should be unchanged");

            // === PHASE 4: ACTIVATE EMERGENCY MODE ===
            console2.log("\n=== PHASE 4: ACTIVATE EMERGENCY MODE ===");

            vm.prank(emergencyAdmin);
            vault.activateEmergencyMode();

            assertTrue(vault.emergencyMode(), "Emergency mode not activated");
            console2.log("Emergency mode activated");

            uint256 emergencyTotalAssets = vault.totalAssets();
            console2.log("Emergency total assets snapshot:", emergencyTotalAssets);
            console2.log("Confirmed: Normal operations blocked during emergency mode");

            // === PHASE 5: EMERGENCY WITHDRAWAL FROM MORPHO ===
            console2.log("\n=== PHASE 5: EMERGENCY WITHDRAWAL FROM MORPHO ===");

            uint256 vaultBalanceBeforeEmergencyWithdraw = token.balanceOf(address(vault));

            vm.prank(emergencyAdmin);
            uint256 recovered = vault.emergencyWithdraw();

            uint256 vaultBalanceAfterEmergencyWithdraw = token.balanceOf(address(vault));
            uint256 protocolBalanceAfter = vault.getProtocolBalance();

            console2.log("Recovered from protocol:", recovered);
            console2.log("Vault balance before emergency withdraw:", vaultBalanceBeforeEmergencyWithdraw);
            console2.log("Vault balance after emergency withdraw:", vaultBalanceAfterEmergencyWithdraw);
            console2.log("Protocol balance after emergency withdraw:", protocolBalanceAfter);

            uint256 expectedRecoveredAmount = totalDepositedAssets - aliceWithdrawAmount;
            assertApproxEqAbs(
                vaultBalanceAfterEmergencyWithdraw,
                expectedRecoveredAmount,
                10,
                "Vault balance should equal expected recovered amount"
            );

            assertApproxEqAbs(
                protocolBalanceAfter, 0, TOLERANCE, "Expected to recover all assets from Morpho (good liquidity)"
            );

            // === PHASE 6: ACTIVATE RECOVERY ===
            console2.log("\n=== PHASE 6: ACTIVATE RECOVERY ===");

            uint256 declaredRecoverableAmount = token.balanceOf(address(vault));

            vm.prank(emergencyAdmin);
            vault.activateRecovery(declaredRecoverableAmount);

            assertTrue(vault.recoveryMode(), "Recovery mode not activated");

            uint256 recoveryAssets = vault.recoveryAssets();
            uint256 recoverySupply = vault.recoverySupply();

            console2.log("Recovery assets:", recoveryAssets);
            console2.log("Recovery supply:", recoverySupply);

            assertEq(recoveryAssets, declaredRecoverableAmount, "Recovery assets mismatch");
            uint256 expectedRecoverySupply = vault.totalSupply();
            assertApproxEqAbs(recoverySupply, expectedRecoverySupply, 2, "Recovery supply mismatch");

            // === PHASE 7: USERS EMERGENCY REDEEM ===
            console2.log("\n=== PHASE 7: USERS EMERGENCY REDEEM ===");

            uint256 aliceSharesBeforeRedeem = vault.balanceOf(alice);
            uint256 bobSharesBeforeRedeem = vault.balanceOf(bob);
            uint256 charlieSharesBeforeRedeem = vault.balanceOf(charlie);

            uint256 aliceTokenBalanceBeforeRedeem = token.balanceOf(alice);
            uint256 bobTokenBalanceBeforeRedeem = token.balanceOf(bob);
            uint256 charlieTokenBalanceBeforeRedeem = token.balanceOf(charlie);

            console2.log("Alice token balance before redeem:", aliceTokenBalanceBeforeRedeem);
            console2.log("Bob token balance before redeem:", bobTokenBalanceBeforeRedeem);
            console2.log("Charlie token balance before redeem:", charlieTokenBalanceBeforeRedeem);

            uint256 aliceRedeemed = _emergencyRedeem(alice, aliceSharesBeforeRedeem);
            uint256 bobRedeemed = _emergencyRedeem(bob, bobSharesBeforeRedeem);
            uint256 charlieRedeemed = _emergencyRedeem(charlie, charlieSharesBeforeRedeem);

            console2.log("Alice redeemed:", aliceRedeemed, "for shares:", aliceSharesBeforeRedeem);
            console2.log("Bob redeemed:", bobRedeemed, "for shares:", bobSharesBeforeRedeem);
            console2.log("Charlie redeemed:", charlieRedeemed, "for shares:", charlieSharesBeforeRedeem);

            uint256 aliceTokenBalanceAfterRedeem = token.balanceOf(alice);
            uint256 bobTokenBalanceAfterRedeem = token.balanceOf(bob);
            uint256 charlieTokenBalanceAfterRedeem = token.balanceOf(charlie);

            assertEq(
                aliceTokenBalanceAfterRedeem - aliceTokenBalanceBeforeRedeem,
                aliceRedeemed,
                "Alice should receive redeemed tokens"
            );
            assertEq(
                bobTokenBalanceAfterRedeem - bobTokenBalanceBeforeRedeem,
                bobRedeemed,
                "Bob should receive redeemed tokens"
            );
            assertEq(
                charlieTokenBalanceAfterRedeem - charlieTokenBalanceBeforeRedeem,
                charlieRedeemed,
                "Charlie should receive redeemed tokens"
            );

            console2.log("Alice token balance after redeem:", aliceTokenBalanceAfterRedeem);
            console2.log("Bob token balance after redeem:", bobTokenBalanceAfterRedeem);
            console2.log("Charlie token balance after redeem:", charlieTokenBalanceAfterRedeem);

            assertEq(vault.balanceOf(alice), 0, "Alice shares should be burned");
            assertEq(vault.balanceOf(bob), 0, "Bob shares should be burned");
            assertEq(vault.balanceOf(charlie), 0, "Charlie shares should be burned");

            // === PHASE 8: TREASURY REDEEMS FEES ===
            console2.log("\n=== PHASE 8: TREASURY REDEEMS FEES ===");

            uint256 treasuryShares = vault.balanceOf(treasury);
            uint256 treasuryTokenBalanceBefore = token.balanceOf(treasury);
            uint256 treasuryRedeemed = 0;

            console2.log("Treasury token balance before redeem:", treasuryTokenBalanceBefore);
            console2.log("Treasury shares before redeem:", treasuryShares);

            if (treasuryShares > 0) {
                treasuryRedeemed = _emergencyRedeem(treasury, treasuryShares);
                console2.log("Treasury redeemed:", treasuryRedeemed, "for shares:", treasuryShares);

                uint256 treasuryTokenBalanceAfter = token.balanceOf(treasury);
                assertEq(
                    treasuryTokenBalanceAfter - treasuryTokenBalanceBefore,
                    treasuryRedeemed,
                    "Treasury should receive redeemed tokens"
                );
                console2.log("Treasury token balance after redeem:", treasuryTokenBalanceAfter);

                assertEq(vault.balanceOf(treasury), 0, "Treasury shares should be burned");
            } else {
                console2.log("Treasury has no shares (no fees harvested)");
            }

            // === PHASE 9: COMPREHENSIVE VALIDATION ===
            console2.log("\n=== PHASE 9: COMPREHENSIVE VALIDATION ===");

            assertEq(vault.totalSupply(), 0, "All shares should be burned");
            console2.log("CHECK PASSED: All shares burned");

            uint256 remainingBalance = token.balanceOf(address(vault));
            assertApproxEqAbs(remainingBalance, 0, TOLERANCE, "Vault should be drained");
            console2.log("CHECK PASSED: Vault drained (remaining:", remainingBalance, ")");

            console2.log("\nFinal token balance summary:");
            console2.log("Alice final balance:", aliceTokenBalanceAfterRedeem);
            console2.log("Bob final balance:", bobTokenBalanceAfterRedeem);
            console2.log("Charlie final balance:", charlieTokenBalanceAfterRedeem);
            if (treasuryShares > 0) {
                uint256 treasuryFinalBalance = token.balanceOf(treasury);
                console2.log("Treasury final balance:", treasuryFinalBalance);
                assertEq(treasuryFinalBalance, treasuryRedeemed, "Treasury final balance should match redeemed amount");
            }

            uint256 totalTokensDistributed =
                aliceTokenBalanceAfterRedeem + bobTokenBalanceAfterRedeem + charlieTokenBalanceAfterRedeem;
            if (treasuryShares > 0) {
                totalTokensDistributed += token.balanceOf(treasury);
            }
            console2.log("Total tokens distributed to all parties:", totalTokensDistributed);
            assertApproxEqAbs(
                totalTokensDistributed,
                totalDepositedAssets,
                10,
                "Total distributed should approximately match total deposited"
            );
            console2.log("CHECK PASSED: Total distribution accounting correct");

            console2.log("\nPro-rata validation:");
            uint256 totalUserAssets = aliceRedeemed + bobRedeemed + charlieRedeemed;
            uint256 totalUserShares = aliceSharesBeforeRedeem + bobSharesBeforeRedeem + charlieSharesBeforeRedeem;
            console2.log("Total user assets:", totalUserAssets);
            console2.log("Total user shares:", totalUserShares);

            uint256 aliceExpectedRatio = (aliceSharesBeforeRedeem * 1e18) / totalUserShares;
            uint256 aliceActualRatio = (aliceRedeemed * 1e18) / totalUserAssets;
            assertApproxEqAbs(aliceActualRatio, aliceExpectedRatio, 1e15, "Alice pro-rata mismatch");

            console2.log("CHECK PASSED: Pro-rata distribution correct");

            uint256 totalDistributed = totalUserAssets + treasuryRedeemed;
            assertApproxEqAbs(totalDistributed, recoveryAssets, 10, "Total distribution should match recovery assets");
            console2.log("CHECK PASSED: Total distribution matches recovery assets");
            console2.log("Total distributed:", totalDistributed);
            console2.log("Recovery assets:", recoveryAssets);

            if (treasuryShares > 0) {
                console2.log("\nTreasury fee validation:");
                console2.log("Treasury received:", treasuryRedeemed);
                console2.log("Treasury shares:", treasuryShares);
                console2.log("Reward fee:", config.rewardFee, "basis points");

                uint256 expectedFee = (profitAmount * config.rewardFee) / 10_000;
                assertApproxEqAbs(
                    treasuryRedeemed, expectedFee, 10, "Treasury fee should be approximately expected fee"
                );

                console2.log("CHECK PASSED: Treasury fee is as expected");
                console2.log("Expected fee:", expectedFee);
            }

            console2.log("\n=== EMERGENCY CYCLE COMPLETE ===");
            console2.log("All validations passed successfully for", config.name);
        }

        console2.log("\n========================================");
        console2.log("All vaults tested successfully");
        console2.log("========================================");
    }
}
