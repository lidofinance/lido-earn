# Test Plan

**Last Updated:** 2025-12-12
**Total Test Files:** 33
**Test Coverage:** Unit, Integration, and Invariant tests

---

## Environment Overrides

- All tests default to a 6-decimal mock asset. Set `ASSET_DECIMALS=18` (or any `uint8` value) before running `forge test` to rerun the full suite against an asset with the desired precision. No changes to the test selection are required—just run the command twice with the different env values.

---

## Vault Tests

### Vault.Constructor.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Constructor_ValidParameters | Valid vault construction | Non-zero address, no revert |
| test_Constructor_SetsCorrectParameters | Parameter assignment | Asset, treasury, offset, fee, name/symbol set |
| test_Constructor_GrantsAdminRole | Role assignment | Admin, pauser, fee manager, emergency roles granted |
| test_Constructor_SetsCorrectDecimals | Decimals calculation | Vault decimals = asset decimals (ERC4626) |
| test_Constructor_WithZeroOffset | Zero offset accepted | OFFSET = 0, creation succeeds |
| test_Constructor_WithMaxOffset | Max offset accepted | OFFSET = 23, creation succeeds |
| test_Constructor_WithZeroRewardFee | Zero fee accepted | rewardFee = 0, creation succeeds |
| test_Constructor_WithMaxRewardFee | Max fee accepted | rewardFee = 2000 (20%), creation succeeds |
| test_Constructor_RevertWhen_AssetIsZeroAddress | Zero asset validation | Reverts with InvalidAssetAddress |
| test_Constructor_RevertWhen_TreasuryIsZeroAddress | Zero treasury validation | Reverts with InvalidTreasuryAddress |
| test_Constructor_RevertWhen_OffsetTooHigh | Offset bounds check | Reverts with InvalidOffset for offset > 23 |
| test_Constructor_RevertWhen_RewardFeeExceedsMax | Fee bounds check | Reverts with InvalidRewardFee for fee > 2000 |
| testFuzz_Constructor_ValidRewardFee | Fuzz valid fees 0-2000 | All valid fees accepted |
| testFuzz_Constructor_ValidOffset | Fuzz valid offsets 0-23 | All valid offsets accepted |
| testFuzz_Constructor_InvalidRewardFee | Fuzz invalid fees >2000 | All invalid fees rejected |
| testFuzz_Constructor_InvalidOffset | Fuzz invalid offsets >23 | All invalid offsets rejected |
| test_AdapterConstructor_RevertWhen_TargetVaultIsZeroAddress | Target vault validation | Reverts with InvalidTargetVaultAddress |

---

### Vault.Initialization.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Initialization | Initial state setup | Asset, treasury, offset, fee, name, symbol, decimals |
| test_InitialState | Zero balances/supply | totalSupply = 0, totalAssets = 0 |
| test_InitialRolesAssigned | Role assignment | All roles granted to deployer |
| test_InitialPausedState | Pause state | paused() = false |
| test_InitialRewardFeeAndLastAssets | Fee state | rewardFee set, lastTotalAssets = 0 |
| test_MinFirstDepositConstant | Constant value | MIN_FIRST_DEPOSIT = 1000 |

---

### Vault.Deposit.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Deposit_Basic | Basic deposit | Shares minted = assets * 10^OFFSET, balances updated |
| testFuzz_Deposit_Basic | Fuzz basic deposit | Shares minted correctly for any valid deposit amount |
| test_Deposit_EmitsEvent | Event emission | Deposited event with correct params |
| test_Deposit_MultipleUsers | Multi-user deposits | Each user gets correct shares, totals updated |
| testFuzz_Deposit_MultipleUsers | Fuzz multi-user deposits | Two users get correct shares for any valid amounts |
| test_Deposit_RevertIf_ZeroAmount | Zero amount validation | Reverts with InvalidAssetsAmount |
| test_Deposit_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with InvalidReceiverAddress |
| test_Deposit_RevertIf_Paused | Pause enforcement | Reverts with EnforcedPause |
| test_SecondDeposit_CanBeSmall | Subsequent deposits | Allows deposits of 1 wei after first |
| test_Mint_Basic | Basic mint | Exact shares minted, assets match preview |
| testFuzz_Mint_Basic | Fuzz basic mint | Assets match preview for any valid share amount |
| test_Mint_RevertIf_ZeroShares | Zero shares validation | Reverts with InvalidSharesAmount |
| test_Mint_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with InvalidReceiverAddress |
| test_Mint_RevertIf_FirstDepositTooSmall | First mint minimum | Reverts if assets < MIN_FIRST_DEPOSIT |
| test_Mint_RevertIf_Paused | Pause enforcement | Reverts with EnforcedPause |
| test_PreviewDeposit_Accurate | Preview accuracy | Previewed shares = actual shares |
| test_Offset_ProtectsAgainstInflationAttack | Inflation attack protection | Victim gets fair shares despite donation |
| testFuzz_Deposit_Success | Fuzz deposits | Shares match preview for any valid amount |
| testFuzz_Mint_Success | Fuzz mints | Assets match preview for any valid amount |
| testFuzz_Deposit_WithExistingDeposits | Fuzz sequential deposits | Share price stable, accounting correct |
| testFuzz_Deposit_RoundingFavorsVault | Rounding direction | User receives ≤ previewed shares |
| testFuzz_Mint_RoundingFavorsVault | Rounding direction | User pays ≥ previewed assets |
| test_Deposit_RevertIf_ExceedsMaxDeposit | maxDeposit enforcement | Reverts when deposit exceeds target vault capacity |

---

