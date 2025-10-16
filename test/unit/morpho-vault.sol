// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseVault} from "src/core/BaseVault.sol";
import {MorphoVault} from "src/vaults/MorphoVault.sol";
import {MockMetaMorpho} from "test/mocks/MockMetaMorpho.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract MorphoVaultUnitTest is Test {
    MorphoVault public vault;
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
            "mUSDC"
        );

        vault = new MorphoVault(
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

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertGt(shares, 0, "Should receive shares");
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

        assertGt(aliceShares, bobShares, "Alice should have more shares");
        assertEq(vault.totalSupply(), aliceShares + bobShares);
        assertApproxEqAbs(vault.totalAssets(), 80_000e6, 2);
    }

    function test_Deposit_UpdatesMorphoBalance() public {
        uint256 depositAmount = 10_000e6;

        uint256 morphoBalanceBefore = morpho.balanceOf(address(vault));

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 morphoBalanceAfter = morpho.balanceOf(address(vault));

        assertGt(
            morphoBalanceAfter,
            morphoBalanceBefore,
            "Morpho shares should increase"
        );
    }

    function test_Deposit_RevertIf_ZeroAmount() public {
        vm.expectRevert(BaseVault.ZeroAmount.selector);
        vm.prank(alice);
        vault.deposit(0, alice);
    }

    function test_Deposit_RevertIf_ZeroReceiver() public {
        vm.expectRevert(BaseVault.ZeroAddress.selector);
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
                BaseVault.FirstDepositTooSmall.selector,
                1000,
                999
            )
        );

        vm.prank(alice);
        vault.deposit(999, alice);
    }

    function test_FirstDeposit_SuccessIf_MinimumMet() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_SecondDeposit_CanBeSmall() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vm.prank(bob);
        uint256 shares = vault.deposit(1, bob);

        assertGt(shares, 0, "Should allow small second deposit");
    }

    function test_Withdraw_Basic() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 withdrawAmount = 10_000e6;
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, alice, alice);

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);

        assertGt(shares, 0, "Should burn shares");
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

        vm.prank(alice);
        vault.withdraw(5_000e6, alice, alice);

        uint256 remainingShares = vault.balanceOf(alice);

        assertGt(remainingShares, 0, "Should have remaining shares");
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
                BaseVault.InsufficientShares.selector,
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
                BaseVault.InsufficientLiquidity.selector,
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

        assertGt(assets, 0);
        assertApproxEqAbs(aliceBalanceAfter - aliceBalanceBefore, assets, 2);
        assertEq(vault.balanceOf(alice), totalShares - sharesToRedeem);
    }

    function test_Redeem_AllShares() public {
        vm.prank(alice);
        uint256 totalShares = vault.deposit(100_000e6, alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(totalShares, alice, alice);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), 0, "Should have no shares left");
        assertApproxEqAbs(usdc.balanceOf(alice), INITIAL_BALANCE, 2);
    }

    function test_Mint_Basic() public {
        uint256 sharesToMint = 10_000e6;

        vm.prank(alice);
        uint256 assets = vault.mint(sharesToMint, alice);

        assertGt(assets, 0);
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

    function test_GetMorphoPosition() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        (uint256 shares, uint256 assets, uint256 price) = vault
            .getMorphoPosition();

        assertGt(shares, 0);
        assertApproxEqAbs(assets, 50_000e6, 1);
        assertApproxEqAbs(price, 1e18, 0.01e18);
    }

    function test_MaxWithdrawable() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        uint256 maxWithdraw = vault.maxWithdrawable();

        assertApproxEqAbs(maxWithdraw, 100_000e6, 1);
    }

    function test_CheckMorphoHealth_Healthy() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        (bool isHealthy, string memory reason) = vault.checkMorphoHealth();

        assertTrue(isHealthy);
        assertEq(reason, "");
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

    function test_GetAddresses() public view {
        (
            address asset,
            address morphoVault,
            address treasury_,
            address thisVault
        ) = vault.getAddresses();

        assertEq(asset, address(usdc));
        assertEq(morphoVault, address(morpho));
        assertEq(treasury_, treasury);
        assertEq(thisVault, address(vault));
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

    function _dealAndApprove(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(vault), amount);
    }
}
