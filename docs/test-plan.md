# Test plan

---

## Environment Overrides

- All tests default to a 6-decimal mock asset. Set `ASSET_DECIMALS=18` (or any `uint8` value) before running `forge test` to rerun the full suite against an asset with the desired precision. No changes to the test selection are required—just run the command twice with the different env values.

---

## Vault Tests

### Vault.Constructor.t.sol (17 tests)

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
| test_Constructor_RevertWhen_AssetIsZeroAddress | Zero asset validation | Reverts with ZeroAddress |
| test_Constructor_RevertWhen_TreasuryIsZeroAddress | Zero treasury validation | Reverts with ZeroAddress |
| test_Constructor_RevertWhen_OffsetTooHigh | Offset bounds check | Reverts with OffsetTooHigh for offset > 23 |
| test_Constructor_RevertWhen_RewardFeeExceedsMax | Fee bounds check | Reverts with InvalidFee for fee > 2000 |
| testFuzz_Constructor_ValidRewardFee | Fuzz valid fees 0-2000 | All valid fees accepted |
| testFuzz_Constructor_ValidOffset | Fuzz valid offsets 0-23 | All valid offsets accepted |
| testFuzz_Constructor_InvalidRewardFee | Fuzz invalid fees >2000 | All invalid fees rejected |
| testFuzz_Constructor_InvalidOffset | Fuzz invalid offsets >23 | All invalid offsets rejected |
| test_MorphoConstructor_RevertWhen_MorphoVaultIsZeroAddress | Morpho vault validation | Reverts with MorphoVaultZeroAddress |

---

### Vault.Initialization.t.sol (6 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Initialization | Initial state setup | Asset, treasury, offset, fee, name, symbol, decimals |
| test_InitialState | Zero balances/supply | totalSupply = 0, totalAssets = 0 |
| test_InitialRolesAssigned | Role assignment | All roles granted to deployer |
| test_InitialPausedState | Pause state | paused() = false |
| test_InitialRewardFeeAndLastAssets | Fee state | rewardFee set, lastTotalAssets = 0 |
| test_MinFirstDepositConstant | Constant value | MIN_FIRST_DEPOSIT = 1000 |

---

### Vault.Deposit.t.sol (24 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Deposit_Basic | Basic deposit | Shares minted = assets * 10^OFFSET, balances updated |
| test_Deposit_EmitsEvent | Event emission | Deposited event with correct params |
| test_Deposit_MultipleUsers | Multi-user deposits | Each user gets correct shares, totals updated |
| test_Deposit_RevertIf_ZeroAmount | Zero amount validation | Reverts with ZeroAmount |
| test_Deposit_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with ZeroAddress |
| test_Deposit_RevertIf_Paused | Pause enforcement | Reverts with EnforcedPause |
| test_FirstDeposit_RevertIf_TooSmall | First deposit minimum | Reverts if deposit < MIN_FIRST_DEPOSIT |
| test_FirstDeposit_SuccessIf_MinimumMet | First deposit success | MIN_FIRST_DEPOSIT accepted, shares minted |
| test_SecondDeposit_CanBeSmall | Subsequent deposits | Allows deposits of 1 wei after first |
| test_Mint_Basic | Basic mint | Exact shares minted, assets match preview |
| test_Mint_RevertIf_ZeroShares | Zero shares validation | Reverts with ZeroAmount |
| test_Mint_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with ZeroAddress |
| test_Mint_RevertIf_FirstDepositTooSmall | First mint minimum | Reverts if assets < MIN_FIRST_DEPOSIT |
| test_Mint_RevertIf_Paused | Pause enforcement | Reverts with EnforcedPause |
| test_PreviewDeposit_Accurate | Preview accuracy | Previewed shares = actual shares |
| test_Offset_ProtectsAgainstInflationAttack | Inflation attack protection | Victim gets fair shares despite donation |
| test_Deposit_RevertIf_ProtocolSharesIsZero | Protocol zero shares | Reverts when protocol returns 0 shares |
| test_Mint_RevertIf_ProtocolSharesIsZero | Protocol zero shares | Reverts when protocol returns 0 shares |
| testFuzz_Deposit_Success | Fuzz deposits | Shares match preview for any valid amount |
| testFuzz_Mint_Success | Fuzz mints | Assets match preview for any valid amount |
| testFuzz_Deposit_WithExistingDeposits | Fuzz sequential deposits | Share price stable, accounting correct |
| testFuzz_Deposit_RoundingFavorsVault | Rounding direction | User receives ≤ previewed shares |
| testFuzz_Mint_RoundingFavorsVault | Rounding direction | User pays ≥ previewed assets |

