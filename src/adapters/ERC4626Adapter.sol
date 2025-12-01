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
    error TargetVaultZeroAddress();

    /// @notice Thrown when target vault deposit returns zero shares
    error TargetVaultDepositFailed();

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
        if (targetVault_ == address(0)) revert TargetVaultZeroAddress();

        TARGET_VAULT = IERC4626(targetVault_);
        ASSET = IERC20(asset_);

        ASSET.forceApprove(targetVault_, type(uint256).max);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns total assets under management in the adapter
     * @dev Sums assets in target vault and idle vault balance.
     *      During emergency mode funds may sit idle while being distributed.
     * @return targetAssets Total assets managed by the adapter (in target vault + idle balance during emergency)
     */
    function totalAssets() public view override returns (uint256 targetAssets) {
        uint256 targetShares = TARGET_VAULT.balanceOf(address(this));

        if (targetShares > 0) {
            targetAssets = TARGET_VAULT.convertToAssets(targetShares);
        }
        if (emergencyMode) {
            targetAssets += ASSET.balanceOf(address(this));
        }
    }

    /**
     * @notice Returns maximum assets that can be deposited for a given address
     * @dev Respects pause state plus target vault capacity limits.
     * @return Maximum assets that can be deposited (0 if paused, otherwise target vault capacity)
     */
    function maxDeposit(address /* user */ ) public view override returns (uint256) {
        if (paused()) return 0;
        return TARGET_VAULT.maxDeposit(address(this));
    }

    /**
     * @notice Returns maximum shares that can be minted for a given address
     * @dev Converts available deposit capacity to vault shares.
     * @return Maximum shares that can be minted (0 if paused, otherwise converted from target vault capacity)
     */
    function maxMint(address /* user */ ) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 maxAssets = TARGET_VAULT.maxDeposit(address(this));
        return _convertToShares(maxAssets, Math.Rounding.Floor);
    }

    /**
     * @notice Returns maximum assets that can be withdrawn by owner
     * @dev Minimum of user share value and target vault liquidity.
     * @param owner Address to check maximum withdrawal for
     * @return Maximum assets withdrawable by owner (limited by either share balance or target vault liquidity)
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return Math.min(super.maxWithdraw(owner), TARGET_VAULT.maxWithdraw(address(this)));
    }

    /* ========== INTERNAL PROTOCOL FUNCTIONS ========== */

    /**
     * @notice Deposits assets into the target ERC4626 vault
     * @dev Calls target vault's deposit function and emits TargetVaultDeposit event
     * @param assets Amount of assets to deposit into target vault
     * @return shares Amount of target vault shares received
     */
    function _depositToProtocol(uint256 assets) internal override returns (uint256 shares) {
        shares = TARGET_VAULT.deposit(assets, address(this));
        if (shares == 0) revert TargetVaultDepositFailed();
        emit TargetVaultDeposit(assets, shares, TARGET_VAULT.balanceOf(address(this)));
    }

    /**
     * @notice Withdraws assets from the target ERC4626 vault
     * @dev Validates liquidity before withdrawal and emits TargetVaultWithdrawal event
     * @param assets Amount of assets to withdraw from target vault
     * @param receiver Address that will receive the withdrawn assets
     * @return Amount of assets withdrawn (always equals input assets if successful)
     */
    function _withdrawFromProtocol(uint256 assets, address receiver) internal override returns (uint256) {
        uint256 availableAssets = TARGET_VAULT.maxWithdraw(address(this));
        if (assets > availableAssets) {
            revert InsufficientLiquidity(assets, availableAssets);
        }

        uint256 burnedShares = TARGET_VAULT.withdraw(assets, receiver, address(this));
        emit TargetVaultWithdrawal(assets, burnedShares, TARGET_VAULT.balanceOf(address(this)));
        return assets;
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
