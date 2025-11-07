// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "src/Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockVault is Vault {
    using SafeERC20 for IERC20;

    constructor(
        address asset_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_
    ) Vault(IERC20(asset_), treasury_, rewardFee_, offset_, name_, symbol_) {}

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function _depositToProtocol(uint256 assets, address /* receiver */ ) internal pure override returns (uint256) {
        return assets;
    }

    function _withdrawFromProtocol(uint256 assets, address receiver, address /* owner */ )
        internal
        override
        returns (uint256)
    {
        IERC20(asset()).safeTransfer(receiver, assets);
        return assets;
    }

    function _emergencyWithdrawFromProtocol(address receiver) internal override returns (uint256) {
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        if (balance > 0) {
            IERC20(asset()).safeTransfer(receiver, balance);
        }
        return balance;
    }
}