### Vault.Withdraw.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Withdraw_Basic | Basic withdrawal | Shares burned match preview, assets received |
| test_Withdraw_RevertIf_ZeroAmount | Zero amount validation | Reverts with InvalidAssetsAmount |
| test_Withdraw_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with InvalidReceiverAddress |
| test_Withdraw_DoesNotBurnAllShares | Partial withdrawal | Remaining shares intact (~90% remain) |
| test_Withdraw_EmitsEvent | Event emission | Withdrawn event with correct params |
| test_Withdraw_RevertIf_InsufficientShares | Balance check | Reverts with InsufficientShares |
| test_Withdraw_RevertIf_ProtocolReturnsLessAssets | Protocol liquidity | Reverts with InsufficientLiquidity |
| test_Withdraw_DelegatedWithApproval | Delegated withdrawal | Works with approval, allowance consumed |
| test_Withdraw_DelegatedRevertIf_InsufficientAllowance | Approval check | Reverts with ERC20InsufficientAllowance |
| test_Withdraw_DelegatedRevertIf_NoApproval | Approval requirement | Reverts with ERC20InsufficientAllowance |
| test_Withdraw_WorksWhenPaused | Pause behavior | Withdrawal succeeds despite pause |
| test_Withdraw_SelfDoesNotRequireApproval | Self-withdrawal | No approval needed for self |
| test_Withdraw_DelegatedWithUnlimitedApproval | Unlimited approval | type(uint256).max not consumed |
| test_Withdraw_UpdatesLastTotalAssets | State update | lastTotalAssets = current totalAssets |
| test_Redeem_Basic | Basic redemption | Assets match preview, shares burned |
| test_Redeem_AllShares | Full redemption | All shares burned, balance restored |
| test_Redeem_UpdatesLastTotalAssets | State update | lastTotalAssets updated |
| test_Redeem_RevertIf_ZeroShares | Zero shares validation | Reverts with InvalidSharesAmount |
| test_Redeem_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with InvalidReceiverAddress |
| test_Redeem_RevertIf_NoApproval | Approval requirement | Reverts with ERC20InsufficientAllowance |
| test_Redeem_DelegatedWithApproval | Delegated redemption | Works with approval, allowance consumed |
| test_Redeem_WorksWhenPaused | Pause behavior | Redemption succeeds despite pause |
| test_Redeem_RevertIf_InsufficientShares | Balance check | Reverts with InsufficientShares |
| test_PreviewWithdraw_Accurate | Preview accuracy | Previewed shares = actual shares burned |
| test_PreviewWithdraw_WithPendingFees | Preview with fees | Accounts for fee harvesting |
| test_PreviewRedeem_WithPendingFees_Accurate | Preview with fees | Matches actual assets (±2 wei) |
| test_MaxWithdraw | maxWithdraw calculation | Returns withdrawable amount |
| test_MaxWithdraw_WithPendingFees_ShouldNotRevert | maxWithdraw with fees | No revert, amount withdrawable |
| testFuzz_MaxWithdraw_IsActuallyWithdrawable | Fuzz maxWithdraw | maxWithdraw always withdrawable, 1 wei dust |
| test_DepositWithdraw_RoundingDoesNotCauseLoss | Round-trip preservation | Full balance recovered |
| test_MultipleDepositsWithdraws_MaintainsAccounting | Multi-operation accounting | Share-asset conversions accurate |
| test_TotalAssets | totalAssets accuracy | totalAssets = deposited amount |
| testFuzz_Withdraw_Success | Fuzz withdrawals | Shares burned match preview |
| testFuzz_Redeem_Success | Fuzz redemptions | Assets match preview |
| testFuzz_Withdraw_WithMultipleUsers | Fuzz multi-user | One withdrawal doesn't affect others |
| testFuzz_Withdraw_RoundingFavorsVault | Rounding direction | User burns ≥ previewed shares (±2 wei) |
| testFuzz_Redeem_RoundingFavorsVault | Rounding direction | User receives ≤ previewed assets (±2 wei) |

---

### Vault.Fees.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_HarvestFees_WithProfit | Fee harvest on profit | Treasury receives proportional shares |
| test_HarvestFees_EmitsEvent | Event emission | FeesHarvested event with profit, fee, shares |
| test_HarvestFees_NoProfit | No profit scenario | Treasury receives no shares |
| test_HarvestFees_WithLoss | Loss scenario | Treasury receives no shares |
| test_HarvestFees_UpdatesLastTotalAssets | State update | lastTotalAssets = totalAssets after harvest |
| test_HarvestFees_WhenTotalSupplyIsZero | Zero supply safety | No revert, lastTotalAssets = 0 |
| test_HarvestFees_WhenTotalAssetsIsZero | Zero assets safety | No revert, lastTotalAssets = 0 |
| test_HarvestFees_MultipleHarvests | Sequential harvests | Treasury shares accumulate correctly |
| test_HarvestFees_CalledAutomaticallyOnDeposit | Auto-harvest on deposit | Deposit triggers harvest, treasury receives shares |
| test_HarvestFees_CalledAutomaticallyOnWithdraw | Auto-harvest on withdraw | Withdraw triggers harvest |
| test_HarvestFees_CalledAutomaticallyOnMint | Auto-harvest on mint | Mint triggers harvest |
| test_HarvestFees_CalledAutomaticallyOnRedeem | Auto-harvest on redeem | Redeem triggers harvest |
| test_HarvestFees_CalculatesCorrectFeeAmount | Fee calculation | Fee = profit * rewardFee / 10000 |
| test_HarvestFees_WithZeroFee | Zero fee scenario | Treasury receives no shares |
| test_HarvestFees_WithMaxFee | Max fee (20%) | Treasury receives 20% of profit |
| test_GetPendingFees_WithProfit | Pending fees with profit | Returns correct fee amount (±1 wei) |
| test_GetPendingFees_NoProfit | Pending fees no profit | Returns 0 |
| test_GetPendingFees_WithLoss | Pending fees with loss | Returns 0 |
| test_GetPendingFees_AfterHarvest | Pending fees after harvest | Returns 0 after harvest |
| test_HarvestFees_FeeAmountCappedAtProfit | Defensive cap | Fee capped when rounding causes fee > profit |
| test_GetPendingFees_FeeAmountCappedAtProfit | View function cap | Pending fees ≤ profit |
| testFuzz_HarvestFees_WithProfit | Fuzz profit amounts | Correct fees for any profit, treasury receives shares |
| testFuzz_HarvestFees_DifferentRewardRates | Fuzz fee rates 0-20% | Correct fees for any rate, 0% = no shares |
| testFuzz_HarvestFees_MultipleHarvests | Fuzz sequential harvests | Treasury accumulates, total within tolerance |
| testFuzz_HarvestFees_NoFeeWhenZeroRewardFee | Fuzz with 0% fee | No shares minted regardless of profit |

---

### Vault.AccessControl.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_AdminRole_DefaultAdmin | Admin role assignment | Deployer has DEFAULT_ADMIN_ROLE |
| test_PauserRole_GrantAndRevoke | PAUSER_ROLE management | Admin can grant/revoke, status changes |
| test_FeeManagerRole_GrantAndRevoke | MANAGER_ROLE management | Admin can grant/revoke |
| test_EmergencyRole_GrantAndRevoke | EMERGENCY_ROLE management | Admin can grant/revoke |
| test_AccessControl_RevertIf_NonAdminGrantsRole | Non-admin grant attempt | Reverts with AccessControlUnauthorizedAccount |
| test_AccessControl_RevertIf_NonAdminRevokesRole | Non-admin revoke attempt | Reverts with AccessControlUnauthorizedAccount |
| test_AccessControl_MultipleRoleHolders | Multiple role holders | Multiple pausers can pause/unpause |
| test_AccessControl_RoleAdminOfRole | Role admin | DEFAULT_ADMIN_ROLE is admin of all roles |
| test_AccessControl_RenounceRole | Role renouncement | Role holder can renounce, status updates |
| test_AccessControl_RenounceRole_RevertIf_CallerDiffers | Renounce validation | Reverts with AccessControlBadConfirmation |
| test_AccessControl_DeployerGetsAllRoles | Initial roles | Deployer has admin, pauser, fee manager, emergency |

---

### Vault.Pausable.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Pause_Basic | Basic pause | Vault enters paused state |
| test_Pause_RevertIf_NotPauser | Pause authorization | Reverts with AccessControlUnauthorizedAccount |
| test_Pause_WithPauserRole | PAUSER_ROLE pause | Role holder can pause |
| test_Unpause_Basic | Basic unpause | Vault exits paused state |
| test_Pause_RevertIf_AlreadyPaused | Double pause | Reverts with EnforcedPause |
| test_Unpause_RevertIf_NotPaused | Unpause when active | Reverts with ExpectedPause |
| test_Unpause_RevertIf_NotPauser | Unpause authorization | Reverts with AccessControlUnauthorizedAccount |
| test_Pause_BlocksDeposit | Deposit during pause | Reverts with EnforcedPause |
| test_Pause_BlocksMint | Mint during pause | Reverts with EnforcedPause |
| test_Pause_AllowsWithdraw | Withdraw during pause | Withdrawal succeeds, user exit ability preserved |
| test_Pause_AllowsRedeem | Redeem during pause | Redemption succeeds, user exit ability preserved |
| test_Unpause_AllowsOperations | Operations after unpause | Deposits work after unpause |
| test_Pause_DoesNotBlockViews | View functions during pause | totalAssets, balanceOf, preview functions work |
| test_Pause_DoesNotBlockPreviewDeposit | previewDeposit during pause | Returns valid value |
| test_MaxDepositPositiveWhenUnpaused | maxDeposit when active | maxDeposit = type(uint256).max |
| test_Pause_MultipleTimesDifferentPausers | Multiple pausers | Different pausers can control state |

