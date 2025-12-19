// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "src/Vault.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterRecoverTest is ERC4626AdapterTestBase {
    address public receiver = makeAddr("receiver");

    function test_RecoverERC20_RevertsWhenTokenIsTargetVaultShares() public {
        uint256 depositAmount = 1_000e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.expectRevert(
            abi.encodeWithSelector(Vault.InvalidRecoveryTokenAddress.selector, address(targetVault))
        );
        vault.recoverERC20(address(targetVault), receiver);
    }

    /// @notice Tests that TARGET_VAULT shares can be recovered in recovery mode
    /// @dev Verifies that stuck target vault shares can be claimed after recovery activation
    function test_RecoverERC20_AllowsTargetVaultSharesInRecoveryMode() public {
        // Setup: Alice deposits
        uint256 depositAmount = 100_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Set liquidity cap to simulate stuck shares (partial withdrawal)
        targetVault.setLiquidityCap(depositAmount / 2);

        // Emergency withdraw (partial - leaves shares stuck)
        vault.emergencyWithdraw();

        // Activate recovery mode
        vault.activateRecovery();

        // Verify we have stuck target vault shares
        uint256 stuckShares = targetVault.balanceOf(address(vault));
        assertGt(stuckShares, 0, "Should have stuck target vault shares");

        // Recover stuck shares to receiver (should succeed in recovery mode)
        uint256 receiverBalanceBefore = targetVault.balanceOf(receiver);
        vault.recoverERC20(address(targetVault), receiver);

        // Verify shares were transferred
        assertEq(targetVault.balanceOf(address(vault)), 0, "Vault should have no target shares left");
        assertEq(
            targetVault.balanceOf(receiver),
            receiverBalanceBefore + stuckShares,
            "Receiver should have received stuck shares"
        );
    }
}
