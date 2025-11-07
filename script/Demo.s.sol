// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MorphoAdapter} from "src/adapters/Morpho.sol";
import {RewardDistributor} from "src/RewardDistributor.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockMetaMorpho} from "test/mocks/MockMetaMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DemoDeploy is Script {
    address constant ADMIN = 0x583FcCB743E846b639796bb56dBfE705Cbb65f31;

    address constant RECIPIENT_1 = 0x1111111111111111111111111111111111111111;
    address constant RECIPIENT_2 = 0x2222222222222222222222222222222222222222;
    uint256 constant RECIPIENT_1_BPS = 500; // 5%
    uint256 constant RECIPIENT_2_BPS = 9500; // 95%

    uint16 constant REWARD_FEE = 500;
    uint8 constant DECIMALS_OFFSET = 6;

    MockERC20 public token;
    MockMetaMorpho public morphoVault;
    RewardDistributor public rewardDistributor;
    MorphoAdapter public vault;

    function setUp() public {}

    function run() public {
        console.log("Starting Demo Deployment...");
        console.log("Deployer:", msg.sender);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy Mock ERC20 Token
        console.log("1. Deploying MockERC20...");
        token = new MockERC20("Demo USDC", "dUSDC", 6);
        console.log("   MockERC20 deployed at:", address(token));
        console.log("");

        // 2. Deploy Mock Morpho Vault
        console.log("2. Deploying MockMetaMorpho...");
        morphoVault = new MockMetaMorpho(IERC20(address(token)), "Mock Morpho USDC Vault", "mmUSDC", DECIMALS_OFFSET);
        console.log("   MockMetaMorpho deployed at:", address(morphoVault));
        console.log("");

        // 3. Deploy RewardDistributor
        console.log("3. Deploying RewardDistributor...");
        address[] memory recipients = new address[](2);
        recipients[0] = RECIPIENT_1;
        recipients[1] = RECIPIENT_2;

        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = RECIPIENT_1_BPS;
        basisPoints[1] = RECIPIENT_2_BPS;

        rewardDistributor = new RewardDistributor(ADMIN, recipients, basisPoints);
        console.log("   RewardDistributor deployed at:", address(rewardDistributor));
        console.log("   Recipient 1 (5%):", RECIPIENT_1);
        console.log("   Recipient 2 (95%):", RECIPIENT_2);
        console.log("");

        // 4. Deploy MorphoVault
        console.log("4. Deploying MorphoVault...");
        vault = new MorphoAdapter(
            address(token),
            address(morphoVault),
            address(rewardDistributor),
            REWARD_FEE,
            DECIMALS_OFFSET,
            "Demo Morpho Vault",
            "dmvUSDC"
        );
        console.log("   MorphoVault deployed at:", address(vault));
        console.log("");

        // 5. Mint initial tokens to admin for testing
        console.log("5. Minting initial tokens to admin...");
        uint256 initialMint = 1_000_000e6; // 1M tokens
        token.mint(ADMIN, initialMint);
        console.log("   Minted", initialMint / 1e6, "tokens to:", ADMIN);
        console.log("");

        vm.stopBroadcast();

        // Print summary
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("MockERC20 (dUSDC):", address(token));
        console.log("MockMetaMorpho:", address(morphoVault));
        console.log("RewardDistributor:", address(rewardDistributor));
        console.log("MorphoVault:", address(vault));
        console.log("");
        console.log("Admin:", ADMIN);
        console.log("Initial Balance:", initialMint / 1e6, "dUSDC");
        console.log("");
        console.log("Reward Distribution:");
        console.log("  Recipient 1 (5%):", RECIPIENT_1);
        console.log("  Recipient 2 (95%):", RECIPIENT_2);
        console.log("");
        console.log("=========================");
    }
}