---

### Vault.Config.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_SetRewardFee_Basic | Basic fee update | rewardFee updated, RewardFeeUpdated event |
| test_SetRewardFee_ToZero | Zero fee | Accepts 0%, event emitted |
| test_SetRewardFee_ToMaximum | Max fee | Accepts MAX_REWARD_FEE (20%), event emitted |
| test_SetRewardFee_RevertIf_ExceedsMaximum | Fee bounds | Reverts with InvalidRewardFee |
| test_SetRewardFee_RevertIf_SameValue | Same value check | Reverts with InvalidRewardFee if setting same value |
| test_SetRewardFee_RevertIf_NotFeeManager | Fee manager authorization | Reverts with AccessControlUnauthorizedAccount |
| test_SetRewardFee_HarvestsFeesBeforeChange | Pre-change harvest | Pending fees harvested at old rate |
| test_SetRewardFee_UpdatesLastTotalAssets | State update | lastTotalAssets = totalAssets after update |
| test_SetRewardFee_WithFeeManagerRole | MANAGER_ROLE update | Role holder can update fee |
| test_SetRewardFee_MultipleChanges | Sequential changes | Each change succeeds, events emitted |
| testFuzz_SetRewardFee_WithinBounds | Fuzz valid fees | Any value 0-MAX_REWARD_FEE accepted |
| test_SetTreasury_Basic | Treasury update | MANAGER_ROLE can update treasury, event emitted |
| test_SetTreasury_RevertIf_ZeroAddress | Input validation | Reverts with InvalidTreasuryAddress for zero treasury |
| test_SetTreasury_RevertIf_SameAddress | No-op prevention | Reverts with InvalidTreasuryAddress if address is unchanged |
| test_SetTreasury_RevertIf_NotFeeManager | Access control | Only MANAGER_ROLE can update treasury |
| test_SetTreasury_HarvestsFeesBeforeUpdate | Treasury migration | Fees harvested to old treasury before address update |
| test_SetTreasury_DoesNotTransferExistingShares | Fee accounting | Legacy treasury shares remain with old address, future fees go to new |

---

### Vault.Permit.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Permit_Basic | Basic permit | Signature verified, allowance set, nonce incremented |
| test_Permit_WithdrawAfterPermit | Withdrawal using permit | Permit enables delegated withdrawal |
| test_Permit_RevertIf_Expired | Expiration check | Reverts with ERC2612ExpiredSignature |
| test_Permit_RevertIf_InvalidSignature | Signature validation | Reverts with ERC2612InvalidSigner |
| test_Permit_RevertIf_ReplayAttack | Replay protection | Signature cannot be reused |
| test_Permit_Nonces_Increment | Nonce management | Nonce increases with each permit |
| test_Permit_DomainSeparator | EIP-712 compliance | DOMAIN_SEPARATOR matches EIP-712 spec |

---

### Vault.Recover.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_RecoverERC20_Basic | Basic token recovery | MANAGER_ROLE recovers accidentally sent ERC20 tokens, event emitted |
| test_RecoverERC20_MultipleTokens | Multiple token recovery | Can recover different tokens in sequence |
| test_RecoverERC20_LargeAmount | Large amount recovery | Handles large token amounts correctly |
| test_RecoverERC20_EmitsEvent | Event emission | TokenRecovered event with correct params |
| testFuzz_RecoverERC20_AnyAmount | Fuzz recovery amounts | Works for any valid token amount |
| test_RecoverERC20_RevertIf_NotManager | Authorization check | Reverts with AccessControlUnauthorizedAccount |
| test_RecoverERC20_RevertsWhenTokenIsVaultAsset | Asset protection | Reverts with InvalidRecoveryTokenAddress when trying to recover main asset |
| test_RecoverERC20_RevertsWhenTokenIsZeroAddress | Zero token validation | Reverts with InvalidRecoveryTokenAddress for zero token |
| test_RecoverERC20_RevertsWhenReceiverIsZeroAddress | Zero receiver validation | Reverts with InvalidRecoveryReceiverAddress for zero receiver |
| test_RecoverERC20_RevertsWhenBalanceIsZero | Empty balance | Reverts with InsufficientRecoveryTokenBalance when balance is 0 |
| test_RecoverERC20_WorksAfterDeposits | Recovery with active vault | Recovery works even when vault has user deposits |
| test_RecoverERC20_SucceedsWhenCallerHasManagerRole | Role-based recovery | Manager role holder can recover tokens |
| test_RecoverERC20_WithDifferentDecimals | Different token decimals | Works with tokens of different decimal precision |
| testFuzz_RecoverERC20_MultipleRecoveries | Fuzz multiple recoveries | Multiple recovery operations work correctly |

---

### Vault.RedeemZero.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Redeem_Success_WhenAssetsEqualOneWei | Minimal redemption | Successfully redeems when assets equal 1 wei |
| testFuzz_Redeem_Revert_DustShares | Dust share redemption | Reverts with InvalidAssetsAmount when redeeming dust shares that round to 0 assets |

---

### Vault.Reentrancy.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Reentrancy_HarvestFeesProtected | Reentrancy protection | harvestFees() is protected with ReentrancyGuard, reverts on reentry |
| test_Reentrancy_DepositProtected | Deposit reentrancy protection | deposit() is protected, cannot reenter during _depositToProtocol |

---

### Vault.EdgeCases.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Deposit_RevertIf_ProtocolSharesIsZero | Protocol zero shares coverage | Reverts with InvalidSharesAmount when protocol returns 0 |
| test_Deposit_EdgeCase_SharesMintedZero_ExtremeRounding | sharesMinted == 0 coverage | Attempts extreme rounding, may be unreachable |
| test_Mint_RevertIf_ProtocolSharesIsZero | Protocol zero shares coverage | Reverts with InvalidSharesAmount when protocol returns 0 |
| test_Mint_EdgeCase_AssetsRequiredZero_ExtremeRounding | assetsRequired == 0 coverage | May be mathematically unreachable |
| test_Withdraw_EdgeCase_SharesBurnedZero_ExtremeRounding | sharesBurned == 0 coverage | May be mathematically unreachable |
| test_HarvestFees_FeeAmountCappedByProfit | feeAmount > profit coverage | Fee correctly capped with ceiling rounding |
| test_HarvestFees_FeeAmountExceedsProfit_CeilingRounding | Aggressive rounding coverage | Safety check prevents fee > profit |
| test_GetPendingFees_FeeAmountCappedByProfit | getPendingFees cap coverage | View function caps fee at profit |
| test_GetPendingFees_CeilingRoundingEdgeCase | View function rounding coverage | Pending fees ≤ profit, no revert |
| testFuzz_HarvestFees_VariousProfitsHighFee | Fuzz harvest 20% fee | Never reverts, treasury receives shares |
| testFuzz_GetPendingFees_VariousProfits | Fuzz pending fees | Never reverts, pending fees ≤ profit |

