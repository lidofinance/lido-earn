// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMetaMorpho} from "@morpho/interfaces/IMetaMorpho.sol";

import {Vault} from "src/Vault.sol";
import {MorphoAdapter} from "src/adapters/Morpho.sol";

import {USDC, STEAKHOUSE_USDC_VAULT} from "src/utils/Constants.sol";

contract MorphoConnectorIntegrationTest is Test {
    address public treasury = makeAddr("treasury");
    address public usdcHolder = 0xaD354CfBAa4A8572DD6Df021514a3931A8329Ef5;

    MorphoAdapter public vault;
    IMetaMorpho public morphoVault;

    function setUp() public {
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        vault = new MorphoAdapter(
            USDC,
            STEAKHOUSE_USDC_VAULT,
            treasury,
            500,
            10,
            "MorphoVault",
            "MORPHO"
        );

        morphoVault = IMetaMorpho(STEAKHOUSE_USDC_VAULT);

        vm.prank(usdcHolder);
        IERC20(USDC).approve(address(vault), type(uint256).max);
    }

    function test_Deposit_HappyPath() public {
        uint256 amount = 1_000e6;

        uint256 balanceBefore = IERC20(USDC).balanceOf(usdcHolder);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.prank(usdcHolder);
        uint256 mintedShares = vault.deposit(amount, usdcHolder);

        uint256 balanceAfter = IERC20(USDC).balanceOf(usdcHolder);
        uint256 holderShares = vault.balanceOf(usdcHolder);
        uint256 assetsFromShares = vault.convertToAssets(holderShares);

        assertEq(balanceBefore - balanceAfter, amount);
        assertEq(mintedShares, expectedShares);
        assertEq(holderShares, expectedShares);
        assertEq(vault.totalSupply(), expectedShares);

        assertApproxEqAbs(assetsFromShares, amount, 2);
        assertApproxEqAbs(vault.totalAssets(), amount, 2);
        assertApproxEqAbs(
            morphoVault.convertToAssets(morphoVault.balanceOf(address(vault))),
            amount,
            2
        );
    }
}
