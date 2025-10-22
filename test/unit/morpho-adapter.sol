// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Vault} from "src/Vault.sol";
import {Morpho} from "src/adapters/Morpho.sol";
import {MockMetaMorpho} from "test/mocks/MockMetaMorpho.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract MorphoAdapterUnitTest is Test {
    Morpho public vault;
    MockMetaMorpho public morpho;
    MockERC20 public usdc;

    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 1_000_000e6;
    uint16 constant REWARD_FEE = 500;
    uint8 constant OFFSET = 6;

    event Deposited(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);

        morpho = new MockMetaMorpho(
            IERC20(address(usdc)),
            "Mock Morpho USDC",
            "mUSDC",
            OFFSET
        );

        vault = new Morpho(
            address(usdc),
            address(morpho),
            treasury,
            REWARD_FEE,
            OFFSET,
            "Morpho USDC Vault",
            "mvUSDC"
        );

        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    function test_Initialization() public view {
        assertEq(address(vault.ASSET()), address(usdc));
        assertEq(address(vault.MORPHO_VAULT()), address(morpho));
        assertEq(vault.TREASURY(), treasury);
        assertEq(vault.OFFSET(), OFFSET);
        assertEq(vault.rewardFee(), REWARD_FEE);
        assertEq(vault.name(), "Morpho USDC Vault");
        assertEq(vault.symbol(), "mvUSDC");
        assertEq(vault.decimals(), 6);
    }

    function test_InitialState() public view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(treasury), 0);
    }

    function test_MorphoApprovalSetup() public view {
        assertEq(
            usdc.allowance(address(vault), address(morpho)),
            type(uint256).max,
            "Vault should have infinite approval for Morpho"
        );
    }

    function test_Deposit_Basic() public {
        uint256 depositAmount = 10_000e6;
        uint256 expectedShares = depositAmount * 10 ** vault.OFFSET(); // First deposit with offset

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, expectedShares, "Should receive exact shares");
        assertEq(vault.balanceOf(alice), shares, "Alice should have shares");
        assertEq(vault.totalSupply(), shares, "Total supply should match");
        assertApproxEqAbs(
            vault.totalAssets(),
            depositAmount,
            1,
            "Total assets should match deposit"
        );
    }

    function test_Deposit_EmitsEvent() public {
        uint256 depositAmount = 10_000e6;
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        vm.expectEmit(true, true, false, true);
        emit Deposited(alice, alice, depositAmount, expectedShares);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);
    }

    function test_Deposit_MultipleUsers() public {
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(50_000e6, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(30_000e6, bob);

        // Alice deposited more, so should have more shares
        uint256 expectedAliceShares = 50_000e6 * 10 ** vault.OFFSET();
        uint256 expectedBobShares = 30_000e6 * 10 ** vault.OFFSET();

        assertEq(
            aliceShares,
            expectedAliceShares,
            "Alice should have exact shares"
        );
        assertEq(bobShares, expectedBobShares, "Bob should have exact shares");
        assertEq(vault.totalSupply(), aliceShares + bobShares);
        assertApproxEqAbs(vault.totalAssets(), 80_000e6, 2);
    }

    function test_Deposit_UpdatesMorphoBalance() public {
        uint256 depositAmount = 10_000e6;

        uint256 morphoBalanceBefore = morpho.balanceOf(address(vault));
        assertEq(
            morphoBalanceBefore,
            0,
            "Should start with zero Morpho shares"
        );

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 morphoBalanceAfter = morpho.balanceOf(address(vault));
        // MockMetaMorpho теперь использует offset, первый депозит: depositAmount * 10^OFFSET
        uint256 expectedMorphoShares = depositAmount * 10 ** OFFSET;

        assertEq(
            morphoBalanceAfter,
            expectedMorphoShares,
            "Morpho shares should include offset multiplication"
        );
    }

    function test_Deposit_RevertIf_ZeroAmount() public {
        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.deposit(0, alice);
    }

    function test_Deposit_RevertIf_ZeroReceiver() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(alice);
        vault.deposit(10_000e6, address(0));
    }

    function test_Deposit_RevertIf_Paused() public {
        vault.pause();

        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
    }

    function test_FirstDeposit_RevertIf_TooSmall() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Vault.FirstDepositTooSmall.selector,
                1000,
                999
            )
        );

        vm.prank(alice);
        vault.deposit(999, alice);
    }

    function test_FirstDeposit_SuccessIf_MinimumMet() public {
        uint256 depositAmount = 1000;
        uint256 expectedShares = depositAmount * 10 ** vault.OFFSET();

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, expectedShares, "Should receive exact shares");
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_SecondDeposit_CanBeSmall() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 smallDeposit = 1;
        uint256 expectedShares = vault.previewDeposit(smallDeposit);

        vm.prank(bob);
        uint256 shares = vault.deposit(smallDeposit, bob);

        assertEq(
            shares,
            expectedShares,
            "Should receive calculated shares for small deposit"
        );
    }

    function test_Withdraw_Basic() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);

        assertEq(shares, expectedShares, "Should burn exact calculated shares");
        assertApproxEqAbs(
            aliceBalanceAfter - aliceBalanceBefore,
            withdrawAmount,
            2,
            "Should receive withdrawn amount"
        );
    }

    function test_Withdraw_DoesNotBurnAllShares() public {
        vm.prank(alice);
        uint256 initialShares = vault.deposit(50_000e6, alice);

        uint256 withdrawAmount = 5_000e6;
        uint256 sharesBurned = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        uint256 remainingShares = vault.balanceOf(alice);
        uint256 expectedRemainingShares = initialShares - sharesBurned;

        assertEq(
            remainingShares,
            expectedRemainingShares,
            "Should have exact remaining shares"
        );
        assertApproxEqRel(
            remainingShares,
            (initialShares * 9) / 10,
            2,
            "Should burn ~10% of shares, not all"
        );
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;

        vm.expectEmit(true, true, true, false);
        emit Withdrawn(alice, alice, alice, withdrawAmount, 0);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
    }

    function test_Withdraw_RevertIf_InsufficientShares() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 sharesRequested = vault.convertToShares(20_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                Vault.InsufficientShares.selector,
                sharesRequested,
                shares
            )
        );
        vm.prank(alice);
        vault.withdraw(20_000e6, alice, alice);
    }

    function test_Withdraw_RevertIf_InsufficientLiquidity() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        morpho.setLiquidityCap(5_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                Vault.InsufficientLiquidity.selector,
                10_000e6,
                5_000e6
            )
        );

        vm.prank(alice);
        vault.withdraw(10_000e6, alice, alice);
    }

    function test_Redeem_Basic() public {
        vm.prank(alice);
        uint256 totalShares = vault.deposit(100_000e6, alice);

        uint256 sharesToRedeem = totalShares / 10;
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(sharesToRedeem, alice, alice);

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);

        assertEq(
            assets,
            expectedAssets,
            "Should receive exact calculated assets"
        );
        assertApproxEqAbs(aliceBalanceAfter - aliceBalanceBefore, assets, 2);
        assertEq(vault.balanceOf(alice), totalShares - sharesToRedeem);
    }

    function test_Redeem_AllShares() public {
        vm.prank(alice);
        uint256 totalShares = vault.deposit(100_000e6, alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(totalShares, alice, alice);
        uint256 expectedAssets = vault.previewRedeem(totalShares);

        assertEq(
            assets,
            expectedAssets,
            "Should receive exact calculated assets"
        );
        assertEq(vault.balanceOf(alice), 0, "Should have no shares left");
        assertApproxEqAbs(usdc.balanceOf(alice), INITIAL_BALANCE, 2);
    }

    function test_Mint_Basic() public {
        uint256 sharesToMint = 10_000e6;
        uint256 expectedAssets = vault.previewMint(sharesToMint);

        vm.prank(alice);
        uint256 assets = vault.mint(sharesToMint, alice);

        assertEq(
            assets,
            expectedAssets,
            "Should require exact calculated assets"
        );
        assertEq(vault.balanceOf(alice), sharesToMint);
        assertApproxEqAbs(vault.totalAssets(), assets, 1);
    }

    function test_PreviewDeposit_Accurate() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 previewedShares = vault.previewDeposit(10_000e6);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(10_000e6, bob);

        assertEq(previewedShares, actualShares);
    }

    function test_PreviewWithdraw_Accurate() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 previewedShares = vault.previewWithdraw(10_000e6);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(10_000e6, alice, alice);

        assertEq(previewedShares, actualShares);
    }

    function test_Offset_InitialValue() public view {
        assertEq(vault.OFFSET(), OFFSET);
    }

    function test_Offset_ProtectsAgainstInflationAttack() public {
        vm.prank(alice);
        vault.deposit(1000, alice);

        deal(
            address(usdc),
            address(morpho),
            usdc.balanceOf(address(morpho)) + 100_000e6
        );

        vm.prank(bob);
        uint256 victimShares = vault.deposit(10_000e6, bob);

        assertGt(
            victimShares,
            0,
            "Offset should protect against inflation attack"
        );
    }

    function test_TotalAssets_ReflectsMorphoBalance() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 morphoShares = morpho.balanceOf(address(vault));
        uint256 morphoAssets = morpho.convertToAssets(morphoShares);

        assertEq(vaultTotalAssets, morphoAssets);
    }

    function test_MaxWithdraw() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);

        assertApproxEqAbs(maxWithdraw, 100_000e6, 1);
    }

    function test_GetVaultConfig() public view {
        (
            address treasury_,
            uint256 rewardFee_,
            uint256 minFirstDeposit_,
            uint8 offset_,
            bool isPaused_
        ) = vault.getVaultConfig();

        assertEq(treasury_, treasury);
        assertEq(rewardFee_, REWARD_FEE);
        assertEq(minFirstDeposit_, 1000);
        assertEq(offset_, OFFSET);
        assertEq(isPaused_, false);
    }

    function test_DepositWithdraw_RoundingDoesNotCauseLoss() public {
        vm.prank(alice);
        vault.deposit(1000, alice);

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertApproxEqAbs(usdc.balanceOf(alice), INITIAL_BALANCE, 2);
    }

    function test_MultipleDepositsWithdraws_MaintainsAccounting() public {
        for (uint i = 0; i < 5; i++) {
            vm.prank(alice);
            vault.deposit(10_000e6, alice);
        }

        for (uint i = 0; i < 3; i++) {
            vm.prank(alice);
            vault.withdraw(10_000e6, alice, alice);
        }

        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        assertApproxEqAbs(assets, 20_000e6, 5);
    }

    function test_Withdraw_DelegatedWithApproval() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 requiredShares = vault.previewWithdraw(withdrawAmount);

        // Alice approves Bob to spend her shares
        vm.prank(alice);
        vault.approve(bob, requiredShares);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Bob withdraws Alice's shares, assets go to Bob
        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, bob, alice);

        uint256 bobUsdcAfter = usdc.balanceOf(bob);
        uint256 aliceSharesAfter = vault.balanceOf(alice);

        // Verify results
        assertEq(sharesBurned, requiredShares, "Should burn expected shares");
        assertEq(
            aliceSharesAfter,
            aliceSharesBefore - sharesBurned,
            "Alice shares should decrease"
        );
        assertApproxEqAbs(
            bobUsdcAfter - bobUsdcBefore,
            withdrawAmount,
            2,
            "Bob should receive assets"
        );
        assertEq(
            vault.allowance(alice, bob),
            0,
            "Allowance should be consumed"
        );
    }

    function test_Withdraw_DelegatedRevertIf_InsufficientAllowance() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 requiredShares = vault.previewWithdraw(withdrawAmount);

        // Alice approves Bob for less than required
        vm.prank(alice);
        vault.approve(bob, requiredShares - 1);

        // Bob tries to withdraw more than approved
        vm.expectRevert();
        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, alice);
    }

    function test_Withdraw_DelegatedRevertIf_NoApproval() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Bob tries to withdraw without approval
        vm.expectRevert();
        vm.prank(bob);
        vault.withdraw(10_000e6, bob, alice);
    }

    function test_Withdraw_SelfDoesNotRequireApproval() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        // Alice withdraws her own shares (no approval needed)
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceUsdcAfter = usdc.balanceOf(alice);

        assertEq(
            sharesBurned,
            expectedShares,
            "Should burn exact calculated shares"
        );
        assertApproxEqAbs(
            aliceUsdcAfter - aliceUsdcBefore,
            withdrawAmount,
            2,
            "Alice should receive assets"
        );
    }

    function test_Withdraw_DelegatedWithUnlimitedApproval() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        // Alice gives unlimited approval to Bob
        vm.prank(alice);
        vault.approve(bob, type(uint256).max);

        uint256 withdrawAmount = 10_000e6;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        // Bob withdraws, should work with unlimited approval
        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, bob, alice);

        uint256 bobUsdcAfter = usdc.balanceOf(bob);

        assertEq(
            sharesBurned,
            expectedShares,
            "Should burn exact calculated shares"
        );
        assertApproxEqAbs(
            bobUsdcAfter - bobUsdcBefore,
            withdrawAmount,
            2,
            "Bob should receive assets"
        );
        assertEq(
            vault.allowance(alice, bob),
            type(uint256).max,
            "Unlimited allowance should remain"
        );
    }

    function _dealAndApprove(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(vault), amount);
    }

    /* ========== PERMIT TESTS ========== */

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
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vault.permit(owner, bob, amount, deadline, v, r, s);

        assertEq(
            vault.allowance(owner, bob),
            amount,
            "Allowance should be set"
        );
        assertEq(vault.nonces(owner), nonce + 1, "Nonce should increment");
    }

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
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                bob,
                requiredShares,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vault.permit(owner, bob, requiredShares, deadline, v, r, s);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, owner);

        uint256 bobUsdcAfter = usdc.balanceOf(bob);

        assertApproxEqAbs(
            bobUsdcAfter - bobUsdcBefore,
            withdrawAmount,
            2,
            "Bob should receive assets after permit"
        );
    }

    function test_Permit_RevertIf_Expired() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp - 1; // Already expired

        uint256 nonce = vault.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert();
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }

    function test_Permit_RevertIf_InvalidSignature() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 nonce = vault.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash)
        );

        uint256 wrongPrivateKey = 0xBADBAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        vm.expectRevert();
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
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vault.permit(owner, bob, amount, deadline, v, r, s);
        assertEq(vault.allowance(owner, bob), amount);

        vm.expectRevert();
        vault.permit(owner, bob, amount, deadline, v, r, s);
    }

    function test_Permit_Nonces_Increment() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);

        uint256 initialNonce = vault.nonces(owner);
        assertEq(initialNonce, 0, "Initial nonce should be 0");

        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 1 hours;

        _permitHelper(ownerPrivateKey, owner, bob, amount, 0, deadline);
        assertEq(
            vault.nonces(owner),
            1,
            "Nonce should be 1 after first permit"
        );

        _permitHelper(ownerPrivateKey, owner, alice, amount, 1, deadline);
        assertEq(
            vault.nonces(owner),
            2,
            "Nonce should be 2 after second permit"
        );
    }

    function _permitHelper(
        uint256 ownerPrivateKey,
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                spender,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        vault.permit(owner, spender, amount, deadline, v, r, s);
    }

    function test_Permit_DomainSeparator() public view {
        bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();

        // Calculate expected domain separator according to EIP-712
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(vault.name())),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );

        assertEq(domainSeparator, expectedDomainSeparator);
    }
}