---

### Vault.ERC4626Compliance.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_PreviewDeposit_MatchesActualDeposit | ERC4626 preview accuracy | Previewed shares = actual shares |
| test_PreviewMint_MatchesActualMint | ERC4626 preview accuracy | Previewed assets = actual assets (±1 wei) |
| test_PreviewWithdraw_MatchesActualWithdraw | ERC4626 preview accuracy | Previewed shares = actual shares (±1 wei) |
| test_PreviewRedeem_MatchesActualRedeem | ERC4626 preview accuracy | Previewed assets = actual assets (±1 wei) |
| test_MaxDeposit_ReturnsMaxUint256 | maxDeposit in normal state | maxDeposit = type(uint256).max when unpaused |
| test_MaxMint_ReturnsMaxUint256 | maxMint in normal state | maxMint = type(uint256).max when unpaused |
| test_MaxWithdraw_ReturnsCorrectAmount | maxWithdraw calculation | maxWithdraw ≈ convertToAssets(user shares) - 1 wei |
| test_MaxRedeem_ReturnsShareBalance | maxRedeem calculation | maxRedeem = balanceOf(user) |
| test_ConvertToShares_RoundsDown | Rounding direction | Round-trip loses precision in vault's favor |
| test_ConvertToAssets_RoundsDown | Rounding direction | Round-trip loses precision in vault's favor |
| test_ConvertToShares_WithZeroAssets | Zero conversion | Returns 0 shares for 0 assets |
| test_ConvertToAssets_WithZeroShares | Zero conversion | Returns 0 assets for 0 shares |
| test_Deposit_SharesMatchPreview | Deposit preview match | Actual shares = previewed shares |
| test_Mint_AssetsMatchPreview | Mint preview match | Actual assets = previewed (±1 wei) |
| test_Withdraw_SharesMatchPreview | Withdraw preview match | Actual shares = previewed (±1 wei) |
| test_Redeem_AssetsMatchPreview | Redeem preview match | Actual assets = previewed (±1 wei) |
| test_Deposit_RoundingFavorsVault | Deposit rounding | User gets fewer shares than exact conversion |
| test_Mint_RoundingFavorsVault | Mint rounding | User pays ≥ previewed assets |
| test_Withdraw_RoundingFavorsVault | Withdraw rounding | User burns more shares than assets worth |
| test_Redeem_RoundingFavorsVault | Redeem rounding | User receives less assets than shares worth |
| testFuzz_PreviewDeposit_AlwaysMatchesActual | Fuzz preview-actual match | Preview matches for any valid deposit |
| testFuzz_Convert_RoundsDown | Fuzz conversion rounding | assets → shares → assets always rounds down |
| testFuzz_MaxDeposit_AlwaysMaxUint256 | Fuzz maxDeposit | Always max uint256 (pause via modifier) |
| testFuzz_WithdrawRedeem_Consistency | Fuzz withdraw-redeem consistency | Redeeming previewWithdraw shares yields ≥ assets |

---

### Vault.PreviewAccuracy.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_PreviewDeposit_ExactMatch | Preview accuracy with profit (deposit) | Fuzz test: previewDeposit() exactly matches deposit() even after 10% profit injection, tests all OFFSET values (1-22), validates formula correctness with fee harvesting and ratio disruption |
| test_PreviewMint_ExactMatch | Preview accuracy with profit (mint) | Fuzz test: previewMint() exactly matches mint() even after 10% profit injection, tests all OFFSET values (1-22), validates that assets required match preview despite share price changes |
| test_PreviewRedeem_ExactMatch | Preview accuracy with profit (redeem) | Fuzz test: previewRedeem() exactly matches redeem() even after 10% profit injection, tests all OFFSET values (1-22), validates pro-rata asset distribution with fee dilution |
| test_PreviewWithdraw_ExactMatch | Preview accuracy with profit (withdraw) | Fuzz test: previewWithdraw() exactly matches withdraw() even after 10% profit injection, tests all OFFSET values (1-22), validates shares burned match preview despite exchange rate changes |

---

## EmergencyVault Tests

