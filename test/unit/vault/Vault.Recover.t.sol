// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultRecoverTest is VaultTestBase {
    MockERC20 public otherToken;
    address public receiver = makeAddr("receiver");

    event TokenRecovered(address indexed token, address indexed receiver, uint256 amount);

    function setUp() public override {
        super.setUp();
        // Create another token to test recovery
        otherToken = new MockERC20("Other Token", "OTHER", 18);
    }

    /* ========== HAPPY PATH RECOVERY TESTS ========== */

    function test_RecoverERC20_Basic() public {
        uint256 amount = 1000e18;

        // Send some tokens to the vault accidentally
        otherToken.mint(address(vault), amount);

        // Manager recovers the tokens
        vm.expectEmit(true, true, false, true);
        emit TokenRecovered(address(otherToken), receiver, amount);

        vault.recoverERC20(address(otherToken), receiver);

        // Verify tokens were transferred
        assertEq(otherToken.balanceOf(receiver), amount);
        assertEq(otherToken.balanceOf(address(vault)), 0);
    }

    function test_RecoverERC20_MultipleTokens() public {
        MockERC20 token1 = new MockERC20("Token1", "TK1", 6);
        MockERC20 token2 = new MockERC20("Token2", "TK2", 18);

        uint256 amount1 = 500e6;
        uint256 amount2 = 2000e18;

        token1.mint(address(vault), amount1);
        token2.mint(address(vault), amount2);

        // Recover first token
        vault.recoverERC20(address(token1), receiver);
        assertEq(token1.balanceOf(receiver), amount1);

        // Recover second token
        vault.recoverERC20(address(token2), receiver);
        assertEq(token2.balanceOf(receiver), amount2);
    }

    /* ========== ERROR TESTS ========== */

    function test_RecoverERC20_RevertsWhenTokenIsVaultAsset() public {
        // Send vault's main asset to the vault
        asset.mint(address(vault), 1000e6);

        vm.expectRevert(abi.encodeWithSelector(Vault.CannotRecoverVaultAsset.selector, address(asset)));
        vault.recoverERC20(address(asset), receiver);
    }

    function test_RecoverERC20_RevertsWhenTokenIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.RecoveryTokenZeroAddress.selector));
        vault.recoverERC20(address(0), receiver);
    }

    function test_RecoverERC20_RevertsWhenReceiverIsZeroAddress() public {
        otherToken.mint(address(vault), 1000e18);

        vm.expectRevert(abi.encodeWithSelector(Vault.RecoveryReceiverZeroAddress.selector));
        vault.recoverERC20(address(otherToken), address(0));
    }

    function test_RecoverERC20_RevertsWhenBalanceIsZero() public {
        // Don't mint any tokens to vault
        vm.expectRevert(abi.encodeWithSelector(Vault.RecoveryTokenBalanceZero.selector, address(otherToken)));
        vault.recoverERC20(address(otherToken), receiver);
    }

    function test_RecoverERC20_RevertsWhenCallerNotManager() public {
        otherToken.mint(address(vault), 1000e18);

        // Get MANAGER_ROLE before prank
        bytes32 managerRole = vault.MANAGER_ROLE();

        // Alice tries to recover tokens without MANAGER_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, managerRole)
        );

        vm.prank(alice);
        vault.recoverERC20(address(otherToken), receiver);
    }

    /* ========== ROLE MANAGEMENT TESTS ========== */

    function test_RecoverERC20_SucceedsWhenCallerHasManagerRole() public {
        otherToken.mint(address(vault), 1000e18);

        address newManager = makeAddr("newManager");

        // Grant MANAGER_ROLE to newManager
        vault.grantRole(vault.MANAGER_ROLE(), newManager);

        // newManager can recover tokens
        vm.prank(newManager);
        vault.recoverERC20(address(otherToken), receiver);

        assertEq(otherToken.balanceOf(receiver), 1000e18);
    }

    /* ========== EDGE CASE TESTS ========== */

    function test_RecoverERC20_WithDifferentDecimals() public {
        // Test with 6 decimals token
        MockERC20 token6 = new MockERC20("Six Decimals", "SIX", 6);
        token6.mint(address(vault), 999e6);

        vault.recoverERC20(address(token6), receiver);
        assertEq(token6.balanceOf(receiver), 999e6);

        // Test with 8 decimals token
        MockERC20 token8 = new MockERC20("Eight Decimals", "EIGHT", 8);
        token8.mint(address(vault), 777e8);

        vault.recoverERC20(address(token8), receiver);
        assertEq(token8.balanceOf(receiver), 777e8);
    }

    /* ========== FUZZING TESTS ========== */

    function testFuzz_RecoverERC20_AnyAmount(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2); // Avoid overflow

        otherToken.mint(address(vault), amount);

        vault.recoverERC20(address(otherToken), receiver);

        assertEq(otherToken.balanceOf(receiver), amount);
        assertEq(otherToken.balanceOf(address(vault)), 0);
    }

    function testFuzz_RecoverERC20_MultipleRecoveries(uint8 count) public {
        vm.assume(count > 0 && count <= 10); // Limit to reasonable number

        for (uint256 i = 0; i < count; i++) {
            MockERC20 token = new MockERC20(
                string(abi.encodePacked("Token", vm.toString(i))), string(abi.encodePacked("TK", vm.toString(i))), 18
            );

            uint256 amount = (i + 1) * 100e18;
            token.mint(address(vault), amount);

            vault.recoverERC20(address(token), receiver);

            assertEq(token.balanceOf(receiver), amount);
        }
    }
}
