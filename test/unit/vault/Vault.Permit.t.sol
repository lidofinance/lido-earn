// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract VaultPermitTest is VaultTestBase {
    function test_Permit_Basic() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        asset.mint(owner, 100_000e6);
        vm.prank(owner);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        vault.deposit(100_000e6, owner);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);

        _permitHelper(ownerPrivateKey, owner, bob, amount, nonce, deadline);

        assertEq(vault.allowance(owner, bob), amount);
        assertEq(vault.nonces(owner), nonce + 1);
    }

    function test_Permit_WithdrawAfterPermit() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        asset.mint(owner, 100_000e6);
        vm.prank(owner);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        vault.deposit(100_000e6, owner);

        uint256 withdrawAmount = 10_000e6;
        uint256 requiredShares = vault.previewWithdraw(withdrawAmount);
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);

        _permitHelper(ownerPrivateKey, owner, bob, requiredShares, nonce, deadline);

        uint256 bobAssetBefore = asset.balanceOf(bob);

        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, owner);

        uint256 bobAssetAfter = asset.balanceOf(bob);

        assertApproxEqAbs(bobAssetAfter - bobAssetBefore, withdrawAmount, 2);
    }

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

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }

    function test_Permit_RevertIf_InvalidSignature() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);

        uint256 wrongPrivateKey = 0xBADBAD;
        address wrongSigner = vm.addr(wrongPrivateKey);

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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, wrongSigner, owner));
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }

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

        address recoveredSigner = ecrecover(digest, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, recoveredSigner, owner));
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }

    function test_Permit_Nonces_Increment() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 initialNonce = vault.nonces(owner);
        assertEq(initialNonce, 0);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        _permitHelper(ownerPrivateKey, owner, bob, amount, 0, deadline);

        assertEq(vault.nonces(owner), 1);

        _permitHelper(ownerPrivateKey, owner, alice, amount, 1, deadline);

        assertEq(vault.nonces(owner), 2);
    }

    function test_Permit_DomainSeparator() public view {
        bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();

        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(vault.name())),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );

        assertEq(domainSeparator, expectedDomainSeparator);
    }
}