---

### Vault.Withdraw.t.sol (36 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Withdraw_Basic | Basic withdrawal | Shares burned match preview, assets received |
| test_Withdraw_RevertIf_ZeroAmount | Zero amount validation | Reverts with ZeroAmount |
| test_Withdraw_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with ZeroAddress |
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
| test_Redeem_RevertIf_ZeroShares | Zero shares validation | Reverts with ZeroAmount |
| test_Redeem_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with ZeroAddress |
| test_Redeem_RevertIf_NoApproval | Approval requirement | Reverts with ERC20InsufficientAllowance |
| test_Redeem_DelegatedWithApproval | Delegated redemption | Works with approval, allowance consumed |
| test_Redeem_WorksWhenPaused | Pause behavior | Redemption succeeds despite pause |
| test_Redeem_RevertIf_InsufficientShares | Balance check | Reverts with InsufficientShares |
| test_PreviewWithdraw_Accurate | Preview accuracy | Previewed shares = actual shares burned |
| test_PreviewWithdraw_WithPendingFees | Preview with fees | Accounts for fee harvesting |
| test_PreviewRedeem_WithPendingFees_Accurate | Preview with fees | Matches actual assets (±2 wei) |
| test_MaxWithdraw | maxWithdraw calculation | Returns withdrawable amount |
| test_MaxWithdraw_WithPendingFees_ShouldNotRevert | maxWithdraw with fees | No revert, amount withdrawable |
| testFuzz_MaxWithdraw_IsActuallyWithdrawable | Fuzz maxWithdraw | maxWithdraw always withdrawable, ≤10^OFFSET dust |
| test_DepositWithdraw_RoundingDoesNotCauseLoss | Round-trip preservation | Full balance recovered |
| test_MultipleDepositsWithdraws_MaintainsAccounting | Multi-operation accounting | Share-asset conversions accurate |
| test_TotalAssets | totalAssets accuracy | totalAssets = deposited amount |
| testFuzz_Withdraw_Success | Fuzz withdrawals | Shares burned match preview |
| testFuzz_Redeem_Success | Fuzz redemptions | Assets match preview |
| testFuzz_Withdraw_WithMultipleUsers | Fuzz multi-user | One withdrawal doesn't affect others |
| testFuzz_Withdraw_RoundingFavorsVault | Rounding direction | User burns ≥ previewed shares (±2 wei) |
| testFuzz_Redeem_RoundingFavorsVault | Rounding direction | User receives ≤ previewed assets (±2 wei) |

---

### Vault.Fees.t.sol (26 tests)

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

### Vault.AccessControl.t.sol (11 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_AdminRole_DefaultAdmin | Admin role assignment | Deployer has DEFAULT_ADMIN_ROLE |
| test_PauserRole_GrantAndRevoke | PAUSER_ROLE management | Admin can grant/revoke, status changes |
| test_FeeManagerRole_GrantAndRevoke | FEE_MANAGER_ROLE management | Admin can grant/revoke |
| test_EmergencyRole_GrantAndRevoke | EMERGENCY_ROLE management | Admin can grant/revoke |
| test_AccessControl_RevertIf_NonAdminGrantsRole | Non-admin grant attempt | Reverts with AccessControlUnauthorizedAccount |
| test_AccessControl_RevertIf_NonAdminRevokesRole | Non-admin revoke attempt | Reverts with AccessControlUnauthorizedAccount |
| test_AccessControl_MultipleRoleHolders | Multiple role holders | Multiple pausers can pause/unpause |
| test_AccessControl_RoleAdminOfRole | Role admin | DEFAULT_ADMIN_ROLE is admin of all roles |
| test_AccessControl_RenounceRole | Role renouncement | Role holder can renounce, status updates |
| test_AccessControl_RenounceRole_RevertIf_CallerDiffers | Renounce validation | Reverts with AccessControlBadConfirmation |
| test_AccessControl_DeployerGetsAllRoles | Initial roles | Deployer has admin, pauser, fee manager, emergency |

---

### Vault.Pausable.t.sol (16 tests)

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

