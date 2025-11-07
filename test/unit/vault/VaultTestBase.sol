// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vault} from "src/Vault.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract VaultTestBase is Test {
    MockVault public vault;
    MockERC20 public asset;

    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 1_000_000e6;
    uint16 constant REWARD_FEE = 500;
    uint8 constant OFFSET = 6;

    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdrawn(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        asset = new MockERC20("USD Coin", "USDC", 6);

        vault = new MockVault(address(asset), treasury, REWARD_FEE, OFFSET, "Mock Vault", "mvUSDC");

        asset.mint(alice, INITIAL_BALANCE);
        asset.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function _dealAndApprove(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.prank(user);
        asset.approve(address(vault), amount);
    }

    function _calculateExpectedFeeShares(uint256 profit) internal view returns (uint256) {
        uint256 currentTotal = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        uint256 feeAmount = (profit * REWARD_FEE) / vault.MAX_BASIS_POINTS();
        return (feeAmount * supply) / (currentTotal - feeAmount);
    }

    function _permitHelper(
        uint256 ownerPrivateKey,
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        vault.permit(owner, spender, amount, deadline, v, r, s);
    }
}
