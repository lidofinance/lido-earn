// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RewardDistributor} from "src/RewardDistributor.sol";
import {ETHEREUM_MAINNET, ETHEREUM_SEPOLIA, BASE_MAINNET} from "utils/Constants.sol";

/// @title DeployRewardDistributor
/// @notice Deployment script for RewardDistributor with env-based configuration
/// @dev All parameters are read from environment variables
contract DeployRewardDistributor is Script {
    // Validation constants
    uint256 constant TOTAL_BPS = 10000; // 100%

    RewardDistributor public distributor;

    function run() public returns (address) {
        // Validate network
        _validateNetwork();

        // Read configuration from environment
        address manager = vm.envAddress("DISTRIBUTOR_MANAGER");
        uint256 recipientCount = vm.envUint("DISTRIBUTOR_RECIPIENT_COUNT");

        require(recipientCount > 0, "DeployRewardDistributor: DISTRIBUTOR_RECIPIENT_COUNT must be > 0");
        require(recipientCount <= 50, "DeployRewardDistributor: too many recipients (max 50)");

        address[] memory recipients = new address[](recipientCount);
        uint256[] memory basisPoints = new uint256[](recipientCount);

        // Read each recipient's configuration
        for (uint256 i = 0; i < recipientCount; i++) {
            string memory addrKey = string(abi.encodePacked("DISTRIBUTOR_RECIPIENT_", _toString(i), "_ADDRESS"));
            string memory bpsKey = string(abi.encodePacked("DISTRIBUTOR_RECIPIENT_", _toString(i), "_BPS"));

            recipients[i] = vm.envAddress(addrKey);
            basisPoints[i] = vm.envUint(bpsKey);
        }

        // Validate all parameters
        _validateParams(manager, recipients, basisPoints);

        // Log configuration
        _logConfig(manager, recipients, basisPoints);

        // Deploy
        vm.startBroadcast();
        distributor = new RewardDistributor(manager, recipients, basisPoints);
        vm.stopBroadcast();

        _logSuccess(address(distributor), recipientCount);

        return address(distributor);
    }

    /// @notice Validate network is supported
    function _validateNetwork() internal view {
        uint256 chainId = block.chainid;
        require(
            chainId == ETHEREUM_MAINNET || chainId == ETHEREUM_SEPOLIA || chainId == BASE_MAINNET,
            "DeployRewardDistributor: unsupported network. Allowed: Ethereum Mainnet (1), Sepolia (11155111), Base Mainnet (8453)"
        );

        string memory networkName = _getNetworkName(chainId);
        console.log("=== RewardDistributor Deployment ===");
        console.log("Network:", networkName);
        console.log("Chain ID:", chainId);
        console.log("Deployer:", msg.sender);
        console.log("");
    }

    /// @notice Validate all deployment parameters
    function _validateParams(address manager, address[] memory recipients, uint256[] memory basisPoints)
        internal
        pure
    {
        require(manager != address(0), "DeployRewardDistributor: DISTRIBUTOR_MANAGER cannot be zero");
        require(recipients.length == basisPoints.length, "DeployRewardDistributor: recipients and basisPoints length mismatch");
        require(recipients.length > 0, "DeployRewardDistributor: must have at least one recipient");

        uint256 totalBps = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), string(abi.encodePacked("DeployRewardDistributor: recipient ", _toString(i), " cannot be zero")));
            require(basisPoints[i] > 0, string(abi.encodePacked("DeployRewardDistributor: recipient ", _toString(i), " bps must be > 0")));
            totalBps += basisPoints[i];
        }

        require(totalBps == TOTAL_BPS, "DeployRewardDistributor: total basis points must equal 10000");
    }

    /// @notice Log deployment configuration
    function _logConfig(address manager, address[] memory recipients, uint256[] memory basisPoints) internal pure {
        console.log("Configuration:");
        console.log("  Manager:", manager);
        console.log("  Recipients:", recipients.length);

        for (uint256 i = 0; i < recipients.length; i++) {
            console.log("    [%s] Address:", i, recipients[i]);
            console.log("        Share:", basisPoints[i], "bps");
        }

        console.log("");
        console.log("Deploying...");
        console.log("");
    }

    /// @notice Log deployment success
    function _logSuccess(address distributorAddress, uint256 recipientCount) internal pure {
        console.log("=== Deployment Complete ===");
        console.log("RewardDistributor:", distributorAddress);
        console.log("Total Recipients:", recipientCount);
        console.log("");
        console.log("Manager has MANAGER_ROLE and can:");
        console.log("  - redeem(vault): Redeem vault shares held by distributor");
        console.log("  - distribute(token): Distribute tokens to recipients");
        console.log("");
        console.log("Next steps:");
        console.log("  1. Verify the contract on block explorer");
        console.log("  2. Set distributor as treasury in vault (if applicable)");
        console.log("  3. Test redeem/distribute flow");
        console.log("");
    }

    /// @notice Get network name from chain ID
    function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "Ethereum Mainnet";
        if (chainId == ETHEREUM_SEPOLIA) return "Ethereum Sepolia";
        if (chainId == BASE_MAINNET) return "Base Mainnet";
        return "Unknown";
    }

    /// @notice Convert uint256 to string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
