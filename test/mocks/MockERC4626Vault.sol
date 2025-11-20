// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockERC4626Vault is ERC4626 {
    using SafeERC20 for IERC20;

    uint256 public yieldRate = 1000;
    uint256 public liquidityCap = type(uint256).max;
    uint8 private immutable OFFSET;
    bool public forceZeroDeposit;

    event YieldAccrued(uint256 amount);

    constructor(IERC20 asset_, string memory name_, string memory symbol_, uint8 offset_)
        ERC4626(asset_)
        ERC20(name_, symbol_)
    {
        OFFSET = offset_;
    }

    function setLiquidityCap(uint256 cap) external {
        liquidityCap = cap;
    }

    function getSharePrice() external view returns (uint256) {
        return totalSupply() > 0 ? (totalAssets() * 1e18) / totalSupply() : 1e18;
    }

    function setForceZeroDeposit(bool status) external {
        forceZeroDeposit = status;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (forceZeroDeposit) {
            IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
            return 0;
        }
        return super.deposit(assets, receiver);
    }

    function maxDeposit(address) public view override returns (uint256) {
        uint256 currentAssets = totalAssets();
        if (currentAssets >= liquidityCap) {
            return 0;
        }
        return liquidityCap - currentAssets;
    }

    function maxMint(address) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(address(0));
        return convertToShares(maxAssets);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 baseMax = super.maxWithdraw(owner);
        return baseMax > liquidityCap ? liquidityCap : baseMax;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        return convertToShares(maxAssets);
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return OFFSET;
    }
}
