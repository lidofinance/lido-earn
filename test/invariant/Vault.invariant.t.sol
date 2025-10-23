// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title VaultInvariantTest
 * @notice General invariant tests for vault core functionality
 *
 * TESTED INVARIANTS:
 *
 * 1. Conversion round-trip accuracy
 *    - invariant_ConversionRoundTrip()
 *    - Tests assets -> shares -> assets conversion
 *    - Must preserve value within 0.01% (0.0001e18)
 *
 * 2. Total supply equals sum of balances
 *    - invariant_TotalSupplyEqualsSumOfBalances()
 *    - Ensures no shares are created or lost outside of mint/burn
 *
 * 3. Vault has assets when has shares
 *    - invariant_VaultHasAssetsWhenHasShares()
 *    - If totalSupply > 0, then totalAssets > 0 (no orphan shares)
 */

import "forge-std/Test.sol";
import {MorphoAdapter} from "src/adapters/Morpho.sol";
import {MockMetaMorpho} from "test/mocks/MockMetaMorpho.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {RewardDistributor} from "src/RewardDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultHandler} from "./handlers/VaultHandler.sol";

contract VaultInvariantTest is Test {
    MorphoAdapter public vault;
    MockMetaMorpho public morpho;
    MockERC20 public usdc;
    RewardDistributor public rewardDistributor;
    VaultHandler public handler;

    address public manager = makeAddr("manager");
    address public recipient1 = makeAddr("recipient1");
    address public recipient2 = makeAddr("recipient2");
    address public initialDepositor;

    uint16 constant REWARD_FEE = 500;
    uint8 constant OFFSET = 6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);

        morpho = new MockMetaMorpho(
            IERC20(address(usdc)),
            "Mock Morpho USDC",
            "mUSDC",
            OFFSET
        );

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = 500;
        basisPoints[1] = 9500;

        rewardDistributor = new RewardDistributor(
            manager,
            recipients,
            basisPoints
        );

        vault = new MorphoAdapter(
            address(usdc),
            address(morpho),
            address(rewardDistributor),
            REWARD_FEE,
            OFFSET,
            "Morpho USDC Vault",
            "mvUSDC"
        );

        address[] memory actors = new address[](3);
        actors[0] = makeAddr("actor1");
        actors[1] = makeAddr("actor2");
        actors[2] = makeAddr("actor3");

        handler = new VaultHandler(vault, usdc, morpho, actors);

        targetContract(address(handler));

        excludeContract(address(vault));
        excludeContract(address(morpho));
        excludeContract(address(usdc));
        excludeContract(address(rewardDistributor));

        initialDepositor = makeAddr("initialDepositor");
        usdc.mint(initialDepositor, 10_000e6);
        vm.startPrank(initialDepositor);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6, initialDepositor);
        vm.stopPrank();
    }

    function invariant_ConversionRoundTrip() public view {
        if (vault.totalSupply() == 0) return;

        uint256 testAmount = 1000e6;
        uint256 shares = vault.convertToShares(testAmount);

        if (shares == 0) return;

        uint256 assetsBack = vault.convertToAssets(shares);

        assertApproxEqRel(
            assetsBack,
            testAmount,
            0.0001e18,
            "INVARIANT VIOLATION: Round-trip conversion lost >0.01%"
        );
    }

    function invariant_TotalSupplyEqualsSumOfBalances() public view {
        uint256 totalSupply = vault.totalSupply();

        uint256 sumOfBalances = vault.balanceOf(address(rewardDistributor));
        sumOfBalances += vault.balanceOf(initialDepositor);
        sumOfBalances += vault.balanceOf(handler.actors(0));
        sumOfBalances += vault.balanceOf(handler.actors(1));
        sumOfBalances += vault.balanceOf(handler.actors(2));

        assertEq(
            totalSupply,
            sumOfBalances,
            "INVARIANT VIOLATION: Total supply != sum of balances"
        );
    }

    function invariant_VaultHasAssetsWhenHasShares() public view {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        if (totalSupply > 0) {
            assertGt(
                totalAssets,
                0,
                "INVARIANT VIOLATION: Vault has shares but zero assets"
            );
        }
    }

    function invariant_callSummary() public view {
        console.log("\n=== Vault Invariant Test Summary ===");
        console.log("Deposits:", handler.depositsCount());
        console.log("Withdraws:", handler.withdrawsCount());
        console.log("Mints:", handler.mintsCount());
        console.log("Redeems:", handler.redeemsCount());
        console.log("Total supply:", vault.totalSupply());
        console.log("Total assets:", vault.totalAssets());
        console.log("====================================\n");
    }
}
