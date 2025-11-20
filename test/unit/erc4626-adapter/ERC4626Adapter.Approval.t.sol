// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterApprovalTest is ERC4626AdapterTestBase {
    function test_RefreshVaultApproval_Success() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);
        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);

        vault.refreshVaultApproval();

        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    function test_RefreshVaultApproval_RevertWhen_NotAdmin() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.refreshVaultApproval();
    }

    function test_RefreshVaultApproval_SetsMaxApproval() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 1_000e6);
        assertEq(usdc.allowance(address(vault), address(targetVault)), 1_000e6);

        vault.refreshVaultApproval();
        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    function test_RefreshVaultApproval_EmitsApprovalEvent() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);

        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Approval(address(vault), address(targetVault), type(uint256).max);

        vault.refreshVaultApproval();
    }

    function test_RefreshVaultApproval_WorksWhenAlreadyMax() public {
        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
        vault.refreshVaultApproval();
        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    function test_RefreshVaultApproval_RestoresDepositFunctionality() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);

        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.refreshVaultApproval();

        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_RefreshVaultApproval_OnlyAdminRole() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert();
        vm.prank(randomUser);
        vault.refreshVaultApproval();

        vault.refreshVaultApproval();

        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), randomUser);

        vm.prank(randomUser);
        vault.refreshVaultApproval();

        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }
}
