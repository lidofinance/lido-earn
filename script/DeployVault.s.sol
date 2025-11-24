// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {USDC, STEAKHOUSE_USDC_VAULT} from "utils/Constants.sol";

contract DeployVault is Script {
    address constant ASSET = USDC;
    address constant TARGET_VAULT = STEAKHOUSE_USDC_VAULT;
    address constant TREASURY = address(0);
    address constant ADMIN = address(0);

    uint16 constant REWARD_FEE = 500;
    uint8 constant OFFSET = 10;

    string constant NAME = "Lido Earn USDC Vault";
    string constant SYMBOL = "leUSDC";

    ERC4626Adapter public vault;

    function run() public returns (address) {
        console.log("=== ERC4626Adapter Deployment ===");
        console.log("Deployer:", msg.sender);
        console.log("");

        console.log("Configuration:");
        console.log("  Asset (underlying):", ASSET);
        console.log("  Target Vault (ERC4626):", TARGET_VAULT);
        console.log("  Treasury:", TREASURY);
        console.log("  Admin:", ADMIN);
        console.log("  Reward Fee:", REWARD_FEE, "bps");
        console.log("  Decimals Offset:", uint256(OFFSET));
        console.log("  Vault Name:", NAME);
        console.log("  Vault Symbol:", SYMBOL);
        console.log("");

        vm.startBroadcast();

        vault = new ERC4626Adapter(ASSET, TARGET_VAULT, TREASURY, REWARD_FEE, OFFSET, NAME, SYMBOL, ADMIN);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("ERC4626Adapter:", address(vault));
        console.log("");
        console.log("Admin has the following roles:");
        console.log("  - DEFAULT_ADMIN_ROLE: Can grant/revoke all roles");
        console.log("  - PAUSER_ROLE: Can pause/unpause the vault");
        console.log("  - FEE_MANAGER_ROLE: Can update reward fee and treasury");
        console.log("  - EMERGENCY_ROLE: Can trigger emergency withdrawal");
        console.log("");
        console.log("Next steps:");
        console.log("  1. Verify the contract on Etherscan");
        console.log("  2. Grant roles to appropriate addresses if needed");
        console.log("  3. Test deposit/withdraw functionality");
        console.log("");

        return address(vault);
    }
}
