// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultAccessControlTest is VaultTestBase {
    function test_AdminRole_DefaultAdmin() public view {
        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        assertTrue(vault.hasRole(adminRole, address(this)));
    }

    function test_PauserRole_GrantAndRevoke() public {
        address pauser = makeAddr("pauser");
        bytes32 pauserRole = vault.PAUSER_ROLE();

        assertFalse(vault.hasRole(pauserRole, pauser));

        vault.grantRole(pauserRole, pauser);
        assertTrue(vault.hasRole(pauserRole, pauser));

        vault.revokeRole(pauserRole, pauser);
        assertFalse(vault.hasRole(pauserRole, pauser));
    }

    function test_FeeManagerRole_GrantAndRevoke() public {
        address feeManager = makeAddr("feeManager");
        bytes32 feeManagerRole = vault.FEE_MANAGER_ROLE();

        assertFalse(vault.hasRole(feeManagerRole, feeManager));

        vault.grantRole(feeManagerRole, feeManager);
        assertTrue(vault.hasRole(feeManagerRole, feeManager));

        vault.revokeRole(feeManagerRole, feeManager);
        assertFalse(vault.hasRole(feeManagerRole, feeManager));
    }

    function test_EmergencyRole_GrantAndRevoke() public {
        address emergency = makeAddr("emergency");
        bytes32 emergencyRole = vault.EMERGENCY_ROLE();

        assertFalse(vault.hasRole(emergencyRole, emergency));

        vault.grantRole(emergencyRole, emergency);
        assertTrue(vault.hasRole(emergencyRole, emergency));

        vault.revokeRole(emergencyRole, emergency);
        assertFalse(vault.hasRole(emergencyRole, emergency));
    }

    function test_AccessControl_RevertIf_NonAdminGrantsRole() public {
        address pauser = makeAddr("pauser");
        bytes32 pauserRole = vault.PAUSER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.getRoleAdmin(pauserRole)
            )
        );
        vm.prank(alice);
        vault.grantRole(pauserRole, pauser);
    }

    function test_AccessControl_RevertIf_NonAdminRevokesRole() public {
        address pauser = makeAddr("pauser");
        bytes32 pauserRole = vault.PAUSER_ROLE();

        vault.grantRole(pauserRole, pauser);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.getRoleAdmin(pauserRole)
            )
        );
        vm.prank(alice);
        vault.revokeRole(pauserRole, pauser);
    }

    function test_AccessControl_MultipleRoleHolders() public {
        address pauser1 = makeAddr("pauser1");
        address pauser2 = makeAddr("pauser2");
        bytes32 pauserRole = vault.PAUSER_ROLE();

        vault.grantRole(pauserRole, pauser1);
        vault.grantRole(pauserRole, pauser2);

        assertTrue(vault.hasRole(pauserRole, pauser1));
        assertTrue(vault.hasRole(pauserRole, pauser2));

        vm.prank(pauser1);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(pauser2);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_AccessControl_RoleAdminOfRole() public view {
        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        bytes32 pauserRole = vault.PAUSER_ROLE();

        assertEq(vault.getRoleAdmin(pauserRole), adminRole);
    }

    function test_AccessControl_RenounceRole() public {
        address pauser = makeAddr("pauser");
        bytes32 pauserRole = vault.PAUSER_ROLE();

        vault.grantRole(pauserRole, pauser);
        assertTrue(vault.hasRole(pauserRole, pauser));

        vm.prank(pauser);
        vault.renounceRole(pauserRole, pauser);

        assertFalse(vault.hasRole(pauserRole, pauser));
    }

    function test_AccessControl_DeployerGetsAllRoles() public view {
        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        bytes32 pauserRole = vault.PAUSER_ROLE();
        bytes32 feeManagerRole = vault.FEE_MANAGER_ROLE();
        bytes32 emergencyRole = vault.EMERGENCY_ROLE();

        assertTrue(vault.hasRole(adminRole, address(this)));
        assertTrue(vault.hasRole(pauserRole, address(this)));
        assertTrue(vault.hasRole(feeManagerRole, address(this)));
        assertTrue(vault.hasRole(emergencyRole, address(this)));
    }
}
