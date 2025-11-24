// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ERC4626AdapterTestBase.sol";

contract ERC4626AdapterPermitTest is ERC4626AdapterTestBase {
    /// @notice Exercises standard permit happy path.
    /// @dev Verifies balances and state remain correct in the success scenario.
    function test_Permit_Basic() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        usdc.mint(owner, 100_000e6);
        vm.prank(owner);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        vault.deposit(100_000e6, owner);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vault.permit(owner, bob, amount, deadline, v, r, s);

        assertEq(vault.allowance(owner, bob), amount);
        assertEq(vault.nonces(owner), nonce + 1);
    }

    /// @notice Tests that permit withdraw after permit.
    /// @dev Validates that permit withdraw after permit.
    function test_Permit_WithdrawAfterPermit() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        usdc.mint(owner, 100_000e6);
        vm.prank(owner);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        vault.deposit(100_000e6, owner);

        uint256 withdrawAmount = 10_000e6;
        uint256 requiredShares = vault.previewWithdraw(withdrawAmount);
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                bob,
                requiredShares,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vault.permit(owner, bob, requiredShares, deadline, v, r, s);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, owner);

        uint256 bobUsdcAfter = usdc.balanceOf(bob);

        assertApproxEqAbs(bobUsdcAfter - bobUsdcBefore, withdrawAmount, 2);
    }

    /// @notice Ensures permit reverts when expired.
    /// @dev Verifies the revert protects against expired.
    function test_Permit_RevertIf_Expired() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp - 1;

        uint256 nonce = vault.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert();
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }

    /// @notice Ensures permit reverts when invalid signature.
    /// @dev Verifies the revert protects against invalid signature.
    function test_Permit_RevertIf_InvalidSignature() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));

        uint256 wrongPrivateKey = 0xBADBAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        vm.expectRevert();
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }

    /// @notice Ensures permit reverts when replay attack.
    /// @dev Verifies the revert protects against replay attack.
    function test_Permit_RevertIf_ReplayAttack() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vault.permit(owner, bob, amount, deadline, v, r, s);
        assertEq(vault.allowance(owner, bob), amount);

        nonce = vault.nonces(owner);
        structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));

        vm.expectRevert();
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }
}
