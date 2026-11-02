// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {CouponServicer} from "../src/CouponServicer.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IMandateVerifier} from "../src/interfaces/IMandateVerifier.sol";
import {MandateFixture} from "./utils/MandateFixture.sol";

/// @dev A different proof source behind the same interface: says yes to everyone.
contract YesVerifier is IMandateVerifier {
    function isMandated(address, address, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @notice CouponServicer with real mandates (real EAS, our resolvers and verifier).
///         The bond: 1,000 units, 5.20% annual, semi-annual coupon = 26.00 mUSDC per unit per period.
contract CouponServicerTest is MandateFixture {
    CouponServicer servicer;
    MockUSDC usdc;

    address registrar = makeAddr("registrar");
    address calcAgent = makeAddr("calcAgent");
    address payingAgent = makeAddr("payingAgent");
    address newPayingAgent = makeAddr("newPayingAgent");

    address alice = makeAddr("holderAlice");
    address bob = makeAddr("holderBob");
    address carol = makeAddr("holderCarol");

    uint256 constant RATE = 52_000; // 5.20%
    uint256 constant PER_UNIT = 26_000_000; // 26.00 mUSDC
    uint256 constant TOTAL_UNITS = 1_000;
    bytes32 constant RESET_1 = keccak256("cdm/period-1/reset.json");
    bytes32 constant TRANSFER_1 = keccak256("cdm/period-1/transfer.json");

    bytes32 payingMandate;

    function setUp() public {
        _deployMandateLayer();
        usdc = new MockUSDC();
        servicer = new CouponServicer(issuer, issuer, verifier, usdc);

        _appointAndAccept(registrar, address(servicer), REGISTRAR);
        _appointAndAccept(calcAgent, address(servicer), CALC_AGENT);
        payingMandate = _appointAndAccept(payingAgent, address(servicer), PAYING_AGENT);
    }

    // ------------------------------------------------------------------
    // Helpers: one per demo step
    // ------------------------------------------------------------------

    function _snapshot(uint256 period) internal {
        address[] memory holders = new address[](3);
        (holders[0], holders[1], holders[2]) = (alice, bob, carol);
        uint256[] memory units = new uint256[](3);
        (units[0], units[1], units[2]) = (100, 250, 650);
        vm.prank(registrar);
        servicer.recordSnapshot(period, uint64(block.timestamp), holders, units);
    }

    function _setCoupon(uint256 period, bytes32 resetHash) internal {
        vm.prank(calcAgent);
        servicer.setCoupon(period, RATE, PER_UNIT, resetHash);
    }

    function _fund(uint256 amount) internal {
        usdc.mint(issuer, amount);
        vm.prank(issuer);
        usdc.transfer(address(servicer), amount);
    }

    function _pay(address who, uint256 period, bytes32 transferHash) internal {
        vm.prank(who);
        servicer.pay(period, transferHash);
    }

    // ------------------------------------------------------------------
    // The demo flow
    // ------------------------------------------------------------------

    function test_Period1_FullFlow() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(TOTAL_UNITS * PER_UNIT);
        assertEq(servicer.totalDueOf(1), 26_000e6);

        vm.expectEmit(address(servicer));
        emit CouponServicer.CouponPaid(1, payingAgent, 26_000e6, TRANSFER_1, RESET_1);
        _pay(payingAgent, 1, TRANSFER_1);

        assertEq(usdc.balanceOf(alice), 100 * PER_UNIT);
        assertEq(usdc.balanceOf(bob), 250 * PER_UNIT);
        assertEq(usdc.balanceOf(carol), 650 * PER_UNIT);
        assertEq(usdc.balanceOf(address(servicer)), 0);

        // Read-back: the payment is linked to the fixing it relied on.
        assertTrue(servicer.isPaid(1));
        assertEq(servicer.resetHashOf(1), RESET_1);
        assertEq(servicer.transferHashOf(1), TRANSFER_1);
        assertEq(servicer.rateOf(1), RATE);
        assertEq(servicer.amountPerUnitOf(1), PER_UNIT);
        assertEq(servicer.totalUnitsOf(1), TOTAL_UNITS);
        assertEq(servicer.holdersOf(1).length, 3);
    }

    function test_Period2_SameMandatesSameFunctions() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(TOTAL_UNITS * PER_UNIT);
        _pay(payingAgent, 1, TRANSFER_1);

        vm.warp(start + 182 days);
        _snapshot(2);
        _setCoupon(2, keccak256("reset-2"));
        _fund(TOTAL_UNITS * PER_UNIT);
        _pay(payingAgent, 2, keccak256("transfer-2"));

        assertEq(usdc.balanceOf(carol), 2 * 650 * PER_UNIT);
        assertTrue(servicer.isPaid(1) && servicer.isPaid(2));
    }

    // ------------------------------------------------------------------
    // Mandates enforced
    // ------------------------------------------------------------------

    function test_RevertWhen_CalcAgentTriesToPay() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(TOTAL_UNITS * PER_UNIT);

        // A mandated party acting outside its mandate.
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.NotMandated.selector, calcAgent, PAYING_AGENT));
        _pay(calcAgent, 1, TRANSFER_1);
    }

    function test_RevertWhen_AdminTriesToService() public {
        // Governance does not imply servicing: the issuer/admin holds no mandate.
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.NotMandated.selector, issuer, CALC_AGENT));
        servicer.setCoupon(1, RATE, PER_UNIT, RESET_1);
    }

    function test_RevertWhen_AppointedButNotAccepted() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(TOTAL_UNITS * PER_UNIT);
        _appoint(newPayingAgent, address(servicer), PAYING_AGENT, start);

        vm.expectRevert(abi.encodeWithSelector(CouponServicer.NotMandated.selector, newPayingAgent, PAYING_AGENT));
        _pay(newPayingAgent, 1, TRANSFER_1);
    }

    function test_ReplacePayingAgent_MidLife() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(TOTAL_UNITS * PER_UNIT);

        // Issuer withdraws the old mandate and appoints a new agent, who accepts.
        _revoke(issuer, mandateSchema, payingMandate);
        _appointAndAccept(newPayingAgent, address(servicer), PAYING_AGENT);

        vm.expectRevert(abi.encodeWithSelector(CouponServicer.NotMandated.selector, payingAgent, PAYING_AGENT));
        _pay(payingAgent, 1, TRANSFER_1);

        _pay(newPayingAgent, 1, TRANSFER_1); // no change to the servicer
        assertTrue(servicer.isPaid(1));
    }

    function test_RevertWhen_MandateExpired() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(TOTAL_UNITS * PER_UNIT);

        vm.warp(start + 365 days); // a lapsed mandate blocks the payment (see README: grace periods)
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.NotMandated.selector, payingAgent, PAYING_AGENT));
        _pay(payingAgent, 1, TRANSFER_1);
    }

    // ------------------------------------------------------------------
    // Governance: swap the proof source without touching the servicer
    // ------------------------------------------------------------------

    function test_SetVerifier_OnlyAdmin_SwapsProofSource() public {
        YesVerifier other = new YesVerifier();
        bytes32 adminRole = servicer.DEFAULT_ADMIN_ROLE();

        vm.prank(registrar);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, registrar, adminRole)
        );
        servicer.setVerifier(other);

        vm.prank(issuer);
        servicer.setVerifier(other);
        assertEq(address(servicer.verifier()), address(other));

        // Under the new proof source, a party with no EAS mandate is accepted.
        vm.prank(newPayingAgent);
        servicer.setCoupon(1, RATE, PER_UNIT, RESET_1);
    }

    function test_IMandatedContract() public view {
        assertEq(servicer.issuer(), issuer);
        assertTrue(servicer.isMandateRole(PAYING_AGENT));
        assertFalse(servicer.isMandateRole(keccak256("TRANSFER_AGENT")));
    }

    // ------------------------------------------------------------------
    // Write-once and ordering
    // ------------------------------------------------------------------

    function test_RevertWhen_PaidTwice() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(2 * TOTAL_UNITS * PER_UNIT);
        _pay(payingAgent, 1, TRANSFER_1);

        vm.expectRevert(abi.encodeWithSelector(CouponServicer.AlreadyPaid.selector, 1));
        _pay(payingAgent, 1, TRANSFER_1);
    }

    function test_RevertWhen_SnapshotTwice() public {
        _snapshot(1);
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.SnapshotAlreadyRecorded.selector, 1));
        _snapshot(1);
    }

    function test_RevertWhen_CouponTwice() public {
        _setCoupon(1, RESET_1);
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.CouponAlreadySet.selector, 1));
        _setCoupon(1, RESET_1);
    }

    function test_RevertWhen_PayBeforeSnapshotOrCoupon() public {
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.SnapshotMissing.selector, 1));
        _pay(payingAgent, 1, TRANSFER_1);

        _snapshot(1);
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.CouponMissing.selector, 1));
        _pay(payingAgent, 1, TRANSFER_1);
    }

    function test_RevertWhen_NotFunded() public {
        _snapshot(1);
        _setCoupon(1, RESET_1);
        _fund(1e6);
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.InsufficientCash.selector, 1e6, 26_000e6));
        _pay(payingAgent, 1, TRANSFER_1);
    }

    // ------------------------------------------------------------------
    // Snapshot input checks
    // ------------------------------------------------------------------

    function test_RevertWhen_BadSnapshot() public {
        address[] memory two = new address[](2);
        (two[0], two[1]) = (alice, alice);
        uint256[] memory one = new uint256[](1);
        uint256[] memory twoUnits = new uint256[](2);

        vm.startPrank(registrar);
        vm.expectRevert(CouponServicer.LengthMismatch.selector);
        servicer.recordSnapshot(1, 0, two, one);

        vm.expectRevert(CouponServicer.EmptySnapshot.selector);
        servicer.recordSnapshot(1, 0, new address[](0), new uint256[](0));

        vm.expectRevert(abi.encodeWithSelector(CouponServicer.ZeroUnits.selector, alice));
        servicer.recordSnapshot(1, 0, two, twoUnits);

        (twoUnits[0], twoUnits[1]) = (10, 20);
        vm.expectRevert(abi.encodeWithSelector(CouponServicer.DuplicateHolder.selector, alice));
        servicer.recordSnapshot(1, 0, two, twoUnits);
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroCoupon() public {
        vm.prank(calcAgent);
        vm.expectRevert(CouponServicer.ZeroAmount.selector);
        servicer.setCoupon(1, RATE, 0, RESET_1);
    }
}