### Vault.Emergency.t.sol (13 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_EmergencyWithdraw_Basic | Basic emergency withdrawal | All assets transferred, totalAssets = 0 |
| test_EmergencyWithdraw_RevertIf_NotEmergencyRole | Emergency authorization | Reverts with AccessControlUnauthorizedAccount |
| test_EmergencyWithdraw_WithEmergencyRole | EMERGENCY_ROLE withdrawal | Role holder can trigger withdrawal |
| test_EmergencyWithdraw_WithZeroAssets | Empty vault emergency | Succeeds, receiver gets 0 |
| test_EmergencyWithdraw_RevertIf_ReceiverZeroAddress | Zero receiver validation | Reverts with ZeroAddress |
| test_EmergencyWithdraw_DoesNotAffectShares | User shares after emergency | totalSupply and balances unchanged |
| test_EmergencyWithdraw_PausesVault | Vault state after emergency | Vault becomes paused |
| test_EmergencyWithdraw_EmitsEventAndTransfersProfit | Event and profit transfer | EmergencyWithdrawal event, all assets transferred |
| test_EmergencyWithdraw_WhenAlreadyPaused | Emergency when paused | Succeeds, assets transferred |
| test_EmergencyWithdraw_MultipleDepositors | Multi-depositor emergency | All depositors' assets recovered |
| test_EmergencyWithdraw_UsersCanWithdrawAfter | User withdrawals after emergency | Users retain shares, can redeem if assets restored |
| test_EmergencyWithdraw_BlocksNewDeposits | Deposits after emergency | Deposit reverts with EnforcedPause |
| testFuzz_EmergencyWithdraw_ResetsLastTotalAssets | lastTotalAssets reset | lastTotalAssets = 0 after emergency |

---

### Vault.Config.t.sol (10 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_SetRewardFee_Basic | Basic fee update | rewardFee updated, RewardFeeUpdated event |
| test_SetRewardFee_ToZero | Zero fee | Accepts 0%, event emitted |
| test_SetRewardFee_ToMaximum | Max fee | Accepts MAX_REWARD_FEE (20%), event emitted |
| test_SetRewardFee_RevertIf_ExceedsMaximum | Fee bounds | Reverts with InvalidFee |
| test_SetRewardFee_RevertIf_NotFeeManager | Fee manager authorization | Reverts with AccessControlUnauthorizedAccount |
| test_SetRewardFee_HarvestsFeesBeforeChange | Pre-change harvest | Pending fees harvested at old rate |
| test_SetRewardFee_UpdatesLastTotalAssets | State update | lastTotalAssets = totalAssets after update |
| test_SetRewardFee_WithFeeManagerRole | FEE_MANAGER_ROLE update | Role holder can update fee |
| test_SetRewardFee_MultipleChanges | Sequential changes | Each change succeeds, events emitted |
| testFuzz_SetRewardFee_WithinBounds | Fuzz valid fees | Any value 0-MAX_REWARD_FEE accepted |
| test_SetTreasury_Basic | Treasury update | DEFAULT_ADMIN_ROLE can update treasury, event emitted |
| test_SetTreasury_RevertIf_ZeroAddress | Input validation | Reverts with ZeroAddress for zero treasury |
| test_SetTreasury_RevertIf_SameAddress | No-op prevention | Reverts with InvalidTreasuryAddress if address is unchanged |
| test_SetTreasury_RevertIf_NotFeeManager | Access control | Only FEE_MANAGER_ROLE can update treasury |
| test_SetTreasury_DoesNotTransferExistingShares | Fee accounting | Legacy treasury shares remain with old address, future fees go to new |

---

### Vault.Permit.t.sol (7 tests)

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

