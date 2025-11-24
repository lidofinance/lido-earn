// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RewardDistributor} from "src/RewardDistributor.sol";

contract DeployRewardDistributor is Script {
    address constant MANAGER = 0x583FcCB743E846b639796bb56dBfE705Cbb65f31;

    address constant RECIPIENT_1 = 0x1111111111111111111111111111111111111111;
    address constant RECIPIENT_2 = 0x2222222222222222222222222222222222222222;

    uint256 constant RECIPIENT_1_BPS = 500;
    uint256 constant RECIPIENT_2_BPS = 9500;

    RewardDistributor public distributor;

    function run() public returns (address) {
        console.log("=== RewardDistributor Deployment ===");
        console.log("Deployer:", msg.sender);
        console.log("");

        console.log("Configuration:");
        console.log("  Manager:", MANAGER);
        console.log("  Recipients:");
        console.log("    1. Address:", RECIPIENT_1);
        console.log("       Share:", RECIPIENT_1_BPS, "bps");
        console.log("    2. Address:", RECIPIENT_2);
        console.log("       Share:", RECIPIENT_2_BPS, "bps");
        console.log("");

        vm.startBroadcast();

        address[] memory recipients = new address[](2);
        recipients[0] = RECIPIENT_1;
        recipients[1] = RECIPIENT_2;

        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = RECIPIENT_1_BPS;
        basisPoints[1] = RECIPIENT_2_BPS;

        distributor = new RewardDistributor(MANAGER, recipients, basisPoints);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("RewardDistributor:", address(distributor));
        console.log("");
        console.log("Manager has MANAGER_ROLE and can:");
        console.log("  - redeem(vault): Redeem vault shares held by distributor");
        console.log("  - distribute(token): Distribute tokens to recipients");
        console.log("");

        return address(distributor);
    }
}
