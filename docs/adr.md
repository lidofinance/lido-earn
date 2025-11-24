# Lido Earn – Architecture Decision Record

---

## Context and Problem Statement

The project builds a DeFi accessibility layer for institutional capital. Stakeholders require standard vault primitives that plug into existing custody, reporting, and compliance systems without custom work. Existing DeFi integrations lack unified interfaces, consistent fee distribution, and robust emergency tooling. The architecture therefore must:

- Present a single ERC4626-compliant interface while hiding protocol differences.
- Make adapter integrations fast and predictable without duplicating security logic.
- Guarantee fee harvesting and distribution in a way that partners and governance can audit.
- Provide crisis tooling (pause, emergency withdraw, recovery) that satisfies risk/compliance demands.

---

## Core Constraints

### Constraint 1 — Unified Standard Interface
The system must support any wallet/custodian/analytics tool. **Decision:** base everything on OpenZeppelin’s ERC4626 implementation. All vault/token math, allowance patterns, and previews follow the standard so downstream tools work unchanged.

### Constraint 2 — Fast Extensibility
Adapters should only implement protocol-specific mechanics. **Decision:** split into `Vault` (shared logic), `EmergencyVault` (crisis tooling), and `ERC4626Adapter` (protocol glue).

### Constraint 3 — Immutable Reward Splits
Partners require predictable fee payouts. **Decision:** a dedicated `RewardDistributor` that owns treasury shares, redeems, and distributes assets using immutable recipient schedules.

### Constraint 4 — Emergency Resilience
Deterministic crisis handling (pauses, emergency withdrawals, pro-rata recovery) is mandatory for compliance-focused deployments. **Decision:** embed a dedicated `EmergencyVault` layer that enforces emergency mode, multi-step recoveries, and transparent loss accounting before allowing user claims.

---

## Decisions

### ERC4626 Tokenized Vault Standard

**Decision:** Use OpenZeppelin ERC4626 as the single share interface.
- **Benefits:** Maximum ecosystem compatibility, known security profile, easier audits.
- **Costs:** Higher gas overhead vs custom implementation, need to handle preview rounding carefully.
- **Clarifications:**
  - Multi-asset or multi-strategy token models (e.g., ERC1155) are intentionally out of scope; each strategy receives its own ERC4626 vault.
  - Guidance about preview accuracy during volatile markets is documented within this ADR rather than a separate partner guide.

**Decision:** Vault contract implements all ERC4626 user flows while adapters inherit it and only add protocol-specific logic.
- Adapters supply minimal overrides (`totalAssets`, `_depositToProtocol`, `_withdrawFromProtocol`, previews) so any ERC4626-compliant strategy works out of the box; non-ERC4626 integrations need thin wrappers that expose the same surface.

**Decision:** `OFFSET` and `MIN_FIRST_DEPOSIT` enforce inflation-attack protection with per-asset tuning documented alongside deployments.
- **Benefits:** Users cannot grief share price on first deposit; both 6- and 18-decimal assets remain safe; rebasing tokens are acceptable because the vault primarily relays shares rather than holding balances long term.
- **Costs:** Adds math complexity, requires consistent environment configuration in tests/deployments.

### Snapshot-Based Fee Harvesting

**Decision:** Track `lastTotalAssets` and mint treasury shares on each user interaction.
- **Benefits:** No keeper infrastructure, works across any adapter, predictable economics.
- **Costs:** Fees only harvest on activity (idle vault = stale profit/loss), slight gas overhead per call.
- **Clarifications:**
  - The 20% fee ceiling is immutable to guarantee users that performance fees never exceed the advertised cap.

### Reward Distribution

**Decision:** RewardDistributor contract with immutable recipients/bps.
- **Benefits:** Fully transparent and immutable fee-sharing schedule; all commissions accrue according to the on-chain “contract” until the vault explicitly swaps to a new distributor.
- **Costs:** Zero flexibility (must redeploy to change recipients), manager must run redeem/distribute steps.
- **Clarifications:**
  - Recipient rotation happens only by deploying a fresh Distributor and updating the treasury address in the vault; no mutable state exists inside the contract.
  - Auto-distribution from the vault is intentionally avoided because manual `redeem`/`distribute` calls offer better legal/compliance controls.