### Vault.EdgeCases.t.sol (13 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Deposit_RevertIf_ProtocolSharesIsZero | Protocol zero shares coverage | Reverts with ZeroAmount when protocol returns 0 |
| test_Deposit_EdgeCase_SharesMintedZero_ExtremeRounding | sharesMinted == 0 coverage | Attempts extreme rounding, may be unreachable |
| test_Mint_RevertIf_ProtocolSharesIsZero | Protocol zero shares coverage | Reverts with ZeroAmount when protocol returns 0 |
| test_Mint_EdgeCase_AssetsRequiredZero_ExtremeRounding | assetsRequired == 0 coverage | May be mathematically unreachable |
| test_Withdraw_EdgeCase_SharesBurnedZero_ExtremeRounding | sharesBurned == 0 coverage | May be mathematically unreachable |
| test_HarvestFees_FeeAmountCappedByProfit | feeAmount > profit coverage | Fee correctly capped with ceiling rounding |
| test_HarvestFees_FeeAmountExceedsProfit_CeilingRounding | Aggressive rounding coverage | Safety check prevents fee > profit |
| test_GetPendingFees_FeeAmountCappedByProfit | getPendingFees cap coverage | View function caps fee at profit |
| test_GetPendingFees_CeilingRoundingEdgeCase | View function rounding coverage | Pending fees ≤ profit, no revert |
| test_EdgeCase_DepositAfterMultipleDeposits_ZeroProtocolShares | Multi-deposit zero shares | Reverts with ZeroAmount |
| test_EdgeCase_MintAfterDeposits_ZeroProtocolShares | Mint zero shares coverage | Reverts with ZeroAmount |
| testFuzz_HarvestFees_VariousProfitsHighFee | Fuzz harvest 20% fee | Never reverts, treasury receives shares |
| testFuzz_GetPendingFees_VariousProfits | Fuzz pending fees | Never reverts, pending fees ≤ profit |

---

### Vault.ERC4626Compliance.t.sol (23 tests)

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

## MorphoAdapter Tests

### MorphoAdapter.Initialization.t.sol (10 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Initialization | State variable setup | ASSET, MORPHO_VAULT, TREASURY, OFFSET, rewardFee set |
| test_InitialState | Zero balances/supply | totalSupply, totalAssets, balances = 0 |
| test_MorphoApprovalSetup | Infinite approval | Allowance = type(uint256).max for Morpho |
| test_Offset_InitialValue | OFFSET setup | OFFSET matches constructor input |
| test_Offset_ProtectsAgainstInflationAttack | Inflation protection | Victim receives fair shares despite donation |
| testFuzz_TotalAssets_ReflectsMorphoBalance | totalAssets accuracy | totalAssets = Morpho convertToAssets(shares) |
| testFuzz_MaxWithdraw | maxWithdraw calculation | maxWithdraw ≈ user's deposit |
| testFuzz_DepositWithdraw_RoundingDoesNotCauseLoss | Round-trip preservation | User recovers ~full balance (±2 wei) |
| test_MultipleDepositsWithdraws_MaintainsAccounting | Multi-operation accounting | Assets ≈ expected after multiple ops |

---

### MorphoAdapter.Deposit.t.sol (10 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| testFuzz_Deposit_EmitsEvent | Event emission | Deposited event with correct params |
| testFuzz_Deposit_MultipleUsers | Multi-user deposits | Each user receives correct shares, totals correct |
| testFuzz_Deposit_UpdatesMorphoBalance | Morpho position update | Morpho shares increase by deposit * 10^OFFSET |
| test_Deposit_RevertIf_MorphoReturnsZeroShares | Morpho zero shares | Reverts with MorphoDepositFailed |
| test_Deposit_RevertIf_ZeroAmount | Zero amount validation | Reverts with ZeroAmount |
| test_Deposit_RevertIf_ZeroReceiver | Zero receiver validation | Reverts with ZeroAddress |
| test_Deposit_RevertIf_Paused | Pause enforcement | Reverts when paused |
| test_FirstDeposit_RevertIf_TooSmall | First deposit minimum | Reverts with FirstDepositTooSmall |
| testFuzz_FirstDeposit_SuccessIf_MinimumMet | Fuzz valid first deposits | Accepts any amount ≥ MIN_FIRST_DEPOSIT |

---

### MorphoAdapter.Withdraw.t.sol (10 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| testFuzz_Withdraw_LeavesPositiveShares | Partial withdrawals | Remaining shares > 0, accounting correct |
| testFuzz_Withdraw_EmitsEvent | Event emission | Withdrawn event with correct params |
| testFuzz_Withdraw_RevertIf_InsufficientShares | Balance check | Reverts with InsufficientShares |
| testFuzz_Withdraw_RevertIf_InsufficientLiquidity | Morpho liquidity | Reverts with InsufficientLiquidity at cap |
| testFuzz_Redeem_AllShares | Full redemption | All shares burned, all assets recovered |
| testFuzz_Withdraw_DelegatedWithApproval | Delegated withdrawal | Works with approval, allowance consumed |
| testFuzz_Withdraw_DelegatedRevertIf_InsufficientAllowance | Insufficient allowance | Reverts when allowance insufficient |
| testFuzz_Withdraw_DelegatedRevertIf_NoApproval | No approval | Reverts when no allowance |
| testFuzz_Withdraw_SelfDoesNotRequireApproval | Self-withdrawal | Always succeeds without approval |
| testFuzz_Withdraw_DelegatedWithUnlimitedApproval | Unlimited approval | type(uint256).max not consumed |

