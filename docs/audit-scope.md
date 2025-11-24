## Summary
- Tech Design
- Contracts [Repo](https://github.com/lidofinance/lido-earn)
- Solidity 0.8.30

### Scope
**Contracts**

* src/EmergencyVault.sol
* src/Vault.sol
* src/RewardDistributor.sol
* src/adapters/ERC4626Adapter.sol

Lines of code: ~600 (non-comment, non-blank)

### Final commit

TBD

[Link](https://github.com/lidofinance/lido-earn/commit)

## Context

Lido Earn provides an ERC4626-compliant middleware layer that wraps external ERC4626 vaults (e.g., Morpho strategies) and adds fee harvesting, reward distribution, inflation-attack defenses, and a robust emergency withdrawal/recovery flow. The system is structured as a reusable `Vault` core, an `EmergencyVault` extension, and concrete adapters (today focused on ERC4626 targets) so new strategies can reuse the same risk controls while exposing a standard interface to wallets, custodians, and integrators.

## Links

- [README](../README.md)
- [ADR](./adr.md)
