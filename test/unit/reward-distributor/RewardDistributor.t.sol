// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {RewardDistributor} from "src/RewardDistributor.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockVault} from "test/mocks/MockVault.sol";

contract RewardDistributorTest is Test {
    MockERC20 internal asset;
    MockVault internal vault;

    address internal manager = makeAddr("manager");
    address internal nonManager = makeAddr("nonManager");
    address internal recipientA = makeAddr("recipientA");
    address internal recipientB = makeAddr("recipientB");
    address internal treasury = makeAddr("treasury");

    uint16 internal constant REWARD_FEE = 500;
    uint8 internal constant OFFSET = 6;
    uint256 internal constant MAX_BPS = 10_000;

    function setUp() public {
        asset = new MockERC20("Mock USD", "mUSD", 6);
        vault = new MockVault(address(asset), treasury, REWARD_FEE, OFFSET, "Mock Vault", "mvMock");
    }

    function _defaultRecipients()
        internal
        view
        returns (address[] memory recs, uint256[] memory bps)
    {
        recs = new address[](2);
        recs[0] = recipientA;
        recs[1] = recipientB;

        bps = new uint256[](2);
        bps[0] = 4_000;
        bps[1] = 6_000;
    }

    function _deployDefaultDistributor() internal returns (RewardDistributor distributor) {
        (address[] memory recs, uint256[] memory bps) = _defaultRecipients();
        distributor = new RewardDistributor(manager, recs, bps);
    }

    /* ========== CONSTRUCTOR TESTS ========== */

    function test_Constructor_RevertIf_LengthMismatch() public {
        address[] memory recs = new address[](1);
        recs[0] = recipientA;
        uint256[] memory bps = new uint256[](2);
        bps[0] = 5_000;
        bps[1] = 5_000;

        vm.expectRevert(RewardDistributor.InvalidRecipientsLength.selector);
        new RewardDistributor(manager, recs, bps);
    }

    function test_Constructor_RevertIf_ZeroRecipients() public {
        address[] memory recs = new address[](0);
        uint256[] memory bps = new uint256[](0);

        vm.expectRevert(RewardDistributor.InvalidRecipientsLength.selector);
        new RewardDistributor(manager, recs, bps);
    }

    function test_Constructor_RevertIf_ZeroAddress() public {
        address[] memory recs = new address[](1);
        recs[0] = address(0);
        uint256[] memory bps = new uint256[](1);
        bps[0] = MAX_BPS;

        vm.expectRevert(RewardDistributor.ZeroAddress.selector);
        new RewardDistributor(manager, recs, bps);
    }

    function test_Constructor_RevertIf_ZeroBasisPoints() public {
        address[] memory recs = new address[](1);
        recs[0] = recipientA;
        uint256[] memory bps = new uint256[](1);
        bps[0] = 0;

        vm.expectRevert(RewardDistributor.ZeroBasisPoints.selector);
        new RewardDistributor(manager, recs, bps);
    }

    function test_Constructor_RevertIf_InvalidBasisPointsSum() public {
        address[] memory recs = new address[](2);
        recs[0] = recipientA;
        recs[1] = recipientB;
        uint256[] memory bps = new uint256[](2);
        bps[0] = 3_000;
        bps[1] = 5_000; // sums to 8_000

        vm.expectRevert(RewardDistributor.InvalidBasisPointsSum.selector);
        new RewardDistributor(manager, recs, bps);
    }

    function test_Constructor_RevertIf_DuplicateRecipients() public {
        address dup = makeAddr("dup");
        address[] memory recs = new address[](2);
        recs[0] = dup;
        recs[1] = dup;

        uint256[] memory bps = new uint256[](2);
        bps[0] = 5_000;
        bps[1] = 5_000;

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.DuplicateRecipient.selector, dup));
        new RewardDistributor(manager, recs, bps);
    }

    function test_Constructor_SetsRecipientsAndManagerRole() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        assertTrue(distributor.hasRole(distributor.MANAGER_ROLE(), manager));
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

        RewardDistributor distributor = new RewardDistributor(manager, recs, bps);
        assertEq(distributor.getRecipientsCount(), 2);
    }

    /* ========== DISTRIBUTE TESTS ========== */

    function test_Distribute_RevertIf_NoBalance() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        vm.expectRevert(RewardDistributor.NoBalance.selector);
        vm.prank(manager);
        distributor.distribute(address(asset));
    }

    function test_Distribute_RevertIf_NotManager() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        asset.mint(address(distributor), 1_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonManager,
                distributor.MANAGER_ROLE()
            )
        );
        vm.prank(nonManager);
        distributor.distribute(address(asset));
    }

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
        vm.prank(manager);
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

    function testFuzz_Distribute_TwoRecipients(uint256 totalAmount, uint256 splitBps) public {
        totalAmount = bound(totalAmount, 1, 1_000_000_000e6);
        splitBps = bound(splitBps, 1, MAX_BPS - 1);

        address[] memory recs = new address[](2);
        recs[0] = recipientA;
        recs[1] = recipientB;

        uint256[] memory bps = new uint256[](2);
        bps[0] = splitBps;
        bps[1] = MAX_BPS - splitBps;

        RewardDistributor distributor = new RewardDistributor(manager, recs, bps);
        asset.mint(address(distributor), totalAmount);

        vm.prank(manager);
        distributor.distribute(address(asset));

        uint256 expectedA = (totalAmount * bps[0]) / MAX_BPS;
        uint256 expectedB = (totalAmount * bps[1]) / MAX_BPS;

        assertEq(asset.balanceOf(recipientA), expectedA);
        assertEq(asset.balanceOf(recipientB), expectedB);
        assertEq(asset.balanceOf(address(distributor)), totalAmount - expectedA - expectedB);
    }

    /* ========== REDEEM TESTS ========== */

    function test_Redeem_RevertIf_NoShares() public {
        RewardDistributor distributor = _deployDefaultDistributor();

        vm.expectRevert(RewardDistributor.NoShares.selector);
        vm.prank(manager);
        distributor.redeem(address(vault));
    }

    function test_Redeem_RevertIf_NotManager() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        _depositSharesForDistributor(distributor, 50_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonManager,
                distributor.MANAGER_ROLE()
            )
        );
        vm.prank(nonManager);
        distributor.redeem(address(vault));
    }

    function test_Redeem_SendsAssetsAndEmitsEvent() public {
        RewardDistributor distributor = _deployDefaultDistributor();
        uint256 depositAmount = 75_000e6;
        uint256 shares = _depositSharesForDistributor(distributor, depositAmount);

        vm.expectEmit(true, true, false, true);
        emit RewardDistributor.VaultRedeemed(address(vault), shares, depositAmount);

        vm.prank(manager);
        uint256 assetsRedeemed = distributor.redeem(address(vault));

        assertEq(assetsRedeemed, depositAmount);
        assertEq(asset.balanceOf(address(distributor)), depositAmount);
        assertEq(vault.balanceOf(address(distributor)), 0);
    }

    /* ========== HELPERS ========== */

    function _depositSharesForDistributor(RewardDistributor distributor, uint256 assetsAmount) private returns (uint256) {
        asset.mint(address(this), assetsAmount);
        asset.approve(address(vault), assetsAmount);
        uint256 shares = vault.deposit(assetsAmount, address(distributor));
        return shares;
    }
}
