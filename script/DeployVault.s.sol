// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {ETHEREUM_MAINNET, ETHEREUM_SEPOLIA, BASE_MAINNET} from "utils/Constants.sol";

/// @title DeployVault
/// @notice Deployment script for ERC4626Adapter with env-based configuration
/// @dev All parameters are read from environment variables
contract DeployVault is Script {
    // Validation constants
    uint16 constant MAX_REWARD_FEE = 2000; // 20%
    uint8 constant MAX_OFFSET = 23;

    ERC4626Adapter public vault;

    function run() public returns (address) {
        // Validate network
        _validateNetwork();

        // Read configuration from environment
        address asset = vm.envAddress("VAULT_ASSET");
        address targetVault = vm.envAddress("VAULT_TARGET_VAULT");
        address treasury = vm.envAddress("VAULT_TREASURY");
        address admin = vm.envAddress("VAULT_ADMIN");
        uint16 rewardFee = uint16(vm.envUint("VAULT_REWARD_FEE"));
        uint8 offset = uint8(vm.envUint("VAULT_DECIMALS_OFFSET"));
        string memory name = vm.envString("VAULT_NAME");
        string memory symbol = vm.envString("VAULT_SYMBOL");

        // Validate all parameters
        _validateParams(asset, targetVault, treasury, admin, rewardFee, offset, name, symbol);

        // Log configuration
        _logConfig(asset, targetVault, treasury, admin, rewardFee, offset, name, symbol);

        // Deploy
        vm.startBroadcast();
        vault = new ERC4626Adapter(asset, targetVault, treasury, rewardFee, offset, name, symbol, admin);
        vm.stopBroadcast();

        _logSuccess(address(vault));

        return address(vault);
    }

    /// @notice Validate network is supported
    function _validateNetwork() internal view {
        uint256 chainId = block.chainid;
        require(
            chainId == ETHEREUM_MAINNET || chainId == ETHEREUM_SEPOLIA || chainId == BASE_MAINNET,
            "DeployVault: unsupported network. Allowed: Ethereum Mainnet (1), Sepolia (11155111), Base Mainnet (8453)"
        );

        string memory networkName = _getNetworkName(chainId);
        console.log("=== ERC4626Adapter Deployment ===");
        console.log("Network:", networkName);
        console.log("Chain ID:", chainId);
        console.log("Deployer:", msg.sender);
        console.log("");
    }

    /// @notice Validate all deployment parameters
    function _validateParams(
        address asset,
        address targetVault,
        address treasury,
        address admin,
        uint16 rewardFee,
        uint8 offset,
        string memory name,
        string memory symbol
    ) internal pure {
        require(asset != address(0), "DeployVault: VAULT_ASSET cannot be zero");
        require(targetVault != address(0), "DeployVault: VAULT_TARGET_VAULT cannot be zero");
        require(treasury != address(0), "DeployVault: VAULT_TREASURY cannot be zero");
        require(admin != address(0), "DeployVault: VAULT_ADMIN cannot be zero");
        require(rewardFee <= MAX_REWARD_FEE, "DeployVault: VAULT_REWARD_FEE exceeds maximum (2000 bps)");
        require(offset <= MAX_OFFSET, "DeployVault: VAULT_DECIMALS_OFFSET exceeds maximum (23)");
        require(bytes(name).length > 0, "DeployVault: VAULT_NAME cannot be empty");
        require(bytes(symbol).length > 0, "DeployVault: VAULT_SYMBOL cannot be empty");
    }

    /// @notice Log deployment configuration
    function _logConfig(
        address asset,
        address targetVault,
        address treasury,
        address admin,
        uint16 rewardFee,
        uint8 offset,
        string memory name,
        string memory symbol
    ) internal pure {
        console.log("Configuration:");
        console.log("  Asset (underlying):", asset);
        console.log("  Target Vault (ERC4626):", targetVault);
        console.log("  Treasury:", treasury);
        console.log("  Admin:", admin);
        console.log("  Reward Fee:", rewardFee, "bps");
        console.log("  Decimals Offset:", uint256(offset));
        console.log("  Vault Name:", name);
        console.log("  Vault Symbol:", symbol);
        console.log("");
        console.log("Deploying...");
        console.log("");
    }

    /// @notice Log deployment success
    function _logSuccess(address vaultAddress) internal pure {
        console.log("=== Deployment Complete ===");
        console.log("ERC4626Adapter:", vaultAddress);
        console.log("");
        console.log("Admin has the following roles:");
        console.log("  - DEFAULT_ADMIN_ROLE: Can grant/revoke all roles");
        console.log("  - PAUSER_ROLE: Can pause/unpause the vault");
        console.log("  - FEE_MANAGER_ROLE: Can update reward fee and treasury");
        console.log("  - EMERGENCY_ROLE: Can trigger emergency withdrawal");
        console.log("");
        console.log("Next steps:");
        console.log("  1. Verify the contract on block explorer");
        console.log("  2. Grant roles to appropriate addresses if needed");
        console.log("  3. Test deposit/withdraw functionality");
        console.log("");
    }

    /// @notice Get network name from chain ID
    function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "Ethereum Mainnet";
        if (chainId == ETHEREUM_SEPOLIA) return "Ethereum Sepolia";
        if (chainId == BASE_MAINNET) return "Base Mainnet";
        return "Unknown";
    }
}
