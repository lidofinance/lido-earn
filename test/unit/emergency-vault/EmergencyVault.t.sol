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
    event RecoveryActivated(
        uint256 recoveryAssets, uint256 recoverySupply, uint256 protocolBalance, uint256 implicitLoss
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

    function testFuzz_EmergencyWithdraw_FirstCall_ActivatesEmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_EmergencyWithdraw_RecoversAllFunds(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_EmergencyWithdraw_MultipleUsers_RecoversTotalAssets(
        uint96 aliceAmount,
        uint96 bobAmount,
        uint96 charlieAmount
    ) public {
        uint256 aliceDeposit = bound(uint256(aliceAmount), vault.MIN_FIRST_DEPOSIT(), type(uint80).max);
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

    function testFuzz_EmergencyWithdraw_MultipleCallsAccumulate(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2);
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

    function testFuzz_EmergencyWithdraw_EmitsCorrectEvent(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_EmergencyWithdraw_RevertIf_NotEmergencyRole(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.emergencyWithdraw();
    }

    function testFuzz_EmergencyWithdraw_RevertIf_AfterRecoveryActivated(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.expectRevert(EmergencyVault.RecoveryAlreadyActive.selector);
        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();
    }

    function testFuzz_EmergencyWithdraw_SecondCallDoesNotPauseAgain(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2);
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

    function testFuzz_activateRecovery_SnapshotsCorrectly(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 totalSupply = vault.totalSupply();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        assertEq(vault.recoveryAssets(), vaultBalance);
        assertEq(vault.recoverySupply(), totalSupply);
        assertTrue(vault.recoveryActive());
    }

    function testFuzz_activateRecovery_HarvestsFeesBeforeSnapshot(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        usdc.mint(address(targetVault), amount / 10);

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        assertGt(vault.totalSupply(), totalSupplyBefore);
        assertEq(vault.balanceOf(treasury), vault.totalSupply() - totalSupplyBefore);
    }

    function testFuzz_activateRecovery_EmitsEvent(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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
        emit RecoveryActivated(vaultBalance, totalSupply, protocolBalance, implicitLoss);

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        assertEq(vault.recoveryAssets(), vaultBalance);
        assertEq(vault.recoverySupply(), totalSupply);
    }

    function testFuzz_activateRecovery_RevertIf_AmountMismatch_TooHigh(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 declaredAmount = vaultBalance + 1000;

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyVault.RecoverableAmountMismatch.selector, declaredAmount, vaultBalance)
        );
        vm.prank(emergencyAdmin);
        vault.activateRecovery(declaredAmount);
    }

    function testFuzz_activateRecovery_RevertIf_AmountMismatch_TooLow(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        vm.assume(vaultBalance > 1000);
        uint256 declaredAmount = vaultBalance - 1000;

        vm.expectRevert(
            abi.encodeWithSelector(EmergencyVault.RecoverableAmountMismatch.selector, declaredAmount, vaultBalance)
        );
        vm.prank(emergencyAdmin);
        vault.activateRecovery(declaredAmount);
    }

    function testFuzz_activateRecovery_AllowsPartialRecovery(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT() * 10, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 partialCap = amount * 90 / 100;
        targetVault.setLiquidityCap(partialCap);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 protocolBalance = vault.getProtocolBalance();

        assertGt(protocolBalance, 100);
        assertApproxEqAbs(vaultBalance, partialCap, 2);

        vm.prank(emergencyAdmin);
        vault.activateRecovery(vaultBalance);

        assertTrue(vault.recoveryActive());
        assertEq(vault.recoveryAssets(), vaultBalance);
    }

    function testFuzz_activateRecovery_RevertIf_AlreadyActive(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));

        vm.prank(emergencyAdmin);
        vault.activateRecovery(vaultBalance);

        vm.expectRevert(EmergencyVault.RecoveryAlreadyActive.selector);
        vm.prank(emergencyAdmin);
        vault.activateRecovery(vaultBalance);
    }

    function testFuzz_activateRecovery_RevertIf_EmergencyModeNotActive(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        assertGt(vault.getProtocolBalance(), 0, "Funds should be in protocol");
        assertEq(vault.emergencyMode(), false, "Emergency mode should not be active");
        assertEq(vault.emergencyTotalAssets(), 0, "emergencyTotalAssets should be 0 (never set)");

        uint256 vaultBalance = usdc.balanceOf(address(vault));

        vm.expectRevert(EmergencyVault.EmergencyModeNotActive.selector);
        vm.prank(emergencyAdmin);
        vault.activateRecovery(vaultBalance);

        assertEq(vault.emergencyMode(), false, "Emergency mode should still be false");
        assertEq(vault.recoveryActive(), false, "Recovery should not be active");
        assertGt(vault.getProtocolBalance(), 0, "Funds should still be in protocol");
    }

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

        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(emergencyAdmin);
        vault.activateRecovery(0);
    }

    function testFuzz_activateRecovery_RevertIf_NotEmergencyRole(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));

        vm.expectRevert();
        vm.prank(alice);
        vault.activateRecovery(vaultBalance);
    }

    /* ========== EMERGENCY REDEEM TESTS ========== */

    function testFuzz_EmergencyRedeem_ProRataDistribution(uint96 depositAmount, uint96 sharesToRedeem) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 redeemShares = bound(uint256(sharesToRedeem), shares / 100, shares);
        if (redeemShares == 0) redeemShares = shares;

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 expectedAssets =
            redeemShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedAssets > 0);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 receivedAssets = vault.emergencyRedeem(redeemShares, alice, alice);

        assertEq(receivedAssets, expectedAssets);
        assertEq(usdc.balanceOf(alice) - aliceBalanceBefore, receivedAssets);
        assertEq(vault.balanceOf(alice), shares - redeemShares);
    }

    function testFuzz_EmergencyRedeem_MultipleUsers_FairDistribution(
        uint96 aliceAmount,
        uint96 bobAmount,
        uint96 charlieAmount
    ) public {
        uint256 aliceDeposit = bound(uint256(aliceAmount), vault.MIN_FIRST_DEPOSIT(), type(uint80).max);
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
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 recoveryAssets = vault.recoveryAssets();
        uint256 recoverySupply = vault.recoverySupply();

        vm.prank(alice);
        uint256 aliceReceived = vault.emergencyRedeem(aliceShares, alice, alice);

        vm.prank(bob);
        uint256 bobReceived = vault.emergencyRedeem(bobShares, bob, bob);

        vm.prank(charlie);
        uint256 charlieReceived = vault.emergencyRedeem(charlieShares, charlie, charlie);

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

    function testFuzz_EmergencyRedeem_ClaimOrderDoesNotMatter(uint96 aliceAmount, uint96 bobAmount) public {
        uint256 aliceDeposit = bound(uint256(aliceAmount), vault.MIN_FIRST_DEPOSIT(), type(uint80).max);
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
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 recoveryAssets = vault.recoveryAssets();
        uint256 recoverySupply = vault.recoverySupply();

        uint256 expectedAlice = aliceShares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);
        uint256 expectedBob = bobShares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);

        vm.prank(bob);
        uint256 bobReceived = vault.emergencyRedeem(bobShares, bob, bob);

        vm.prank(alice);
        uint256 aliceReceived = vault.emergencyRedeem(aliceShares, alice, alice);

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

    function testFuzz_EmergencyRedeem_PartialRedeem(uint96 depositAmount, uint96 redeemPortion) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 redeemShares = bound(uint256(redeemPortion), shares / 100, shares / 2);
        if (redeemShares == 0) redeemShares = shares / 2;
        vm.assume(redeemShares > 0 && redeemShares < shares);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 expectedFirst = redeemShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedFirst > 0);

        vm.prank(alice);
        uint256 firstRedeem = vault.emergencyRedeem(redeemShares, alice, alice);

        uint256 remainingShares = vault.balanceOf(alice);
        assertEq(remainingShares, shares - redeemShares);

        uint256 expectedSecond =
            remainingShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedSecond > 0);

        vm.prank(alice);
        uint256 secondRedeem = vault.emergencyRedeem(remainingShares, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertGt(firstRedeem + secondRedeem, 0);
    }

    function testFuzz_EmergencyRedeem_BurnsSharesCorrectly(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.prank(alice);
        vault.emergencyRedeem(shares, alice, alice);

        assertEq(vault.totalSupply(), totalSupplyBefore - shares);
        assertEq(vault.balanceOf(alice), 0);
    }

    function testFuzz_EmergencyRedeem_WithApproval(uint96 depositAmount, uint96 sharesToRedeem) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 redeemShares = bound(uint256(sharesToRedeem), shares / 100, shares);
        if (redeemShares == 0) redeemShares = shares;

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 expectedAssets =
            redeemShares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);
        vm.assume(expectedAssets > 0);

        vm.prank(alice);
        vault.approve(bob, redeemShares);

        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        uint256 assets = vault.emergencyRedeem(redeemShares, bob, alice);

        assertEq(usdc.balanceOf(bob) - bobBalanceBefore, assets);
        assertEq(vault.balanceOf(alice), shares - redeemShares);
        assertEq(vault.allowance(alice, bob), 0);
    }

    function testFuzz_EmergencyRedeem_RevertIf_RecoveryNotActive(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.expectRevert(EmergencyVault.RecoveryNotActive.selector);
        vm.prank(alice);
        vault.emergencyRedeem(shares, alice, alice);
    }

    function testFuzz_EmergencyRedeem_RevertIf_ZeroShares(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.emergencyRedeem(0, alice, alice);
    }

    function testFuzz_EmergencyRedeem_RevertIf_ZeroReceiver(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.emergencyRedeem(shares, address(0), alice);
    }

    function testFuzz_EmergencyRedeem_RevertIf_InsufficientShares(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        uint256 requestShares = shares + 1;

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientShares.selector, requestShares, shares));
        vm.prank(alice);
        vault.emergencyRedeem(requestShares, alice, alice);
    }

    function testFuzz_EmergencyRedeem_RevertIf_NoApproval(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.expectRevert();
        vm.prank(bob);
        vault.emergencyRedeem(shares, bob, alice);
    }

    /* ========== BLOCKED OPERATIONS DURING EMERGENCY TESTS ========== */

    function testFuzz_Withdraw_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_Redeem_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
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

    function testFuzz_Deposit_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2);
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

    function testFuzz_Mint_RevertIf_EmergencyMode(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max / 2);
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

    function testFuzz_EmergencyRedeem_RoundingDoesNotBenefitUser(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 expectedAssets = shares.mulDiv(vault.recoveryAssets(), vault.recoverySupply(), Math.Rounding.Floor);

        vm.prank(alice);
        uint256 receivedAssets = vault.emergencyRedeem(shares, alice, alice);

        assertEq(receivedAssets, expectedAssets);
    }

    function test_EmergencyRedeem_MinimalShares() public {
        uint256 amount = 1_000_000e6;
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 minShares = 10 ** vault.OFFSET();

        vm.prank(alice);
        uint256 assets = vault.emergencyRedeem(minShares, alice, alice);

        assertGt(assets, 0);
    }

    function test_EmergencyRedeem_RevertIf_AssetsRoundToZero() public {
        uint256 amount = vault.MIN_FIRST_DEPOSIT();
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        vm.prank(address(vault));
        usdc.transfer(treasury, vaultBalance - 1);

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        uint256 tinyShares = 1;
        uint256 expectedAssets = tinyShares * vault.recoveryAssets() / vault.recoverySupply();
        assertEq(expectedAssets, 0);

        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.emergencyRedeem(tinyShares, alice, alice);
    }

    function testFuzz_EmergencyMode_TotalAssets_ReflectsVaultBalance(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 totalAssets = vault.totalAssets();

        assertApproxEqAbs(totalAssets, vaultBalance, 2);
    }

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

        // Now activateRecovery should revert with ZeroAmount due to zero supply
        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(emergencyAdmin);
        vault.activateRecovery(directMint);
    }

    function testFuzz_activateRecovery_WithPartialRecovery(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT() * 10, type(uint96).max);
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
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        assertTrue(vault.recoveryActive());
        assertApproxEqAbs(vault.recoveryAssets(), amount, 2);
    }

    function testFuzz_DustSweep_AfterAllSharesRedeemed(uint96 depositAmount, uint96 dustAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.prank(alice);
        uint256 received = vault.emergencyRedeem(shares, alice, alice);
        assertGt(received, 0);
        assertEq(vault.totalSupply(), 0);

        uint256 leftover = bound(uint256(dustAmount), 1, amount);
        usdc.mint(address(vault), leftover);

        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

        vm.expectEmit(true, true, true, true);
        emit EmergencyVault.DustSwept(treasury, leftover);

        vm.prank(emergencyAdmin);
        vault.sweepDust(treasury);

        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, leftover);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_DustSweep_RevertIf_NotActive() public {
        vm.expectRevert(EmergencyVault.RecoveryNotActive.selector);
        vm.prank(emergencyAdmin);
        vault.sweepDust(treasury);
    }

    function testFuzz_DustSweep_RevertIf_SharesRemain(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.expectRevert(EmergencyVault.SweepNotReady.selector);
        vm.prank(emergencyAdmin);
        vault.sweepDust(treasury);
    }

    function testFuzz_DustSweep_RevertIf_NoBalance(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.prank(alice);
        vault.emergencyRedeem(shares, alice, alice);

        assertEq(usdc.balanceOf(address(vault)), 0);

        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(emergencyAdmin);
        vault.sweepDust(treasury);
    }

    function testFuzz_DustSweep_RevertIf_ZeroRecipient(uint96 depositAmount, uint96 dustAmount) public {
        uint256 amount = bound(uint256(depositAmount), vault.MIN_FIRST_DEPOSIT(), type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(emergencyAdmin);
        vault.emergencyWithdraw();

        vm.prank(emergencyAdmin);
        vault.activateRecovery(usdc.balanceOf(address(vault)));

        vm.prank(alice);
        vault.emergencyRedeem(shares, alice, alice);

        uint256 leftover = bound(uint256(dustAmount), 1, amount);
        usdc.mint(address(vault), leftover);

        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(emergencyAdmin);
        vault.sweepDust(address(0));
    }

    /* ========== IMPLICIT LOSS TRACKING TESTS ========== */

    function test_activateRecovery_TracksImplicitLoss_WithSharePriceDecline() public {
        // Deposit funds
        uint256 amount = vault.MIN_FIRST_DEPOSIT() * 1000;
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

        // Activate recovery
        vm.prank(emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit RecoveryActivated(remainingBalance, vault.totalSupply(), protocolBalance, lossAmount);
        vault.activateRecovery(remainingBalance);
    }

    function test_activateRecovery_TracksImplicitLoss_WithPartialWithdrawal() public {
        // Deposit funds
        uint256 amount = vault.MIN_FIRST_DEPOSIT() * 1000;
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
        uint256 expectedLoss = 0;

        vm.prank(emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit RecoveryActivated(vaultBalance, vault.totalSupply(), protocolBalance, expectedLoss);
        vault.activateRecovery(vaultBalance);

        // Verify: emergencySnapshot = vaultBalance + protocolBalance (no loss)
        assertApproxEqAbs(emergencySnapshot, vaultBalance + protocolBalance, 2);
    }
}
