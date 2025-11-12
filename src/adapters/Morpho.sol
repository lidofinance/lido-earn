// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMetaMorpho} from "@morpho/interfaces/IMetaMorpho.sol";

import {Vault} from "../Vault.sol";

/**
 * @title MorphoAdapter
 * @notice ERC4626 vault adapter that integrates with Morpho MetaMorpho lending vaults
 * @dev Extends the base Vault contract with Morpho-specific implementation:
 *      - Deposits user assets into Morpho MetaMorpho vaults to earn yield
 *      - Tracks positions via Morpho vault shares
 *      - Respects Morpho's liquidity caps in maxDeposit/maxMint
 *      - Uses infinite approval pattern for gas efficiency
 *      - Inherits all security features from base Vault (fees, pause, access control, etc.)
 *
 *      Key design decisions:
 *      - One-time infinite approval set in constructor
 *      - maxDeposit/maxWithdraw respect both vault and Morpho constraints
 *      - Emergency withdrawal redeems all Morpho shares
 */
contract MorphoAdapter is Vault {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== IMMUTABLES ========== */

    /// @notice The Morpho MetaMorpho vault where assets are deposited to earn yield
    IMetaMorpho public immutable MORPHO_VAULT;

    /// @notice The underlying asset token (cached for gas efficiency)
    IERC20 public immutable ASSET;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when assets are deposited into Morpho vault
     * @param assets Amount of assets deposited
     * @param morphoSharesMinted Amount of Morpho vault shares received
     * @param morphoSharesBalance Total Morpho shares held after deposit
     */
    event MorphoDeposit(uint256 assets, uint256 morphoSharesMinted, uint256 morphoSharesBalance);

    /**
     * @notice Emitted when assets are withdrawn from Morpho vault
     * @param assets Amount of assets withdrawn
     * @param morphoSharesBurned Amount of Morpho vault shares burned
     * @param morphoSharesBalance Total Morpho shares held after withdrawal
     */
    event MorphoWithdrawal(uint256 assets, uint256 morphoSharesBurned, uint256 morphoSharesBalance);

    /* ========== ERRORS ========== */

    /// @notice Thrown when Morpho vault address is zero in constructor
    error MorphoVaultZeroAddress();

    /// @notice Thrown when Morpho deposit returns zero shares
    error MorphoDepositFailed();

    /// @notice Thrown when deposit amount is below Morpho's minimum
    /// @param amount The invalid deposit amount
    error MorphoDepositTooSmall(uint256 amount);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the MorphoAdapter with vault configuration and Morpho integration
     * @dev Sets up base Vault and establishes infinite approval to Morpho vault for gas efficiency.
     *      The approval is set once and persists throughout the contract lifetime.
     * @param asset_ Address of the underlying asset (USDC, USDT, etc.)
     * @param morphoVault_ Address of the Morpho MetaMorpho vault to integrate with
     * @param treasury_ Address that receives performance fees
     * @param rewardFee_ Initial reward fee in basis points (0-2000 = 0-20%)
     * @param offset_ Decimals offset for inflation protection (0-23)
     * @param name_ ERC20 name for vault shares
     * @param symbol_ ERC20 symbol for vault shares
     */
    constructor(
        address asset_,
        address morphoVault_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_
    ) Vault(IERC20(asset_), treasury_, rewardFee_, offset_, name_, symbol_) {
        if (morphoVault_ == address(0)) revert MorphoVaultZeroAddress();

        MORPHO_VAULT = IMetaMorpho(morphoVault_);
        ASSET = IERC20(asset_);

        ASSET.forceApprove(morphoVault_, type(uint256).max);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns total assets under management in the vault
     * @dev Converts Morpho vault shares held by this contract to underlying asset value.
     *      This is the primary accounting function - all ERC4626 conversions depend on it.
     * @return Total underlying assets (includes deposited assets and accrued yield)
     */
    function totalAssets() public view override returns (uint256) {
        uint256 morphoShares = MORPHO_VAULT.balanceOf(address(this));
        if (morphoShares == 0) return 0;
        return MORPHO_VAULT.convertToAssets(morphoShares);
    }

    /**
     * @notice Returns maximum assets that can be deposited for a given address
     * @dev Respects both vault pause state and Morpho vault capacity limits.
     *      Returns 0 when paused to prevent new deposits while allowing withdrawals.
     *      When not paused, returns Morpho's available capacity (cap - totalAssets).
     * @return Maximum assets that can be deposited (0 if paused or Morpho at cap)
     */
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;
        return MORPHO_VAULT.maxDeposit(address(this));
    }

    /**
     * @notice Returns maximum shares that can be minted for a given address
     * @dev Converts maxDeposit capacity to shares using current exchange rate.
     *      Returns 0 when paused or when Morpho vault is at capacity.
     * @return Maximum shares that can be minted (0 if paused or Morpho at cap)
     */
    function maxMint(address) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 maxAssets = MORPHO_VAULT.maxDeposit(address(this));
        return _convertToShares(maxAssets, Math.Rounding.Floor);
    }

    /**
     * @notice Returns maximum assets that can be withdrawn by owner
     * @dev Returns the minimum of:
     *      1. User's share value (from base Vault, accounting for pending fees)
     *      2. Morpho vault's available liquidity
     *      This ensures withdrawals never exceed Morpho's actual liquidity.
     * @param owner Address to check maximum withdrawal for
     * @return Maximum assets withdrawable (limited by user balance and Morpho liquidity)
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return Math.min(super.maxWithdraw(owner), MORPHO_VAULT.maxWithdraw(address(this)));
    }

    /* ========== INTERNAL PROTOCOL FUNCTIONS ========== */

    /**
     * @notice Deposits assets into Morpho vault
     * @dev Internal function called by deposit() and mint() in base Vault.
     *      Uses the infinite approval set in constructor for gas efficiency.
     *      Emits MorphoDeposit event with share tracking information.
     * @param assets Amount of assets to deposit into Morpho
     * @return shares Amount of Morpho vault shares received (not to be confused with our vault shares)
     */
    function _depositToProtocol(uint256 assets) internal override returns (uint256 shares) {
        shares = MORPHO_VAULT.deposit(assets, address(this));

        if (shares == 0) {
            revert MorphoDepositFailed();
        }

        emit MorphoDeposit(assets, shares, MORPHO_VAULT.balanceOf(address(this)));

        return shares;
    }

    /**
     * @notice Withdraws assets from Morpho vault
     * @dev Internal function called by withdraw() and redeem() in base Vault.
     *      Checks Morpho liquidity before withdrawal to prevent reverts.
     *      Emits MorphoWithdrawal event with share tracking information.
     * @param assets Amount of assets to withdraw from Morpho
     * @param receiver Address that receives the withdrawn assets
     * @return Actual amount of assets withdrawn (should equal requested amount)
     */
    function _withdrawFromProtocol(uint256 assets, address receiver) internal override returns (uint256) {
        uint256 availableAssets = MORPHO_VAULT.maxWithdraw(address(this));

        if (assets > availableAssets) {
            revert Vault.InsufficientLiquidity(assets, availableAssets);
        }

        uint256 morphoSharesBurned = MORPHO_VAULT.withdraw(assets, receiver, address(this));
        emit MorphoWithdrawal(assets, morphoSharesBurned, MORPHO_VAULT.balanceOf(address(this)));
        return assets;
    }

    /**
     * @notice Emergency withdrawal of all Morpho positions
     * @dev Internal function called by emergencyWithdraw() in base Vault.
     *      Redeems ALL Morpho shares held by this contract in one transaction.
     *      Returns 0 if no shares to redeem (safe no-op).
     *      Only callable by EMERGENCY_ROLE via base Vault's access control.
     * @param receiver Address that receives the withdrawn assets
     * @return assets Amount of assets recovered from Morpho vault
     */
    function _emergencyWithdrawFromProtocol(address receiver) internal override returns (uint256 assets) {
        uint256 morphoShares = MORPHO_VAULT.maxRedeem(address(this));
        if (morphoShares == 0) return 0;
        assets = MORPHO_VAULT.redeem(morphoShares, receiver, address(this));
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @notice Refreshes the infinite approval to Morpho vault
     * @dev Can be called by DEFAULT_ADMIN_ROLE if the approval needs to be reset
     *      (e.g., if Morpho vault is upgraded or approval is somehow consumed).
     *      Sets approval back to type(uint256).max for gas efficiency.
     *      Only callable by DEFAULT_ADMIN_ROLE.
     */
    function refreshMorphoApproval() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ASSET.forceApprove(address(MORPHO_VAULT), type(uint256).max);
    }
}
