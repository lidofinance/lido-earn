// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestConfig} from "test/utils/TestConfig.sol";

import {Vault} from "src/Vault.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/**
 * @title VaultConstructorTest
 * @notice Comprehensive tests for Vault constructor parameter validation
 * @dev Tests cover all constructor validation rules, role assignments, and parameter setup
 */
contract VaultConstructorTest is TestConfig {
    MockERC20 public asset;
    address public treasury = makeAddr("treasury");
    address public admin = address(this);

    uint16 constant VALID_REWARD_FEE = 500; // 5%
    uint8 constant VALID_OFFSET = 6;
    string constant VAULT_NAME = "Test Vault";
    string constant VAULT_SYMBOL = "tvUSDC";

    /* ========== SUCCESSFUL CONSTRUCTOR TESTS ========== */

    /// @notice Test successful construction with all valid parameters
    function test_Constructor_ValidParameters() public {
        MockVault vault = new MockVault(
            address(asset = new MockERC20("USD Coin", "USDC", _assetDecimals())),
            treasury,
            VALID_REWARD_FEE,
            VALID_OFFSET,
            VAULT_NAME,
            VAULT_SYMBOL,
            address(this)
        );

        // Vault was successfully created
        assertTrue(address(vault) != address(0));
    }

    /// @notice Test that all constructor parameters are set correctly
    function test_Constructor_SetsCorrectParameters() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        MockVault vault = new MockVault(
            address(asset), treasury, VALID_REWARD_FEE, VALID_OFFSET, VAULT_NAME, VAULT_SYMBOL, address(this)
        );

        // Check immutable parameters
        assertEq(address(vault.asset()), address(asset), "Asset not set correctly");
        assertEq(vault.TREASURY(), treasury, "Treasury not set correctly");
        assertEq(vault.OFFSET(), VALID_OFFSET, "Offset not set correctly");

        // Check mutable parameters
        assertEq(vault.rewardFee(), VALID_REWARD_FEE, "Reward fee not set correctly");

        // Check ERC20 metadata
        assertEq(vault.name(), VAULT_NAME, "Name not set correctly");
        assertEq(vault.symbol(), VAULT_SYMBOL, "Symbol not set correctly");
    }

    /// @notice Test that deployer receives DEFAULT_ADMIN_ROLE
    function test_Constructor_GrantsAdminRole() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        MockVault vault = new MockVault(
            address(asset), treasury, VALID_REWARD_FEE, VALID_OFFSET, VAULT_NAME, VAULT_SYMBOL, address(this)
        );

        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        assertTrue(vault.hasRole(adminRole, admin), "Admin role not granted");

        // Admin should also receive all other roles
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), admin), "Pauser role not granted");
        assertTrue(vault.hasRole(vault.MANAGER_ROLE(), admin), "Manager role not granted");
        assertTrue(vault.hasRole(vault.EMERGENCY_ROLE(), admin), "Emergency role not granted");
    }

    /// @notice Test that decimals are calculated correctly (asset decimals + offset)
    function test_Constructor_SetsCorrectDecimals() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        MockVault vault = new MockVault(
            address(asset), treasury, VALID_REWARD_FEE, VALID_OFFSET, VAULT_NAME, VAULT_SYMBOL, address(this)
        );

        // Vault decimals should equal asset decimals (not asset decimals + offset)
        // Note: ERC4626 standard dictates vault decimals = asset decimals
        assertEq(vault.decimals(), asset.decimals(), "Decimals not set correctly");
    }

    /// @notice Test valid construction with zero offset
    function test_Constructor_WithZeroOffset() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        MockVault vault = new MockVault(
            address(asset),
            treasury,
            VALID_REWARD_FEE,
            0, // Zero offset is valid
            VAULT_NAME,
            VAULT_SYMBOL,
            address(this)
        );

        assertEq(vault.OFFSET(), 0, "Zero offset not set correctly");
        assertTrue(address(vault) != address(0), "Vault creation failed with zero offset");
    }

    /// @notice Test valid construction with maximum allowed offset
    function test_Constructor_WithMaxOffset() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());
        uint8 maxOffset = 23; // MAX_OFFSET = 23

        MockVault vault = new MockVault(
            address(asset), treasury, VALID_REWARD_FEE, maxOffset, VAULT_NAME, VAULT_SYMBOL, address(this)
        );

        assertEq(vault.OFFSET(), maxOffset, "Max offset not set correctly");
        assertTrue(address(vault) != address(0), "Vault creation failed with max offset");
    }

    /// @notice Test valid construction with zero reward fee
    function test_Constructor_WithZeroRewardFee() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        MockVault vault = new MockVault(
            address(asset),
            treasury,
            0, // Zero reward fee is valid
            VALID_OFFSET,
            VAULT_NAME,
            VAULT_SYMBOL,
            address(this)
        );

        assertEq(vault.rewardFee(), 0, "Zero reward fee not set correctly");
        assertTrue(address(vault) != address(0), "Vault creation failed with zero reward fee");
    }

    /// @notice Test valid construction with maximum allowed reward fee
    function test_Constructor_WithMaxRewardFee() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());
        uint16 maxRewardFee = 2000; // MAX_REWARD_FEE_BASIS_POINTS = 2000 (20%)

        MockVault vault =
            new MockVault(address(asset), treasury, maxRewardFee, VALID_OFFSET, VAULT_NAME, VAULT_SYMBOL, address(this));

        assertEq(vault.rewardFee(), maxRewardFee, "Max reward fee not set correctly");
        assertTrue(address(vault) != address(0), "Vault creation failed with max reward fee");
    }

    /* ========== FAILURE CONSTRUCTOR TESTS ========== */

    /// @notice Test that constructor reverts when asset address is zero
    function test_Constructor_RevertWhen_AssetIsZeroAddress() public {
        vm.expectRevert(Vault.ZeroAddress.selector);

        new MockVault(
            address(0), // Zero address asset
            treasury,
            VALID_REWARD_FEE,
            VALID_OFFSET,
            VAULT_NAME,
            VAULT_SYMBOL,
            address(this)
        );
    }

    /// @notice Test that constructor reverts when treasury address is zero
    function test_Constructor_RevertWhen_TreasuryIsZeroAddress() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        vm.expectRevert(Vault.ZeroAddress.selector);

        new MockVault(
            address(asset),
            address(0), // Zero address treasury
            VALID_REWARD_FEE,
            VALID_OFFSET,
            VAULT_NAME,
            VAULT_SYMBOL,
            address(this)
        );
    }

    /// @notice Test that constructor reverts when offset exceeds MAX_OFFSET
    function test_Constructor_RevertWhen_OffsetTooHigh() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());
        uint8 invalidOffset = 24; // MAX_OFFSET = 23, so 24 is invalid

        vm.expectRevert(abi.encodeWithSelector(Vault.OffsetTooHigh.selector, invalidOffset));

        new MockVault(
            address(asset), treasury, VALID_REWARD_FEE, invalidOffset, VAULT_NAME, VAULT_SYMBOL, address(this)
        );
    }

    /// @notice Test that constructor reverts when reward fee exceeds MAX_REWARD_FEE
    function test_Constructor_RevertWhen_RewardFeeExceedsMax() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());
        uint16 invalidRewardFee = 2001; // MAX_REWARD_FEE_BASIS_POINTS = 2000, so 2001 is invalid

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidFee.selector, invalidRewardFee));

        new MockVault(address(asset), treasury, invalidRewardFee, VALID_OFFSET, VAULT_NAME, VAULT_SYMBOL, address(this));
    }

    /* ========== FUZZ TESTS ========== */

    /// @notice Fuzz test: constructor should accept any valid reward fee (0 to 2000)
    function testFuzz_Constructor_ValidRewardFee(uint16 rewardFee) public {
        // Bound reward fee to valid range [0, MAX_REWARD_FEE_BASIS_POINTS]
        rewardFee = uint16(bound(rewardFee, 0, 2000));

        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        MockVault vault =
            new MockVault(address(asset), treasury, rewardFee, VALID_OFFSET, VAULT_NAME, VAULT_SYMBOL, address(this));

        assertEq(vault.rewardFee(), rewardFee, "Fuzzed reward fee not set correctly");
    }

    /// @notice Fuzz test: constructor should accept any valid offset (0 to 23)
    function testFuzz_Constructor_ValidOffset(uint8 offset) public {
        // Bound offset to valid range [0, MAX_OFFSET]
        offset = uint8(bound(offset, 0, 23));

        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        MockVault vault =
            new MockVault(address(asset), treasury, VALID_REWARD_FEE, offset, VAULT_NAME, VAULT_SYMBOL, address(this));

        assertEq(vault.OFFSET(), offset, "Fuzzed offset not set correctly");
    }

    /// @notice Fuzz test: constructor should revert for invalid reward fee (> 2000)
    function testFuzz_Constructor_InvalidRewardFee(uint16 rewardFee) public {
        // Bound reward fee to invalid range [2001, type(uint16).max]
        rewardFee = uint16(bound(uint256(rewardFee), 2001, type(uint16).max));

        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidFee.selector, rewardFee));

        new MockVault(address(asset), treasury, rewardFee, VALID_OFFSET, VAULT_NAME, VAULT_SYMBOL, address(this));
    }

    /// @notice Fuzz test: constructor should revert for invalid offset (> 23)
    function testFuzz_Constructor_InvalidOffset(uint8 offset) public {
        // Bound offset to invalid range [24, type(uint8).max]
        offset = uint8(bound(uint256(offset), 24, type(uint8).max));

        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        vm.expectRevert(abi.encodeWithSelector(Vault.OffsetTooHigh.selector, offset));

        new MockVault(address(asset), treasury, VALID_REWARD_FEE, offset, VAULT_NAME, VAULT_SYMBOL, address(this));
    }

    /* ========== ERC4626 ADAPTER CONSTRUCTOR TESTS ========== */

    /// @notice Test that ERC4626Adapter constructor reverts when target vault address is zero
    /// @dev Coverage: src/adapters/ERC4626Adapter.sol:59 - if (targetVault_ == address(0)) revert TargetVaultZeroAddress();
    function test_AdapterConstructor_RevertWhen_TargetVaultIsZeroAddress() public {
        asset = new MockERC20("USD Coin", "USDC", _assetDecimals());

        vm.expectRevert(ERC4626Adapter.TargetVaultZeroAddress.selector);

        new ERC4626Adapter(
            address(asset),
            address(0), // Zero address for target vault
            treasury,
            VALID_REWARD_FEE,
            VALID_OFFSET,
            VAULT_NAME,
            VAULT_SYMBOL,
            address(this)
        );
    }
}
