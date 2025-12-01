// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MockVault} from "test/mocks/MockVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Vault} from "src/Vault.sol";
import {TestConfig} from "test/utils/TestConfig.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HarvestReentrancyHook {
    Vault public immutable vault;

    constructor(Vault vault_) {
        vault = vault_;
    }

    function trigger() external {
        vault.harvestFees();
    }
}

contract ReentrantMockVault is MockVault {
    HarvestReentrancyHook public hook;

    constructor(
        address asset_,
        address treasury_,
        uint16 rewardFee_,
        uint8 offset_,
        string memory name_,
        string memory symbol_,
        address admin_
    ) MockVault(asset_, treasury_, rewardFee_, offset_, name_, symbol_, admin_) {}

    function setHook(HarvestReentrancyHook hook_) external {
        hook = hook_;
    }

    function _depositToProtocol(uint256 assets) internal override returns (uint256) {
        uint256 shares = super._depositToProtocol(assets);
        if (address(hook) != address(0)) {
            hook.trigger();
        }
        return shares;
    }
}

contract VaultReentrancyTest is TestConfig {
    MockERC20 internal asset;
    ReentrantMockVault internal vault;
    HarvestReentrancyHook internal hook;

    address internal alice = makeAddr("alice");
    address internal treasury = makeAddr("treasury");

    function setUp() public {
        uint8 decimals = _assetDecimals();
        asset = new MockERC20("USD Coin", "USDC", decimals);
        vault = new ReentrantMockVault(address(asset), treasury, 500, 6, "Mock Vault", "mvUSDC", address(this));

        asset.mint(alice, 10_000e6);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        // Seed initial deposit to avoid zero supply edge cases.
        hook = new HarvestReentrancyHook(vault);
        vault.setHook(hook);

        // Seed initial deposit before installing hook to avoid reentrancy during setup.
        vault.setHook(HarvestReentrancyHook(address(0)));
        vm.prank(alice);
        vault.deposit(1_000e6, alice);
        vault.setHook(hook);
    }

    function test_Mint_RevertsWhenTargetAttemptsHarvestReentrancy() public {
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(alice);
        vault.mint(100e6, alice);
    }

    function test_HarvestFees_SucceedsOutsideReentrancy() public {
        // Disable hook to simulate normal harvest call
        vault.setHook(HarvestReentrancyHook(address(0)));
        vm.prank(alice);
        vault.harvestFees();
    }
}
