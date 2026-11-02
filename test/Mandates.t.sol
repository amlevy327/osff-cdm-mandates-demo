// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessDenied} from "@eas/Common.sol";

import {IMandatedContract} from "../src/interfaces/IMandatedContract.sol";
import {MandateResolver} from "../src/mandates/MandateResolver.sol";
import {AcceptanceResolver} from "../src/mandates/AcceptanceResolver.sol";
import {EASMandateVerifier} from "../src/mandates/EASMandateVerifier.sol";
import {MandateSchemas} from "../src/mandates/MandateSchemas.sol";
import {MandateFixture} from "./utils/MandateFixture.sol";

/// @dev Stand-in servicing contract, so the mandate layer is tested on its own.
contract StubServicer is IMandatedContract {
    address public immutable issuer;

    constructor(address issuer_) {
        issuer = issuer_;
    }

    function isMandateRole(bytes32 role) external pure returns (bool) {
        return role == keccak256("REGISTRAR") || role == keccak256("CALC_AGENT") || role == keccak256("PAYING_AGENT");
    }
}

/// @notice Mandate layer tests, run against the real EAS + SchemaRegistry deployed locally (no mocks).
contract MandatesTest is MandateFixture {
    StubServicer servicer;
    StubServicer otherServicer;

    address agent = makeAddr("payingAgent");
    address otherAgent = makeAddr("otherPayingAgent");
    address outsider = makeAddr("outsider");

    function setUp() public {
        _deployMandateLayer();
        servicer = new StubServicer(issuer);
        otherServicer = new StubServicer(issuer);
    }

    function _status(address who, address servicer_, bytes32 role) internal view returns (EASMandateVerifier.Status s) {
        (s,) = verifier.status(who, servicer_, role);
    }

    // ------------------------------------------------------------------
    // In force
    // ------------------------------------------------------------------

    function test_AppointedAndAccepted_IsMandated() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        bytes32 a = _accept(agent, m);

        assertTrue(verifier.isMandated(agent, address(servicer), PAYING_AGENT));
        (EASMandateVerifier.Status s, bytes32 uid) = verifier.status(agent, address(servicer), PAYING_AGENT);
        assertEq(uint8(s), uint8(EASMandateVerifier.Status.Active));
        assertEq(uid, m);
        assertEq(acceptanceResolver.mandateOf(agent, address(servicer), PAYING_AGENT), m);
        assertEq(acceptanceResolver.acceptanceOf(m), a);
    }

    function test_AppointedNotAccepted_NotMandated() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        // The pending appointment is discoverable on-chain, so the agent can find it and accept.
        assertEq(mandateResolver.appointmentOf(agent, address(servicer), PAYING_AGENT), m);
        assertFalse(verifier.isMandated(agent, address(servicer), PAYING_AGENT));
        assertEq(uint8(_status(agent, address(servicer), PAYING_AGENT)), uint8(EASMandateVerifier.Status.NoMandate));
    }

    // ------------------------------------------------------------------
    // Scope: only this agent, this contract, this role
    // ------------------------------------------------------------------

    function test_WrongRoleOrServicerOrAgent_NotMandated() public {
        _accept(agent, _appoint(agent, address(servicer), PAYING_AGENT, start));

        assertFalse(verifier.isMandated(agent, address(servicer), CALC_AGENT)); // other role
        assertFalse(verifier.isMandated(agent, address(otherServicer), PAYING_AGENT)); // other contract
        assertFalse(verifier.isMandated(outsider, address(servicer), PAYING_AGENT)); // other party
    }

    // ------------------------------------------------------------------
    // Term: not yet in force, expired
    // ------------------------------------------------------------------

    function test_BeforeValidFrom_NotYetInForce_ThenActive() public {
        uint64 later = start + 30 days;
        _accept(agent, _appoint(agent, address(servicer), PAYING_AGENT, later));

        assertEq(uint8(_status(agent, address(servicer), PAYING_AGENT)), uint8(EASMandateVerifier.Status.NotYetInForce));
        vm.warp(later);
        assertTrue(verifier.isMandated(agent, address(servicer), PAYING_AGENT));
    }

    function test_AfterExpiry_Expired() public {
        _accept(agent, _appoint(agent, address(servicer), PAYING_AGENT, start));

        vm.warp(start + 365 days - 1);
        assertTrue(verifier.isMandated(agent, address(servicer), PAYING_AGENT));
        vm.warp(start + 365 days);
        assertEq(uint8(_status(agent, address(servicer), PAYING_AGENT)), uint8(EASMandateVerifier.Status.Expired));
    }

    // ------------------------------------------------------------------
    // Withdrawal: issuer revokes, agent resigns
    // ------------------------------------------------------------------

    function test_IssuerRevokes_MandateRevoked() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        _accept(agent, m);
        _revoke(issuer, mandateSchema, m);

        assertEq(uint8(_status(agent, address(servicer), PAYING_AGENT)), uint8(EASMandateVerifier.Status.MandateRevoked));
        // The record survives for audit.
        assertGt(eas.getAttestation(m).revocationTime, 0);
    }

    function test_AgentResigns_Resigned_ThenReaccepts() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        bytes32 a = _accept(agent, m);
        _revoke(agent, acceptanceSchema, a);

        assertEq(uint8(_status(agent, address(servicer), PAYING_AGENT)), uint8(EASMandateVerifier.Status.Resigned));

        _accept(agent, m);
        assertTrue(verifier.isMandated(agent, address(servicer), PAYING_AGENT));
    }

    function test_OnlyAttesterCanRevoke() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        bytes32 a = _accept(agent, m);

        vm.expectRevert(AccessDenied.selector);
        _revoke(agent, mandateSchema, m); // the agent cannot withdraw the issuer's appointment
        vm.expectRevert(AccessDenied.selector);
        _revoke(issuer, acceptanceSchema, a); // the issuer cannot withdraw the agent's acceptance
    }

    // ------------------------------------------------------------------
    // Succession: replace the agent, renew the same agent
    // ------------------------------------------------------------------

    function test_Replacement_OldRevokedNewActive() public {
        bytes32 m1 = _appoint(agent, address(servicer), PAYING_AGENT, start);
        _accept(agent, m1);

        _revoke(issuer, mandateSchema, m1);
        _accept(otherAgent, _appoint(otherAgent, address(servicer), PAYING_AGENT, start));

        assertFalse(verifier.isMandated(agent, address(servicer), PAYING_AGENT));
        assertTrue(verifier.isMandated(otherAgent, address(servicer), PAYING_AGENT));
    }

    function test_Renewal_SameAgentNewMandate() public {
        bytes32 m1 = _appoint(agent, address(servicer), PAYING_AGENT, start);
        _accept(agent, m1);

        vm.warp(start + 300 days);
        bytes32 m2 = _appoint(agent, address(servicer), PAYING_AGENT, start + 300 days);
        _accept(agent, m2);

        vm.warp(start + 400 days); // m1 has expired, m2 has not
        (EASMandateVerifier.Status s, bytes32 uid) = verifier.status(agent, address(servicer), PAYING_AGENT);
        assertEq(uint8(s), uint8(EASMandateVerifier.Status.Active));
        assertEq(uid, m2);
    }

    // ------------------------------------------------------------------
    // Write-time rules: MandateResolver
    // ------------------------------------------------------------------

    function test_RevertWhen_AttesterIsNotIssuer() public {
        bytes memory data = _mandateData(address(servicer), PAYING_AGENT, start, AGREEMENT);
        vm.expectRevert(abi.encodeWithSelector(MandateResolver.NotIssuer.selector, outsider, issuer));
        _attest(outsider, mandateSchema, agent, start + 365 days, true, bytes32(0), data);
    }

    function test_RevertWhen_UnknownRole() public {
        bytes32 role = keccak256("TRANSFER_AGENT");
        bytes memory data = _mandateData(address(servicer), role, start, AGREEMENT);
        vm.expectRevert(abi.encodeWithSelector(MandateResolver.UnknownRole.selector, role));
        _attest(issuer, mandateSchema, agent, start + 365 days, true, bytes32(0), data);
    }

    function test_RevertWhen_ServicerIsNotAContract() public {
        bytes memory data = _mandateData(outsider, PAYING_AGENT, start, AGREEMENT);
        vm.expectRevert(abi.encodeWithSelector(MandateResolver.NotAMandatedContract.selector, outsider));
        _attest(issuer, mandateSchema, agent, start + 365 days, true, bytes32(0), data);
    }

    function test_RevertWhen_MandateNotRevocable() public {
        bytes memory data = _mandateData(address(servicer), PAYING_AGENT, start, AGREEMENT);
        vm.expectRevert(MandateResolver.MandateMustBeRevocable.selector);
        _attest(issuer, mandateSchema, agent, start + 365 days, false, bytes32(0), data);
    }

    function test_RevertWhen_StartsAfterItEnds() public {
        uint64 validFrom = start + 400 days;
        bytes memory data = _mandateData(address(servicer), PAYING_AGENT, validFrom, AGREEMENT);
        vm.expectRevert(
            abi.encodeWithSelector(MandateResolver.InvalidTerm.selector, validFrom, start + 365 days)
        );
        _attest(issuer, mandateSchema, agent, start + 365 days, true, bytes32(0), data);
    }

    // ------------------------------------------------------------------
    // Write-time rules: AcceptanceResolver
    // ------------------------------------------------------------------

    function test_RevertWhen_AcceptedBySomeoneElse() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        vm.expectRevert(abi.encodeWithSelector(AcceptanceResolver.NotTheAppointee.selector, outsider, agent));
        _accept(outsider, m);
    }

    function test_RevertWhen_AcceptingADifferentAgreement() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        bytes32 wrong = keccak256("some other agreement");
        vm.expectRevert(abi.encodeWithSelector(AcceptanceResolver.AgreementMismatch.selector, wrong, AGREEMENT));
        _attest(agent, acceptanceSchema, issuer, 0, true, m, MandateSchemas.encodeAcceptance(wrong));
    }

    function test_RevertWhen_AcceptingARevokedMandate() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        _revoke(issuer, mandateSchema, m);
        vm.expectRevert(abi.encodeWithSelector(AcceptanceResolver.MandateRevoked.selector, m));
        _accept(agent, m);
    }

    function test_RevertWhen_AlreadyAccepted() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        bytes32 a = _accept(agent, m);
        vm.expectRevert(abi.encodeWithSelector(AcceptanceResolver.AlreadyAccepted.selector, m, a));
        _accept(agent, m);
    }

    function test_RevertWhen_RefIsNotAMandate() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        bytes32 a = _accept(agent, m);
        // Pointing an "acceptance" at another acceptance must fail.
        vm.expectRevert(abi.encodeWithSelector(AcceptanceResolver.NotAMandate.selector, a));
        _accept(agent, a);
    }

    function test_RevertWhen_AcceptanceNotRevocable() public {
        bytes32 m = _appoint(agent, address(servicer), PAYING_AGENT, start);
        vm.expectRevert(AcceptanceResolver.AcceptanceMustBeRevocable.selector);
        _attest(agent, acceptanceSchema, issuer, 0, false, m, MandateSchemas.encodeAcceptance(AGREEMENT));
    }
}