---

### MorphoAdapter.Fees.t.sol (23 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_SetRewardFee_Basic | Fee update | Fee updates, event emitted |
| test_SetRewardFee_ToZero | Zero fee | Accepts 0% |
| test_SetRewardFee_ToMaximum | Max fee | Accepts 20% |
| test_SetRewardFee_RevertIf_ExceedsMaximum | Fee bounds | Reverts with InvalidFee |
| test_SetRewardFee_RevertIf_NotFeeManager | Authorization | Reverts with access control error |
| test_SetRewardFee_HarvestsFeesBeforeChange | Pre-change harvest | Treasury receives shares at old rate |
| test_SetRewardFee_UpdatesLastTotalAssets | State update | lastTotalAssets = totalAssets after update |
| test_SetRewardFee_WithFeeManagerRole | Role-based update | Role holder can update |
| test_SetRewardFee_MultipleChanges | Sequential changes | All changes succeed |
| test_HarvestFees_WithProfit | Morpho profit harvest | Treasury receives shares from profit |
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

---

### MorphoAdapter.Emergency.t.sol (3 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_EmergencyWithdraw_ReturnsZeroWhenNoShares | Empty position emergency | Returns 0, receiver gets 0 |
| test_EmergencyWithdraw_RedeemsMorphoShares | Morpho shares redemption | All shares redeemed, assets transferred, balance = 0 |
| test_EmergencyWithdraw_WithLiquidityCap | Emergency withdrawal with liquidity cap | Withdraws up to cap, then remaining after cap removal |

---

### MorphoAdapter.MaxDeposit.t.sol (17 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_MaxDeposit_RespectsMorphoLimits | Morpho cap enforcement | Vault maxDeposit = Morpho maxDeposit |
| test_MaxDeposit_ReturnsZeroWhenPaused | maxDeposit when paused | maxDeposit = 0 when paused |
| test_MaxMint_RespectsMorphoLimits | Morpho cap for mint | maxMint = convertToShares(Morpho maxDeposit) |
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

---

### MorphoAdapter.Permit.t.sol (5 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Permit_Basic | Basic permit | Signature verified, allowance set, nonce incremented |
| test_Permit_WithdrawAfterPermit | Withdrawal using permit | Permit enables delegated withdrawal |
| test_Permit_RevertIf_Expired | Expiration check | Reverts when deadline passed |
| test_Permit_RevertIf_InvalidSignature | Signature validation | Reverts with invalid signer |
| test_Permit_RevertIf_ReplayAttack | Replay protection | Signature cannot be reused |

---

### MorphoAdapter.Approval.t.sol (7 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_RefreshMorphoApproval_Success | Approval refresh | Approval reset to type(uint256).max |
| test_RefreshMorphoApproval_RevertWhen_NotAdmin | Admin authorization | Reverts without DEFAULT_ADMIN_ROLE |
| test_RefreshMorphoApproval_SetsMaxApproval | Max approval | Allowance = type(uint256).max |
| test_RefreshMorphoApproval_EmitsApprovalEvent | Event emission | Approval event with correct params |
| test_RefreshMorphoApproval_WorksWhenAlreadyMax | Refresh when max | Succeeds without revert |
| test_RefreshMorphoApproval_RestoresDepositFunctionality | Functionality restoration | Refresh enables deposits after approval consumed |
| test_RefreshMorphoApproval_OnlyAdminRole | Role requirement | DEFAULT_ADMIN_ROLE required |

---

## RewardDistributor Tests