### EmergencyVault.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| testFuzz_EmergencyWithdraw_FirstCall_ActivatesEmergencyMode | Emergency activation | emergencyMode = true, snapshot taken, event emitted |
| test_activateEmergencyMode_HappyPath | Manual emergency activation | emergencyMode = true, emergencyTotalAssets set |
| test_activateEmergencyMode_RevertsIfAlreadyActive | Activation idempotency | Reverts with EmergencyModeAlreadyActive |
| testFuzz_EmergencyWithdraw_RecoversAllFunds | Fund recovery | All protocol assets transferred to vault |
| testFuzz_EmergencyWithdraw_MultipleUsers_RecoversTotalAssets | Multi-user recovery | Total assets recovered match deposits |
| testFuzz_EmergencyWithdraw_MultipleCallsAccumulate | Sequential withdrawals | Multiple calls accumulate recovered assets |
| testFuzz_EmergencyWithdraw_EmitsCorrectEvent | Event validation | EmergencyWithdrawal event with correct amounts |
| testFuzz_EmergencyWithdraw_RevertIf_NotEmergencyRole | Authorization check | Reverts without EMERGENCY_ROLE |
| testFuzz_EmergencyWithdraw_RevertIf_AfterRecoveryActivated | State validation | Reverts when recovery already active |
| testFuzz_EmergencyWithdraw_SecondCallDoesNotPauseAgain | Pause idempotency | Subsequent calls don't re-pause |
| testFuzz_activateRecovery_SnapshotsCorrectly | Recovery snapshot | recoveryAssets and recoverySupply set correctly |
| testFuzz_activateRecovery_HarvestsFeesBeforeSnapshot | Pre-recovery harvest | Fees harvested before snapshot |
| testFuzz_activateRecovery_EmitsEvent | Event validation | RecoveryModeActivated event with correct data |
| testFuzz_activateRecovery_AllowsDeclaringLowerAmount | Amount validation | Admin can declare lower amount than actual balance without revert |
| testFuzz_activateRecovery_AllowsPartialRecovery | Partial recovery | Works with partial liquidity (90% recovered) |
| testFuzz_activateRecovery_RevertIf_AlreadyActive | Recovery idempotency | Reverts with RecoveryModeAlreadyActive |
| testFuzz_activateRecovery_RevertIf_EmergencyModeNotActive | State validation | Reverts if emergency mode not active |
| testFuzz_activateRecovery_RevertIf_ZeroVaultBalance | Balance validation | Reverts with InvalidRecoveryAssets if no funds recovered |
| testFuzz_activateRecovery_RevertIf_NotEmergencyRole | Authorization check | Reverts without EMERGENCY_ROLE |
| testFuzz_EmergencyRedeem_ProRataDistribution | Pro-rata redemption | Users receive proportional share of recoveryAssets |
| testFuzz_EmergencyRedeem_MultipleUsers_FairDistribution | Multi-user fairness | All users receive fair pro-rata distribution |
| testFuzz_EmergencyRedeem_ClaimOrderDoesNotMatter | Order independence | Redemption order doesn't affect outcomes |
| testFuzz_EmergencyRedeem_PartialRedeem | Partial redemption | Users can redeem portion of shares |
| testFuzz_EmergencyRedeem_BurnsSharesCorrectly | Share burning | Shares burned, totalSupply decreased |
| testFuzz_EmergencyRedeem_WithApproval | Delegated redemption | Works with approval mechanism |
| testFuzz_EmergencyRedeem_RevertIf_ZeroShares | Zero shares validation | Reverts with InvalidSharesAmount |
| testFuzz_EmergencyRedeem_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with InvalidReceiverAddress |
| testFuzz_EmergencyRedeem_RevertIf_InsufficientShares | Balance check | Reverts with InsufficientShares |
| testFuzz_EmergencyRedeem_RevertIf_NoApproval | Approval requirement | Reverts without approval for delegation |
| testFuzz_EmergencyRedeem_NormalMode | Normal mode operation | Standard redeem() works in normal mode (not emergency/recovery) |
| testFuzz_EmergencyRedeem_RoundingDoesNotBenefitUser | Rounding direction | Floor rounding favors vault |
| test_EmergencyRedeem_MinimalShares | Minimal share redemption | Can redeem minimal share amounts (10^OFFSET) |
| test_EmergencyRedeem_RevertIf_AssetsRoundToZero | Zero assets check | Reverts with InvalidAssetsAmount when assets round to 0 |
| test_HarvestFees_RevertsIf_RecoveryMode | Recovery mode block | harvestFees() reverts with DisabledDuringEmergencyMode in recovery mode |
| test_HarvestFees_RevertsIf_EmergencyMode | Emergency mode block | harvestFees() reverts with DisabledDuringEmergencyMode before recovery activated |
| testFuzz_Withdraw_RevertIf_EmergencyMode | Operation blocking | withdraw() reverts in emergency mode |
| testFuzz_Redeem_RevertIf_EmergencyMode | Operation blocking | redeem() reverts in emergency mode |
| testFuzz_Deposit_RevertIf_EmergencyMode | Operation blocking | deposit() reverts in emergency mode |
| testFuzz_Mint_RevertIf_EmergencyMode | Operation blocking | mint() reverts in emergency mode |
| testFuzz_EmergencyMode_TotalAssets_ReflectsVaultBalance | totalAssets in emergency | totalAssets = vault balance in emergency/recovery |
| test_activateRecovery_RevertIf_ZeroSupply | Zero supply check | Reverts with InvalidRecoverySupply when totalSupply = 0 |
| testFuzz_activateRecovery_WithPartialRecovery | Partial recovery flow | Multiple emergency withdrawals followed by recovery activation |
| test_activateRecovery_TracksImplicitLoss_WithSharePriceDecline | Implicit loss tracking | Tracks loss when vault balance < emergencySnapshot (e.g., 50% burn), emits RecoveryModeActivated with implicitLoss |
| test_activateRecovery_TracksImplicitLoss_WithPartialWithdrawal | Partial withdrawal loss | Tracks implicit loss with partial recovery, distinguishes stuck funds from actual loss |
| test_TreasuryRedeem_DuringRecoveryMode | Treasury recovery redemption | Treasury (RewardDistributor) can redeem fee shares via standard redeem() in recovery mode, receives pro-rata assets |
| test_getProtocolBalance_ReturnsCorrectBalance | Balance query | Returns accurate protocol balance |
| test_convertToAssets_EmergencyModeUsesLiveRatio | Conversion during emergency | convertToAssets returns same live ratio before vs after emergencyWithdraw |
| test_convertToShares_EmergencyModeUsesLiveRatio | Conversion during emergency | convertToShares returns same live ratio before vs after emergencyWithdraw |
| test_previewRedeem_EmergencyModeReverts | Preview blocking (redeem) | previewRedeem reverts with DisabledDuringEmergencyMode while emergency mode is active |
| test_previewRedeem_RecoveryModeUsesSnapshot | Preview accuracy (recovery) | previewRedeem matches recovery snapshot ratio during recovery mode |
| test_previewWithdraw_EmergencyModeReverts | Preview blocking (withdraw) | previewWithdraw reverts with DisabledDuringEmergencyMode during emergency/recovery |
| test_previewDeposit_EmergencyModeReverts | Preview blocking (deposit) | previewDeposit reverts with DisabledDuringEmergencyMode during emergency/recovery |
| test_previewMint_EmergencyModeReverts | Preview blocking (mint) | previewMint reverts with DisabledDuringEmergencyMode during emergency/recovery |

---

## ERC4626Adapter Tests

### ERC4626Adapter.Initialization.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Initialization | State variable setup | ASSET, TARGET_VAULT, TREASURY, OFFSET, rewardFee set |
| test_InitialState | Zero balances/supply | totalSupply, totalAssets, balances = 0 |
| test_TargetVaultApprovalSetup | Infinite approval | Allowance = type(uint256).max for target vault |
| test_Offset_InitialValue | OFFSET setup | OFFSET matches constructor input |
| test_Offset_ProtectsAgainstInflationAttack | Inflation protection | Victim receives fair shares despite donation |
| testFuzz_TotalAssets_ReflectsTargetVaultBalance | totalAssets accuracy | totalAssets = targetVault.convertToAssets(shares) |
| testFuzz_MaxWithdraw | maxWithdraw calculation | maxWithdraw ≈ user's deposit |
| testFuzz_DepositWithdraw_RoundingDoesNotCauseLoss | Round-trip preservation | User recovers ~full balance (±2 wei) |
| test_MultipleDepositsWithdraws_MaintainsAccounting | Multi-operation accounting | Assets ≈ expected after multiple ops |

---

### ERC4626Adapter.Deposit.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| testFuzz_Deposit_EmitsEvent | Event emission | Deposited event with correct params |
| testFuzz_Deposit_MultipleUsers | Multi-user deposits | Each user receives correct shares, totals correct |
| testFuzz_Deposit_UpdatesTargetVaultBalance | Target vault position update | Target shares increase by deposit * 10^OFFSET |
| test_Deposit_RevertIf_TargetVaultReturnsZeroShares | Target vault zero shares | Reverts with TargetVaultDepositFailed |
| test_Deposit_RevertIf_ZeroAmount | Zero amount validation | Reverts with InvalidAssetsAmount |
| test_Deposit_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with InvalidReceiverAddress |
| test_Deposit_RevertIf_Paused | Pause enforcement | Reverts when paused |
| test_Deposit_RevertIf_ExceedsMaxDeposit | Cap enforcement | Reverts when exceeding target vault capacity |

---

### ERC4626Adapter.Withdraw.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| testFuzz_Withdraw_LeavesPositiveShares | Partial withdrawals | Remaining shares > 0, accounting correct |
| testFuzz_Withdraw_EmitsEvent | Event emission | Withdrawn event with correct params |
| testFuzz_Withdraw_RevertIf_InsufficientShares | Balance check | Reverts with InsufficientShares |
| testFuzz_Withdraw_RevertIf_InsufficientLiquidity | Target vault liquidity | Reverts with InsufficientLiquidity at cap |
| testFuzz_Redeem_AllShares | Full redemption | All shares burned, all assets recovered |
| testFuzz_Withdraw_DelegatedWithApproval | Delegated withdrawal | Works with approval, allowance consumed |
| testFuzz_Withdraw_DelegatedRevertIf_InsufficientAllowance | Insufficient allowance | Reverts when allowance insufficient |
| testFuzz_Withdraw_DelegatedRevertIf_NoApproval | No approval | Reverts when no allowance |
| testFuzz_Withdraw_SelfDoesNotRequireApproval | Self-withdrawal | Always succeeds without approval |
| testFuzz_Withdraw_DelegatedWithUnlimitedApproval | Unlimited approval | type(uint256).max not consumed |