### Emergency Mechanism

**Decision:** EmergencyVault layer that enforces emergency mode, multiple pulls, recovery snapshots, and pro-rata emergency redemptions.
- **Benefits:** predictable crisis response, transparent implicit loss metrics, protects remaining users.
- **Costs:** Vault becomes “pumpkin” once recovery mode starts; requires trusted EMERGENCY_ROLE to behave correctly.
- **Clarifications:**
  - Role separation: fast multisigs manage operational levers (`PAUSER_ROLE`, etc.), while a slower “multisig of multisigs” governs high-impact actions (e.g., activating recovery).
  - Recovery activation is approved by the slow multisig when liquidity cannot be safely restored; once triggered, the vault never returns to normal operation and users exit solely via `emergencyRedeem`.
  - `emergencyRedeem` honors the same allowance mechanics as standard withdrawals so custodial flows remain consistent even during crises.

---

## Key Risks & Mitigations

### Emergency Withdrawal Insolvency (Smart Contract, Critical)
- **Threat:** Once emergency withdrawal drains the underlying protocol, vault shares remain outstanding but have no backing until recovery completes; users cannot resume normal withdrawals.
- **Mitigation:** Emergency mode freezes deposits/mints, recovery snapshots track withdrawal rights, two-tier multisig governance manages emergency triggers, and users exit via `emergencyRedeem` using recovered balances. Runbooks and communications make it clear that operations never resume after recovery, so expectations stay aligned.
- **Residual risk:** If little or no value is recovered, users still face losses; the mitigation focuses on fairness and transparency rather than full restitution.

### MetaMorpho Bad Debt Realization (Integration, Medium/High)
- **Threat:** MetaMorpho v1.1 defers loss realization, so `totalAssets` can appear healthy while `maxWithdraw` collapses, trapping late withdrawers.
- **Mitigation:** Integration due diligence limits onboarding to curator vaults with clear bad-debt coverage, off-chain monitors compare assets vs withdrawable amounts, alerts feed into pause/runbook decisions, and treasury reserves or manual pausing keep new deposits out until curators resolve the deficit.
- **Residual risk:** Losses inside MetaMorpho aren’t eliminated; mitigations reduce exposure time and provide operational response levers but cannot guarantee full recovery.

### Morpho Protocol Pause/Upgrade (Operational Dependency, Medium/Low)
- **Threat:** Morpho could pause withdrawals or upgrade contracts, causing `_withdrawFromProtocol` to revert and temporarily stranding funds.
- **Mitigation:** Adapter logic already caps withdrawals to `maxWithdraw`, so errors are explicit; emergency withdrawal plus recovery mode allows evacuating funds if needed; operations monitor Morpho governance, test upgrades in staging, and maintain diversification plans across multiple strategies.
- **Residual risk:** Short-term illiquidity is still possible, but clear error messaging and documented emergency flows prevent silent failure modes.

### Admin Key Compromise (Operational, Medium)
- **Threat:** Compromised admin roles could pause the vault, raise fees to the ceiling, or redirect treasury distributions, but they cannot withdraw user principal—only fee flows and treasury assets are at risk when keys are compromised.
- **Mitigation:** Production deployments require multi-sig control per role, hardware wallets for signers, timelocks for fee/role changes, real-time monitoring of admin transactions, and incident response playbooks (pause, notify users, migrate to fresh contracts) so any malicious action is contained before treasury balances accumulate.
- **Residual risk:** Insider threats or multi-sig signer collusion remain, and stolen keys can still drain the treasury or capture upcoming profits, so governance processes, audits, and treasury size limits remain essential.

### Vault Shares Used as Collateral (Composability, Medium)
- **Threat:** Fee harvest dilution or protocol losses can lower share price, causing downstream lending protocols to liquidate users who use vault shares as collateral.
- **Mitigation:** Public guidance recommends high collateralization buffers, conservative LTV caps for integrators, and monitoring of harvest schedules; partners are advised to treat vault tokens like yield-bearing assets with variable share price rather than stablecoin equivalents.
- **Residual risk:** External protocols may still adopt aggressive parameters, so education and coordination with integrators remain ongoing tasks.
