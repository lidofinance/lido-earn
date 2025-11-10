// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";

contract VaultInitializationTest is VaultTestBase {
    function test_Initialization() public view {
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.TREASURY(), treasury);
        assertEq(vault.OFFSET(), OFFSET);
        assertEq(vault.rewardFee(), REWARD_FEE);
        assertEq(vault.name(), "Mock Vault");
        assertEq(vault.symbol(), "mvUSDC");
        assertEq(vault.decimals(), 6);
    }

    function test_InitialState() public view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(treasury), 0);
    }

    function test_InitialRolesAssigned() public view {
        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        bytes32 pauserRole = vault.PAUSER_ROLE();
        bytes32 feeManagerRole = vault.FEE_MANAGER_ROLE();
        bytes32 emergencyRole = vault.EMERGENCY_ROLE();

        assertTrue(vault.hasRole(adminRole, address(this)));
        assertTrue(vault.hasRole(pauserRole, address(this)));
        assertTrue(vault.hasRole(feeManagerRole, address(this)));
        assertTrue(vault.hasRole(emergencyRole, address(this)));
    }

    function test_InitialPausedState() public view {
        assertFalse(vault.paused());
    }

    function test_InitialRewardFeeAndLastAssets() public view {
        assertEq(vault.rewardFee(), REWARD_FEE);
        assertEq(vault.lastTotalAssets(), 0);
    }

    function test_MinFirstDepositConstant() public view {
        assertEq(vault.MIN_FIRST_DEPOSIT(), 1_000);
    }
}