---

### ERC4626Adapter.Fees.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_SetRewardFee_Basic | Fee update | Fee updates, event emitted |
| test_SetRewardFee_ToZero | Zero fee | Accepts 0% |
| test_SetRewardFee_ToMaximum | Max fee | Accepts 20% |
| test_SetRewardFee_RevertIf_ExceedsMaximum | Fee bounds | Reverts with InvalidRewardFee |
| test_SetRewardFee_RevertIf_SameValue | Same value check | Reverts with InvalidRewardFee if setting same value |
| test_SetRewardFee_RevertIf_NotFeeManager | Authorization | Reverts with access control error |
| test_SetRewardFee_HarvestsFeesBeforeChange | Pre-change harvest | Treasury receives shares at old rate |
| test_SetRewardFee_UpdatesLastTotalAssets | State update | lastTotalAssets = totalAssets after update |
| test_SetRewardFee_WithFeeManagerRole | Role-based update | Role holder can update |
| test_SetRewardFee_MultipleChanges | Sequential changes | All changes succeed |
| test_HarvestFees_WithProfit | Profit harvest | Treasury receives shares from profit |
| test_HarvestFees_EmitsEvent | Event emission | FeesHarvested event emitted |
| test_HarvestFees_NoProfit | No profit scenario | Treasury receives no shares |
| test_HarvestFees_WithLoss | Loss scenario | Treasury receives no shares |
| test_HarvestFees_UpdatesLastTotalAssets | State update | lastTotalAssets updated |
| test_HarvestFees_WhenTotalSupplyIsZero | Zero supply safety | No revert |
| test_HarvestFees_WhenTotalAssetsIsZero | Zero assets safety | No revert |
| test_HarvestFees_MultipleHarvests | Sequential harvests | Treasury accumulates correctly |
| test_HarvestFees_CalledAutomaticallyOnDeposit | Auto-harvest on deposit | Deposit triggers harvest |
| test_HarvestFees_CalledAutomaticallyOnWithdraw | Auto-harvest on withdraw | Withdraw triggers harvest |
| test_GetPendingFees_WithProfit | Pending fees with profit | Returns correct amount |
| test_GetPendingFees_NoProfit | Pending fees no profit | Returns 0 |
| test_GetPendingFees_WithLoss | Pending fees with loss | Returns 0 |
| test_GetPendingFees_AfterHarvest | Pending fees after harvest | Returns 0 after harvest |
| testFuzz_HarvestFees_WithProfit | Fuzz profit amounts | Treasury receives correct fee shares for any profit |
| testFuzz_HarvestFees_DifferentRewardRates | Fuzz fee rates | Correct fees for any rate 0-20% |
| testFuzz_HarvestFees_MultipleHarvests | Fuzz sequential harvests | Treasury accumulates correctly |

---

### ERC4626Adapter.MaxDeposit.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_MaxDeposit_RespectsTargetVaultLimits | Target cap enforcement | Vault maxDeposit = targetVault.maxDeposit |
| test_MaxDeposit_ReturnsZeroWhenPaused | maxDeposit when paused | maxDeposit = 0 when paused |
| test_MaxMint_RespectsTargetVaultLimits | Target cap for mint | maxMint = convertToShares(targetVault.maxDeposit) |
| test_MaxMint_ReturnsZeroWhenPaused | maxMint when paused | maxMint = 0 when paused |
| test_Deposit_RevertIf_ExceedsMaxDeposit | Deposit cap check | Reverts with ExceedsMaxDeposit |
| test_Mint_RevertIf_ExceedsMaxDeposit | Mint cap check | Reverts when assets required exceed cap |
| test_Mint_ChecksMaxDepositAfterHarvest | Critical: post-harvest cap | Harvest before cap check, assets after fee dilution |
| test_MaxDeposit_UpdatesAfterDeposit | Cap reduction | maxDeposit ≤ initial after deposit |
| test_MaxDeposit_MultipleDepositsApproachingCap | Sequential deposits | maxDeposit decreases, eventually exhausted |
| test_Deposit_WithCap_UpdatesMaxDeposit | Deposit impact on cap | maxDeposit decreases by deposit amount |
| test_Deposit_WithFeeDilution_StaysWithinCap | Harvest before cap check | Total assets ≤ cap despite fee dilution |
| test_Deposit_WithLargeFeeDilution_MaxDepositBecomesZero | Profit over cap | maxDeposit = 0, deposits blocked |
| test_Deposit_ConvertToAssetsVsPreviewDeposit_WithPendingFees | Snapshot vs simulation | previewDeposit accounts for harvest, convertToAssets doesn't |
| test_Mint_WithFeeDilution_StaysWithinCap | Mint with fees | Total assets ≤ cap |
| test_Mint_WithLargeFeeDilution_MaxDepositBecomesZero | Mint when over cap | maxDeposit = 0, mint reverts |
| test_Mint_ConvertToSharesVsPreviewMint_WithPendingFees | Snapshot vs simulation | previewMint accounts for harvest, convertToShares doesn't |
| testFuzz_MaxDeposit_RespectsTargetVaultLimits | Fuzz target vault caps | maxDeposit respects target vault capacity for any cap |
| testFuzz_MaxMint_RespectsTargetVaultLimits | Fuzz maxMint with caps | maxMint = convertToShares(target.maxDeposit) |
| testFuzz_MaxDeposit_DecreasesWithDeposits | Fuzz deposit impact | maxDeposit decreases after deposits |
| testFuzz_Deposit_NearCapacity | Fuzz deposits near cap | Can deposit up to available capacity |

---

