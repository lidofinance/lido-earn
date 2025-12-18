// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/**
 * @title VaultDecimalsTest
 * @notice Fuzz tests for vault decimals() function with offset
 */
contract VaultDecimalsTest is VaultTestBase {
    /// @notice Fuzz test for decimals with various offset values using VaultTestBase asset
    /// @dev Tests that decimals() = asset.decimals() + offset for all valid offsets
    function testFuzz_Decimals_VariousOffsets(uint8 offset) public {
        offset = uint8(bound(uint256(offset), 0, vault.MAX_OFFSET()));

        MockVault testVault =
            new MockVault(address(asset), treasury, REWARD_FEE, offset, "Test Vault", "tVault", address(this));

        uint8 assetDecimals = asset.decimals();
        uint8 vaultDecimals = testVault.decimals();

        assertEq(vaultDecimals, assetDecimals + offset, "Vault decimals should equal asset decimals + offset");
    }

    /// @notice Fuzz test for decimals with various offset and asset decimal values
    /// @dev Tests decimals() = asset.decimals() + offset for different token configurations
    function testFuzz_Decimals_VariousOffsetsAndAssetDecimals(uint8 assetDecimals, uint8 offset) public {
        assetDecimals = uint8(bound(uint256(assetDecimals), 0, 24));
        offset = uint8(bound(uint256(offset), 0, vault.MAX_OFFSET()));

        MockERC20 testAsset = new MockERC20("Test Token", "TEST", assetDecimals);
        MockVault testVault =
            new MockVault(address(testAsset), treasury, REWARD_FEE, offset, "Test Vault", "tVault", address(this));

        uint8 vaultDecimals = testVault.decimals();

        assertEq(vaultDecimals, assetDecimals + offset, "Vault decimals should equal asset decimals + offset");
    }
}
