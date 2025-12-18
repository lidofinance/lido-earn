// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Vault
 * @notice Abstract base contract for ERC4626-compliant yield vaults
 * @dev Provides foundation for protocol-specific vault adapters with:
 *      - ERC4626 standard compliance for tokenized vault shares
 *      - Role-based access control for administrative functions
 *      - Performance fee harvesting with configurable rates (0-20%)
 *      - Inflation attack protection via decimals offset
 *      - Pausable deposits and withdrawals
 *      - Reentrancy guards on state-changing operations
 *      - ERC20Permit support for gasless approvals
 *
 *      Inheriting contracts must implement:
 *      - _depositToProtocol(): Protocol-specific deposit logic
 *      - _withdrawFromProtocol(): Protocol-specific withdrawal logic
 *      - totalAssets(): Total assets under management
 */
abstract contract Vault is ERC4626, ERC20Permit, AccessControl, ReentrancyGuardTransient, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== CONSTANTS ========== */

    /// @notice Basis points denominator (100% = 10,000 basis points)
    uint256 public constant MAX_BASIS_POINTS = 10_000;

    /// @notice Maximum allowed reward fee in basis points (20%)
    uint256 public constant MAX_REWARD_FEE_BASIS_POINTS = 2_000;

    /// @notice Maximum allowed decimals offset for share inflation protection
    uint8 public constant MAX_OFFSET = 23;

    /// @notice Role identifier for addresses that can pause/unpause the vault
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role identifier for addresses that can update fee parameters
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role identifier for addresses that can trigger emergency withdrawals
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /* ========== STATE VARIABLES ========== */

    /// @notice Address that receives performance fees
    address public TREASURY;

    /// @notice Decimals offset for virtual shares/assets (inflation attack protection)
    uint8 public immutable OFFSET;

    /// @notice Last recorded total assets value (used for fee calculations)
    uint256 public lastTotalAssets;

    /// @notice Current reward fee in basis points (0-2000, i.e., 0-20%)
    uint16 public rewardFee;

    /* ========== EVENTS ========== */

    /// @notice Emitted when performance fees are harvested
    /// @param sharesMinted Amount of shares minted to treasury as fees
    event FeesHarvested(uint256 sharesMinted);

    /// @notice Emitted when reward fee percentage is updated
    /// @param oldFee Previous fee in basis points
    /// @param newFee New fee in basis points
    event RewardFeeUpdated(uint256 oldFee, uint256 newFee);

    /// @notice Emitted when treasury address is updated
    /// @param oldTreasury Previous treasury address
    /// @param newTreasury New treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /// @notice Emitted when vault is paused
    /// @param timestamp Block timestamp when vault was paused
    event VaultPaused(uint256 timestamp);

    /// @notice Emitted when vault is unpaused
    /// @param timestamp Block timestamp when vault was unpaused
    event VaultUnpaused(uint256 timestamp);

    /// @notice Emitted when tokens are recovered from the vault
    /// @param token Address of the recovered token
    /// @param receiver Address that received the tokens
    /// @param amount Amount of tokens recovered
    event TokenRecovered(address indexed token, address indexed receiver, uint256 amount);

    /* ========== ERRORS ========== */

    /// @notice Thrown when an operation is attempted with zero assets amount
    /// @param assetsAmount Amount of assets supplied to the operation
    /// @param sharesAmount Amount of shares associated with the operation
    error InvalidAssetsAmount(uint256 assetsAmount, uint256 sharesAmount);

    /// @notice Thrown when an operation is attempted with zero shares amount
    /// @param sharesAmount Amount of shares supplied to the operation
    /// @param assetsAmount Amount of assets associated with the operation
    error InvalidSharesAmount(uint256 sharesAmount, uint256 assetsAmount);

    /// @notice Thrown when an operation is attempted with invalid receiver address
    /// @param receiver Receiver address provided for the operation
    error InvalidReceiverAddress(address receiver);

    /// @notice Thrown when an operation is attempted with invalid asset address
    /// @param assetAddress Asset address provided for the operation
    error InvalidAssetAddress(address assetAddress);

    /// @notice Thrown when an operation is attempted with invalid treasury address
    /// @param treasuryAddress Treasury address provided for the operation
    error InvalidTreasuryAddress(address treasuryAddress);

    /// @notice Thrown when an operation is attempted with invalid admin address
    /// @param adminAddress Admin address provided for role assignment
    error InvalidAdminAddress(address adminAddress);

    /// @notice Thrown when user doesn't have enough shares for the operation
    /// @param requested Amount of shares requested
    /// @param available Amount of shares available
    error InsufficientShares(uint256 requested, uint256 available);

    /// @notice Thrown when fee value exceeds maximum allowed
    /// @param fee Fee value in basis points that violated the limit
    error InvalidRewardFee(uint256 fee);

    /// @notice Thrown when decimals offset exceeds maximum allowed
    /// @param offset Decimals offset value that exceeded MAX_OFFSET
    error InvalidOffset(uint8 offset);

    /// @notice Thrown when deposit amount exceeds maximum allowed
    /// @param requested Amount of assets requested to deposit
    /// @param maximum Maximum amount allowed to deposit
    error ExceedsMaxDeposit(uint256 requested, uint256 maximum);

    /// @notice Thrown when recovery token address is zero
    /// @param token Token address requested for recovery
    error InvalidRecoveryTokenAddress(address token);

    /// @notice Thrown when recovery receiver address is zero
    /// @param receiver Receiver address requested for recovery payout
    error InvalidRecoveryReceiverAddress(address receiver);

    /// @notice Thrown when token balance is zero and cannot be recovered
    /// @param token The token address with zero balance
    error InsufficientRecoveryTokenBalance(address token);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the vault with configuration parameters
     * @param asset_ Underlying ERC20 asset address
     * @param treasury_ Address that will receive performance fees
     * @param rewardFee_ Initial reward fee in basis points (max 2000 = 20%)
     * @param offset_ Decimals offset for share inflation protection (max 23)
     * @param name_ ERC20 name for vault shares
     * @param symbol_ ERC20 symbol for vault shares
     * @param admin_ Address that will receive all roles (admin, pauser, fee manager, emergency)
     */
    constructor(
        IERC20 asset_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_,
        address admin_
    ) ERC4626(asset_) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (address(asset_) == address(0)) revert InvalidAssetAddress(address(asset_));
        if (treasury_ == address(0)) revert InvalidTreasuryAddress(treasury_);
        if (admin_ == address(0)) revert InvalidAdminAddress(admin_);
        if (rewardFee_ > MAX_REWARD_FEE_BASIS_POINTS) revert InvalidRewardFee(rewardFee_);
        if (offset_ > MAX_OFFSET) revert InvalidOffset(offset_);

        OFFSET = offset_;
        TREASURY = treasury_;
        rewardFee = rewardFee_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(MANAGER_ROLE, admin_);
        _grantRole(EMERGENCY_ROLE, admin_);
    }

    /* ========== ERC4626 OVERRIDES ========== */

    /**
     * @notice Deposits assets into the vault and mints shares to receiver
     * @dev Harvests pending fees before deposit.
     *      Reverts if vault is paused.
     * @param assetsToDeposit Amount of assets to deposit
     * @param shareReceiver Address that will receive the minted shares
     * @return sharesMinted Amount of shares minted to receiver
     */
    function deposit(uint256 assetsToDeposit, address shareReceiver)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 sharesMinted)
    {
        if (assetsToDeposit == 0) revert InvalidAssetsAmount(assetsToDeposit, 0);
        if (shareReceiver == address(0)) revert InvalidReceiverAddress(shareReceiver);

        _harvestFees();

        uint256 maxAssets = maxDeposit(shareReceiver);
        if (assetsToDeposit > maxAssets) revert ExceedsMaxDeposit(assetsToDeposit, maxAssets);

        sharesMinted = _convertToShares(assetsToDeposit, Math.Rounding.Floor);
        if (sharesMinted == 0) revert InvalidSharesAmount(sharesMinted, assetsToDeposit);

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assetsToDeposit);

        _depositToProtocol(assetsToDeposit);
        _mint(shareReceiver, sharesMinted);
        lastTotalAssets += assetsToDeposit;

        emit Deposit(msg.sender, shareReceiver, assetsToDeposit, sharesMinted);
    }

    /**
     * @notice Mints exact amount of shares to receiver by depositing required assets
     * @dev Harvests pending fees before minting. First mint must result in MIN_FIRST_DEPOSIT assets.
     *      Reverts if vault is paused.
     * @param sharesToMint Exact amount of shares to mint
     * @param shareReceiver Address that will receive the minted shares
     * @return assetsRequired Amount of assets deposited from caller
     */
    function mint(uint256 sharesToMint, address shareReceiver)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assetsRequired)
    {
        if (sharesToMint == 0) revert InvalidSharesAmount(sharesToMint, 0);
        if (shareReceiver == address(0)) revert InvalidReceiverAddress(shareReceiver);

        _harvestFees();

        assetsRequired = _convertToAssets(sharesToMint, Math.Rounding.Ceil);
        if (assetsRequired == 0) revert InvalidAssetsAmount(assetsRequired, sharesToMint);

        uint256 maxAssets = maxDeposit(shareReceiver);
        if (assetsRequired > maxAssets) revert ExceedsMaxDeposit(assetsRequired, maxAssets);

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assetsRequired);

        _depositToProtocol(assetsRequired);
        _mint(shareReceiver, sharesToMint);
        lastTotalAssets += assetsRequired;

        emit Deposit(msg.sender, shareReceiver, assetsRequired, sharesToMint);
    }

    /**
     * @notice Withdraws exact amount of assets by burning required shares from owner
     * @dev Harvests pending fees before withdrawal. Works even when vault is paused.
     *      Caller must have sufficient allowance if not the owner.
     * @param assetsToWithdraw Exact amount of assets to withdraw
     * @param assetReceiver Address that will receive the withdrawn assets
     * @param shareOwner Address whose shares will be burned
     * @return sharesBurned Amount of shares burned from owner
     */
    function withdraw(uint256 assetsToWithdraw, address assetReceiver, address shareOwner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 sharesBurned)
    {
        if (assetsToWithdraw == 0) revert InvalidAssetsAmount(assetsToWithdraw, 0);
        if (assetReceiver == address(0)) revert InvalidReceiverAddress(assetReceiver);

        _harvestFees();

        sharesBurned = _convertToShares(assetsToWithdraw, Math.Rounding.Ceil);
        if (sharesBurned == 0) revert InvalidSharesAmount(sharesBurned, assetsToWithdraw);
        if (sharesBurned > balanceOf(shareOwner)) {
            revert InsufficientShares(sharesBurned, balanceOf(shareOwner));
        }
        if (msg.sender != shareOwner) _spendAllowance(shareOwner, msg.sender, sharesBurned);

        _withdrawFromProtocol(assetsToWithdraw, assetReceiver);
        _burn(shareOwner, sharesBurned);
        lastTotalAssets -= assetsToWithdraw;

        emit Withdraw(msg.sender, assetReceiver, shareOwner, assetsToWithdraw, sharesBurned);
    }

    /**
     * @notice Redeems exact amount of shares for assets
     * @dev Harvests pending fees before redemption. Works even when vault is paused.
     *      Caller must have sufficient allowance if not the owner.
     * @param sharesToRedeem Exact amount of shares to burn
     * @param assetReceiver Address that will receive the withdrawn assets
     * @param shareOwner Address whose shares will be burned
     * @return assetsWithdrawn Amount of assets withdrawn to receiver
     */
    function redeem(uint256 sharesToRedeem, address assetReceiver, address shareOwner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 assetsWithdrawn)
    {
        if (sharesToRedeem == 0) revert InvalidSharesAmount(sharesToRedeem, 0);
        if (assetReceiver == address(0)) revert InvalidReceiverAddress(assetReceiver);
        if (msg.sender != shareOwner) _spendAllowance(shareOwner, msg.sender, sharesToRedeem);

        _harvestFees();

        if (sharesToRedeem > balanceOf(shareOwner)) {
            revert InsufficientShares(sharesToRedeem, balanceOf(shareOwner));
        }

        assetsWithdrawn = _convertToAssets(sharesToRedeem, Math.Rounding.Floor);
        if (assetsWithdrawn == 0) revert InvalidAssetsAmount(assetsWithdrawn, sharesToRedeem);

        _withdrawFromProtocol(assetsWithdrawn, assetReceiver);
        _burn(shareOwner, sharesToRedeem);
        lastTotalAssets -= assetsWithdrawn;

        emit Withdraw(msg.sender, assetReceiver, shareOwner, assetsWithdrawn, sharesToRedeem);
    }

    /* ========== INTERNAL PROTOCOL FUNCTIONS ========== */

    /**
     * @notice Deposits assets into the underlying protocol
     * @dev Must be implemented by inheriting contracts to handle protocol-specific logic
     * @param assets Amount of assets to deposit
     */
    function _depositToProtocol(uint256 assets) internal virtual;

    /**
     * @notice Withdraws assets from the underlying protocol
     * @dev Must be implemented by inheriting contracts to handle protocol-specific logic
     * @param assets Amount of assets to withdraw
     * @param receiver Address that will receive the assets
     */
    function _withdrawFromProtocol(uint256 assets, address receiver) internal virtual;

    /**
     * @notice Returns current balance in underlying protocol
     * @dev Must be implemented by inheriting contracts to track protocol exposure
     * @return Amount currently locked in protocol (in asset terms)
     */
    function _getProtocolBalance() internal view virtual returns (uint256);

    /* ========== FEE MANAGEMENT ========== */

    /**
     * @notice Manually triggers fee harvesting
     * @dev Calculates profit since last harvest and mints fee shares to treasury.
     *      Also called automatically on deposits and withdrawals.
     */
    function harvestFees() external virtual nonReentrant {
        _harvestFees();
    }

    /**
     * @notice Internal function to harvest pending performance fees
     * @dev Calculates profit as (currentTotal - lastTotalAssets), takes fee percentage,
     *      and mints corresponding shares to TREASURY address
     */
    function _harvestFees() internal virtual {
        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (currentTotal > lastTotalAssets) {
            uint256 sharesMinted = _calculateFeeShares(currentTotal, supply);
            if (sharesMinted > 0) {
                _mint(TREASURY, sharesMinted);
                emit FeesHarvested(sharesMinted);
            }
        }

        lastTotalAssets = currentTotal;
    }

    /**
     * @notice Internal helper to calculate fee amount that would be minted
     * @dev Simulates fee calculation without state changes
     * @param currentTotal Current total assets in the vault
     * @return feeAmount Amount of assets that would be minted as fees
     */
    function _calculateFeeAmount(uint256 currentTotal) internal view returns (uint256 feeAmount) {
        if (currentTotal <= lastTotalAssets || rewardFee == 0) {
            return 0;
        }
        uint256 profit = currentTotal - lastTotalAssets;
        feeAmount = profit.mulDiv(rewardFee, MAX_BASIS_POINTS, Math.Rounding.Ceil);
    }

    /**
     * @notice Internal helper to calculate fee shares that would be minted
     * @dev Simulates fee calculation without state changes
     * @param currentTotal Current total assets in the vault
     * @param supply Current total supply of vault shares
     * @return feeShares Number of shares that would be minted as fees
     */
    function _calculateFeeShares(uint256 currentTotal, uint256 supply) internal view returns (uint256 feeShares) {
        if (supply == 0) return 0;
        uint256 feeAmount = _calculateFeeAmount(currentTotal);
        if (feeAmount > 0 && feeAmount < currentTotal) {
            return feeAmount.mulDiv(supply, currentTotal - feeAmount, Math.Rounding.Ceil);
        }
        return 0;
    }

    /**
     * @notice Updates the reward fee percentage
     * @dev Harvests pending fees before updating. Only callable by MANAGER_ROLE.
     * @param newFee New fee in basis points (max 2000 = 20%)
     */
    function setRewardFee(uint16 newFee) external onlyRole(MANAGER_ROLE) {
        if (newFee > MAX_REWARD_FEE_BASIS_POINTS) revert InvalidRewardFee(newFee);

        uint16 oldFee = rewardFee;
        if (newFee == oldFee) revert InvalidRewardFee(newFee);

        _harvestFees();
        rewardFee = newFee;
        emit RewardFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Updates the treasury address
     * @dev Only callable by MANAGER_ROLE.
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(MANAGER_ROLE) {
        if (newTreasury == address(0)) revert InvalidTreasuryAddress(newTreasury);

        address oldTreasury = TREASURY;
        if (newTreasury == oldTreasury) revert InvalidTreasuryAddress(newTreasury);

        _harvestFees();
        TREASURY = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /* ========== INFLATION ATTACK PROTECTION ========== */

    /**
     * @notice Returns the decimals offset for virtual shares/assets
     * @dev Part of ERC4626 inflation attack protection mechanism
     * @return Decimals offset value (set at deployment)
     */
    function _decimalsOffset() internal view override returns (uint8) {
        return OFFSET;
    }

    /* ========== PAUSE MECHANISM ========== */

    /**
     * @notice Pauses the vault, blocking deposits and mints
     * @dev Withdrawals and redemptions remain functional when paused.
     *      Only callable by PAUSER_ROLE.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit VaultPaused(block.timestamp);
    }

    /**
     * @notice Unpauses the vault, re-enabling all operations
     * @dev Only callable by PAUSER_ROLE
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit VaultUnpaused(block.timestamp);
    }

    /* ========== TOKEN RECOVERY ========== */

    /**
     * @notice Recovers accidentally sent ERC20 tokens from the vault
     * @dev Only callable by MANAGER_ROLE. Cannot recover the vault's main asset.
     *      Transfers the entire balance of the specified token to the receiver.
     * @param token Address of the ERC20 token to recover
     * @param receiver Address that will receive the recovered tokens
     */
    function recoverERC20(address token, address receiver) public virtual onlyRole(MANAGER_ROLE) {
        if (receiver == address(0)) revert InvalidRecoveryReceiverAddress(receiver);
        if (token == address(0)) revert InvalidRecoveryTokenAddress(token);
        if (token == asset()) revert InvalidRecoveryTokenAddress(token);

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert InsufficientRecoveryTokenBalance(token);

        SafeERC20.safeTransfer(IERC20(token), receiver, balance);
        emit TokenRecovered(token, receiver, balance);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns current balance in underlying protocol
     * @dev Useful for monitoring protocol exposure and tracking emergency withdrawal progress
     * @return Amount currently locked in protocol (in asset terms)
     */
    function getProtocolBalance() public view returns (uint256) {
        return _getProtocolBalance();
    }

    /**
     * @notice Returns the number of decimals for vault shares
     * @dev Matches the decimals of the underlying asset
     * @return Number of decimals
     */
    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return IERC20Metadata(asset()).decimals() + _decimalsOffset();
    }

    /**
     * @notice Returns maximum assets that can be withdrawn by owner
     * @dev Overrides ERC4626 to account for pending fees that will be harvested during withdrawal.
     *      Without this adjustment, maxWithdraw could return a value that causes withdraw to revert.
     *
     *      This function computes the inverse of _convertToShares to ensure withdraw(maxWithdraw(owner))
     *      never reverts due to insufficient shares.
     *
     *      Formula derivation:
     *      withdraw() uses: sharesBurned = assets * (supply + 10^offset) / (total + 1) [Ceil]
     *      We need: sharesBurned ≤ shares
     *      Solving for max assets: assets = shares * (total + 1) / (supply + 10^offset) [Floor]
     *
     * @param owner Address to check maximum withdrawal for
     * @return Maximum assets withdrawable accounting for pending fee dilution and offset protection
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 shares = balanceOf(owner);
        if (shares == 0) return 0;

        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (supply == 0) return 0;

        uint256 feeShares = _calculateFeeShares(currentTotal, supply);
        uint256 adjustedSupply = supply + feeShares;

        // Use the inverse formula of _convertToShares to ensure withdraw never reverts
        // This accounts for the decimals offset used in inflation attack protection
        uint256 assets = shares.mulDiv(currentTotal + 1, adjustedSupply + 10 ** _decimalsOffset(), Math.Rounding.Floor);

        // Subtract 1 wei buffer for additional safety margin
        return assets > 1 ? assets - 1 : 0;
    }

    /**
     * @notice Simulates the amount of shares that would be minted for a given deposit
     * @dev Overrides ERC4626 to account for pending fees that will be harvested during deposit.
     *      This ensures the preview matches the actual execution in deposit().
     *      Per ERC4626: MUST return "no more than" the exact shares that would be minted.
     * @param assets Amount of assets to deposit
     * @return shares Amount of shares that would be minted (accounting for pending fee dilution)
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256 shares) {
        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (supply == 0) {
            return _convertToShares(assets, Math.Rounding.Floor);
        }

        uint256 feeShares = _calculateFeeShares(currentTotal, supply);
        uint256 adjustedSupply = supply + feeShares;

        shares = assets.mulDiv(adjustedSupply + 10 ** _decimalsOffset(), currentTotal + 1, Math.Rounding.Floor);
    }

    /**
     * @notice Simulates the amount of assets required to mint given shares
     * @dev Overrides ERC4626 to account for pending fees that will be harvested during mint.
     *      This ensures the preview matches the actual execution in mint().
     *      Per ERC4626: MUST return "no less than" the exact assets required.
     * @param shares Amount of shares to mint
     * @return assets Amount of assets required (accounting for pending fee dilution)
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256 assets) {
        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (supply == 0) {
            return _convertToAssets(shares, Math.Rounding.Ceil);
        }

        uint256 feeShares = _calculateFeeShares(currentTotal, supply);
        uint256 adjustedSupply = supply + feeShares;

        assets = shares.mulDiv(currentTotal + 1, adjustedSupply + 10 ** _decimalsOffset(), Math.Rounding.Ceil);
    }

    /**
     * @notice Simulates the amount of assets that would be received for redeeming given shares
     * @dev Overrides ERC4626 to account for pending fees that will be harvested during redemption.
     *      This ensures the preview matches the actual execution in redeem().
     *      Per ERC4626: MUST return "no more than" the exact assets that would be received.
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets that would be received (accounting for pending fee dilution)
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256 assets) {
        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (supply == 0 || currentTotal == 0) {
            return _convertToAssets(shares, Math.Rounding.Floor);
        }

        uint256 feeShares = _calculateFeeShares(currentTotal, supply);
        uint256 adjustedSupply = supply + feeShares;

        assets = shares.mulDiv(currentTotal + 1, adjustedSupply + 10 ** _decimalsOffset(), Math.Rounding.Floor);
    }

    /**
     * @notice Simulates the amount of shares that would be burned to withdraw given assets
     * @dev Overrides ERC4626 to account for pending fees that will be harvested during withdrawal.
     *      This ensures the preview matches the actual execution in withdraw().
     *      Per ERC4626: MUST return "no fewer than" the actual shares that would be burned.
     * @param assets Amount of assets to withdraw
     * @return shares Amount of shares that would be burned (accounting for pending fee dilution)
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256 shares) {
        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (supply == 0 || currentTotal == 0) {
            return _convertToShares(assets, Math.Rounding.Ceil);
        }

        uint256 feeShares = _calculateFeeShares(currentTotal, supply);
        uint256 adjustedSupply = supply + feeShares;

        shares = assets.mulDiv(adjustedSupply + 10 ** _decimalsOffset(), currentTotal + 1, Math.Rounding.Ceil);
    }

    /**
     * @notice Calculates pending performance fees not yet harvested
     * @dev Returns fee amount based on profit since last harvest
     * @return feeAmount Amount of assets that will be taken as fees on next harvest
     */
    function getPendingFees() external view returns (uint256 feeAmount) {
        feeAmount = _calculateFeeAmount(totalAssets());
    }

    /* ========== PROTOCOL APPROVAL MANAGEMENT ========== */

    /**
     * @notice Hook to revoke protocol approvals during emergency withdrawal
     * @dev Called by inheriting contracts during first emergency withdrawal.
     *      Default implementation is no-op. Override to revoke specific protocol approvals.
     */
    function _revokeProtocolApproval() internal virtual {}

    /**
     * @notice Hook to refresh protocol approvals (e.g., after revocation or for maintenance)
     * @dev Override in inheriting contract with protocol-specific logic.
     *      Default implementation is no-op.
     */
    function _refreshProtocolApproval() internal virtual {}

    /**
     * @notice Revokes protocol approvals
     * @dev Calls internal _revokeProtocolApproval() hook.
     *      Only callable by EMERGENCY_ROLE.
     */
    function revokeProtocolApproval() public onlyRole(EMERGENCY_ROLE) {
        _revokeProtocolApproval();
    }

    /**
     * @notice Refreshes protocol approvals (e.g., after revocation or for maintenance)
     * @dev Calls internal _refreshProtocolApproval() hook.
     *      Only callable by EMERGENCY_ROLE.
     */
    function refreshProtocolApproval() public onlyRole(EMERGENCY_ROLE) {
        _refreshProtocolApproval();
    }
}