### ERC4626Adapter.MaxRedeem.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_MaxRedeem_ReturnsUserBalanceWithFullLiquidity | maxRedeem in normal state | maxRedeem = user balance when target vault has full liquidity |
| test_MaxRedeem_RespectsTargetVaultLiquidityLimits | Liquidity constraints | maxRedeem capped by target vault available assets |
| test_MaxRedeem_ReturnsZeroWhenUserHasNoShares | Zero shares edge case | maxRedeem = 0 for users with no position |
| test_MaxRedeem_ReturnsZeroWhenPaused | Paused state | maxRedeem = 0 when vault is paused |
| test_MaxRedeem_MultipleUsers | Multi-user scenario | Each user gets correct maxRedeem based on their shares |
| test_MaxRedeem_AfterPartialWithdraw | Post-withdrawal state | maxRedeem updates correctly after partial redemption |
| test_MaxRedeem_WithPendingFees | Pending fees impact | maxRedeem accounts for fee dilution |
| test_MaxRedeem_DecreasesProportionally | Proportional reduction | maxRedeem decreases proportionally with liquidity constraints |
| testFuzz_MaxRedeem_MatchesUserBalance | Fuzz user balances | maxRedeem = balanceOf(user) with full liquidity |
| testFuzz_MaxRedeem_RespectsLiquidityCap | Fuzz liquidity limits | maxRedeem respects target vault caps |
| testFuzz_MaxRedeem_IsActuallyRedeemable | Fuzz redemption execution | Can always redeem maxRedeem amount |
| test_MaxRedeem_EmergencyMode_ReturnsUserBalance | Emergency mode behavior | maxRedeem = user balance in emergency mode |
| test_MaxRedeem_RecoveryActive_ReturnsUserBalance | Recovery mode behavior | maxRedeem = user balance when recovery active |
| test_MaxRedeem_EmergencyMode_MultipleUsers | Multi-user emergency | All users can see maxRedeem in emergency |
| test_MaxRedeem_RecoveryActive_AfterPartialRedemption | Recovery partial redemption | maxRedeem updates after partial emergency redemption |
| testFuzz_MaxRedeem_EmergencyMode | Fuzz emergency maxRedeem | maxRedeem always equals user balance in emergency |
| testFuzz_MaxRedeem_RecoveryActive | Fuzz recovery maxRedeem | maxRedeem always equals user balance in recovery |
| test_MaxRedeem_NormalMode_WithZeroLiquidity | Zero liquidity edge case | maxRedeem = 0 when target vault has no liquidity |
| test_MaxRedeem_TransitionFromNormalToEmergency | Mode transition | maxRedeem changes correctly on emergency activation |
| testFuzz_MaxRedeem_ConsistentWithMaxWithdraw | maxRedeem vs maxWithdraw | maxRedeem ≈ convertToShares(maxWithdraw) |
| test_MaxRedeem_WithLargeShareBalance | Large balance handling | Handles large share amounts correctly |
| test_MaxRedeem_WithDustShares | Dust amount handling | Handles very small share amounts |
| testFuzz_MaxRedeem_AlwaysLteUserBalance | Upper bound invariant | maxRedeem ≤ balanceOf(user) in all modes |
| test_MaxRedeem_AfterProfitAccrual | Post-profit state | maxRedeem accounts for profit and fees |
| testFuzz_MaxRedeem_RedeemableImpliesNoRevert | Redeemability check | redeem(maxRedeem) never reverts |
| test_MaxRedeem_ZeroWhenProtocolInsolvent | Protocol insolvency | maxRedeem = 0 when target vault is insolvent |
| testFuzz_MaxRedeem_ProportionalToShares | Proportionality check | maxRedeem proportional to user's share of supply |
| test_MaxRedeem_ConsistentAcrossMultipleCalls | View function stability | Multiple maxRedeem calls return same value |
| testFuzz_MaxRedeem_BoundedByTargetVaultMaxRedeem | Target vault bounds | maxRedeem ≤ target vault's maxRedeem |

---

### ERC4626Adapter.Permit.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Permit_Basic | Basic permit | Signature verified, allowance set, nonce incremented |
| test_Permit_WithdrawAfterPermit | Withdrawal using permit | Permit enables delegated withdrawal |
| test_Permit_RevertIf_Expired | Expiration check | Reverts when deadline passed |
| test_Permit_RevertIf_InvalidSignature | Signature validation | Reverts with invalid signer |
| test_Permit_RevertIf_ReplayAttack | Replay protection | Signature cannot be reused |

---

