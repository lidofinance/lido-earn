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
}
