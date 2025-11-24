// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626Vault} from "test/mocks/MockERC4626Vault.sol";
import {TestConfig} from "test/utils/TestConfig.sol";

/**
 * @title EmergencyVaultTestBase
 * @notice Base test contract for EmergencyVault functionality
 * @dev Uses ERC4626Adapter as concrete implementation for testing
 */
abstract contract EmergencyVaultTestBase is Test, TestConfig {
    ERC4626Adapter public vault;
    MockERC20 public usdc;
    MockERC4626Vault public targetVault;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public treasury = makeAddr("treasury");

    uint256 public constant INITIAL_BALANCE = 10_000_000;
    uint16 public constant FEE_BPS = 1000; // 10%
    uint8 public constant OFFSET = 9;

    function setUp() public virtual {
        uint8 decimals = _assetDecimals();

        usdc = new MockERC20("USD Coin", "USDC", decimals);
        targetVault = new MockERC4626Vault(usdc, "Mock Yield Vault", "yUSDC", OFFSET);

        vault =
            new ERC4626Adapter(address(usdc), address(targetVault), treasury, FEE_BPS, OFFSET, "Lido Earn Vault", "LEV", address(this));

        uint256 initialBalance = scaleAmount(INITIAL_BALANCE);
        usdc.mint(alice, initialBalance);
        usdc.mint(bob, initialBalance);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    function scaleAmount(uint256 base) internal returns (uint256) {
        return base * (10 ** _assetDecimals());
    }
}
