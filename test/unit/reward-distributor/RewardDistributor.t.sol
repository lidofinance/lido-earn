// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestConfig} from "test/utils/TestConfig.sol";
import {Vm} from "forge-std/Vm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {RewardDistributor} from "src/RewardDistributor.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {MockERC4626Vault} from "test/mocks/MockERC4626Vault.sol";

contract RewardDistributorTest is TestConfig {
    MockERC20 internal asset;
    MockVault internal vault;

    address internal admin = makeAddr("admin");
    address internal nonManager = makeAddr("nonManager");
    address internal recipientA = makeAddr("recipientA");
    address internal recipientB = makeAddr("recipientB");
    address internal treasury = makeAddr("treasury");

    uint16 internal constant REWARD_FEE = 500;
    uint8 internal constant OFFSET = 6;
    uint256 internal constant MAX_BPS = 10_000;

    function setUp() public {
        asset = new MockERC20("Mock USD", "mUSD", _assetDecimals());
        vault = new MockVault(address(asset), treasury, REWARD_FEE, OFFSET, "Mock Vault", "mvMock", address(this));
    }

    function _defaultRecipients() internal view returns (address[] memory recs, uint256[] memory bps) {
        recs = new address[](2);
        recs[0] = recipientA;
        recs[1] = recipientB;

        bps = new uint256[](2);
        bps[0] = 4_000;
        bps[1] = 6_000;
    }

    function _deployDefaultDistributor() internal returns (RewardDistributor distributor) {
        (address[] memory recs, uint256[] memory bps) = _defaultRecipients();
        distributor = new RewardDistributor(admin, recs, bps);
    }

    /* ========== CONSTRUCTOR TESTS ========== */

    /// @notice Ensures constructor reverts when length mismatch.
    /// @dev Verifies the revert protects against length mismatch.
    function test_Constructor_RevertIf_LengthMismatch() public {
        address[] memory recs = new address[](1);
        recs[0] = recipientA;
        uint256[] memory bps = new uint256[](2);
        bps[0] = 5_000;
        bps[1] = 5_000;

        vm.expectRevert(RewardDistributor.InvalidRecipientsLength.selector);
        new RewardDistributor(admin, recs, bps);
    }

    /// @notice Ensures constructor reverts when zero recipients.
    /// @dev Verifies the revert protects against zero recipients.
    function test_Constructor_RevertIf_ZeroRecipients() public {
        address[] memory recs = new address[](0);
        uint256[] memory bps = new uint256[](0);

        vm.expectRevert(RewardDistributor.InvalidRecipientsLength.selector);
        new RewardDistributor(admin, recs, bps);
    }

    /// @notice Ensures constructor reverts when zero address.
    /// @dev Verifies the revert protects against zero address.
    function test_Constructor_RevertIf_ZeroAddress() public {
        address[] memory recs = new address[](1);
        recs[0] = address(0);
        uint256[] memory bps = new uint256[](1);
        bps[0] = MAX_BPS;

        vm.expectRevert(RewardDistributor.ZeroAddress.selector);
        new RewardDistributor(admin, recs, bps);
    }

    /// @notice Ensures constructor reverts when zero basis points.
    /// @dev Verifies the revert protects against zero basis points.
    function test_Constructor_RevertIf_ZeroBasisPoints() public {
        address[] memory recs = new address[](1);
        recs[0] = recipientA;
        uint256[] memory bps = new uint256[](1);
        bps[0] = 0;

        vm.expectRevert(RewardDistributor.ZeroBasisPoints.selector);
        new RewardDistributor(admin, recs, bps);
    }

    /// @notice Ensures constructor reverts when invalid basis points sum.
    /// @dev Verifies the revert protects against invalid basis points sum.
    function test_Constructor_RevertIf_InvalidBasisPointsSum() public {
        address[] memory recs = new address[](2);
        recs[0] = recipientA;
        recs[1] = recipientB;
        uint256[] memory bps = new uint256[](2);
        bps[0] = 3_000;
        bps[1] = 5_000; // sums to 8_000

        vm.expectRevert(RewardDistributor.InvalidBasisPointsSum.selector);
        new RewardDistributor(admin, recs, bps);
    }

    /// @notice Ensures constructor reverts when duplicate recipients.
    /// @dev Verifies the revert protects against duplicate recipients.
    function test_Constructor_RevertIf_DuplicateRecipients() public {
        address dup = makeAddr("dup");
        address[] memory recs = new address[](2);
        recs[0] = dup;
        recs[1] = dup;

        uint256[] memory bps = new uint256[](2);
        bps[0] = 5_000;
        bps[1] = 5_000;

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.DuplicateRecipient.selector, dup));
        new RewardDistributor(admin, recs, bps);
    }

    /// @notice Tests that constructor sets recipients and manager role.
    /// @dev Validates that constructor sets recipients and manager role.
    function test_Constructor_SetsRecipientsAndManagerRole() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        assertTrue(distributor.hasRole(distributor.MANAGER_ROLE(), admin));
        assertEq(distributor.getRecipientsCount(), 2);

        (address account0, uint256 bps0) = distributor.getRecipient(0);
        (address account1, uint256 bps1) = distributor.getRecipient(1);

        assertEq(account0, recipientA);
        assertEq(account1, recipientB);
        assertEq(bps0, 4_000);
        assertEq(bps1, 6_000);

        RewardDistributor.Recipient[] memory allRecipients = distributor.getAllRecipients();
        assertEq(allRecipients.length, 2);
        assertEq(allRecipients[0].account, recipientA);
        assertEq(allRecipients[1].account, recipientB);
    }

    /// @notice Fuzzes that constructor succeeds with valid two way split.
    /// @dev Validates that constructor succeeds with valid two way split.
    function testFuzz_Constructor_SucceedsWithValidTwoWaySplit(uint16 shareA, address addrA, address addrB) public {
        addrA = addrA == address(0) ? makeAddr("addrA") : addrA;
        addrB = addrB == address(0) ? makeAddr("addrB") : addrB;

        vm.assume(addrA != addrB);
        uint256 bpsA = bound(uint256(shareA), 1, MAX_BPS - 1);
        uint256 bpsB = MAX_BPS - bpsA;

        address[] memory recs = new address[](2);
        recs[0] = addrA;
        recs[1] = addrB;

        uint256[] memory bps = new uint256[](2);
        bps[0] = bpsA;
        bps[1] = bpsB;

        RewardDistributor distributor = new RewardDistributor(admin, recs, bps);
        assertEq(distributor.getRecipientsCount(), 2);
    }

    /* ========== RECIPIENT REPLACEMENT TESTS ========== */

    /// @notice Tests that admin can replace recipient address and emit event.
    function test_ReplaceRecipient_Succeeds() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        address newRecipient = makeAddr("newRecipient");

        (address oldRecipient,) = distributor.getRecipient(0);

        vm.expectEmit(true, true, true, true);
        emit RewardDistributor.RecipientReplaced(0, oldRecipient, newRecipient);

        vm.prank(admin);
        distributor.replaceRecipient(0, newRecipient);

        (address updatedRecipient,) = distributor.getRecipient(0);
        assertEq(updatedRecipient, newRecipient);
    }

    /// @notice Ensures replace recipient reverts when caller lacks recipients manager role.
    function test_ReplaceRecipient_RevertIf_NotRecipientsManager() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        address newRecipient = makeAddr("newRecipient");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonManager,
                distributor.RECIPIENTS_MANAGER_ROLE()
            )
        );
        vm.prank(nonManager);
        distributor.replaceRecipient(0, newRecipient);
    }

    /// @notice Ensures replace recipient reverts when index is invalid.
    function test_ReplaceRecipient_RevertIf_InvalidIndex() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.InvalidRecipientIndex.selector, 2));
        vm.prank(admin);
        distributor.replaceRecipient(2, makeAddr("newRecipient"));
    }

    /// @notice Ensures replace recipient reverts when using existing recipient address.
    function test_ReplaceRecipient_RevertIf_DuplicateAddress() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.DuplicateRecipient.selector, recipientB));
        vm.prank(admin);
        distributor.replaceRecipient(0, recipientB);
    }

    /// @notice Ensures replace recipient reverts when address unchanged.
    function test_ReplaceRecipient_RevertIf_Unchanged() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        (address currentRecipient,) = distributor.getRecipient(0);

        vm.expectRevert(RewardDistributor.RecipientUnchanged.selector);
        vm.prank(admin);
        distributor.replaceRecipient(0, currentRecipient);
    }

    /// @notice Ensures default admin without recipients role cannot replace recipient.
    function test_ReplaceRecipient_RevertIf_AdminOnly() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        address adminOnly = makeAddr("adminOnly");

        bytes32 role = distributor.DEFAULT_ADMIN_ROLE();

        vm.prank(admin);
        distributor.grantRole(role, adminOnly);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                adminOnly,
                distributor.RECIPIENTS_MANAGER_ROLE()
            )
        );
        vm.prank(adminOnly);
        distributor.replaceRecipient(0, makeAddr("newRecipient"));
    }

    /* ========== DISTRIBUTE TESTS ========== */

    /// @notice Ensures distribute reverts when no balance.
    /// @dev Verifies the revert protects against no balance.
    function test_Distribute_RevertIf_NoBalance() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        vm.expectRevert(RewardDistributor.NoBalance.selector);
        vm.prank(admin);
        distributor.distribute(address(asset));
    }

    /// @notice Ensures distribute reverts when not manager.
    /// @dev Verifies the revert protects against not manager.
    function test_Distribute_RevertIf_NotManager() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        asset.mint(address(distributor), 1_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonManager, distributor.MANAGER_ROLE()
            )
        );
        vm.prank(nonManager);
        distributor.distribute(address(asset));
    }

    /// @notice Tests that distribute distributes according to bps.
    /// @dev Validates that distribute distributes according to bps.
    function test_Distribute_DistributesAccordingToBps() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        uint256 amount = 10_000e6;
        asset.mint(address(distributor), amount);

        address[] memory recipients = new address[](2);
        recipients[0] = recipientA;
        recipients[1] = recipientB;

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = (amount * 4_000) / MAX_BPS;
        expectedAmounts[1] = (amount * 6_000) / MAX_BPS;

        vm.recordLogs();
        vm.prank(admin);
        distributor.distribute(address(asset));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 expectedLogCount = recipients.length + 1;
        Vm.Log[] memory distributorLogs = new Vm.Log[](expectedLogCount);
        uint256 matched;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(distributor)) {
                distributorLogs[matched] = entries[i];
                matched++;
            }
        }
        assertEq(matched, expectedLogCount, "Should emit expected number of RewardDistributor events");

        for (uint256 i = 0; i < recipients.length; i++) {
            Vm.Log memory entry = distributorLogs[i];
            assertEq(entry.topics[0], RewardDistributor.RecipientPaid.selector);
            assertEq(address(uint160(uint256(entry.topics[1]))), recipients[i], "Recipient mismatch");
            assertEq(abi.decode(entry.data, (uint256)), expectedAmounts[i], "Amount mismatch");
        }

        Vm.Log memory finalLog = distributorLogs[recipients.length];
        assertEq(finalLog.topics[0], RewardDistributor.RewardsDistributed.selector);
        assertEq(address(uint160(uint256(finalLog.topics[1]))), address(asset));
        assertEq(abi.decode(finalLog.data, (uint256)), amount);

        assertEq(asset.balanceOf(recipientA), expectedAmounts[0]);
        assertEq(asset.balanceOf(recipientB), expectedAmounts[1]);
        assertEq(asset.balanceOf(address(distributor)), amount - expectedAmounts[0] - expectedAmounts[1]);
    }

    /// @notice Fuzzes that distribute two recipients.
    /// @dev Validates that distribute two recipients.
    function testFuzz_Distribute_TwoRecipients(uint256 totalAmount, uint256 splitBps) public {
        totalAmount = bound(totalAmount, 1, 1_000_000_000e6);
        splitBps = bound(splitBps, 1, MAX_BPS - 1);

        address[] memory recs = new address[](2);
        recs[0] = recipientA;
        recs[1] = recipientB;

        uint256[] memory bps = new uint256[](2);
        bps[0] = splitBps;
        bps[1] = MAX_BPS - splitBps;

        RewardDistributor distributor = new RewardDistributor(admin, recs, bps);
        asset.mint(address(distributor), totalAmount);

        vm.prank(admin);
        distributor.distribute(address(asset));

        uint256 expectedA = (totalAmount * bps[0]) / MAX_BPS;
        uint256 expectedB = (totalAmount * bps[1]) / MAX_BPS;

        assertEq(asset.balanceOf(recipientA), expectedA);
        assertEq(asset.balanceOf(recipientB), expectedB);
        assertEq(asset.balanceOf(address(distributor)), totalAmount - expectedA - expectedB);
    }

    /* ========== REDEEM TESTS ========== */

    /// @notice Ensures redeem reverts when no shares.
    /// @dev Verifies the revert protects against no shares.
    function test_Redeem_RevertIf_NoShares() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        vm.expectRevert(RewardDistributor.NoShares.selector);
        vm.prank(admin);
        distributor.redeem(address(vault));
    }

    /// @notice Ensures redeem reverts when not manager.
    /// @dev Verifies the revert protects against not manager.
    function test_Redeem_RevertIf_NotManager() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        _depositSharesForDistributor(distributor, 50_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonManager, distributor.MANAGER_ROLE()
            )
        );
        vm.prank(nonManager);
        distributor.redeem(address(vault));
    }

    /// @notice Tests that redeem sends assets and emits event.
    /// @dev Validates that redeem sends assets and emits event.
    function test_Redeem_SendsAssetsAndEmitsEvent() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        uint256 depositAmount = 75_000e6;
        uint256 shares = _depositSharesForDistributor(distributor, depositAmount);

        vm.expectEmit(true, true, false, true);
        emit RewardDistributor.VaultRedeemed(address(vault), shares, depositAmount);

        vm.prank(admin);
        uint256 assetsRedeemed = distributor.redeem(address(vault));

        assertEq(assetsRedeemed, depositAmount);
        assertEq(asset.balanceOf(address(distributor)), depositAmount);
        assertEq(vault.balanceOf(address(distributor)), 0);
    }

    /// @notice Ensures distributor can redeem treasury shares after emergency + recovery cycle.
    /// @dev Flow: deposit -> harvest -> emergency mode -> recovery -> distributor redeem.
    function test_Redeem_DistributorAfterEmergencyRecovery() public {
        uint8 decimals = _assetDecimals();
        MockERC20 recoveryAsset = new MockERC20("Recovery USD", "rUSD", decimals);
        MockERC4626Vault target = new MockERC4626Vault(recoveryAsset, "Target Vault", "tVAULT", OFFSET);
        RewardDistributor distributor = _deployDefaultDistributor();
        ERC4626Adapter emergencyVault = new ERC4626Adapter(
            address(recoveryAsset),
            address(target),
            address(distributor),
            REWARD_FEE,
            OFFSET,
            "Emergency Adapter",
            "eADPT",
            address(this)
        );

        address depositor = makeAddr("recoveryDepositor");
        uint256 depositAmount = 1_000_000 * (10 ** decimals);
        recoveryAsset.mint(depositor, depositAmount);

        vm.startPrank(depositor);
        recoveryAsset.approve(address(emergencyVault), depositAmount);
        emergencyVault.deposit(depositAmount, depositor);
        vm.stopPrank();

        uint256 profit = depositAmount / 10;
        recoveryAsset.mint(address(target), profit);

        emergencyVault.harvestFees();

        uint256 distributorShares = emergencyVault.balanceOf(address(distributor));
        assertGt(distributorShares, 0, "Treasury distributor should hold fee shares");

        emergencyVault.activateEmergencyMode();
        emergencyVault.emergencyWithdraw();

        uint256 vaultBalance = recoveryAsset.balanceOf(address(emergencyVault));
        assertGt(vaultBalance, 0, "Vault should hold assets for recovery");

        emergencyVault.activateRecovery(vaultBalance);
        assertTrue(emergencyVault.recoveryMode(), "Recovery mode should be active");

        vm.prank(admin);
        uint256 assetsRedeemed = distributor.redeem(address(emergencyVault));

        uint256 expectedAssets = Math.mulDiv(
            distributorShares, emergencyVault.recoveryAssets(), emergencyVault.recoverySupply(), Math.Rounding.Floor
        );

        assertEq(assetsRedeemed, expectedAssets, "Distributor should redeem pro-rata assets");
        assertEq(emergencyVault.balanceOf(address(distributor)), 0, "Distributor shares should be burned");
        assertEq(
            recoveryAsset.balanceOf(address(distributor)), expectedAssets, "Distributor should receive assets"
        );
    }

    /* ========== HELPERS ========== */

    function _depositSharesForDistributor(RewardDistributor distributor, uint256 assetsAmount)
        private
        returns (uint256)
    {
        asset.mint(address(this), assetsAmount);
        asset.approve(address(vault), assetsAmount);
        uint256 shares = vault.deposit(assetsAmount, address(distributor));
        return shares;
    }
}
