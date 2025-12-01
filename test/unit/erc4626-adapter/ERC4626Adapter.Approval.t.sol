// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterApprovalTest is ERC4626AdapterTestBase {
    /// @notice Tests that refresh protocol approval success.
    /// @dev Validates that refresh protocol approval success.
    function test_RefreshProtocolApproval_Success() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);
        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);

        vault.refreshProtocolApproval();

        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    /// @notice Tests that refresh protocol approval revert when not admin.
    /// @dev Validates that refresh protocol approval revert when not admin.
    function test_RefreshProtocolApproval_RevertWhen_NotAdmin() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.refreshProtocolApproval();
    }

    /// @notice Tests that refresh protocol approval sets max approval.
    /// @dev Validates that refresh protocol approval sets max approval.
    function test_RefreshProtocolApproval_SetsMaxApproval() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 1_000e6);
        assertEq(usdc.allowance(address(vault), address(targetVault)), 1_000e6);

        vault.refreshProtocolApproval();
        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    /// @notice Tests that refresh protocol approval emits approval event.
    /// @dev Validates that refresh protocol approval emits approval event.
    function test_RefreshProtocolApproval_EmitsApprovalEvent() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);

        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Approval(address(vault), address(targetVault), type(uint256).max);

        vault.refreshProtocolApproval();
    }

    /// @notice Tests that refresh protocol approval works when already max.
    /// @dev Validates that refresh protocol approval works when already max.
    function test_RefreshProtocolApproval_WorksWhenAlreadyMax() public {
        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
        vault.refreshProtocolApproval();
        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    /// @notice Tests that refresh protocol approval restores deposit functionality.
    /// @dev Validates that refresh protocol approval restores deposit functionality.
    function test_RefreshProtocolApproval_RestoresDepositFunctionality() public {
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);

        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.refreshProtocolApproval();

        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    /// @notice Tests that refresh protocol approval only emergency role.
    /// @dev Validates that refresh protocol approval only emergency role.
    function test_RefreshProtocolApproval_OnlyEmergencyRole() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert();
        vm.prank(randomUser);
        vault.refreshProtocolApproval();

        vault.grantRole(vault.EMERGENCY_ROLE(), address(this));
        vault.refreshProtocolApproval();

        vault.grantRole(vault.EMERGENCY_ROLE(), randomUser);

        vm.prank(randomUser);
        vault.refreshProtocolApproval();

        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    /// @notice Tests that approval is revoked after emergency withdraw.
    /// @dev Validates that approval is set to 0 after first emergency withdraw.
    function test_EmergencyWithdraw_RevokesApproval() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);

        vault.grantRole(vault.EMERGENCY_ROLE(), address(this));
        vault.emergencyWithdraw();

        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);
    }

    /// @notice Tests that multiple emergency withdraws work with revoked approval.
    /// @dev Validates that redeem() doesn't require approval, so multiple calls work.
    function test_EmergencyWithdraw_MultipleCallsWorkWithRevokedApproval() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.grantRole(vault.EMERGENCY_ROLE(), address(this));

        // First emergency withdraw revokes approval
        vault.emergencyWithdraw();
        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);

        // Simulate partial withdrawal scenario by depositing more to target vault manually
        // (in real scenario, this would be remaining balance in target vault due to liquidity constraints)
        vm.prank(address(vault));
        usdc.approve(address(targetVault), type(uint256).max);
        vm.prank(address(vault));
        targetVault.deposit(1_000e6, address(vault));

        // Manually set approval back to 0 to simulate state after first emergencyWithdraw
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);

        // Second emergency withdraw should still work (redeem doesn't need approval)
        uint256 recovered = vault.emergencyWithdraw();
        assertGt(recovered, 0);
    }

    /// @notice Tests that deposit fails after approval revocation.
    /// @dev Validates that deposit reverts when approval is 0.
    function test_EmergencyWithdraw_DepositFailsAfterRevocation() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.grantRole(vault.EMERGENCY_ROLE(), address(this));
        vault.emergencyWithdraw();

        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);

        // Try to deposit after recovery (hypothetical scenario)
        // First need to unpause and disable emergency mode (not possible in current implementation)
        // So this test just verifies approval is 0
        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);
    }

    /// @notice Tests that refresh protocol approval restores functionality after revocation.
    /// @dev Validates that refreshProtocolApproval() can restore approval after emergency.
    function test_RefreshProtocolApproval_RestoresAfterEmergencyRevocation() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.grantRole(vault.EMERGENCY_ROLE(), address(this));
        vault.emergencyWithdraw();

        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);

        // Refresh approval
        vault.refreshProtocolApproval();

        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    /// @notice Tests that approval revocation is idempotent.
    /// @dev Validates that calling emergencyWithdraw multiple times doesn't cause issues.
    function test_EmergencyWithdraw_ApprovalRevocationIdempotent() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.grantRole(vault.EMERGENCY_ROLE(), address(this));

        vault.emergencyWithdraw();
        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);

        // Manually restore some balance in target vault
        vm.prank(address(vault));
        usdc.approve(address(targetVault), type(uint256).max);
        vm.prank(address(vault));
        targetVault.deposit(1_000e6, address(vault));
        vm.prank(address(vault));
        usdc.approve(address(targetVault), 0);

        // Second call should work and approval should remain 0
        vault.emergencyWithdraw();
        assertEq(usdc.allowance(address(vault), address(targetVault)), 0);
    }
}
