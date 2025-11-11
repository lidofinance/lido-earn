// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "src/Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockVault is Vault {
    using SafeERC20 for IERC20;

    uint256 public forcedShortfall;
    bool public forceZeroProtocolShares;
    bool public forceZeroPreviewDeposit;
    bool public forceZeroPreviewMint;
    bool public forceZeroPreviewWithdraw;

    constructor(
        address asset_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_
    ) Vault(IERC20(asset_), treasury_, rewardFee_, offset_, name_, symbol_) {}

    function setForcedShortfall(uint256 amount) external {
        forcedShortfall = amount;
    }

    function setForceZeroProtocolShares(bool value) external {
        forceZeroProtocolShares = value;
    }

    function setForceZeroPreviewDeposit(bool value) external {
        forceZeroPreviewDeposit = value;
    }

    function setForceZeroPreviewMint(bool value) external {
        forceZeroPreviewMint = value;
    }

    function setForceZeroPreviewWithdraw(bool value) external {
        forceZeroPreviewWithdraw = value;
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        if (forceZeroPreviewDeposit) return 0;
        return super.previewDeposit(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        if (forceZeroPreviewMint) return 0;
        return super.previewMint(shares);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        if (forceZeroPreviewWithdraw) return 0;
        return super.previewWithdraw(assets);
    }

    function _depositToProtocol(uint256 assets) internal override returns (uint256) {
        if (forceZeroProtocolShares) return 0;
        return assets;
    }

    function _withdrawFromProtocol(uint256 assets, address receiver)
        internal
        override
        returns (uint256)
    {
        uint256 shortfall = forcedShortfall;
        if (shortfall > assets) {
            shortfall = assets;
        }
        uint256 actualAssets = assets - shortfall;
        if (shortfall > 0) {
            forcedShortfall = 0;
        }

        IERC20(asset()).safeTransfer(receiver, actualAssets);
        return actualAssets;
    }

    function _emergencyWithdrawFromProtocol(address receiver) internal override returns (uint256) {
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        if (balance > 0) {
            IERC20(asset()).safeTransfer(receiver, balance);
        }
        return balance;
    }
}