### ERC4626Adapter.Approval.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_RefreshProtocolApproval_Success | Approval refresh | Approval reset to type(uint256).max |
| test_RefreshProtocolApproval_RevertWhen_NotAdmin | Emergency role authorization | Reverts without EMERGENCY_ROLE |
| test_RefreshProtocolApproval_SetsMaxApproval | Max approval | Allowance = type(uint256).max |
| test_RefreshProtocolApproval_EmitsApprovalEvent | Event emission | Approval event with correct params |
| test_RefreshProtocolApproval_WorksWhenAlreadyMax | Refresh when max | Succeeds without revert |
| test_RefreshProtocolApproval_RestoresDepositFunctionality | Functionality restoration | Refresh enables deposits after approval consumed |
| test_RefreshProtocolApproval_OnlyEmergencyRole | Role requirement | EMERGENCY_ROLE required |
| test_EmergencyWithdraw_RevokesApproval | Approval revocation on emergency | emergencyWithdraw() sets approval to 0 |
| test_EmergencyWithdraw_MultipleCallsWorkWithRevokedApproval | Multiple emergency withdrawals | Subsequent emergencyWithdraw calls work despite revoked approval (redeem doesn't need approval) |
| test_EmergencyWithdraw_DepositFailsAfterRevocation | Deposit blocked after emergency | Approval = 0 after emergency withdrawal |
| test_RefreshProtocolApproval_RestoresAfterEmergencyRevocation | Approval restoration | refreshProtocolApproval() restores approval after emergency revocation |

---

### ERC4626Adapter.DepositUnallocated.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_DepositUnallocatedAssets_Success | Basic unallocated deposit | MANAGER_ROLE deposits idle USDC to target vault, balance clears, totalAssets increases |
| test_DepositUnallocatedAssets_RevertWhen_NotManager | Authorization check | Reverts with AccessControlUnauthorizedAccount for non-MANAGER |
| test_DepositUnallocatedAssets_RevertWhen_EmergencyMode | Emergency mode block | Reverts with DisabledDuringEmergencyMode when emergency active |
| test_DepositUnallocatedAssets_RevertsIf_ZeroBalance | Zero balance check | Reverts with TargetVaultDepositFailed when no idle balance |
| test_DepositUnallocatedAssets_MultipleDonations | Sequential deposits | Multiple donations can be deposited incrementally, totalAssets accumulates |
| test_DepositUnallocatedAssets_AfterDeposit_FeeHarvesting | Fee harvest interaction | Donation deposited as unrealized profit, fees harvested on next operation |
| test_DepositUnallocatedAssets_DonationTreatedAsUnrealizedProfit | Profit attribution | Donation not immediately treated as profit, included in next harvest, lastTotalAssets unchanged |
| test_DepositUnallocatedAssets_RespectsTargetVaultCapacity | Target vault cap enforcement | Only deposits up to target vault available capacity, excess remains idle |
| test_DepositUnallocatedAssets_RevertsWhen_TargetVaultCapacityZero | Zero capacity handling | Reverts with TargetVaultDepositFailed when target vault at capacity |
| test_DepositUnallocatedAssets_PartialDeposit_CanBeCalledAgainLater | Incremental deposits | Partial deposits work with limited capacity, can be called multiple times as capacity increases |

---

### ERC4626Adapter.Recover.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_RecoverERC20_RevertsWhenTokenIsTargetVaultShares | Target vault share protection | Reverts with InvalidRecoveryTokenAddress when trying to recover target vault shares |

---

## RewardDistributor Tests

### RewardDistributor.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Constructor_RevertIf_AdminZeroAddress | Zero admin validation | Reverts with InvalidAdminAddress for zero admin |
| test_Constructor_RevertIf_LengthMismatch | Array length validation | Reverts with InvalidRecipientsLength |
| test_Constructor_RevertIf_ZeroRecipients | Empty array validation | Reverts with InvalidRecipientsLength |
| test_Constructor_RevertIf_RecipientZeroAddress | Zero recipient validation | Reverts with InvalidRecipientAddress |
| test_Constructor_RevertIf_ZeroBasisPoints | Zero basis points validation | Reverts with InvalidBasisPoints |
| test_Constructor_RevertIf_InvalidBasisPoints | Invalid basis points validation | Reverts with InvalidBasisPoints |
| test_Constructor_RevertIf_InvalidBasisPointsSum | Basis points sum validation | Reverts with InvalidBasisPointsSum if ≠ 10000 |
| test_Constructor_RevertIf_DuplicateRecipients | Duplicate validation | Reverts with DuplicateRecipient |
| test_Constructor_SetsRecipientsAndManagerRole | Successful construction | Manager has MANAGER_ROLE, recipients stored, getAllRecipients works |
| testFuzz_Constructor_SucceedsWithValidTwoWaySplit | Fuzz two-way splits | Accepts any split summing to 10000 |
| test_ReplaceRecipient_Succeeds | Recipient replacement | Successfully replaces recipient address |
| test_ReplaceRecipient_RevertIf_NotRecipientsManager | Authorization check | Reverts with AccessControlUnauthorizedAccount |
| test_ReplaceRecipient_RevertIf_InvalidIndex | Index validation | Reverts with InvalidRecipientIndex |
| test_ReplaceRecipient_RevertIf_ZeroAddress | Zero address validation | Reverts with InvalidRecipientAddress |
| test_ReplaceRecipient_RevertIf_DuplicateAddress | Duplicate check | Reverts with DuplicateRecipient |
| test_ReplaceRecipient_RevertIf_Unchanged | Unchanged check | Reverts with InvalidRecipientAddress if same address |
| test_ReplaceRecipient_RevertIf_AdminOnly | Role requirement | Reverts when admin tries without RECIPIENTS_MANAGER_ROLE |
| test_Distribute_RevertIf_NoBalance | Empty balance check | Reverts with InsufficientBalance |
| test_Distribute_RevertIf_NotManager | Manager authorization | Reverts with AccessControlUnauthorizedAccount |
| test_Distribute_DistributesAccordingToBps | Proportional distribution | Each recipient receives correct %, events emitted |
| testFuzz_Distribute_TwoRecipients | Fuzz distribution | Correct for any split/amount, rounding dust remains |
| test_Redeem_RevertIf_NoShares | Empty shares check | Reverts with NoAvailableSharesToRedeem |
| test_Redeem_RevertIf_NotManager | Manager authorization | Reverts with AccessControlUnauthorizedAccount |
| test_Redeem_SendsAssetsAndEmitsEvent | Redemption | All shares redeemed, assets transferred, event emitted |
| test_Redeem_RespectsMaxRedeemLimit | Max redeem enforcement | Respects vault maxRedeem limit when shares exceed capacity |
| test_Redeem_DistributorAfterEmergencyRecovery | Emergency recovery redemption | Distributor can redeem shares after vault emergency recovery |

---

## Invariant Tests

### Vault.invariant.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| invariant_ConversionRoundTrip | assets → shares → assets conversion | Round-trip accurate within 0.01%, no significant loss |
| invariant_TotalSupplyEqualsSumOfBalances | Supply accounting | totalSupply = Σ balanceOf(user), integrity maintained |
| invariant_VaultHasAssetsWhenHasShares | Share backing | totalSupply > 0 → totalAssets > 0, no orphan shares |
| invariant_callSummary | Test execution summary | Shows deposit/withdraw/mint/redeem counts, final state |

---

### RewardDistribution.invariant.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| invariant_TreasurySharesMintedOnlyWithProfit | Critical: fees only on profit | treasuryMintsWithoutProfit = 0, fees never on capital |
| invariant_TreasuryReceivesSharesWhenProfit | Fee collection | When profit harvested, treasury gets shares |
| invariant_LastTotalAssetsNeverExceedsCurrent | lastTotalAssets integrity | lastTotalAssets ≤ totalAssets, harvest logic correct |
| invariant_RewardFeeWithinLimits | Fee bounds | rewardFee ≤ MAX_REWARD_FEE_BASIS_POINTS |
| invariant_callSummary | Test execution summary | Shows ops, treasury mints, cumulative profit, expected vs actual shares |

---

## Integration Tests

### Solvency.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Solvency_WithRandomCycles | Comprehensive solvency | 100 random deposit/withdraw cycles across 256 users, periodic profit injections (10K USDC every 10 cycles), validates: totalAssets ≈ netDeposited + totalProfit (±9 wei), all users can redeem, vault ends with ≤9 wei dust |
| test_EmergencySolvency_AllUsersRedeemVaultEmpty | Emergency recovery solvency | 32 users deposit, profit added, emergency withdrawal triggered, recovery activated, all users redeem via emergencyRedeem(), validates: pro-rata distribution fair, vault balance = 0, totalSupply = 0, treasury shares redeemed |

---

### Donation.t.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Donation_SharesDonatedToVault | Donation handling | External party deposits into target vault and transfers shares to our vault, donated shares counted as profit, fee harvest triggered on donation, treasury receives fee shares from total profit (target vault gains + donation), users can withdraw proportionally |

---

### morpho-vault.integration.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_FullEmergencyCycle_AllVaults | Comprehensive emergency flow across all Morpho vaults | Forks mainnet, tests full 9-phase emergency cycle for all 3 vaults (Steakhouse USDC, USDT, WETH): Phase 1 - multi-user deposits with balance validation, Phase 2 - profit injection (50M USDC / 50k WETH), Phase 3 - partial withdrawal with balance checks, Phase 4 - emergency mode activation, Phase 5 - emergency withdrawal from Morpho, Phase 6 - recovery activation, Phase 7 - users emergency redeem with token balance verification, Phase 8 - treasury fee redemption with balance checks, Phase 9 - comprehensive validation (all shares burned, vault drained ≤10 wei, pro-rata distribution correct ±1e15, total distribution accounting ±10 wei), requires MAINNET_RPC_URL env var |

---

### reward-distribution.integration.sol

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_RewardDistribution_HappyPath | End-to-end reward flow | Multi-user deposits (Alice, Bob, Charlie), 3 profit injections (0.1%, 0.1%, 0.2%), fee harvesting on each operation, users withdraw all, RewardDistributor redeems vault shares, distributes to 2 recipients (5% / 95% split), validates: fee calculations accurate, treasury accumulation correct, distribution matches basis points, final balances correct (±2 wei) |

---

## Test Execution

```bash
# Run all tests (default: 6-decimal asset)
forge test

# Run with 18-decimal asset
ASSET_DECIMALS=18 forge test

# Run both decimal configurations
forge test && ASSET_DECIMALS=18 forge test

# Run specific category
forge test --match-path "test/unit/vault/**/*.sol"
forge test --match-path "test/unit/erc4626-adapter/**/*.sol"
forge test --match-path "test/unit/emergency-vault/**/*.sol"
forge test --match-path "test/unit/reward-distributor/**/*.sol"
forge test --match-path "test/invariant/**/*.sol"
forge test --match-path "test/integration/**/*.sol"

# Run specific test file
forge test --match-path test/unit/vault/Vault.Deposit.t.sol

# Run specific test function
forge test --match-test test_Deposit_Basic

# Run with verbosity
forge test -vvvv

# Gas report
forge test --gas-report

# Run mainnet integration tests (requires RPC)
MAINNET_RPC_URL=<your_rpc> forge test --match-path "test/integration/mainnet/**/*.sol"
```
