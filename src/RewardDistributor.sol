// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardDistributor is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public constant MAX_BASIS_POINTS = 10_000;

    struct Recipient {
        address account;
        uint256 basisPoints;
    }

    Recipient[] public recipients;
    mapping(address => bool) private recipientExists;

    event RewardsDistributed(address indexed token, uint256 totalAmount);
    event RecipientPaid(address indexed recipient, address indexed token, uint256 amount);
    event VaultRedeemed(address indexed vault, uint256 shares, uint256 assets);

    error InvalidRecipientsLength();
    error InvalidBasisPointsSum();
    error ZeroAddress();
    error ZeroBasisPoints();
    error NoBalance();
    error NoShares();
    error DuplicateRecipient(address account);

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

    function redeem(address vault) external onlyRole(MANAGER_ROLE) returns (uint256 assets) {
        IERC4626 vaultContract = IERC4626(vault);
        uint256 shares = vaultContract.balanceOf(address(this));

        if (shares == 0) {
            revert NoShares();
        }

        assets = vaultContract.redeem(shares, address(this), address(this));

        emit VaultRedeemed(vault, shares, assets);
    }

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

    function getRecipientsCount() external view returns (uint256) {
        return recipients.length;
    }

    function getRecipient(uint256 index) external view returns (address account, uint256 basisPoints) {
        Recipient memory recipient = recipients[index];
        return (recipient.account, recipient.basisPoints);
    }

    function getAllRecipients() external view returns (Recipient[] memory) {
        return recipients;
    }
}