### RewardDistributor.t.sol (14 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| test_Constructor_RevertIf_LengthMismatch | Array length validation | Reverts with InvalidRecipientsLength |
| test_Constructor_RevertIf_ZeroRecipients | Empty array validation | Reverts with InvalidRecipientsLength |
| test_Constructor_RevertIf_ZeroAddress | Zero address validation | Reverts with ZeroAddress |
| test_Constructor_RevertIf_ZeroBasisPoints | Zero basis points validation | Reverts with ZeroBasisPoints |
| test_Constructor_RevertIf_InvalidBasisPointsSum | Basis points sum validation | Reverts with InvalidBasisPointsSum if ≠ 10000 |
| test_Constructor_RevertIf_DuplicateRecipients | Duplicate validation | Reverts with DuplicateRecipient |
| test_Constructor_SetsRecipientsAndManagerRole | Successful construction | Manager has MANAGER_ROLE, recipients stored, getAllRecipients works |
| testFuzz_Constructor_SucceedsWithValidTwoWaySplit | Fuzz two-way splits | Accepts any split summing to 10000 |
| test_Distribute_RevertIf_NoBalance | Empty balance check | Reverts with NoBalance |
| test_Distribute_RevertIf_NotManager | Manager authorization | Reverts with AccessControlUnauthorizedAccount |
| test_Distribute_DistributesAccordingToBps | Proportional distribution | Each recipient receives correct %, events emitted |
| testFuzz_Distribute_TwoRecipients | Fuzz distribution | Correct for any split/amount, rounding dust remains |
| test_Redeem_RevertIf_NoShares | Empty shares check | Reverts with NoShares |
| test_Redeem_RevertIf_NotManager | Manager authorization | Reverts with AccessControlUnauthorizedAccount |
| test_Redeem_SendsAssetsAndEmitsEvent | Redemption | All shares redeemed, assets transferred, event emitted |

---

## Invariant Tests

### Vault.invariant.t.sol (5 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| invariant_ConversionRoundTrip | assets → shares → assets conversion | Round-trip accurate within 0.01%, no significant loss |
| invariant_TotalSupplyEqualsSumOfBalances | Supply accounting | totalSupply = Σ balanceOf(user), integrity maintained |
| invariant_VaultHasAssetsWhenHasShares | Share backing | totalSupply > 0 → totalAssets > 0, no orphan shares |
| invariant_callSummary | Test execution summary | Shows deposit/withdraw/mint/redeem counts, final state |

---

### RewardDistribution.invariant.t.sol (5 tests)

| Test Name | What It Tests | Key Checks |
|-----------|---------------|------------|
| invariant_TreasurySharesMintedOnlyWithProfit | Critical: fees only on profit | treasuryMintsWithoutProfit = 0, fees never on capital |
| invariant_TreasuryReceivesSharesWhenProfit | Fee collection | When profit harvested, treasury gets shares |
| invariant_LastTotalAssetsNeverExceedsCurrent | lastTotalAssets integrity | lastTotalAssets ≤ totalAssets, harvest logic correct |
| invariant_RewardFeeWithinLimits | Fee bounds | rewardFee ≤ MAX_REWARD_FEE_BASIS_POINTS |
| invariant_callSummary | Test execution summary | Shows ops, treasury mints, cumulative profit, expected vs actual shares |

---

## Test Execution

```bash
# Run all tests
forge test

# Run specific category
forge test --match-path "test/unit/vault/**/*.sol"
forge test --match-path "test/unit/morpho-adapter/**/*.sol"
forge test --match-path "test/unit/reward-distributor/**/*.sol"
forge test --match-path "test/invariant/**/*.sol"

# Run specific test file
forge test --match-path test/unit/vault/Vault.Deposit.t.sol

# Run specific test function
forge test --match-test test_Deposit_Basic

# Run with verbosity
forge test -vvvv

# Gas report
forge test --gas-report
```

---

## Key Testing Patterns

**Security Focus:**
- Reentrancy protection, access control enforcement, zero address checks
- Overflow/underflow scenarios, inflation attack protection

**ERC4626 Compliance:**
- Preview function accuracy (accounts for harvest)
- Rounding always favors vault
- Max functions respect protocol limits

**Integration Testing:**
- Morpho vault interaction, capacity limit respect
- Fee harvesting with external profit, emergency scenarios
- `test/integration/Solvency.t.sol::test_Solvency_WithRandomCycles` — randomized deposit/withdraw cycles across 32 actors with periodic profit injections; validates solvency, treasury fee redemption, and that the vault ends with zero residual assets under sub-10 wei tolerances

**Edge Cases:**
- Zero amounts, first deposit minimum, extreme rounding
- Protocol returning zero shares, fee amount exceeding profit

---

*Generated: 2025-01-12*
*Total Tests: ~301*
*Coverage: Comprehensive across all contract functionality*
