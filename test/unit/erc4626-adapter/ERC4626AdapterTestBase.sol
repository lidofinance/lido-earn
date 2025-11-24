// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {MockERC4626Vault} from "test/mocks/MockERC4626Vault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestConfig} from "test/utils/TestConfig.sol";

contract ERC4626AdapterTestBase is TestConfig {
    using Math for uint256;

    ERC4626Adapter public vault;
    MockERC4626Vault public targetVault;
    MockERC20 public usdc;
    uint8 internal assetDecimals;

    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_BALANCE = 1_000_000e6;
    uint16 public constant REWARD_FEE = 500;
    uint8 public constant OFFSET = 6;

    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdrawn(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        assetDecimals = _assetDecimals();
        usdc = new MockERC20("USD Coin", "USDC", assetDecimals);
        targetVault = new MockERC4626Vault(IERC20(address(usdc)), "Mock Yield Vault", "yUSDC", OFFSET);

        vault = new ERC4626Adapter(
            address(usdc), address(targetVault), treasury, REWARD_FEE, OFFSET, "Lido ERC4626 Vault", "lido4626", address(this)
        );

        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _dealAndApprove(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(vault), amount);
    }
}
