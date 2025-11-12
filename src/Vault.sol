// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
 *      - Inflation attack protection via decimals offset and minimum first deposit
 *      - Pausable deposits and withdrawals
 *      - Reentrancy guards on state-changing operations
 *      - ERC20Permit support for gasless approvals
 *
 *      Inheriting contracts must implement:
 *      - _depositToProtocol(): Protocol-specific deposit logic
 *      - _withdrawFromProtocol(): Protocol-specific withdrawal logic
 *      - _emergencyWithdrawFromProtocol(): Protocol-specific emergency recovery
 *      - totalAssets(): Total assets under management
 */
abstract contract Vault is ERC4626, ERC20Permit, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== CONSTANTS ========== */

    /// @notice Basis points denominator (100% = 10,000 basis points)
    uint256 public constant MAX_BASIS_POINTS = 10_000;

    /// @notice Maximum allowed reward fee in basis points (20%)
    uint256 public constant MAX_REWARD_FEE_BASIS_POINTS = 2_000;

    /// @notice Minimum amount required for first deposit to prevent inflation attacks
    uint256 public constant MIN_FIRST_DEPOSIT = 1_000;

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

    /// @notice Emitted when assets are deposited into the vault
    /// @param caller Address that initiated the deposit
    /// @param owner Address that received the vault shares
    /// @param assets Amount of assets deposited
    /// @param shares Amount of vault shares minted
    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Emitted when assets are withdrawn from the vault
    /// @param caller Address that initiated the withdrawal
    /// @param receiver Address that received the assets
    /// @param owner Address whose shares were burned
    /// @param assets Amount of assets withdrawn
    /// @param shares Amount of vault shares burned
    event Withdrawn(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Emitted when performance fees are harvested
    /// @param profit Total profit since last harvest
    /// @param feeAmount Amount of profit taken as fees
    /// @param sharesMinted Amount of shares minted to treasury as fees
    event FeesHarvested(uint256 profit, uint256 feeAmount, uint256 sharesMinted);

    /// @notice Emitted when reward fee percentage is updated
    /// @param oldFee Previous fee in basis points
    /// @param newFee New fee in basis points
    event RewardFeeUpdated(uint256 oldFee, uint256 newFee);

    /// @notice Emitted when treasury address is updated
    /// @param oldTreasury Previous treasury address
    /// @param newTreasury New treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /// @notice Emitted when emergency withdrawal is executed
    /// @param receiver Address that received the withdrawn assets
    /// @param amount Amount of assets withdrawn
    event EmergencyWithdrawal(address indexed receiver, uint256 amount);

    /// @notice Emitted when vault is paused
    /// @param timestamp Block timestamp when vault was paused
    event VaultPaused(uint256 timestamp);

    /// @notice Emitted when vault is unpaused
    /// @param timestamp Block timestamp when vault was unpaused
    event VaultUnpaused(uint256 timestamp);

    /* ========== ERRORS ========== */

    /// @notice Thrown when an operation is attempted with zero amount
    error ZeroAmount();

    /// @notice Thrown when a zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when user doesn't have enough shares for the operation
    /// @param requested Amount of shares requested
    /// @param available Amount of shares available
    error InsufficientShares(uint256 requested, uint256 available);

    /// @notice Thrown when protocol doesn't have enough liquidity for withdrawal
    /// @param requested Amount of assets requested
    /// @param available Amount of assets available
    error InsufficientLiquidity(uint256 requested, uint256 available);

    /// @notice Thrown when shares amount is invalid
    /// @param shares The invalid shares amount
    error InvalidSharesAmount(uint256 shares);

    /// @notice Thrown when fee value exceeds maximum allowed
    /// @param fee The invalid fee value
    error InvalidFee(uint256 fee);

    /// @notice Thrown when first deposit is below minimum required amount
    /// @param required Minimum amount required
    /// @param provided Amount provided
    error FirstDepositTooSmall(uint256 required, uint256 provided);

    /// @notice Thrown when decimals offset exceeds maximum allowed
    /// @param offset The invalid offset value
    error OffsetTooHigh(uint8 offset);

    /// @notice Thrown when deposit amount exceeds maximum allowed
    /// @param requested Amount of assets requested to deposit
    /// @param maximum Maximum amount allowed to deposit
    error ExceedsMaxDeposit(uint256 requested, uint256 maximum);

    /// @notice Thrown when mint amount exceeds maximum allowed
    /// @param requested Amount of shares requested to mint
    /// @param maximum Maximum amount of shares allowed to mint
    error ExceedsMaxMint(uint256 requested, uint256 maximum);

    /// @notice Thrown when attempting to update treasury to the same address
    error InvalidTreasuryAddress();

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the vault with configuration parameters
     * @param asset_ Underlying ERC20 asset address
     * @param treasury_ Address that will receive performance fees
     * @param rewardFee_ Initial reward fee in basis points (max 2000 = 20%)
     * @param offset_ Decimals offset for share inflation protection (max 23)
     * @param name_ ERC20 name for vault shares
     * @param symbol_ ERC20 symbol for vault shares
     */
    constructor(
        IERC20 asset_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        if (treasury_ == address(0)) revert ZeroAddress();
        if (rewardFee_ > MAX_REWARD_FEE_BASIS_POINTS) {
            revert InvalidFee(rewardFee_);
        }
        if (offset_ > MAX_OFFSET) revert OffsetTooHigh(offset_);

        TREASURY = treasury_;
        OFFSET = offset_;

        rewardFee = rewardFee_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    /* ========== ERC4626 OVERRIDES ========== */

    /**
     * @notice Deposits assets into the vault and mints shares to receiver
     * @dev Harvests pending fees before deposit. First deposit must meet MIN_FIRST_DEPOSIT.
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
        if (assetsToDeposit == 0) revert ZeroAmount();
        if (shareReceiver == address(0)) revert ZeroAddress();
        if (totalSupply() == 0 && assetsToDeposit < MIN_FIRST_DEPOSIT) {
            revert FirstDepositTooSmall(MIN_FIRST_DEPOSIT, assetsToDeposit);
        }

        _harvestFees();

        uint256 maxAssets = maxDeposit(shareReceiver);
        if (assetsToDeposit > maxAssets) {
            revert ExceedsMaxDeposit(assetsToDeposit, maxAssets);
        }

        sharesMinted = _convertToShares(assetsToDeposit, Math.Rounding.Floor);
        if (sharesMinted == 0) revert ZeroAmount();

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assetsToDeposit);

        uint256 protocolSharesReceived = _depositToProtocol(assetsToDeposit);
        if (protocolSharesReceived == 0) revert ZeroAmount();

        _mint(shareReceiver, sharesMinted);

        lastTotalAssets = totalAssets();

        emit Deposited(msg.sender, shareReceiver, assetsToDeposit, sharesMinted);
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
        if (sharesToMint == 0) revert ZeroAmount();
        if (shareReceiver == address(0)) revert ZeroAddress();

        _harvestFees();

        assetsRequired = _convertToAssets(sharesToMint, Math.Rounding.Ceil);
        if (assetsRequired == 0) revert ZeroAmount();
        if (totalSupply() == 0 && assetsRequired < MIN_FIRST_DEPOSIT) {
            revert FirstDepositTooSmall(MIN_FIRST_DEPOSIT, assetsRequired);
        }

        uint256 maxAssets = maxDeposit(shareReceiver);
        if (assetsRequired > maxAssets) {
            revert ExceedsMaxDeposit(assetsRequired, maxAssets);
        }

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assetsRequired);

        uint256 protocolSharesReceived = _depositToProtocol(assetsRequired);
        if (protocolSharesReceived == 0) revert ZeroAmount();

        _mint(shareReceiver, sharesToMint);
        lastTotalAssets = totalAssets();

        emit Deposited(msg.sender, shareReceiver, assetsRequired, sharesToMint);
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
        if (assetsToWithdraw == 0) revert ZeroAmount();
        if (assetReceiver == address(0)) revert ZeroAddress();

        _harvestFees();

        sharesBurned = _convertToShares(assetsToWithdraw, Math.Rounding.Ceil);
        if (sharesBurned == 0) revert ZeroAmount();
        if (sharesBurned > balanceOf(shareOwner)) {
            revert InsufficientShares(sharesBurned, balanceOf(shareOwner));
        }
        if (msg.sender != shareOwner) {
            _spendAllowance(shareOwner, msg.sender, sharesBurned);
        }

        uint256 assetsWithdrawn = _withdrawFromProtocol(assetsToWithdraw, assetReceiver);

        if (assetsWithdrawn < assetsToWithdraw) {
            revert InsufficientLiquidity(assetsToWithdraw, assetsWithdrawn);
        }

        _burn(shareOwner, sharesBurned);

        lastTotalAssets = totalAssets();

        emit Withdrawn(msg.sender, assetReceiver, shareOwner, assetsWithdrawn, sharesBurned);
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
        if (sharesToRedeem == 0) revert ZeroAmount();
        if (assetReceiver == address(0)) revert ZeroAddress();
        if (msg.sender != shareOwner) {
            _spendAllowance(shareOwner, msg.sender, sharesToRedeem);
        }

        _harvestFees();

        if (sharesToRedeem > balanceOf(shareOwner)) {
            revert InsufficientShares(sharesToRedeem, balanceOf(shareOwner));
        }

        uint256 assetsToWithdraw = _convertToAssets(sharesToRedeem, Math.Rounding.Floor);
        assetsWithdrawn = _withdrawFromProtocol(assetsToWithdraw, assetReceiver);

        if (assetsWithdrawn == 0) revert ZeroAmount();

        _burn(shareOwner, sharesToRedeem);
        lastTotalAssets = totalAssets();

        emit Withdrawn(msg.sender, assetReceiver, shareOwner, assetsWithdrawn, sharesToRedeem);
    }

    /* ========== INTERNAL PROTOCOL FUNCTIONS ========== */

    /**
     * @notice Deposits assets into the underlying protocol
     * @dev Must be implemented by inheriting contracts to handle protocol-specific logic
     * @param assets Amount of assets to deposit
     * @return protocolSharesReceived Amount of protocol shares received (if applicable)
     */
    function _depositToProtocol(uint256 assets) internal virtual returns (uint256 protocolSharesReceived);

    /**
     * @notice Withdraws assets from the underlying protocol
     * @dev Must be implemented by inheriting contracts to handle protocol-specific logic
     * @param assets Amount of assets to withdraw
     * @param receiver Address that will receive the assets
     * @return actualAssets Actual amount of assets withdrawn (may differ due to protocol constraints)
     */
    function _withdrawFromProtocol(uint256 assets, address receiver) internal virtual returns (uint256 actualAssets);

    /* ========== FEE MANAGEMENT ========== */

    /**
     * @notice Manually triggers fee harvesting
     * @dev Calculates profit since last harvest and mints fee shares to treasury.
     *      Also called automatically on deposits and withdrawals.
     */
    function harvestFees() external {
        _harvestFees();
    }

    /**
     * @notice Internal function to harvest pending performance fees
     * @dev Calculates profit as (currentTotal - lastTotalAssets), takes fee percentage,
     *      and mints corresponding shares to TREASURY address
     */
    function _harvestFees() internal {
        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (currentTotal == 0 || supply == 0) {
            lastTotalAssets = currentTotal;
            return;
        }

        if (currentTotal > lastTotalAssets) {
            uint256 profit = currentTotal - lastTotalAssets;
            uint256 sharesMinted = _calculateFeeShares(currentTotal, supply);

            if (sharesMinted > 0) {
                uint256 feeAmount = profit.mulDiv(rewardFee, MAX_BASIS_POINTS, Math.Rounding.Ceil);
                if (feeAmount > profit) feeAmount = profit;

                _mint(TREASURY, sharesMinted);
                emit FeesHarvested(profit, feeAmount, sharesMinted);
            }
        }

        lastTotalAssets = currentTotal;
    }

    /**
     * @notice Internal helper to calculate fee shares that would be minted
     * @dev Simulates fee calculation without state changes. Used by maxWithdraw and _harvestFees.
     * @param currentTotal Current total assets in the vault
     * @param supply Current total supply of vault shares
     * @return Number of shares that would be minted as fees
     */
    function _calculateFeeShares(uint256 currentTotal, uint256 supply) internal view returns (uint256) {
        if (currentTotal <= lastTotalAssets || rewardFee == 0 || supply == 0) {
            return 0;
        }

        uint256 profit = currentTotal - lastTotalAssets;
        uint256 feeAmount = profit.mulDiv(rewardFee, MAX_BASIS_POINTS, Math.Rounding.Ceil);

        if (feeAmount > profit) feeAmount = profit;
        if (feeAmount > 0 && feeAmount < currentTotal) {
            return feeAmount.mulDiv(supply, currentTotal - feeAmount, Math.Rounding.Floor);
        }

        return 0;
    }

    /**
     * @notice Updates the reward fee percentage
     * @dev Harvests pending fees before updating. Only callable by MANAGER_ROLE.
     * @param newFee New fee in basis points (max 2000 = 20%)
     */
    function setRewardFee(uint16 newFee) external onlyRole(MANAGER_ROLE) {
        if (newFee > MAX_REWARD_FEE_BASIS_POINTS) revert InvalidFee(newFee);

        _harvestFees();

        uint256 oldFee = rewardFee;
        rewardFee = newFee;

        emit RewardFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Updates the treasury address
     * @dev Only callable by MANAGER_ROLE.
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(MANAGER_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();

        address oldTreasury = TREASURY;
        if (newTreasury == oldTreasury) revert InvalidTreasuryAddress();

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

    /* ========== EMERGENCY FUNCTIONS ========== */

    /**
     * @notice Executes emergency withdrawal from underlying protocol
     * @dev Automatically pauses vault and withdraws all protocol positions.
     *      Users can still withdraw/redeem their vault shares after this.
     *      Only callable by EMERGENCY_ROLE.
     * @param receiver Address that will receive the withdrawn assets
     * @return amount Amount of assets withdrawn from protocol
     */
    function emergencyWithdraw(address receiver) external virtual onlyRole(EMERGENCY_ROLE) returns (uint256 amount) {
        if (receiver == address(0)) revert ZeroAddress();
        if (!paused()) _pause();

        amount = _emergencyWithdrawFromProtocol(receiver);
        lastTotalAssets = totalAssets();

        emit EmergencyWithdrawal(receiver, amount);
    }

    /**
     * @notice Withdraws all assets from underlying protocol in emergency
     * @dev Must be implemented by inheriting contracts for protocol-specific emergency logic
     * @param receiver Address that will receive all withdrawn assets
     * @return Amount of assets withdrawn
     */
    function _emergencyWithdrawFromProtocol(address receiver) internal virtual returns (uint256);

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the number of decimals for vault shares
     * @dev Matches the decimals of the underlying asset
     * @return Number of decimals
     */
    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }

    /**
     * @notice Returns maximum assets that can be withdrawn by owner
     * @dev Overrides ERC4626 to account for pending fees that will be harvested during withdrawal.
     *      Without this adjustment, maxWithdraw could return a value that causes withdraw to revert.
     * @param owner Address to check maximum withdrawal for
     * @return Maximum assets withdrawable accounting for pending fee dilution
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 shares = balanceOf(owner);
        if (shares == 0) return 0;

        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (supply == 0) return 0;

        uint256 feeShares = _calculateFeeShares(currentTotal, supply);
        uint256 adjustedSupply = supply + feeShares;
        uint256 assets = shares.mulDiv(currentTotal, adjustedSupply, Math.Rounding.Floor);

        // Subtract 1 wei buffer to prevent rounding edge cases in withdraw(maxWithdraw(user))
        return assets > 0 ? assets - 1 : 0;
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

        return assets.mulDiv(adjustedSupply, currentTotal, Math.Rounding.Floor);
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

        return shares.mulDiv(currentTotal, adjustedSupply, Math.Rounding.Ceil);
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

        return shares.mulDiv(currentTotal, adjustedSupply, Math.Rounding.Floor);
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

        shares = assets.mulDiv(adjustedSupply + 10 ** OFFSET, currentTotal + 1, Math.Rounding.Ceil);
    }

    /**
     * @notice Calculates pending performance fees not yet harvested
     * @dev Returns fee amount based on profit since last harvest
     * @return Amount of assets that will be taken as fees on next harvest
     */
    function getPendingFees() external view returns (uint256) {
        uint256 currentTotal = totalAssets();
        if (currentTotal <= lastTotalAssets) return 0;

        uint256 profit = currentTotal - lastTotalAssets;
        uint256 feeAmount = profit.mulDiv(rewardFee, MAX_BASIS_POINTS, Math.Rounding.Ceil);
        if (feeAmount > profit) feeAmount = profit;
        return feeAmount;
    }
}
