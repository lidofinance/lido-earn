// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract BaseVault is
    ERC4626,
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== CONSTANTS ========== */

    uint256 public constant FEE_PRECISION = 10_000;
    uint256 public constant MAX_REWARD_FEE = 2_000;
    uint8 public constant MAX_OFFSET = 23;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /* ========== STATE VARIABLES ========== */

    address public immutable TREASURY;
    uint8 public immutable OFFSET;
    uint16 public rewardFee;
    uint256 public lastTotalAssets;
    uint256 public minFirstDeposit;

    /* ========== EVENTS ========== */

    event Deposited(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event FeesHarvested(
        uint256 profit,
        uint256 feeAmount,
        uint256 sharesMinted
    );

    event RewardFeeUpdated(uint256 oldFee, uint256 newFee);
    event MinFirstDepositUpdated(uint256 oldMin, uint256 newMin);
    event EmergencyWithdrawal(address indexed receiver, uint256 amount);

    /* ========== ERRORS ========== */

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientShares(uint256 requested, uint256 available);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error InvalidSharesAmount(uint256 shares);
    error InvalidFee(uint256 fee);
    error FirstDepositTooSmall(uint256 required, uint256 provided);
    error OffsetTooHigh(uint8 offset);

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IERC20 asset_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        if (treasury_ == address(0)) revert ZeroAddress();
        if (rewardFee_ > MAX_REWARD_FEE) revert InvalidFee(rewardFee_);
        if (offset_ > MAX_OFFSET) revert OffsetTooHigh(offset_);

        TREASURY = treasury_;
        OFFSET = offset_;

        rewardFee = rewardFee_;
        minFirstDeposit = 1000;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(FEE_MANAGER_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    /* ========== ERC4626 OVERRIDES ========== */

    function deposit(
        uint256 assetsToDeposit,
        address shareReceiver
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 sharesMinted)
    {
        if (assetsToDeposit == 0) revert ZeroAmount();
        if (shareReceiver == address(0)) revert ZeroAddress();

        if (totalSupply() == 0 && assetsToDeposit < minFirstDeposit) {
            revert FirstDepositTooSmall(minFirstDeposit, assetsToDeposit);
        }

        _harvestFees();

        sharesMinted = previewDeposit(assetsToDeposit);
        if (sharesMinted == 0) revert ZeroAmount();

        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            msg.sender,
            address(this),
            assetsToDeposit
        );

        _depositToProtocol(assetsToDeposit, shareReceiver);
        _mint(shareReceiver, sharesMinted);

        lastTotalAssets = totalAssets();

        emit Deposited(
            msg.sender,
            shareReceiver,
            assetsToDeposit,
            sharesMinted
        );
    }

    function withdraw(
        uint256 assetsToWithdraw,
        address assetReceiver,
        address shareOwner
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 sharesBurned)
    {
        if (assetsToWithdraw == 0) revert ZeroAmount();
        if (assetReceiver == address(0)) revert ZeroAddress();

        _harvestFees();

        sharesBurned = previewWithdraw(assetsToWithdraw);
        if (sharesBurned == 0) revert ZeroAmount();
        if (sharesBurned > balanceOf(shareOwner)) {
            revert InsufficientShares(sharesBurned, balanceOf(shareOwner));
        }

        if (msg.sender != shareOwner) {
            _spendAllowance(shareOwner, msg.sender, sharesBurned);
        }

        _burn(shareOwner, sharesBurned);

        uint256 actualAssetsWithdrawn = _withdrawFromProtocol(
            assetsToWithdraw,
            assetReceiver,
            shareOwner
        );

        if (actualAssetsWithdrawn < assetsToWithdraw) {
            revert InsufficientLiquidity(
                assetsToWithdraw,
                actualAssetsWithdrawn
            );
        }

        lastTotalAssets = totalAssets();

        emit Withdrawn(
            msg.sender,
            assetReceiver,
            shareOwner,
            actualAssetsWithdrawn,
            sharesBurned
        );
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _harvestFees();

        if (shares > balanceOf(owner)) {
            revert InsufficientShares(shares, balanceOf(owner));
        }

        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAmount();

        _burn(owner, shares);

        uint256 actualAssets = _withdrawFromProtocol(assets, receiver, owner);

        if (actualAssets < assets) {
            revert InsufficientLiquidity(assets, actualAssets);
        }

        assets = actualAssets;
        lastTotalAssets = totalAssets();

        emit Withdrawn(msg.sender, receiver, owner, actualAssets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        _harvestFees();

        assets = previewMint(shares);
        if (assets == 0) revert ZeroAmount();
        if (totalSupply() == 0 && assets < minFirstDeposit) {
            revert FirstDepositTooSmall(minFirstDeposit, assets);
        }

        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            msg.sender,
            address(this),
            assets
        );

        _depositToProtocol(assets, receiver);
        _mint(receiver, shares);
        lastTotalAssets = totalAssets();

        emit Deposited(msg.sender, receiver, assets, shares);
    }

    /* ========== INTERNAL PROTOCOL FUNCTIONS ========== */

    function _depositToProtocol(
        uint256 assets,
        address receiver
    ) internal virtual returns (uint256);

    function _withdrawFromProtocol(
        uint256 assets,
        address receiver,
        address owner
    ) internal virtual returns (uint256 actualAssets);

    /* ========== FEE MANAGEMENT ========== */

    function harvestFees() external {
        _harvestFees();
    }

    function _harvestFees() internal {
        uint256 currentTotal = totalAssets();
        uint256 supply = totalSupply();

        if (currentTotal == 0 || supply == 0) {
            lastTotalAssets = currentTotal;
            return;
        }

        if (currentTotal > lastTotalAssets) {
            uint256 profit = currentTotal - lastTotalAssets;

            uint256 feeAmount = profit.mulDiv(
                rewardFee,
                FEE_PRECISION,
                Math.Rounding.Floor
            );

            if (feeAmount > 0 && feeAmount < currentTotal) {
                uint256 sharesMinted = feeAmount.mulDiv(
                    supply,
                    currentTotal - feeAmount,
                    Math.Rounding.Floor
                );

                if (sharesMinted > 0) {
                    _mint(TREASURY, sharesMinted);
                    emit FeesHarvested(profit, feeAmount, sharesMinted);
                }
            }
        }

        lastTotalAssets = currentTotal;
    }

    function setRewardFee(uint16 newFee) external onlyRole(FEE_MANAGER_ROLE) {
        if (newFee > MAX_REWARD_FEE) revert InvalidFee(newFee);

        _harvestFees();

        uint256 oldFee = rewardFee;
        rewardFee = newFee;

        emit RewardFeeUpdated(oldFee, newFee);
    }

    /* ========== INFLATION ATTACK PROTECTION ========== */

    function _decimalsOffset() internal view override returns (uint8) {
        return OFFSET;
    }

    function setMinFirstDeposit(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldMin = minFirstDeposit;
        minFirstDeposit = amount;

        emit MinFirstDepositUpdated(oldMin, amount);
    }

    /* ========== PAUSE MECHANISM ========== */

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ========== EMERGENCY FUNCTIONS ========== */

    function emergencyWithdraw(
        address receiver
    ) external virtual onlyRole(EMERGENCY_ROLE) returns (uint256 amount) {
        if (receiver == address(0)) revert ZeroAddress();

        amount = _emergencyWithdrawFromProtocol(receiver);

        emit EmergencyWithdrawal(receiver, amount);
    }

    function _emergencyWithdrawFromProtocol(
        address receiver
    ) internal virtual returns (uint256);

    /* ========== VIEW FUNCTIONS ========== */

    function decimals() public view virtual override returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }

    function getPendingFees() external view returns (uint256) {
        uint256 currentTotal = totalAssets();
        if (currentTotal <= lastTotalAssets) return 0;

        uint256 profit = currentTotal - lastTotalAssets;
        return profit.mulDiv(rewardFee, FEE_PRECISION, Math.Rounding.Floor);
    }

    function getVaultConfig()
        external
        view
        returns (
            address treasury,
            uint256 currentRewardFee,
            uint256 currentMinFirstDeposit,
            uint8 currentOffset,
            bool isPaused
        )
    {
        return (TREASURY, rewardFee, minFirstDeposit, OFFSET, paused());
    }
}
