// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";

contract VaultRedeemZeroTest is VaultTestBase {
    address public user = makeAddr("user");

    function setUp() public override {
        super.setUp();
        asset.mint(user, INITIAL_BALANCE);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);
    }

    /// @notice Redeem exactly 10^OFFSET shares (worth 1 wei) should succeed
    function test_Redeem_Success_WhenAssetsEqualOneWei() public {
        // Setup
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // User gets exactly 10^OFFSET shares (worth 1 wei)
        uint256 minShares = 10 ** vault.OFFSET();

        vm.prank(alice);
        vault.transfer(user, minShares);

        // Verify worth 1 wei
        uint256 assetsWorth = vault.convertToAssets(minShares);
        assertEq(assetsWorth, 1, "Min shares should be worth 1 wei");

        // Redeem should succeed
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(minShares, user, user);

        assertEq(assetsReceived, 1, "Should receive 1 wei");
        assertEq(vault.balanceOf(user), 0, "User should have 0 shares left");
    }

    /// @notice Fuzz test: any shares < 10^OFFSET should revert
    function testFuzz_Redeem_Revert_DustShares(uint256 dustAmount) public {
        uint256 offset = 10 ** vault.OFFSET();
        dustAmount = bound(dustAmount, 1, offset - 1);

        // Setup
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vm.prank(alice);
        vault.transfer(user, dustAmount);

        // Should revert for any dust amount
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidAssetsAmount.selector, 0, dustAmount));
        vault.redeem(dustAmount, user, user);
    }
}
