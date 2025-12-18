// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterInitializationTest is ERC4626AdapterTestBase {
    /// @notice Tests that initialization.
    /// @dev Validates that initialization.
    function test_Initialization() public view {
        assertEq(address(vault.ASSET()), address(usdc));
        assertEq(address(vault.TARGET_VAULT()), address(targetVault));
        assertEq(vault.TREASURY(), treasury);
        assertEq(vault.OFFSET(), OFFSET);
        assertEq(vault.rewardFee(), REWARD_FEE);
        assertEq(vault.name(), "Lido ERC4626 Vault");
        assertEq(vault.symbol(), "lido4626");
        assertEq(vault.decimals(), assetDecimals + OFFSET, "Vault decimals should include offset");
    }

    /// @notice Tests that initial state.
    /// @dev Validates that initial state.
    function test_InitialState() public view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(treasury), 0);
    }

    /// @notice Tests that target vault approval setup.
    /// @dev Validates that target vault approval setup.
    function test_TargetVaultApprovalSetup() public view {
        assertEq(usdc.allowance(address(vault), address(targetVault)), type(uint256).max);
    }

    /// @notice Tests that offset initial value.
    /// @dev Validates that offset initial value.
    function test_Offset_InitialValue() public view {
        assertEq(vault.OFFSET(), OFFSET);
    }

    /// @notice Tests that offset protects against inflation attack.
    /// @dev Validates that offset protects against inflation attack.
    function test_Offset_ProtectsAgainstInflationAttack() public {
        vm.prank(alice);
        vault.deposit(1000, alice);

        deal(address(usdc), address(targetVault), usdc.balanceOf(address(targetVault)) + 100_000e6);

        vm.prank(bob);
        uint256 victimShares = vault.deposit(10_000e6, bob);

        assertGt(victimShares, 0);
    }

    /// @notice Fuzzes that total assets reflects target vault balance.
    /// @dev Validates that total assets reflects target vault balance.
    function testFuzz_TotalAssets_ReflectsTargetVaultBalance(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 targetShares = targetVault.balanceOf(address(vault));
        uint256 targetAssets = targetVault.convertToAssets(targetShares);

        assertEq(vaultTotalAssets, targetAssets);
    }

    /// @notice Fuzzes that max withdraw.
    /// @dev Validates that max withdraw.
    function testFuzz_MaxWithdraw(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);

        assertApproxEqAbs(maxWithdraw, amount, 1);
    }

    /// @notice Fuzzes that deposit withdraw rounding does not cause loss.
    /// @dev Validates that deposit withdraw rounding does not cause loss.
    function testFuzz_DepositWithdraw_RoundingDoesNotCauseLoss(uint96 depositAmount) public {
        uint256 amount = bound(uint256(depositAmount), 1, type(uint96).max);
        usdc.mint(alice, amount);

        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        uint256 balanceAfter = usdc.balanceOf(alice);
        assertApproxEqAbs(balanceAfter, balanceBefore, 2);
    }

    /// @notice Tests that multiple deposits withdraws maintains accounting.
    /// @dev Validates that multiple deposits withdraws maintains accounting.
    function test_MultipleDepositsWithdraws_MaintainsAccounting() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            vault.deposit(10_000e6, alice);
        }

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            vault.withdraw(10_000e6, alice, alice);
        }

        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        assertApproxEqAbs(assets, 20_000e6, 5);
    }
}
