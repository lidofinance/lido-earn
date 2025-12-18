// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Vault} from "./Vault.sol";

/**
 * @title EmergencyVault
 * @notice Abstract vault extension providing emergency withdrawal and recovery functionality
 * @dev Extends base Vault with emergency fund recovery and fair pro-rata distribution.
 *      Sits between Vault and protocol-specific adapters in inheritance hierarchy:
 *
 *      Vault (abstract)
 *          ↑
 *      EmergencyVault (abstract) ← adds emergency functionality
 *          ↑
 *      ERC4626Adapter (concrete) ← implements protocol logic
 *
 *      Emergency Flow:
 *      1. Admin calls emergencyWithdraw() as many times as needed to recover funds from protocol
 *         - First call snapshots emergencyTotalAssets and enables emergency mode
 *         - Normal withdraw/redeem are blocked during emergency mode
 *         - Can be called multiple times if protocol has partial liquidity
 *
 *      2. Admin calls activateRecovery() to enable user claims
 *         - Harvests pending fees before snapshot
 *         - Calculates and emits implicitLoss (emergencyTotalAssets - recoverable)
 *         - Snapshots recoveryAssets/recoverySupply for pro-rata distribution
 *
 *      3. Users call redeem() to claim proportional share
 *         - Formula: userAssets = userShares * recoveryAssets / recoverySupply
 *
 *      Supported Scenarios:
 *
 *      Scenario 1: Preventive Emergency (No Loss)
 *      - Situation: Admin withdraws funds as precaution before potential issue
 *      - Example: Security concern about protocol, but no actual exploit yet
 *      - Behavior:
 *        • All funds successfully withdrawn from protocol
 *        • Unharvested yield/rewards included in recovery
 *        • implicitLoss = 0 (no value lost)
 *        • protocolBalance = 0 (nothing stuck)
 *        • Users receive 100% of their value + proportional share of fees
 *
 *      Scenario 2: Protocol Exploit with Full Withdrawal
 *      - Situation: Protocol exploited, but admin manages to withdraw remaining funds
 *      - Example: Hacker drains 30% of protocol, admin withdraws remaining 70%
 *      - Behavior:
 *        • emergencyTotalAssets snapshot includes the 30% that was there initially
 *        • Only 70% actually withdrawn to vault
 *        • protocolBalance = 0 (nothing left in protocol)
 *        • implicitLoss = 30% (emergencyTotalAssets - recoverable)
 *        • Users receive pro-rata share of recovered 70%
 *        • Loss is transparent via implicitLoss event parameter
 *
 *      Scenario 3: Liquidity Constraints (Funds Stuck)
 *      - Situation: Protocol has liquidity issues, cannot withdraw all at once
 *      - Example: Target ERC4626 vault has limited available liquidity for immediate withdrawal
 *      - Behavior:
 *        • Multiple emergencyWithdraw() calls possible as liquidity becomes available
 *        • protocolBalance > 0 shows shares still stuck in protocol
 *        • implicitLoss = 0 (value not lost, just illiquid)
 *        • Admin can call activateRecovery() with partial amount
 *        • Event shows both what's distributed and what's still stuck
 *
 *      Scenario 4: Share Price Decline (ERC4626 Integrator Loss)
 *      - Situation: Underlying ERC4626 vault loses value
 *      - Example: Target vault's share price drops from 1.0 to 0.8 due to bad debt
 *      - Behavior:
 *        • emergencyTotalAssets captured before withdrawal reflects old share price
 *        • After withdrawal, our shares are worth 20% less
 *        • protocolBalance may show remaining shares (their value already declined)
 *        • implicitLoss captures the 20% value decline
 *        • Users receive pro-rata share of reduced value
 *
 *      Scenario 5: Combined Loss and Liquidity Issues
 *      - Situation: Both value loss AND some funds stuck in protocol
 *      - Example: Share price dropped 10%, plus 15% of shares can't be withdrawn
 *      - Behavior:
 *        • implicitLoss shows total value gap (10% price drop + 15% stuck if stuck shares are worthless)
 *        • protocolBalance shows the 15% still stuck
 *        • Users receive pro-rata share of what's actually recovered
 *        • Event provides full transparency of both metrics
 *
 *      Scenario 6: Multiple Partial Withdrawals
 *      - Situation: Need to call emergencyWithdraw() multiple times
 *      - Example: Protocol allows only 25% withdrawal per day
 *      - Behavior:
 *        • First call: snapshots emergencyTotalAssets, withdraws 25%
 *        • Subsequent calls: withdraw more batches (25% + 25% + ...)
 *        • protocolBalance decreases with each successful withdrawal
 *        • activateRecovery() called once all desired withdrawals complete
 *        • implicitLoss reflects any value lost during the multi-day process
 *
 *      Inheriting contracts must implement:
 *      - _emergencyWithdrawFromProtocol(address): Withdraw all available assets from protocol
 */
