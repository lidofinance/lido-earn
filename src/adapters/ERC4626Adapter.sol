// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {Vault} from "../Vault.sol";
import {EmergencyVault} from "../EmergencyVault.sol";

/**
 * @title ERC4626Adapter
 * @notice ERC4626 vault adapter that forwards capital into any underlying ERC4626 strategy
 * @dev Extends EmergencyVault with protocol-agnostic ERC4626 integration:
 *      - Deposits/withdraws assets through the target ERC4626 vault to earn yield
 *      - Tracks positions via target vault shares
 *      - Respects target vault capacity constraints in maxDeposit/maxMint
 *      - Uses infinite approval pattern for gas efficiency
 *      - Multi-stage emergency withdrawal with proportional payouts
 *
 *      This adapter is designed ONLY for standard ERC20 tokens and ERC4626 vaults that
 *      preserve 1:1 value during deposits and withdrawals.
 *
 *      It's not designed to be used with:
 *      1. Fee-on-Transfer tokens (assets with transfer taxes).
 *      2. Rebasing tokens (assets that change balance automatically).
 *      3. Target Vaults that charge Deposit or Withdrawal fees.
 *      4. Target Vaults with slippage on deposit/withdraw.
 *
 *      Using such assets or vaults will result in immediate value dilution for
 *      existing shareholders (loss of funds) because the contract assumes that
 *      sending X assets results in exactly X assets worth of value in the strategy.
 *
 *      Inheritance hierarchy:
 *      Vault (abstract) → EmergencyVault (abstract) → ERC4626Adapter (concrete)
 */
