// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMetaMorpho} from "@morpho/interfaces/IMetaMorpho.sol";

import {Vault} from "../Vault.sol";

contract MorphoAdapter is Vault {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IMetaMorpho public immutable MORPHO_VAULT;
    IERC20 public immutable ASSET;

    event MorphoDeposit(
        uint256 assets,
        uint256 morphoSharesMinted,
        uint256 morphoSharesBalance
    );

    event MorphoWithdrawal(
        uint256 assets,
        uint256 morphoSharesBurned,
        uint256 morphoSharesBalance
    );

    error MorphoVaultZeroAddress();
    error MorphoDepositFailed();
    error MorphoDepositTooSmall(uint256 amount);

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

    function totalAssets() public view override returns (uint256) {
        uint256 morphoShares = MORPHO_VAULT.balanceOf(address(this));
        if (morphoShares == 0) return 0;
        return MORPHO_VAULT.convertToAssets(morphoShares);
    }

    function _depositToProtocol(
        uint256 assets,
        address /* receiver */
    ) internal override returns (uint256 shares) {
        shares = MORPHO_VAULT.deposit(assets, address(this));

        if (shares == 0) {
            revert MorphoDepositFailed();
        }

        emit MorphoDeposit(
            assets,
            shares,
            MORPHO_VAULT.balanceOf(address(this))
        );

        return shares;
    }

    function _withdrawFromProtocol(
        uint256 assets,
        address receiver,
        address /* owner */
    ) internal override returns (uint256) {
        uint256 availableAssets = MORPHO_VAULT.maxWithdraw(address(this));

        if (assets > availableAssets) {
            revert Vault.InsufficientLiquidity(assets, availableAssets);
        }

        uint256 morphoSharesBurned = MORPHO_VAULT.withdraw(
            assets,
            receiver,
            address(this)
        );

        emit MorphoWithdrawal(
            assets,
            morphoSharesBurned,
            MORPHO_VAULT.balanceOf(address(this))
        );

        return assets;
    }

    function _emergencyWithdrawFromProtocol(
        address receiver
    ) internal override returns (uint256 assets) {
        uint256 morphoShares = MORPHO_VAULT.balanceOf(address(this));

        if (morphoShares == 0) return 0;

        assets = MORPHO_VAULT.redeem(morphoShares, receiver, address(this));
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return
            Math.min(
                super.maxWithdraw(owner),
                MORPHO_VAULT.maxWithdraw(address(this))
            );
    }

    function refreshMorphoApproval() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ASSET.forceApprove(address(MORPHO_VAULT), type(uint256).max);
    }
}
