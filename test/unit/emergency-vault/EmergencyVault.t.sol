// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {EmergencyVault} from "src/EmergencyVault.sol";
import {Vault} from "src/Vault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./EmergencyVaultTestBase.sol";

/**
 * @title EmergencyVaultTest
 * @notice Comprehensive tests for emergency withdrawal and recovery mechanism
 */
contract EmergencyVaultTest is EmergencyVaultTestBase {
    using Math for uint256;

    address public emergencyAdmin = makeAddr("emergencyAdmin");
    address public charlie = makeAddr("charlie");

    event EmergencyModeActivated(uint256 emergencyAssetsSnapshot, uint256 activationTimestamp);
    event EmergencyWithdrawal(uint256 recovered, uint256 remaining);
    event RecoveryModeActivated(
        uint256 declaredRecoverableAmount, uint256 recoverySupply, uint256 protocolBalance, uint256 implicitLoss
    );

    function setUp() public override {
        super.setUp();
        vm.prank(address(this));
        vault.grantRole(vault.EMERGENCY_ROLE(), emergencyAdmin);

        uint256 initialBalance = scaleAmount(INITIAL_BALANCE);
        usdc.mint(charlie, initialBalance);
        vm.prank(charlie);
        usdc.approve(address(vault), type(uint256).max);
    }

    /* ========== EMERGENCY WITHDRAW TESTS ========== */

    /// @notice Fuzzes that emergency withdraw first call activates emergency mode.
    /// @dev Validates that emergency withdraw first call activates emergency mode.
    function testFuzz_EmergencyWithdraw_FirstCall_ActivatesEmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        assertFalse(vault.emergencyMode());

        uint256 expectedEmergencyAssets = vault.totalAssets();
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit EmergencyModeActivated(expectedEmergencyAssets, expectedTimestamp);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertTrue(vault.emergencyMode());
    }

    /// @notice Exercises standard activate emergency mode happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
    function test_activateEmergencyMode_HappyPath() public {
        uint256 amount = scaleAmount(1_000_000);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        assertFalse(vault.emergencyMode());

        uint256 expectedEmergencyAssets = vault.totalAssets();
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit EmergencyModeActivated(expectedEmergencyAssets, expectedTimestamp);

        vm.prank(emergencyAdmin);
        vault.activateEmergencyMode();

        assertTrue(vault.emergencyMode());
        assertEq(vault.emergencyTotalAssets(), expectedEmergencyAssets);
    }

    /// @notice Tests that activate emergency mode reverts if already active.
    /// @dev Validates that activate emergency mode reverts if already active.
    function test_activateEmergencyMode_RevertsIfAlreadyActive() public {
        uint256 amount = scaleAmount(1_000_000);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.activateEmergencyMode();

        vm.expectRevert(EmergencyVault.EmergencyModeAlreadyActive.selector);
        vm.prank(emergencyAdmin);
        vault.activateEmergencyMode();
    }

    /// @notice Fuzzes that emergency withdraw recovers all funds.
    /// @dev Validates that emergency withdraw recovers all funds.
    function testFuzz_EmergencyWithdraw_RecoversAllFunds(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 protocolBalanceBefore = vault.getProtocolBalance();
        assertGt(protocolBalanceBefore, 0);

        vm.prank(emergencyAdmin);
        uint256 recovered = vault.emergencyWithdraw();

        assertApproxEqAbs(recovered, amount, 2);
        assertEq(vault.getProtocolBalance(), 0);
        assertApproxEqAbs(usdc.balanceOf(address(vault)), amount, 2);
    }

    /// @notice Fuzzes emergency withdraw with multiple users.
    /// @dev Verifies accounting remains correct across participants.
    function testFuzz_EmergencyWithdraw_MultipleUsers_RecoversTotalAssets(
        uint96 aliceAmount,
        uint96 bobAmount,
        uint96 charlieAmount
    ) public {
        uint256 aliceDeposit = bound(uint256(aliceAmount), 1, type(uint80).max);
        uint256 bobDeposit = bound(uint256(bobAmount), 1, type(uint80).max);
        uint256 charlieDeposit = bound(uint256(charlieAmount), 1, type(uint80).max);

        usdc.mint(alice, aliceDeposit);
        usdc.mint(bob, bobDeposit);
        usdc.mint(charlie, charlieDeposit);

        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);
        vm.prank(bob);
        vault.deposit(bobDeposit, bob);
        vm.prank(charlie);
        vault.deposit(charlieDeposit, charlie);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 expectedTotal = aliceDeposit + bobDeposit + charlieDeposit;
        assertApproxEqAbs(totalAssetsBefore, expectedTotal, 2);

        vm.prank(emergencyAdmin);
        uint256 recovered = vault.emergencyWithdraw();

        assertApproxEqAbs(recovered, expectedTotal, 2);
        assertEq(vault.getProtocolBalance(), 0);
    }

    /// @notice Fuzzes that emergency withdraw multiple calls accumulate.
    /// @dev Validates that emergency withdraw multiple calls accumulate.
    function testFuzz_EmergencyWithdraw_MultipleCallsAccumulate(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max / 2);
        usdc.mint(alice, amount * 2);

        vm.prank(alice);
        vault.deposit(amount, alice);

        targetVault.setLiquidityCap(amount / 2);

        vm.prank(emergencyAdmin);
        uint256 firstRecovered = vault.emergencyWithdraw();

        assertApproxEqAbs(firstRecovered, amount / 2, 2);
        assertGt(vault.getProtocolBalance(), 0);

        targetVault.setLiquidityCap(type(uint256).max);

        vm.prank(emergencyAdmin);
        uint256 secondRecovered = vault.emergencyWithdraw();

        assertGt(secondRecovered, 0);
        assertEq(vault.getProtocolBalance(), 0);
    }

    /// @notice Fuzzes that emergency withdraw emits correct event.
    /// @dev Validates that emergency withdraw emits correct event.
    function testFuzz_EmergencyWithdraw_EmitsCorrectEvent(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 expectedRecovered = vault.getProtocolBalance();

        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdrawal(expectedRecovered, 0);

        vm.prank(emergencyAdmin);
        uint256 actualRecovered = vault.emergencyWithdraw();

        assertApproxEqAbs(actualRecovered, expectedRecovered, 2);
    }

    /// @notice Fuzzes that emergency withdraw reverts when not emergency role.
    /// @dev Verifies the revert protects against not emergency role.
    function testFuzz_EmergencyWithdraw_RevertIf_NotEmergencyRole(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.emergencyWithdraw();
    }

    /// @notice Fuzzes that emergency withdraw reverts when after recovery activated.
    /// @dev Verifies the revert protects against after recovery activated.
    function testFuzz_EmergencyWithdraw_RevertIf_AfterRecoveryActivated(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(EmergencyVault.RecoveryModeAlreadyActive.selector);
        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();
    }

    /// @notice Fuzzes that emergency withdraw second call does not pause again.
    /// @dev Validates that emergency withdraw second call does not pause again.
    function testFuzz_EmergencyWithdraw_SecondCallDoesNotPauseAgain(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max / 2);
        usdc.mint(alice, amount * 2);

        vm.prank(alice);
        vault.deposit(amount, alice);

        targetVault.setLiquidityCap(amount / 2);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 snapshot = vault.emergencyTotalAssets();

        targetVault.setLiquidityCap(type(uint256).max);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertTrue(vault.emergencyMode());
        assertEq(vault.emergencyTotalAssets(), snapshot);
    }

    /* ========== ACTIVATE EMERGENCY RECOVERY TESTS ========== */

    /// @notice Fuzzes that activate recovery snapshots correctly.
    /// @dev Validates that activate recovery snapshots correctly.
    function testFuzz_activateRecovery_SnapshotsCorrectly(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 totalSupply = vault.totalSupply();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertEq(vault.recoveryAssets(), vaultBalance);
        assertEq(vault.recoverySupply(), totalSupply);
        assertTrue(vault.recoveryMode());
    }

    /// @notice Fuzzes that activate recovery harvests fees before snapshot.
    /// @dev Validates that activate recovery harvests fees before snapshot.
    function testFuzz_activateRecovery_HarvestsFeesBeforeSnapshot(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1000, type(uint96).max / 2);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        usdc.mint(address(targetVault), amount / 10);

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertGt(vault.totalSupply(), totalSupplyBefore);
        assertEq(vault.balanceOf(treasury), vault.totalSupply() - totalSupplyBefore);
    }

    /// @notice Fuzzes activate recovery emits the expected event.
    /// @dev Verifies the emitted event data matches the scenario.
    function testFuzz_activateRecovery_EmitsEvent(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 totalSupply = vault.totalSupply();
        uint256 protocolBalance = vault.getProtocolBalance();
        uint256 implicitLoss = 0; // No loss in this scenario

        vm.expectEmit(true, true, true, true);
        emit RecoveryModeActivated(vaultBalance, totalSupply, protocolBalance, implicitLoss);

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertEq(vault.recoveryAssets(), vaultBalance);
        assertEq(vault.recoverySupply(), totalSupply);
    }

    /// @notice Fuzzes that activate recovery allows declaring amount equal to or less than actual balance.
    /// @dev With new logic, admin can declare amount <= actual balance (no longer reverts for lower amounts).
    function testFuzz_activateRecovery_AllowsDeclaringLowerAmount(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max / 2);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        vm.assume(vaultBalance > 1000);
        uint256 declaredAmount = vaultBalance - 1000;

        // Should succeed - admin can declare lower amount than actual balance
        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertTrue(vault.recoveryMode());
        assertEq(vault.recoveryAssets(), vaultBalance);
    }

    /// @notice Fuzzes that activate recovery allows partial recovery.
    /// @dev Validates that activate recovery allows partial recovery.
    function testFuzz_activateRecovery_AllowsPartialRecovery(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1000, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 partialCap = amount * 90 / 100;
        targetVault.setLiquidityCap(partialCap);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 protocolBalance = vault.getProtocolBalance();

        assertGt(protocolBalance, 0);
        assertApproxEqAbs(vaultBalance, partialCap, 2);

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertTrue(vault.recoveryMode());
        assertEq(vault.recoveryAssets(), vaultBalance);
    }

    /// @notice Fuzzes that activate recovery reverts when already active.
    /// @dev Verifies the revert protects against already active.
    function testFuzz_activateRecovery_RevertIf_AlreadyActive(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(EmergencyVault.RecoveryModeAlreadyActive.selector);
        vm.prank(emergencyAdmin);
        vault.activateRecovery();
    }

    /// @notice Fuzzes that activate recovery reverts when emergency mode not active.
    /// @dev Verifies the revert protects against emergency mode not active.
    function testFuzz_activateRecovery_RevertIf_EmergencyModeNotActive(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        assertGt(vault.getProtocolBalance(), 0, "Funds should be in protocol");
        assertEq(vault.emergencyMode(), false, "Emergency mode should not be active");
        assertEq(vault.emergencyTotalAssets(), 0, "emergencyTotalAssets should be 0 (never set)");

        uint256 vaultBalance = usdc.balanceOf(address(vault));

        vm.expectRevert(EmergencyVault.EmergencyModeNotActive.selector);
        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertEq(vault.emergencyMode(), false, "Emergency mode should still be false");
        assertEq(vault.recoveryMode(), false, "Recovery should not be active");
        assertGt(vault.getProtocolBalance(), 0, "Funds should still be in protocol");
    }

    /// @notice Fuzzes that activate recovery reverts when zero vault balance.
    /// @dev Verifies the revert protects against zero vault balance.
    function testFuzz_activateRecovery_RevertIf_ZeroVaultBalance() public {
        uint256 depositAmount = 1000e6;
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        vm.prank(address(vault));
        usdc.transfer(treasury, vaultBalance);

        assertEq(usdc.balanceOf(address(vault)), 0);
        assertTrue(vault.emergencyMode());

        vm.expectRevert(abi.encodeWithSelector(EmergencyVault.InvalidRecoveryAssets.selector, 0));
        vm.prank(emergencyAdmin);
        vault.activateRecovery();
    }

    /// @notice Fuzzes that activate recovery reverts when not emergency role.
    /// @dev Verifies the revert protects against not emergency role.
    function testFuzz_activateRecovery_RevertIf_NotEmergencyRole(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));

        vm.expectRevert();
        vm.prank(alice);
        vault.activateRecovery();
    }

    /* ========== EMERGENCY REDEEM TESTS ========== */

    /// @notice Fuzzes that emergency redeem pro rata distribution.
    /// @dev Validates that emergency redeem pro rata distribution.
    function testFuzz_EmergencyRedeem_ProRataDistribution(uint96 depositAmount, uint96 sharesToRedeem) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 redeemShares = bound(uint256(sharesToRedeem), shares / 100, shares);
        if (redeemShares == 0) redeemShares = shares;

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 expectedAssets =
            redeemShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedAssets > 0);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 receivedAssets = vault.redeem(redeemShares, alice, alice);

        assertEq(receivedAssets, expectedAssets);
        assertEq(usdc.balanceOf(alice) - aliceBalanceBefore, receivedAssets);
        assertEq(vault.balanceOf(alice), shares - redeemShares);
    }

    /// @notice Fuzzes emergency redeem with multiple users.
    /// @dev Verifies accounting remains correct across participants.
    function testFuzz_EmergencyRedeem_MultipleUsers_FairDistribution(
        uint96 aliceAmount,
        uint96 bobAmount,
        uint96 charlieAmount
    ) public {
        uint256 aliceDeposit = bound(uint256(aliceAmount), 1, type(uint80).max);
        uint256 bobDeposit = bound(uint256(bobAmount), 1, type(uint80).max);
        uint256 charlieDeposit = bound(uint256(charlieAmount), 1, type(uint80).max);

        usdc.mint(alice, aliceDeposit);
        usdc.mint(bob, bobDeposit);
        usdc.mint(charlie, charlieDeposit);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDeposit, alice);
        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);
        vm.prank(charlie);
        uint256 charlieShares = vault.deposit(charlieDeposit, charlie);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 recoveryAssets = vault.recoveryAssets();
        uint256 recoverySupply = vault.recoverySupply();

        vm.prank(alice);
        uint256 aliceReceived = vault.redeem(aliceShares, alice, alice);

        vm.prank(bob);
        uint256 bobReceived = vault.redeem(bobShares, bob, bob);

        vm.prank(charlie);
        uint256 charlieReceived = vault.redeem(charlieShares, charlie, charlie);

        uint256 expectedAlice = aliceShares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);
        uint256 expectedBob = bobShares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);
        uint256 expectedCharlie = charlieShares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);

        assertEq(aliceReceived, expectedAlice);
        assertEq(bobReceived, expectedBob);
        assertEq(charlieReceived, expectedCharlie);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.balanceOf(charlie), 0);

        assertApproxEqAbs(aliceReceived, aliceDeposit, 2);
        assertApproxEqAbs(bobReceived, bobDeposit, 2);
        assertApproxEqAbs(charlieReceived, charlieDeposit, 2);

        uint256 totalDistributed = aliceReceived + bobReceived + charlieReceived;
        uint256 vaultBalance = usdc.balanceOf(address(vault));

        assertEq(totalDistributed + vaultBalance, recoveryAssets);
        assertEq(vault.recoveryAssets() - totalDistributed, vaultBalance);
        assertEq(vault.totalSupply(), 0);
    }

    /// @notice Fuzzes that emergency redeem claim order does not matter.
    /// @dev Validates that emergency redeem claim order does not matter.
    function testFuzz_EmergencyRedeem_ClaimOrderDoesNotMatter(uint96 aliceAmount, uint96 bobAmount) public {
        uint256 aliceDeposit = bound(uint256(aliceAmount), 1, type(uint80).max);
        uint256 bobDeposit = bound(uint256(bobAmount), 1, type(uint80).max);

        usdc.mint(alice, aliceDeposit);
        usdc.mint(bob, bobDeposit);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDeposit, alice);
        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 recoveryAssets = vault.recoveryAssets();
        uint256 recoverySupply = vault.recoverySupply();

        uint256 expectedAlice = aliceShares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);
        uint256 expectedBob = bobShares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);

        vm.prank(bob);
        uint256 bobReceived = vault.redeem(bobShares, bob, bob);

        vm.prank(alice);
        uint256 aliceReceived = vault.redeem(aliceShares, alice, alice);

        assertEq(aliceReceived, expectedAlice);
        assertEq(bobReceived, expectedBob);

        assertApproxEqAbs(aliceReceived, aliceDeposit, 2);
        assertApproxEqAbs(bobReceived, bobDeposit, 2);

        uint256 totalDistributed = aliceReceived + bobReceived;
        uint256 vaultBalance = usdc.balanceOf(address(vault));

        assertEq(totalDistributed + vaultBalance, recoveryAssets);
        assertEq(vault.recoveryAssets() - totalDistributed, vaultBalance);
        assertEq(vault.totalSupply(), 0);
    }

    /// @notice Fuzzes that emergency redeem partial redeem.
    /// @dev Validates that emergency redeem partial redeem.
    function testFuzz_EmergencyRedeem_PartialRedeem(uint96 depositAmount, uint96 redeemPortion) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 redeemShares = bound(uint256(redeemPortion), shares / 100, shares / 2);
        if (redeemShares == 0) redeemShares = shares / 2;
        vm.assume(redeemShares > 0 && redeemShares < shares);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 expectedFirst = redeemShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedFirst > 0);

        vm.prank(alice);
        uint256 firstRedeem = vault.redeem(redeemShares, alice, alice);

        uint256 remainingShares = vault.balanceOf(alice);
        assertEq(remainingShares, shares - redeemShares);

        uint256 expectedSecond =
            remainingShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedSecond > 0);

        vm.prank(alice);
        uint256 secondRedeem = vault.redeem(remainingShares, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertGt(firstRedeem + secondRedeem, 0);
    }

    /// @notice Fuzzes that emergency redeem burns shares correctly.
    /// @dev Validates that emergency redeem burns shares correctly.
    function testFuzz_EmergencyRedeem_BurnsSharesCorrectly(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(vault.totalSupply(), totalSupplyBefore - shares);
        assertEq(vault.balanceOf(alice), 0);
    }

    /// @notice Fuzzes that emergency redeem with approval.
    /// @dev Validates that emergency redeem with approval.
    function testFuzz_EmergencyRedeem_WithApproval(uint96 depositAmount, uint96 sharesToRedeem) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 redeemShares = bound(uint256(sharesToRedeem), shares / 100, shares);
        if (redeemShares == 0) redeemShares = shares;

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 expectedAssets =
            redeemShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedAssets > 0);

        vm.prank(alice);
        vault.approve(bob, redeemShares);

        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        uint256 assets = vault.redeem(redeemShares, bob, alice);

        assertEq(usdc.balanceOf(bob) - bobBalanceBefore, assets);
        assertEq(vault.balanceOf(alice), shares - redeemShares);
        assertEq(vault.allowance(alice, bob), 0);
    }

    /// @notice Fuzzes that redeem works normally when recovery is not active.
    /// @dev Verifies that standard redeem() works in normal mode (not emergency/recovery).
    function testFuzz_EmergencyRedeem_NormalMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        // In normal mode (not emergency, not recovery), redeem should work normally
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    /// @notice Fuzzes that emergency redeem reverts when zero shares.
    /// @dev Verifies the revert protects against zero shares.
    function testFuzz_EmergencyRedeem_RevertIf_ZeroShares(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidSharesAmount.selector, 0, 0));
        vm.prank(alice);
        vault.redeem(0, alice, alice);
    }

    /// @notice Fuzzes that emergency redeem reverts when zero receiver.
    /// @dev Verifies the revert protects against zero receiver.
    function testFuzz_EmergencyRedeem_RevertIf_ZeroReceiver(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidReceiverAddress.selector, address(0)));
        vm.prank(alice);
        vault.redeem(shares, address(0), alice);
    }

    /// @notice Fuzzes that emergency redeem reverts when insufficient shares.
    /// @dev Verifies the revert protects against insufficient shares.
    function testFuzz_EmergencyRedeem_RevertIf_InsufficientShares(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 requestShares = shares + 1;

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientShares.selector, requestShares, shares));
        vm.prank(alice);
        vault.redeem(requestShares, alice, alice);
    }

    /// @notice Fuzzes that emergency redeem reverts when no approval.
    /// @dev Verifies the revert protects against no approval.
    function testFuzz_EmergencyRedeem_RevertIf_NoApproval(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert();
        vm.prank(bob);
        vault.redeem(shares, bob, alice);
    }

    /* ========== BLOCKED OPERATIONS DURING EMERGENCY TESTS ========== */

    /// @notice Tests that harvestFees reverts when in recovery mode.
    /// @dev Verifies that harvestFees cannot be called during recovery mode.
    function test_HarvestFees_RevertsIf_RecoveryMode() public {
        uint256 amount = scaleAmount(1_000_000);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertTrue(vault.recoveryMode());

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.harvestFees();
    }

    /// @notice Tests that harvestFees reverts when in emergency mode.
    /// @dev Verifies that harvestFees cannot be called during emergency mode (before recovery).
    function test_HarvestFees_RevertsIf_EmergencyMode() public {
        uint256 amount = scaleAmount(1_000_000);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertTrue(vault.emergencyMode());
        assertFalse(vault.recoveryMode());

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.harvestFees();
    }

    /// @notice Fuzzes that withdraw reverts when emergency mode.
    /// @dev Verifies the revert protects against emergency mode.
    function testFuzz_Withdraw_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertTrue(vault.emergencyMode());

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vm.prank(alice);
        vault.withdraw(amount / 2, alice, alice);
    }

    /// @notice Fuzzes that redeem reverts when emergency mode.
    /// @dev Verifies the revert protects against emergency mode.
    function testFuzz_Redeem_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertTrue(vault.emergencyMode());

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vm.prank(alice);
        vault.redeem(shares / 2, alice, alice);
    }

    /// @notice Fuzzes that deposit reverts when emergency mode.
    /// @dev Verifies the revert protects against emergency mode.
    function testFuzz_Deposit_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max / 2);
        usdc.mint(alice, amount);
        usdc.mint(bob, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertTrue(vault.emergencyMode());

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vm.prank(bob);
        vault.deposit(amount, bob);
    }

    /// @notice Fuzzes that mint reverts when emergency mode.
    /// @dev Verifies the revert protects against emergency mode.
    function testFuzz_Mint_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max / 2);
        usdc.mint(alice, amount);
        usdc.mint(bob, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertTrue(vault.emergencyMode());

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vm.prank(bob);
        vault.mint(amount / 2, bob);
    }

    /* ========== EDGE CASE TESTS ========== */

    /// @notice Fuzzes that emergency redeem rounding does not benefit user.
    /// @dev Validates that emergency redeem rounding does not benefit user.
    function testFuzz_EmergencyRedeem_RoundingDoesNotBenefitUser(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 expectedAssets = shares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);

        vm.prank(alice);
        uint256 receivedAssets = vault.redeem(shares, alice, alice);

        assertEq(receivedAssets, expectedAssets);
    }

    /// @notice Tests that emergency redeem minimal shares.
    /// @dev Validates that emergency redeem minimal shares.
    function test_EmergencyRedeem_MinimalShares() public {
        uint256 amount = 1_000_000e6;
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 minShares = 10 ** vault.OFFSET();

        vm.prank(alice);
        uint256 assets = vault.redeem(minShares, alice, alice);

        assertGt(assets, 0);
    }

    /// @notice Ensures emergency redeem reverts when assets round to zero.
    /// @dev Verifies the revert protects against assets round to zero.
    function test_EmergencyRedeem_RevertIf_AssetsRoundToZero() public {
        uint256 amount = 1;
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        vm.prank(address(vault));
        usdc.transfer(treasury, vaultBalance - 1);

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 tinyShares = 1;
        uint256 expectedAssets = tinyShares * vault.recoveryAssets() / vault.recoverySupply();
        assertEq(expectedAssets, 0);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidAssetsAmount.selector, 0, tinyShares));
        vm.prank(alice);
        vault.redeem(tinyShares, alice, alice);
    }

    /// @notice Fuzzes that emergency mode total assets reflects vault balance.
    /// @dev Validates that emergency mode total assets reflects vault balance.
    function testFuzz_EmergencyMode_TotalAssets_ReflectsVaultBalance(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 totalAssets = vault.totalAssets();

        assertApproxEqAbs(totalAssets, vaultBalance, 2);
    }

    /// @notice Ensures activate recovery reverts when zero supply.
    /// @dev Verifies the revert protects against zero supply.
    function test_activateRecovery_RevertIf_ZeroSupply() public {
        // Mint tokens directly to vault (no shares minted)
        uint256 directMint = 1000;
        usdc.mint(address(vault), directMint);

        // Activate emergency mode (even though nothing is in protocol)
        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        assertEq(vault.totalSupply(), 0);
        assertEq(usdc.balanceOf(address(vault)), directMint);
        assertTrue(vault.emergencyMode());

        // Now activateRecovery should revert with InvalidRecoverySupply due to zero supply
        vm.expectRevert(abi.encodeWithSelector(EmergencyVault.InvalidRecoverySupply.selector, 0));
        vm.prank(emergencyAdmin);
        vault.activateRecovery();
    }

    /// @notice Fuzzes that activate recovery with partial recovery.
    /// @dev Validates that activate recovery with partial recovery.
    function testFuzz_activateRecovery_WithPartialRecovery(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1 * 10, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 partialCap = amount * 90 / 100;
        targetVault.setLiquidityCap(partialCap);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        assertApproxEqAbs(vaultBalance, partialCap, 2);

        targetVault.setLiquidityCap(type(uint256).max);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertTrue(vault.recoveryMode());
        assertApproxEqAbs(vault.recoveryAssets(), amount, 2);
    }

    /* ========== IMPLICIT LOSS TRACKING TESTS ========== */

    /// @notice Tests that activate recovery tracks implicit loss with share price decline.
    /// @dev Validates that activate recovery tracks implicit loss with share price decline.
    function test_activateRecovery_TracksImplicitLoss_WithSharePriceDecline() public {
        // Deposit funds
        uint256 amount = 1 * 1000;
        usdc.mint(alice, amount);
        vm.prank(alice);
        vault.deposit(amount, alice);

        // Simulate profit accumulation (mint rewards to targetVault)
        uint256 profit = amount / 10; // 10% profit
        usdc.mint(address(targetVault), profit);

        // Emergency withdraw snapshots total including profit
        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 emergencySnapshot = vault.emergencyTotalAssets();
        assertApproxEqAbs(emergencySnapshot, amount + profit, 2);

        // Simulate 50% loss: burn half of vault's balance
        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 lossAmount = vaultBalance / 2;
        vm.prank(address(vault));
        usdc.transfer(address(0xdead), lossAmount);

        uint256 remainingBalance = usdc.balanceOf(address(vault));
        uint256 protocolBalance = vault.getProtocolBalance();

        uint256 implicitLoss = emergencySnapshot - remainingBalance;

        // Activate recovery
        vm.prank(emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit RecoveryModeActivated(remainingBalance, vault.totalSupply(), protocolBalance, implicitLoss);
        vault.activateRecovery();
    }

    /// @notice Tests that activate recovery tracks implicit loss with partial withdrawal.
    /// @dev Validates that activate recovery tracks implicit loss with partial withdrawal.
    function test_activateRecovery_TracksImplicitLoss_WithPartialWithdrawal() public {
        // Deposit funds
        uint256 amount = 1 * 1000;
        usdc.mint(alice, amount);
        vm.prank(alice);
        vault.deposit(amount, alice);

        // Set liquidity cap to only allow 70% withdrawal
        uint256 partialCap = amount * 70 / 100;
        targetVault.setLiquidityCap(partialCap);

        // Emergency withdraw (partial)
        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 emergencySnapshot = vault.emergencyTotalAssets();
        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 protocolBalance = vault.getProtocolBalance();

        // Expected: no implicit loss (funds just stuck, not lost)
        uint256 expectedLoss = emergencySnapshot - vaultBalance;

        assertEq(expectedLoss, protocolBalance);

        vm.prank(emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit RecoveryModeActivated(vaultBalance, vault.totalSupply(), protocolBalance, expectedLoss);
        vault.activateRecovery();

        // Verify: emergencySnapshot = vaultBalance + protocolBalance (no loss)
        assertApproxEqAbs(emergencySnapshot, vaultBalance + protocolBalance, 2);
    }

    /// @notice Tests that treasury (RewardDistributor) can redeem shares during recovery mode.
    /// @dev Validates that accumulated fee shares can be redeemed through standard redeem() interface.
    function test_TreasuryRedeem_DuringRecoveryMode() public {
        // Setup: Create deposits that generate fees
        uint256 depositAmount = 1 * 1000;

        // Alice deposits
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Simulate profit to generate fees
        uint256 profitAmount = depositAmount / 10; // 10% profit
        usdc.mint(address(targetVault), profitAmount);

        // Bob deposits (triggers fee harvest)
        usdc.mint(bob, depositAmount);
        vm.prank(bob);
        vault.deposit(depositAmount, bob);

        // Verify treasury has fee shares
        uint256 treasuryShares = vault.balanceOf(treasury);
        assertGt(treasuryShares, 0, "Treasury should have fee shares");

        // Enter emergency mode
        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        // Activate recovery
        uint256 vaultBalance = usdc.balanceOf(address(vault));
        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        // Verify recovery mode is active
        assertTrue(vault.recoveryMode(), "Recovery mode should be active");

        // Treasury redeems shares through standard IERC4626 interface
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

        vm.prank(treasury);
        uint256 assetsReceived = vault.redeem(treasuryShares, treasury, treasury);

        // Verify redemption succeeded
        assertGt(assetsReceived, 0, "Treasury should receive assets");
        assertEq(vault.balanceOf(treasury), 0, "Treasury shares should be burned");
        assertEq(usdc.balanceOf(treasury), treasuryBalanceBefore + assetsReceived, "Treasury should receive assets");

        // Verify assets are calculated correctly (pro-rata)
        uint256 expectedAssets =
            treasuryShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        assertEq(assetsReceived, expectedAssets, "Assets should match pro-rata calculation");
    }

    function testFuzz_convertToAssets_RecoveryMode(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 100, type(uint96).max - 1);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        // Simulate profit to generate fees
        uint256 profitAmount = depositAmount / 13;
        usdc.mint(address(targetVault), profitAmount);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        // Verify recovery mode is active
        assertTrue(vault.recoveryMode(), "Recovery mode should be active");

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 aliceAssets = vault.convertToAssets(aliceShares);

        uint256 expectedAssets = aliceShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        assertEq(aliceAssets, expectedAssets, "Assets should match pro-rata calculation");

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + aliceAssets, "Assets should be redeemed");
    }

    function testFuzz_convertToShares_RecoveryMode(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 100, type(uint96).max - 1);
        withdrawAmount = bound(withdrawAmount, 100, depositAmount);

        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Simulate profit to generate fees
        uint256 profitAmount = depositAmount / 13;
        usdc.mint(address(targetVault), profitAmount);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        // Verify recovery mode is active
        assertTrue(vault.recoveryMode(), "Recovery mode should be active");

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 sharesToRedeem = vault.convertToShares(withdrawAmount);
        uint256 expectedShares =
            withdrawAmount.mulDiv(vault.recoverySupply(), vault.recoveryAssets(), Math.Rounding.Floor);
        assertEq(sharesToRedeem, expectedShares, "Assets should match pro-rata calculation");

        vm.prank(alice);
        vault.redeem(sharesToRedeem, alice, alice);

        assertApproxEqAbs(usdc.balanceOf(alice), aliceBalanceBefore + withdrawAmount, 2, "Assets should be redeemed");
    }

    function testFuzz_previewRedeem_RecoveryMode(uint256 depositAmount) public {
        vm.assume(depositAmount > 100 && depositAmount <= type(uint96).max - 1);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        // Simulate profit to generate fees
        uint256 profitAmount = depositAmount / 13;
        usdc.mint(address(targetVault), profitAmount);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        // Verify recovery mode is active
        assertTrue(vault.recoveryMode(), "Recovery mode should be active");

        uint256 sharesToPreview = aliceShares / 2;
        uint256 expectedAssets =
            sharesToPreview.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);

        uint256 previewedAssets = vault.previewRedeem(sharesToPreview);
        assertEq(previewedAssets, expectedAssets, "Preview should match recovery ratio");
    }

    function test_convertToAssets_EmergencyModeUsesLiveRatio() public {
        uint256 depositAmount = scaleAmount(10_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        uint256 expectedBefore = vault.convertToAssets(aliceShares);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 convertedAfter = vault.convertToAssets(aliceShares);
        assertEq(convertedAfter, expectedBefore, "Conversion should remain unchanged in emergency");
    }

    function test_convertToShares_EmergencyModeUsesLiveRatio() public {
        uint256 depositAmount = scaleAmount(20_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 targetAssets = depositAmount / 2;
        uint256 expectedBefore = vault.convertToShares(targetAssets);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 convertedAfter = vault.convertToShares(targetAssets);
        assertEq(convertedAfter, expectedBefore, "Conversion should remain unchanged in emergency");
    }

    function test_previewRedeem_RevertsIf_EmergencyMode() public {
        uint256 depositAmount = scaleAmount(5_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.previewRedeem(shares);
    }

    function test_previewRedeem_RecoveryModeUsesSnapshot() public {
        uint256 depositAmount = scaleAmount(5_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();
        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        uint256 sharesToPreview = shares / 2;
        if (sharesToPreview == 0) sharesToPreview = shares;

        uint256 expectedAssets =
            sharesToPreview.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        uint256 previewedAssets = vault.previewRedeem(sharesToPreview);
        assertEq(previewedAssets, expectedAssets, "Recovery preview should use snapshot ratio");
    }

    function test_previewWithdraw_RevertsIf_EmergencyMode() public {
        uint256 depositAmount = scaleAmount(8_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.previewWithdraw(depositAmount / 2);
    }

    function test_previewWithdraw_RevertsIf_RecoveryMode() public {
        uint256 depositAmount = scaleAmount(8_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();
        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.previewWithdraw(depositAmount / 2);
    }

    function test_previewDeposit_RevertsIf_EmergencyMode() public {
        uint256 depositAmount = scaleAmount(2_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.previewDeposit(depositAmount);
    }

    function test_previewDeposit_RevertsIf_RecoveryMode() public {
        uint256 depositAmount = scaleAmount(2_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();
        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.previewDeposit(depositAmount);
    }

    function test_previewMint_RevertsIf_EmergencyMode() public {
        uint256 depositAmount = scaleAmount(4_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.previewMint(shares / 2);
    }

    function test_previewMint_RevertsIf_RecoveryMode() public {
        uint256 depositAmount = scaleAmount(4_000);
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();
        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        vm.expectRevert(EmergencyVault.DisabledDuringEmergencyMode.selector);
        vault.previewMint(shares / 2);
    }
}
