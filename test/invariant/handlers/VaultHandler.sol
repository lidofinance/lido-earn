// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {MockERC4626Vault} from "test/mocks/MockERC4626Vault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/**
 * @title VaultHandler
 * @notice General-purpose handler for vault operations in invariant tests
 * @dev Executes random vault operations (deposit, withdraw, mint, redeem)
 */
contract VaultHandler is Test {
    ERC4626Adapter public vault;
    MockERC20 public asset;
    MockERC4626Vault public targetVault;

    address[] public actors;

    uint256 public depositsCount;
    uint256 public withdrawsCount;
    uint256 public mintsCount;
    uint256 public redeemsCount;

    constructor(ERC4626Adapter _vault, MockERC20 _asset, MockERC4626Vault _targetVault, address[] memory _actors) {
        vault = _vault;
        asset = _asset;
        targetVault = _targetVault;
        actors = _actors;

        for (uint256 i = 0; i < actors.length; i++) {
            asset.mint(actors[i], 1_000_000e6);
            vm.prank(actors[i]);
            asset.approve(address(vault), type(uint256).max);
        }
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, 1000, 100_000e6);

        address actor = actors[actorSeed % actors.length];

        uint256 balance = asset.balanceOf(actor);
        if (balance < amount) {
            asset.mint(actor, amount - balance);
        }

        vm.startPrank(actor);
        asset.approve(address(vault), amount);

        try vault.deposit(amount, actor) {
            depositsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Deposit failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];

        uint256 maxWithdraw = vault.maxWithdraw(actor);
        if (maxWithdraw == 0) return;

        amount = bound(amount, 1, maxWithdraw);

        vm.startPrank(actor);
        try vault.withdraw(amount, actor, actor) {
            withdrawsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Withdraw failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function mint(uint256 actorSeed, uint256 shares) external {
        shares = bound(shares, 1000, 100_000e6);

        address actor = actors[actorSeed % actors.length];

        uint256 assetsRequired = vault.previewMint(shares);
        uint256 balance = asset.balanceOf(actor);

        if (balance < assetsRequired) {
            asset.mint(actor, assetsRequired - balance);
        }

        vm.startPrank(actor);
        asset.approve(address(vault), assetsRequired);

        try vault.mint(shares, actor) {
            mintsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Mint failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        address actor = actors[actorSeed % actors.length];

        uint256 maxRedeem = vault.balanceOf(actor);
        if (maxRedeem == 0) return;

        shares = bound(shares, 1, maxRedeem);

        vm.startPrank(actor);
        try vault.redeem(shares, actor, actor) {
            redeemsCount++;
        } catch Error(string memory reason) {
            emit log_named_string("Redeem failed", reason);
        } catch (bytes memory) {}
        vm.stopPrank();
    }

    function addRewards(uint256 amount) external {
        amount = bound(amount, 0, 10_000e6);

        if (amount > 0) {
            asset.mint(address(targetVault), amount);
        }
    }
}
