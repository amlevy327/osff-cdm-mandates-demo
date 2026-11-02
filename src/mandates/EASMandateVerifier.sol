// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEAS, Attestation} from "@eas/IEAS.sol";

import {IMandateVerifier} from "../interfaces/IMandateVerifier.sol";
import {AcceptanceResolver} from "./AcceptanceResolver.sol";
import {MandateSchemas} from "./MandateSchemas.sol";

/// @title EASMandateVerifier
/// @notice Answers IMandateVerifier from EAS attestations: a mandate is in force only if the
///         issuer appointed the agent AND the agent accepted, and neither has been withdrawn,
///         and the mandate has started and not expired.
/// @dev Finds the mandate through the AcceptanceResolver's index, then re-reads both
///      attestations from EAS and checks them on every call.
///      Do NOT replace these checks with `eas.isAttestationValid(uid)`: that only checks the
///      attestation exists, and ignores revocation and expiry.
contract EASMandateVerifier is IMandateVerifier {
    /// @notice Why a party is or is not mandated. Useful for scripts, UIs and audits.
    enum Status {
        Active, //          in force: appointed, accepted, started, not expired, nothing revoked
        NoMandate, //       no accepted mandate on record for this agent, contract and role
        MandateRevoked, //  the issuer withdrew the mandate
        NotYetInForce, //   before validFrom
        Expired, //         at or after the mandate's expirationTime
        Resigned //         the agent withdrew its acceptance
    }

    IEAS public immutable eas;
    AcceptanceResolver public immutable index;
    bytes32 public immutable mandateSchema;
    bytes32 public immutable acceptanceSchema;

    constructor(IEAS eas_, AcceptanceResolver index_, bytes32 acceptanceSchema_) {
        eas = eas_;
        index = index_;
        mandateSchema = index_.mandateSchema();
        acceptanceSchema = acceptanceSchema_;
    }

    /// @inheritdoc IMandateVerifier
    function isMandated(address agent, address servicer, bytes32 role) external view returns (bool) {
        (Status s,) = status(agent, servicer, role);
        return s == Status.Active;
    }

    /// @notice The detailed answer, plus the mandate UID it is based on (zero if none).
    function status(address agent, address servicer, bytes32 role)
        public
        view
        returns (Status, bytes32 mandateUid)
    {
        mandateUid = index.mandateOf(agent, servicer, role);
        if (mandateUid == bytes32(0)) return (Status.NoMandate, bytes32(0));

        // The mandate: right kind, for this agent, this contract and this role.
        Attestation memory m = eas.getAttestation(mandateUid);
        MandateSchemas.Mandate memory d = MandateSchemas.decodeMandate(m.data);
        if (m.schema != mandateSchema || m.recipient != agent || d.servicer != servicer || d.role != role) {
            return (Status.NoMandate, mandateUid); // defensive: the index should never disagree with EAS
        }

        // Withdrawn by the issuer?
        if (m.revocationTime != 0) return (Status.MandateRevoked, mandateUid);
        // Within its term?
        if (block.timestamp < d.validFrom) return (Status.NotYetInForce, mandateUid);
        if (m.expirationTime != 0 && block.timestamp >= m.expirationTime) return (Status.Expired, mandateUid);

        // The acceptance: the agent's counter-signature, still standing.
        bytes32 acceptanceUid = index.acceptanceOf(mandateUid);
        if (acceptanceUid == bytes32(0)) return (Status.NoMandate, mandateUid);
        Attestation memory a = eas.getAttestation(acceptanceUid);
        if (a.schema != acceptanceSchema || a.attester != agent || a.refUID != mandateUid) {
            return (Status.NoMandate, mandateUid);
        }
        if (a.revocationTime != 0) return (Status.Resigned, mandateUid);
        if (a.expirationTime != 0 && block.timestamp >= a.expirationTime) return (Status.Resigned, mandateUid);

        return (Status.Active, mandateUid);
    }
}
