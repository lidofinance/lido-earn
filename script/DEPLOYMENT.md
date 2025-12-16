# Deployment Guide

## 1. Deploy RewardDistributor

### Step 1: Set environment variables

```bash
export DISTRIBUTOR_MANAGER=0x0000000000000000000000000000000000000000
export DISTRIBUTOR_RECIPIENT_COUNT=2
export DISTRIBUTOR_RECIPIENT_0_ADDRESS=0x0000000000000000000000000000000000000000
export DISTRIBUTOR_RECIPIENT_0_BPS=7000
export DISTRIBUTOR_RECIPIENT_1_ADDRESS=0x0000000000000000000000000000000000000000
export DISTRIBUTOR_RECIPIENT_1_BPS=3000
```

### Step 2: Deploy

```bash
forge script script/DeployRewardDistributor.s.sol:DeployRewardDistributor \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### Step 3: Save distributor address

```bash
export DISTRIBUTOR_ADDRESS=<deployed_address>
```

## 2. Deploy Vault

### Step 1: Set environment variables

```bash
export VAULT_ASSET=0x0000000000000000000000000000000000000000
export VAULT_TARGET_VAULT=0x0000000000000000000000000000000000000000
export VAULT_TREASURY=$DISTRIBUTOR_ADDRESS
export VAULT_ADMIN=0x0000000000000000000000000000000000000000
export VAULT_REWARD_FEE=500
export VAULT_DECIMALS_OFFSET=10
export VAULT_NAME="Vault Name"
export VAULT_SYMBOL="SYMBOL"
```

### Step 2: Deploy

```bash
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```
