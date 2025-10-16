// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMetaMorpho} from "@morpho/interfaces/IMetaMorpho.sol";

import {BaseVault} from "../core/BaseVault.sol";

contract MorphoVault is BaseVault {
    using SafeERC20 for IERC20;

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
    )
        BaseVault(
            IERC20(asset_),
            treasury_,
            rewardFee_,
            offset_,
            name_,
            symbol_
        )
    {
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
    ) internal override returns (uint256 morphoShares) {
        morphoShares = MORPHO_VAULT.deposit(assets, address(this));

        if (morphoShares == 0) {
            revert MorphoDepositFailed();
        }

        emit MorphoDeposit(
            assets,
            morphoShares,
            MORPHO_VAULT.balanceOf(address(this))
        );

        return morphoShares;
    }

    function _withdrawFromProtocol(
        uint256 assetsRequested,
        address receiver,
        address /* owner */
    ) internal override returns (uint256 actualAssets) {
        uint256 availableAssets = MORPHO_VAULT.maxWithdraw(address(this));

        if (assetsRequested > availableAssets) {
            revert BaseVault.InsufficientLiquidity(
                assetsRequested,
                availableAssets
            );
        }

        uint256 sharesBurned = MORPHO_VAULT.withdraw(
            assetsRequested,
            receiver,
            address(this)
        );

        emit MorphoWithdrawal(
            assetsRequested,
            sharesBurned,
            MORPHO_VAULT.balanceOf(address(this))
        );

        return assetsRequested;
    }

    function _emergencyWithdrawFromProtocol(
        address receiver
    ) internal override returns (uint256 amount) {
        uint256 allMorphoShares = MORPHO_VAULT.balanceOf(address(this));

        if (allMorphoShares == 0) return 0;

        amount = MORPHO_VAULT.redeem(allMorphoShares, receiver, address(this));

        return amount;
    }

    function getMorphoPosition()
        external
        view
        returns (uint256 morphoShares, uint256 morphoAssets, uint256 sharePrice)
    {
        morphoShares = MORPHO_VAULT.balanceOf(address(this));

        if (morphoShares > 0) {
            morphoAssets = MORPHO_VAULT.convertToAssets(morphoShares);
            sharePrice = (morphoAssets * 1e18) / morphoShares;
        }

        return (morphoShares, morphoAssets, sharePrice);
    }

    function maxWithdrawable() external view returns (uint256) {
        return MORPHO_VAULT.maxWithdraw(address(this));
    }

    function checkMorphoHealth()
        external
        view
        returns (bool isHealthy, string memory reason)
    {
        uint256 ourShares = MORPHO_VAULT.balanceOf(address(this));
        uint256 ourAssets = totalAssets();

        if (totalSupply() > 0 && ourShares == 0) {
            return (false, "Have supply but no Morpho shares");
        }

        if (ourShares > 0) {
            uint256 convertedAssets = MORPHO_VAULT.convertToAssets(ourShares);
            if (convertedAssets == 0) {
                return (false, "Morpho conversion returns 0");
            }
        }

        uint256 maxWithdraw = MORPHO_VAULT.maxWithdraw(address(this));
        if (ourAssets > 0 && maxWithdraw == 0) {
            return (false, "No liquidity available in Morpho");
        }

        return (true, "");
    }

    function refreshMorphoApproval() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ASSET.forceApprove(address(MORPHO_VAULT), type(uint256).max);
    }

    function getAddresses()
        external
        view
        returns (
            address asset,
            address morphoVault,
            address treasury,
            address thisVault
        )
    {
        return (address(ASSET), address(MORPHO_VAULT), TREASURY, address(this));
    }
}