contract ERC4626Adapter is EmergencyVault {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== IMMUTABLES ========== */

    /// @notice The target ERC4626 vault where assets are deposited to earn yield
    IERC4626 public immutable TARGET_VAULT;

    /// @notice The underlying asset token (cached for gas efficiency)
    IERC20 public immutable ASSET;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when assets are deposited into the target ERC4626 vault
     * @param assets Amount of assets deposited
     * @param underlyingSharesMinted Amount of target vault shares received
     * @param underlyingShareBalance Total target vault shares held after deposit
     */
    event TargetVaultDeposit(uint256 assets, uint256 underlyingSharesMinted, uint256 underlyingShareBalance);

    /**
     * @notice Emitted when assets are withdrawn from the target ERC4626 vault
     * @param assets Amount of assets withdrawn
     * @param underlyingSharesBurned Amount of target vault shares burned
     * @param underlyingShareBalance Total target vault shares held after withdrawal
     */
    event TargetVaultWithdrawal(uint256 assets, uint256 underlyingSharesBurned, uint256 underlyingShareBalance);

    /* ========== ERRORS ========== */

    /// @notice Thrown when target vault address is zero in constructor
    /// @param vault Target ERC4626 vault address supplied to the constructor
    error InvalidTargetVaultAddress(address vault);

    /// @notice Thrown when target vault deposit returns unexpected shares
    error TargetVaultDepositFailed();

    /// @notice Thrown when target vault withdraw has insufficient liquidity
    /// @param requested Amount of assets requested
    /// @param available Amount of assets available
    error TargetVaultInsufficientLiquidity(uint256 requested, uint256 available);

    /// @notice Thrown when target vault asset does not match the underlying asset
    /// @param asset Address of the underlying asset (USDC, USDT, etc.)
    /// @param targetVaultAsset Address of the target vault asset
    error TargetVaultAssetMismatch(address asset, address targetVaultAsset);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the adapter with vault configuration and ERC4626 integration
     * @param asset_ Address of the underlying asset (USDC, USDT, etc.)
     * @param targetVault_ Address of the ERC4626 vault to integrate with
     * @param treasury_ Address that receives performance fees
     * @param rewardFee_ Initial reward fee in basis points (0-2000 = 0-20%)
     * @param offset_ Decimals offset for inflation protection (0-23)
     * @param name_ ERC20 name for vault shares
     * @param symbol_ ERC20 symbol for vault shares
     * @param admin_ Address that will receive all roles (admin, pauser, fee manager, emergency)
     */
    constructor(
        address asset_,
        address targetVault_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_,
        address admin_
    ) Vault(IERC20(asset_), treasury_, rewardFee_, offset_, name_, symbol_, admin_) {
        if (targetVault_ == address(0)) revert InvalidTargetVaultAddress(targetVault_);

        TARGET_VAULT = IERC4626(targetVault_);
        if (asset_ != TARGET_VAULT.asset()) revert TargetVaultAssetMismatch(asset_, TARGET_VAULT.asset());

        ASSET = IERC20(asset_);
        ASSET.forceApprove(address(TARGET_VAULT), type(uint256).max);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns total assets under management in the adapter
     * @dev Sums assets in target vault and idle vault balance.
     *      During emergency mode funds may sit idle while being distributed.
     * @return targetAssets Total assets managed by the adapter (in target vault + idle balance during emergency)
     */
    function totalAssets() public view override returns (uint256 targetAssets) {
        targetAssets = _getProtocolBalance();
        if (emergencyMode) targetAssets += ASSET.balanceOf(address(this));
    }

    /**
     * @notice Returns maximum assets that can be deposited for a given address
     * @dev Respects pause state plus target vault capacity limits.
     * @return Maximum assets that can be deposited (0 if paused or in emergency mode, otherwise target vault capacity)
     */
    function maxDeposit(address /* user */ ) public view override returns (uint256) {
        if (paused() || emergencyMode) return 0;
        return TARGET_VAULT.maxDeposit(address(this));
    }

    /**
     * @notice Returns maximum shares that can be minted for a given address
     * @dev Converts available deposit capacity to vault shares.
     * @return Maximum shares that can be minted (0 if paused or in emergency mode, otherwise converted from target vault capacity)
     */
    function maxMint(address /* user */ ) public view override returns (uint256) {
        if (paused() || emergencyMode) return 0;
        uint256 maxAssets = TARGET_VAULT.maxDeposit(address(this));
        if (maxAssets == type(uint256).max) return type(uint256).max;
        return _convertToShares(maxAssets, Math.Rounding.Floor);
    }

    /**
     * @notice Returns maximum assets that can be withdrawn by owner
     * @dev Minimum of user share value and target vault liquidity.
     * @param owner Address to check maximum withdrawal for
     * @return Maximum assets withdrawable by owner (0 if in emergency mode or limited by either share balance or target vault liquidity)
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (emergencyMode) return 0;
        return Math.min(super.maxWithdraw(owner), TARGET_VAULT.maxWithdraw(address(this)));
    }

    /**
     * @notice Returns maximum shares that can be redeemed
     * @dev Checks if the target vault is active/liquid. In recovery mode ignores target vault.
     * @param owner The address of the share owner
     * @return Maximum shares that can be redeemed by owner (0 if in emergency mode or limited by target vault liquidity or user balance)
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 userShares = balanceOf(owner);
        if (recoveryMode) return userShares;
        if (emergencyMode) return 0;
        uint256 availableAssets = TARGET_VAULT.maxWithdraw(address(this));
        uint256 liquidityShares = _convertToShares(availableAssets, Math.Rounding.Floor);
        return Math.min(userShares, liquidityShares);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @notice Deposits unallocated asset balance into the target vault
     * @dev Can be called by MANAGER_ROLE to deposit accidentally donated assets to the target vault.
     *      Donated assets are not immediately counted as profit. They increase totalAssets() and
     *      will be treated as unrealized profit until the next fee harvest (deposit/withdraw).
     *      This ensures fees are only taken on actual yield generated by the donated capital.
     */
    function depositUnallocatedAssets() external onlyRole(MANAGER_ROLE) {
        if (emergencyMode) revert DisabledDuringEmergencyMode();

        uint256 unallocatedBalance = Math.min(ASSET.balanceOf(address(this)), TARGET_VAULT.maxDeposit(address(this)));
        if (unallocatedBalance == 0) revert TargetVaultDepositFailed();

        _depositToProtocol(unallocatedBalance);
    }

    /**
     * @notice Recovers non-core ERC20 tokens accidentally held by the adapter
     * @dev Blocks recovery of the target vault's share token to avoid stealing strategy positions.
     *      Delegates to the base Vault implementation for all other tokens.
     * @param token Address of the ERC20 token to recover
     * @param receiver Address that will receive the recovered tokens
     */
    function recoverERC20(address token, address receiver) public override onlyRole(MANAGER_ROLE) {
        if (token == address(TARGET_VAULT)) revert InvalidRecoveryTokenAddress(token);
        return super.recoverERC20(token, receiver);
    }

    /* ========== INTERNAL PROTOCOL FUNCTIONS ========== */

    /**
     * @notice Deposits assets into the target ERC4626 vault
     * @dev Calls target vault's deposit function and emits TargetVaultDeposit event
     * @param assets Amount of assets to deposit into target vault
     */
    function _depositToProtocol(uint256 assets) internal override {
        uint256 shares = TARGET_VAULT.deposit(assets, address(this));
        if (shares == 0) revert TargetVaultDepositFailed();
        emit TargetVaultDeposit(assets, shares, TARGET_VAULT.balanceOf(address(this)));
    }

    /**
     * @notice Withdraws assets from the target ERC4626 vault
     * @dev Validates liquidity before withdrawal and emits TargetVaultWithdrawal event
     * @param assets Amount of assets to withdraw from target vault
     * @param receiver Address that will receive the withdrawn assets
     */
    function _withdrawFromProtocol(uint256 assets, address receiver) internal override {
        uint256 availableAssets = TARGET_VAULT.maxWithdraw(address(this));
        if (assets > availableAssets) {
            revert TargetVaultInsufficientLiquidity(assets, availableAssets);
        }

        uint256 burnedShares = TARGET_VAULT.withdraw(assets, receiver, address(this));
        emit TargetVaultWithdrawal(assets, burnedShares, TARGET_VAULT.balanceOf(address(this)));
    }

    /**
     * @notice Emergency withdrawal of all target vault positions
     * @dev Redeems all available target vault shares and transfers assets to receiver.
     *      Revokes approval to target vault on first call to prevent compromised vault attacks.
     * @param receiver Address that will receive the withdrawn assets
     * @return assets Amount of assets withdrawn from target vault
     */
    function _emergencyWithdrawFromProtocol(address receiver) internal override returns (uint256 assets) {
        uint256 targetShares = TARGET_VAULT.maxRedeem(address(this));
        if (targetShares == 0) return 0;

        _revokeProtocolApproval();
        assets = TARGET_VAULT.redeem(targetShares, receiver, address(this));
    }

    /**
     * @notice Returns current balance in the target ERC4626 vault
     * @dev Converts adapter's target vault shares to asset value
     * @return Current value of target vault shares held by adapter (in asset terms)
     */
    function _getProtocolBalance() internal view override returns (uint256) {
        uint256 targetShares = TARGET_VAULT.balanceOf(address(this));
        if (targetShares == 0) return 0;
        return TARGET_VAULT.convertToAssets(targetShares);
    }

    /* ========== INTERNAL OVERRIDES ========== */

    /**
     * @notice Revokes approval to target vault (called during emergency withdrawal)
     * @dev Sets approval to 0. Safe to call multiple times (idempotent).
     *      After revocation, vault can no longer deposit to target vault.
     */
    function _revokeProtocolApproval() internal override {
        uint256 currentApproval = ASSET.allowance(address(this), address(TARGET_VAULT));
        if (currentApproval > 0) {
            ASSET.forceApprove(address(TARGET_VAULT), 0);
        }
    }

    /**
     * @notice Refreshes the infinite approval to the target ERC4626 vault
     * @dev Resets approval to type(uint256).max.
     *      Useful if approval was revoked and needs to be restored.
     */
    function _refreshProtocolApproval() internal override {
        ASSET.forceApprove(address(TARGET_VAULT), type(uint256).max);
    }
}
