// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SchemaResolver} from "@eas/resolver/SchemaResolver.sol";
import {IEAS, Attestation} from "@eas/IEAS.sol";

import {IMandatedContract} from "../interfaces/IMandatedContract.sol";
import {MandateSchemas} from "./MandateSchemas.sol";

/// @title MandateResolver
/// @notice Runs inside EAS every time a Mandate attestation is written. Rejects any mandate
///         that is not well-formed or not issued by the servicing contract's issuer.
/// @dev Write-time rules live here; "is it in force now?" lives in the verifier, because
///      time passes and that cannot be decided when the mandate is written.
///      Result: every mandate on record under this schema came from the right issuer.
contract MandateResolver is SchemaResolver {
    /// @notice The latest mandate written for an agent, contract and role (accepted or not).
    ///         Lets an agent discover a pending appointment on-chain before accepting it.
    mapping(address agent => mapping(address servicer => mapping(bytes32 role => bytes32 mandateUid))) public
        appointmentOf;

    event MandateAppointed(
        address indexed agent, address indexed servicer, bytes32 indexed role, bytes32 mandateUid, address issuer
    );

    error MandateMustBeRevocable();
    error MissingRecipient();
    error NotAMandatedContract(address servicer);
    error NotIssuer(address attester, address issuer);
    error UnknownRole(bytes32 role);
    error InvalidTerm(uint64 validFrom, uint64 expirationTime);

    constructor(IEAS eas) SchemaResolver(eas) {}

    function onAttest(Attestation calldata attestation, uint256 /* value */ ) internal override returns (bool) {
        // The issuer must always be able to withdraw a mandate (for example, to replace an agent).
        if (!attestation.revocable) revert MandateMustBeRevocable();
        if (attestation.recipient == address(0)) revert MissingRecipient();

        MandateSchemas.Mandate memory m = MandateSchemas.decodeMandate(attestation.data);

        // Only the party entitled to appoint (the servicing contract's issuer) may write a mandate.
        // (try/catch cannot catch a call to an address with no code, so check that first.)
        if (m.servicer.code.length == 0) revert NotAMandatedContract(m.servicer);
        address issuer_;
        try IMandatedContract(m.servicer).issuer() returns (address i) {
            issuer_ = i;
        } catch {
            revert NotAMandatedContract(m.servicer);
        }
        if (attestation.attester != issuer_) revert NotIssuer(attestation.attester, issuer_);

        if (!IMandatedContract(m.servicer).isMandateRole(m.role)) revert UnknownRole(m.role);

        // If the mandate has an end date, it must start before it ends.
        if (attestation.expirationTime != 0 && m.validFrom >= attestation.expirationTime) {
            revert InvalidTerm(m.validFrom, attestation.expirationTime);
        }

        appointmentOf[attestation.recipient][m.servicer][m.role] = attestation.uid;
        emit MandateAppointed(attestation.recipient, m.servicer, m.role, attestation.uid, issuer_);
        return true;
    }

    /// @dev The issuer may revoke at any time. EAS already restricts revocation to the attester.
    function onRevoke(Attestation calldata, uint256) internal pure override returns (bool) {
        return true;
    }
}
