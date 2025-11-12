// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RewardDistributor
 * @notice Distributes ERC20 tokens and ERC4626 vault shares to multiple recipients based on fixed allocation percentages
 * @dev Two-step distribution flow:
 *      1. `redeem(vault)`: Converts vault shares held by this contract into underlying assets
 *      2. `distribute(token)`: Distributes token balance to all recipients proportionally
 *
 *      Access control: Only MANAGER_ROLE can trigger redemptions and distributions.
 *      Recipient configuration is immutable after deployment.
 */
contract RewardDistributor is AccessControl {
    using SafeERC20 for IERC20;

    /* ========== CONSTANTS ========== */

    /// @notice Role identifier for addresses authorized to redeem and distribute rewards
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Basis points denominator (100% = 10,000 basis points)
    uint256 public constant MAX_BASIS_POINTS = 10_000;

    /* ========== TYPES ========== */

    /**
     * @notice Recipient configuration structure
     * @param account Address that will receive distributed tokens
     * @param basisPoints Allocation percentage in basis points (e.g., 5000 = 50%)
     */
    struct Recipient {
        address account;
        uint256 basisPoints;
    }

    /* ========== STATE VARIABLES ========== */

    /// @notice Array of all recipients with their allocation percentages
    Recipient[] public recipients;

    /// @notice Mapping to track if an address is already configured as a recipient
    mapping(address => bool) private recipientExists;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when tokens are distributed to all recipients
     * @param token Address of the token that was distributed
     * @param totalAmount Total amount of tokens distributed
     */
    event RewardsDistributed(address indexed token, uint256 totalAmount);

    /**
     * @notice Emitted when a recipient receives their share of tokens
     * @param recipient Address of the recipient
     * @param token Address of the token received
     * @param amount Amount of tokens received
     */
    event RecipientPaid(address indexed recipient, address indexed token, uint256 amount);

    /**
     * @notice Emitted when vault shares are redeemed for underlying assets
     * @param vault Address of the ERC4626 vault
     * @param shares Amount of vault shares redeemed
     * @param assets Amount of underlying assets received
     */
    event VaultRedeemed(address indexed vault, uint256 shares, uint256 assets);

    /* ========== ERRORS ========== */

    /// @notice Thrown when recipients and basisPoints arrays have different lengths or are empty
    error InvalidRecipientsLength();

    /// @notice Thrown when the sum of all basis points does not equal MAX_BASIS_POINTS (10,000)
    error InvalidBasisPointsSum();

    /// @notice Thrown when a zero address is provided for recipient or manager
    error ZeroAddress();

    /// @notice Thrown when a recipient's basis points allocation is zero
    error ZeroBasisPoints();

    /// @notice Thrown when attempting to distribute with zero token balance
    error NoBalance();

    /// @notice Thrown when attempting to redeem with zero vault shares
    error NoShares();

    /**
     * @notice Thrown when the same address appears multiple times in recipients array
     * @param account The duplicate address
     */
    error DuplicateRecipient(address account);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the reward distributor with fixed recipients and allocations
     * @dev Recipients and their allocations are immutable after deployment.
     *      The manager receives both DEFAULT_ADMIN_ROLE and MANAGER_ROLE.
     * @param _manager Address that will have permission to redeem and distribute rewards
     * @param _recipients Array of recipient addresses
     * @param _basisPoints Array of allocation percentages in basis points (must sum to 10,000)
     */
    constructor(address _manager, address[] memory _recipients, uint256[] memory _basisPoints) {
        if (_recipients.length != _basisPoints.length) {
            revert InvalidRecipientsLength();
        }

        if (_recipients.length == 0) {
            revert InvalidRecipientsLength();
        }

        uint256 totalBps = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipientAccount = _recipients[i];
            uint256 recipientBps = _basisPoints[i];

            if (recipientAccount == address(0)) {
                revert ZeroAddress();
            }
            if (recipientBps == 0) {
                revert ZeroBasisPoints();
            }
            if (recipientExists[recipientAccount]) {
                revert DuplicateRecipient(recipientAccount);
            }

            recipientExists[recipientAccount] = true;
            recipients.push(Recipient({account: recipientAccount, basisPoints: recipientBps}));

            totalBps += recipientBps;
        }

        if (totalBps != MAX_BASIS_POINTS) {
            revert InvalidBasisPointsSum();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _manager);
        _grantRole(MANAGER_ROLE, _manager);
    }

    /* ========== MANAGER FUNCTIONS ========== */

    /**
     * @notice Redeems all vault shares held by this contract for underlying assets
     * @dev Step 1 of the distribution flow. Call this before distribute() to convert shares to tokens.
     *      Only callable by MANAGER_ROLE.
     * @param vault Address of the ERC4626 vault to redeem from
     * @return assets Amount of underlying assets received from redemption
     */
    function redeem(address vault) external onlyRole(MANAGER_ROLE) returns (uint256 assets) {
        IERC4626 vaultContract = IERC4626(vault);
        uint256 shares = vaultContract.balanceOf(address(this));

        if (shares == 0) {
            revert NoShares();
        }

        assets = vaultContract.redeem(shares, address(this), address(this));
        emit VaultRedeemed(vault, shares, assets);
    }

    /**
     * @notice Distributes entire token balance to all recipients based on their allocation percentages
     * @dev Step 2 of the distribution flow. Distributes the full balance proportionally to all recipients.
     *      Only callable by MANAGER_ROLE.
     * @param token Address of the ERC20 token to distribute
     */
    function distribute(address token) external onlyRole(MANAGER_ROLE) {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));

        if (balance == 0) {
            revert NoBalance();
        }

        for (uint256 i = 0; i < recipients.length; i++) {
            Recipient memory recipient = recipients[i];

            uint256 amount = (balance * recipient.basisPoints) / MAX_BASIS_POINTS;

            if (amount > 0) {
                tokenContract.safeTransfer(recipient.account, amount);
                emit RecipientPaid(recipient.account, token, amount);
            }
        }

        emit RewardsDistributed(token, balance);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the total number of recipients
     * @return Number of configured recipients
     */
    function getRecipientsCount() external view returns (uint256) {
        return recipients.length;
    }

    /**
     * @notice Returns recipient information at a specific index
     * @param index Index in the recipients array
     * @return account Address of the recipient
     * @return basisPoints Allocation percentage in basis points
     */
    function getRecipient(uint256 index) external view returns (address account, uint256 basisPoints) {
        Recipient memory recipient = recipients[index];
        return (recipient.account, recipient.basisPoints);
    }

    /**
     * @notice Returns all recipients and their allocations
     * @return Array of all Recipient structs containing addresses and basis points
     */
    function getAllRecipients() external view returns (Recipient[] memory) {
        return recipients;
    }
}
