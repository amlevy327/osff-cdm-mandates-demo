// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SchemaResolver} from "@eas/resolver/SchemaResolver.sol";
import {IEAS, Attestation} from "@eas/IEAS.sol";

import {MandateSchemas} from "./MandateSchemas.sol";

/// @title AcceptanceResolver
/// @notice Runs inside EAS every time a MandateAcceptance attestation is written or revoked.
///         An acceptance is the agent's counter-signature: it points at a mandate (refUID) and
///         is only valid if the mandate's own recipient wrote it, for the same agreement.
/// @dev It also keeps the on-chain index the verifier reads:
///         agent => servicer => role => current mandate UID
///         mandate UID => acceptance UID
///      Only accepted mandates enter the index. A resignation (revoked acceptance) stays in the
///      index so the verifier can report it; the verifier treats it as not mandated.
contract AcceptanceResolver is SchemaResolver {
    /// @notice The Mandate schema UID. An acceptance may only point at a mandate of this schema.
    bytes32 public immutable mandateSchema;

    mapping(address agent => mapping(address servicer => mapping(bytes32 role => bytes32 mandateUid))) public
        mandateOf;
    mapping(bytes32 mandateUid => bytes32 acceptanceUid) public acceptanceOf;

    event MandateAccepted(
        address indexed agent, address indexed servicer, bytes32 indexed role, bytes32 mandateUid, bytes32 acceptanceUid
    );
    event MandateResigned(
        address indexed agent, address indexed servicer, bytes32 indexed role, bytes32 mandateUid, bytes32 acceptanceUid
    );

    error AcceptanceMustBeRevocable();
    error NotAMandate(bytes32 refUID);
    error NotTheAppointee(address attester, address recipient);
    error MandateRevoked(bytes32 mandateUid);
    error AgreementMismatch(bytes32 accepted, bytes32 mandated);
    error AlreadyAccepted(bytes32 mandateUid, bytes32 acceptanceUid);

    constructor(IEAS eas, bytes32 mandateSchema_) SchemaResolver(eas) {
        mandateSchema = mandateSchema_;
    }

    function onAttest(Attestation calldata acceptance, uint256 /* value */ ) internal override returns (bool) {
        // The agent must be able to resign later by revoking its acceptance.
        if (!acceptance.revocable) revert AcceptanceMustBeRevocable();

        Attestation memory mandate = _eas.getAttestation(acceptance.refUID);
        if (acceptance.refUID == bytes32(0) || mandate.schema != mandateSchema) revert NotAMandate(acceptance.refUID);

        // Only the appointee can accept its own appointment.
        if (acceptance.attester != mandate.recipient) revert NotTheAppointee(acceptance.attester, mandate.recipient);
        if (mandate.revocationTime != 0) revert MandateRevoked(acceptance.refUID);
        // One standing acceptance per mandate. After resigning, the agent may accept again.
        bytes32 previous = acceptanceOf[acceptance.refUID];
        if (previous != bytes32(0) && _eas.getAttestation(previous).revocationTime == 0) {
            revert AlreadyAccepted(acceptance.refUID, previous);
        }

        MandateSchemas.Mandate memory m = MandateSchemas.decodeMandate(mandate.data);

        // The agent confirms the same agreement the issuer referenced.
        bytes32 accepted = MandateSchemas.decodeAcceptance(acceptance.data);
        if (accepted != m.agreementHash) revert AgreementMismatch(accepted, m.agreementHash);

        // A newer accepted mandate for the same agent, contract and role replaces the older one.
        mandateOf[mandate.recipient][m.servicer][m.role] = acceptance.refUID;
        acceptanceOf[acceptance.refUID] = acceptance.uid;

        emit MandateAccepted(mandate.recipient, m.servicer, m.role, acceptance.refUID, acceptance.uid);
        return true;
    }

    /// @dev The agent resigns by revoking its acceptance (EAS restricts revocation to the attester).
    ///      The index is kept on purpose: the verifier then reads the revoked acceptance and reports
    ///      "Resigned" rather than "NoMandate", which is the more useful answer for an audit.
    function onRevoke(Attestation calldata acceptance, uint256 /* value */ ) internal override returns (bool) {
        Attestation memory mandate = _eas.getAttestation(acceptance.refUID);
        MandateSchemas.Mandate memory m = MandateSchemas.decodeMandate(mandate.data);
        emit MandateResigned(mandate.recipient, m.servicer, m.role, acceptance.refUID, acceptance.uid);
        return true;
    }
}
