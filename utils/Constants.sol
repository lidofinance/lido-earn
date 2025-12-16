// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

// Supported networks
uint256 constant ETHEREUM_MAINNET = 1;
uint256 constant ETHEREUM_SEPOLIA = 11155111;
uint256 constant BASE_MAINNET = 8453;

// Mainnet token addresses
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

// Mainnet Steakhouse Morpho vault addresses
address constant STEAKHOUSE_USDC_VAULT = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
address constant STEAKHOUSE_USDT_VAULT = 0xbEef047a543E45807105E51A8BBEFCc5950fcfBa;
address constant STEAKHOUSE_WETH_VAULT = 0xBEEf050ecd6a16c4e7bfFbB52Ebba7846C4b8cD4;

/// @notice Configuration for testing with specific ERC4626 vaults
/// @dev Used for parameterized integration tests on mainnet forks
struct VaultTestConfig {
    address token;
    address targetVault;
    uint8 decimals;
    address holder;
    uint256 testDepositAmount;
    string name;
    string symbol;
    uint16 rewardFee;
    uint8 offset;
}

/// @title VaultTestConfigs
/// @notice Library providing test configurations for mainnet Morpho vault integrations
/// @dev Pure functions return compile-time constants for gas efficiency.
///      Functions are named after the specific vault (e.g., steakhouseUSDC) rather than just
///      the token, as multiple vaults can exist for the same underlying asset.
library VaultTestConfigs {
    /// @notice Steakhouse USDC vault configuration
    /// @dev Uses 6 decimals, 1000 USDC test amount
    /// @return config VaultTestConfig for Steakhouse USDC integration tests
    function steakhouseUSDC() internal pure returns (VaultTestConfig memory config) {
        config = VaultTestConfig({
            token: USDC,
            targetVault: STEAKHOUSE_USDC_VAULT,
            decimals: 6,
            holder: 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa, // Coinbase 14
            testDepositAmount: 1_000e6, // 1000 USDC
            name: "Steakhouse USDC Vault",
            symbol: "stkUSDC",
            rewardFee: 500, // 5%
            offset: 10
        });
    }

    /// @notice Steakhouse USDT vault configuration
    /// @dev Uses 6 decimals, 1000 USDT test amount
    /// @return config VaultTestConfig for Steakhouse USDT integration tests
    function steakhouseUSDT() internal pure returns (VaultTestConfig memory config) {
        config = VaultTestConfig({
            token: USDT,
            targetVault: STEAKHOUSE_USDT_VAULT,
            decimals: 6,
            holder: 0xF977814e90dA44bFA03b6295A0616a897441aceC, // Binance 8
            testDepositAmount: 1_000e6, // 1000 USDT
            name: "Steakhouse USDT Vault",
            symbol: "stkUSDT",
            rewardFee: 500, // 5%
            offset: 10
        });
    }

    /// @notice Steakhouse WETH vault configuration
    /// @dev Uses 18 decimals, 1 WETH test amount
    /// @return config VaultTestConfig for Steakhouse WETH integration tests
    function steakhouseWETH() internal pure returns (VaultTestConfig memory config) {
        config = VaultTestConfig({
            token: WETH,
            targetVault: STEAKHOUSE_WETH_VAULT,
            decimals: 18,
            holder: 0x8EB8a3b98659Cce290402893d0123abb75E3ab28, // Arbitrum Bridge
            testDepositAmount: 1e18, // 1 WETH
            name: "Steakhouse WETH Vault",
            symbol: "stkWETH",
            rewardFee: 500, // 5%
            offset: 10
        });
    }

    /// @notice Returns all available vault test configurations
    /// @dev Used for parameterized testing across all vaults
    /// @return configs Array of all VaultTestConfig structs
    function allConfigs() internal pure returns (VaultTestConfig[] memory configs) {
        configs = new VaultTestConfig[](3);
        configs[0] = steakhouseUSDC();
        configs[1] = steakhouseUSDT();
        configs[2] = steakhouseWETH();
    }
}