abstract contract EmergencyVault is Vault {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== STATE VARIABLES ========== */

    /// @notice Whether emergency mode is active (vault paused, withdrawing from protocol)
    bool public emergencyMode;

    /// @notice Whether emergency recovery is active (users can claim)
    bool public recoveryMode;

    /// @notice Total assets snapshot when emergency mode activated (before any withdrawals)
    uint256 public emergencyTotalAssets;

    /// @notice Total assets snapshot when recovery was activated
    uint256 public recoveryAssets;

    /// @notice Total supply snapshot when recovery was activated
    uint256 public recoverySupply;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when emergency mode is activated
     * @param emergencyAssetsSnapshot Total assets snapshot captured at activation
     * @param activationTimestamp Block timestamp when emergency mode started
     */
    event EmergencyModeActivated(uint256 emergencyAssetsSnapshot, uint256 activationTimestamp);

    /**
     * @notice Emitted when assets are withdrawn from protocol during emergency
     * @param recovered Amount of assets recovered from protocol
     * @param remaining Amount still remaining in protocol
     */
    event EmergencyWithdrawal(uint256 recovered, uint256 remaining);

    /**
     * @notice Emitted when emergency recovery is activated
     * @param recoveryBalance Recoverable amount
     * @param recoverySupply Total shares
     * @param remainingProtocolBalance Amount stuck in protocol due to liquidity constraints
     * @param implicitLoss Value lost compared to emergencyTotalAssets snapshot
     */
    event RecoveryModeActivated(
        uint256 recoveryBalance, uint256 recoverySupply, uint256 remainingProtocolBalance, uint256 implicitLoss
    );

    /* ========== ERRORS ========== */

    /// @notice Thrown when trying to activate recovery that's already active
    error RecoveryModeAlreadyActive();

    /// @notice Thrown when attempting a disabled action while emergency mode is active
    error DisabledDuringEmergencyMode();

    /// @notice Thrown when attempting to activate emergency mode more than once
    error EmergencyModeAlreadyActive();

    /// @notice Thrown when trying to activate recovery without emergency mode being active
    error EmergencyModeNotActive();

    /// @notice Thrown when trying to activate recovery with balance being zero
    /// @param assets Amount of assets on the balance at the moment of operation
    error InvalidRecoveryAssets(uint256 assets);

    /// @notice Thrown when trying to activate recovery with supply being zero
    /// @param supply Supply at the moment of operation
    error InvalidRecoverySupply(uint256 supply);

    /* ========== EMERGENCY FUNCTIONS ========== */

    /**
     * @notice Withdraw assets from underlying protocol to vault
     * @dev First call snapshots emergencyTotalAssets (before withdrawal) and locks vault operations.
     *      This snapshot is used to calculate implicitLoss in activateRecovery().
     *      Can be called multiple times until all assets are recovered.
     *      Cannot be called after recovery is activated.
     *
     *      Only callable by EMERGENCY_ROLE.
     * @return recovered Amount of assets recovered in this call
     */
    function emergencyWithdraw() external virtual nonReentrant onlyRole(EMERGENCY_ROLE) returns (uint256 recovered) {
        if (recoveryMode) revert RecoveryModeAlreadyActive();
        if (!emergencyMode) activateEmergencyMode();

        recovered = _emergencyWithdrawFromProtocol(address(this));
        uint256 remaining = _getProtocolBalance();

        emit EmergencyWithdrawal(recovered, remaining);
    }

    /**
     * @notice Activates emergency mode without performing a withdrawal
     * @dev Snapshots total assets and emits EmergencyModeActivated. Only callable once.
     */
    function activateEmergencyMode() public onlyRole(EMERGENCY_ROLE) {
        if (emergencyMode) revert EmergencyModeAlreadyActive();

        emergencyMode = true;
        uint256 snapshotAssets = totalAssets();
        emergencyTotalAssets = snapshotAssets;
        emit EmergencyModeActivated(snapshotAssets, block.timestamp);
    }

    /**
     * @notice Activate emergency recovery mode for user claims
     * @dev Snapshots vault state and enables pro-rata redemptions.
     *      Permanently locks the vault - users can only redeem() their shares for proportional assets.
     *
     *      Supports partial recovery scenarios:
     *      - If protocolBalance > 0, those funds remain stuck in the target vault
     *      - implicitLoss shows the total amount unavailable to users (stuck funds + phantom value)
     *      - Recovery proceeds with whatever balance is available on the vault contract
     *
     *      Execution flow:
     *      1. Harvests pending fees to ensure fair distribution
     *      2. Snapshots actualBalance and totalSupply for immutable pro-rata calculation
     *      3. Calculates implicitLoss = emergencyTotalAssets - actualBalance
     *      4. Sets recoveryMode = true (permanent, cannot be reversed)
     *
     *      Recovery mode is permanent and CANNOT be deactivated (vault becomes "pumpkin").
     *      After activation, deposits/mints are permanently blocked.
     *
     *      Requirements:
     *      - Emergency mode must be active (funds withdrawn from protocol via emergencyWithdraw)
     *      - Vault must have non-zero asset balance
     *      - Total supply must be > 0 (cannot recover to empty vault)
     *      - Only callable by EMERGENCY_ROLE
     *
     *      Emits RecoveryModeActivated(actualBalance, supply, protocolBalance, implicitLoss)
     *      where implicitLoss = max(0, emergencyTotalAssets - actualBalance)
     */
    function activateRecovery() external virtual nonReentrant onlyRole(EMERGENCY_ROLE) {
        if (recoveryMode) revert RecoveryModeAlreadyActive();
        if (!emergencyMode) revert EmergencyModeNotActive();

        _harvestFees();

        uint256 actualBalance = IERC20(asset()).balanceOf(address(this));
        if (actualBalance == 0) revert InvalidRecoveryAssets(actualBalance);

        uint256 supply = totalSupply();
        if (supply == 0) revert InvalidRecoverySupply(supply);

        uint256 protocolBalance = _getProtocolBalance();
        uint256 implicitLoss = emergencyTotalAssets > actualBalance ? emergencyTotalAssets - actualBalance : 0;

        recoveryAssets = actualBalance;
        recoverySupply = supply;
        recoveryMode = true;

        emit RecoveryModeActivated(actualBalance, supply, protocolBalance, implicitLoss);
    }

    /* ========== OVERRIDES TO BLOCK NORMAL OPERATIONS DURING EMERGENCY ========== */

    /**
     * @inheritdoc Vault
     * @dev Reverts if emergency mode is active to block new exposure while recovering funds.
     */
    function deposit(uint256 assetsToDeposit, address shareReceiver) public virtual override returns (uint256) {
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.deposit(assetsToDeposit, shareReceiver);
    }

    /**
     * @inheritdoc Vault
     * @dev Reverts if emergency mode is active to block new exposure while recovering funds.
     */
    function mint(uint256 sharesToMint, address shareReceiver) public virtual override returns (uint256) {
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.mint(sharesToMint, shareReceiver);
    }

    /**
     * @inheritdoc Vault
     * @dev Reverts if emergency mode is active to preserve pro-rata fairness.
     *      Users must use redeem() after recovery is activated.
     */
    function withdraw(uint256 assetsToWithdraw, address assetReceiver, address shareOwner)
        public
        virtual
        override
        returns (uint256)
    {
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.withdraw(assetsToWithdraw, assetReceiver, shareOwner);
    }

    /**
     * @inheritdoc Vault
     * @dev During recovery mode, automatically delegates to emergencyRedeem() to enable
     *      standard IERC4626 interface for treasury and other integrations.
     *      During emergency mode (before recovery), redemptions are blocked to preserve pro-rata fairness.
     */
    function redeem(uint256 sharesToRedeem, address assetReceiver, address shareOwner)
        public
        virtual
        override
        returns (uint256)
    {
        if (recoveryMode) return _emergencyRedeem(sharesToRedeem, assetReceiver, shareOwner);
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.redeem(sharesToRedeem, assetReceiver, shareOwner);
    }

    /**
     * @inheritdoc Vault
     * @dev Disabled during emergency mode.
     */
    function harvestFees() external override nonReentrant {
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        _harvestFees();
    }

    /* ========== EMERGENCY USER FUNCTIONS ========== */

    /**
     * @notice Internal emergency redemption logic during recovery
     * @dev Called by redeem() when recoveryMode is active.
     *      Uses snapshot ratio from recovery activation for fair pro-rata distribution.
     *      Burns shares and transfers proportional assets from vault balance.
     *      Protected by nonReentrant to prevent reentrancy during token transfer.
     *
     *      Formula: assets = shares * recoveryAssets / recoverySupply
     * @param shares Amount of shares to redeem
     * @param receiver Address that receives assets
     * @param owner Address whose shares are burned
     * @return assets Amount of assets transferred
     */
    function _emergencyRedeem(uint256 shares, address receiver, address owner)
        internal
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert InvalidSharesAmount(shares, 0);
        if (receiver == address(0)) revert InvalidReceiverAddress(receiver);
        if (shares > balanceOf(owner)) revert InsufficientShares(shares, balanceOf(owner));
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

        assets = convertToAssets(shares);
        if (assets == 0) revert InvalidAssetsAmount(assets, shares);

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /* ========== ERC4626 CONVERSION & PREVIEW OVERRIDES ========== */

    /**
     * @inheritdoc ERC4626
     * @dev Uses the recovery snapshot rate during recovery mode.
     */
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        if (recoveryMode) {
            return shares.mulDiv(recoveryAssets, recoverySupply, Math.Rounding.Floor);
        }
        return super.convertToAssets(shares);
    }

    /**
     * @inheritdoc ERC4626
     * @dev Uses the recovery snapshot rate during recovery mode.
     */
    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        if (recoveryMode) {
            return assets.mulDiv(recoverySupply, recoveryAssets, Math.Rounding.Floor);
        }
        return super.convertToShares(assets);
    }

    /**
     * @inheritdoc Vault
     * @dev Reverts during emergency mode and uses the recovery snapshot rate during recovery mode.
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        if (recoveryMode) return convertToAssets(shares);
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.previewRedeem(shares);
    }

    /**
     * @inheritdoc Vault
     * @dev Reverts during emergency mode.
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.previewWithdraw(assets);
    }

    /**
     * @inheritdoc Vault
     * @dev Reverts during emergency mode.
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.previewDeposit(assets);
    }

    /**
     * @inheritdoc Vault
     * @dev Reverts during emergency mode.
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        if (emergencyMode) revert DisabledDuringEmergencyMode();
        return super.previewMint(shares);
    }

    /* ========== INTERNAL VIRTUAL FUNCTIONS ========== */

    /**
     * @notice Withdraws all assets from underlying protocol
     * @dev Must be implemented by inheriting contract with protocol-specific logic
     * @param receiver Address that will receive the withdrawn assets
     * @return Amount of assets withdrawn
     */
    function _emergencyWithdrawFromProtocol(address receiver) internal virtual returns (uint256);
}
