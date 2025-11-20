# Lido Earn - DeFi Yield Vault Middleware

This repository contains the source code for the smart contracts implementing Lido Earn yield vault middleware.

Lido Earn is an ERC4626-compliant vault infrastructure that enables integration of arbitrary ERC4626 yield strategies into wallets and applications. The system provides a foundation for yield aggregation with comprehensive security controls, fee management, and reward distribution.

The architecture implements:
1. **Abstract Vault base** with ERC4626 compliance, access control, fee harvesting, inflation attack protection, and emergency mechanisms
2. **Protocol adapters** for integrating various DeFi protocols
3. **Reward distribution system** with configurable recipient allocations and two-step distribution flow

## Setup

This project uses Foundry for development and testing, so you'll need to have Foundry installed.

* Install Foundry and `forge` https://book.getfoundry.sh/getting-started/installation

    ```sh
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
    ```

* Clone the repository
    ```sh
    git clone https://github.com/your-org/lido-earn.git
    cd lido-earn
    ```

* Install forge dependencies
    ```sh
    forge install
    ```

* Verify installation
    ```sh
    forge --version
    ```


## Running Tests

This repository contains different sets of tests written using the Foundry framework:

- **Unit tests** - Comprehensive tests covering each module in isolation (deposits, withdrawals, fees, access control, pausable behavior, emergency operations, etc.). This is the most thorough set of tests covering every edge case.

- **Integration tests** - Tests that verify how contracts work in a forked environment using real protocol state:
    - **Mainnet fork tests** - Verify integration with real ERC4626 vaults (e.g. Morpho) using mainnet state
    - **Reward distribution tests** - End-to-end testing of fee collection and distribution flows

- **Invariant tests** - Property-based fuzzing tests that verify critical system invariants hold under all conditions:
    - Vault solvency and accounting correctness
    - Reward distribution integrity
    - Handler-based fuzzing for complex multi-step scenarios

The following commands can be used to run different types of tests:

- **Run all tests**
    ```sh
    forge test
    ```

- **Run tests with detailed output**
    ```sh
    forge test -vvv
    ```

- **Run specific test file**
    ```sh
    forge test --match-path test/unit/vault/Vault.Deposit.t.sol
    ```

- **Run specific test function**
    ```sh
    forge test --match-test test_Deposit_Basic
    ```

- **Run unit tests exclusively**
    ```sh
    forge test --match-path "test/unit/**/*.sol"
    ```

- **Run integration tests exclusively**
    ```sh
    forge test --match-path "test/integration/**/*.sol"
    ```

- **Run invariant tests exclusively**
    ```sh
    forge test --match-path "test/invariant/**/*.sol"
    ```

>[!NOTE]
>For mainnet fork tests, you may need to configure `MAINNET_RPC_URL` in your environment if using specific RPC providers.


## Test Coverage Report Generation

1. Install `lcov` package in your OS
    ```sh
    brew install lcov

    -OR-

    apt-get install lcov
    ```

2. Generate coverage report
    ```sh
    forge coverage --report lcov
    genhtml lcov.info -o coverage-report
    ```

3. Open `./coverage-report/index.html` in your browser.


## Documentation

- **[Foundry Book](https://book.getfoundry.sh/)** - Foundry framework documentation
- **[ERC4626 Standard](https://eips.ethereum.org/EIPS/eip-4626)** - Tokenized vault standard specification
- **[Morpho Docs](https://docs.morpho.org/)** - Morpho protocol documentation
- **[OpenZeppelin Docs](https://docs.openzeppelin.com/contracts/5.x/)** - Security primitives and token standards


## License

This project is licensed under the MIT License.
