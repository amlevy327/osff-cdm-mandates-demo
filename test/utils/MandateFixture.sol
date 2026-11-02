// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {EAS} from "@eas/EAS.sol";
import {SchemaRegistry} from "@eas/SchemaRegistry.sol";
import {ISchemaRegistry} from "@eas/ISchemaRegistry.sol";
import {ISchemaResolver} from "@eas/resolver/ISchemaResolver.sol";
import {
    IEAS,
    AttestationRequest,
    AttestationRequestData,
    RevocationRequest,
    RevocationRequestData
} from "@eas/IEAS.sol";

import {MandateSchemas} from "../../src/mandates/MandateSchemas.sol";
import {MandateResolver} from "../../src/mandates/MandateResolver.sol";
import {AcceptanceResolver} from "../../src/mandates/AcceptanceResolver.sol";
import {EASMandateVerifier} from "../../src/mandates/EASMandateVerifier.sol";

/// @notice Shared setup: the real EAS + SchemaRegistry deployed locally (no mocks), our two
///         resolvers and schemas registered in the same order as the deploy script, and helpers
///         to appoint, accept and revoke.
abstract contract MandateFixture is Test {
    bytes32 constant REGISTRAR = keccak256("REGISTRAR");
    bytes32 constant CALC_AGENT = keccak256("CALC_AGENT");
    bytes32 constant PAYING_AGENT = keccak256("PAYING_AGENT");
    bytes32 constant AGREEMENT = keccak256("paying agency agreement v1");

    IEAS eas;
    ISchemaRegistry registry;
    MandateResolver mandateResolver;
    AcceptanceResolver acceptanceResolver;
    EASMandateVerifier verifier;
    bytes32 mandateSchema;
    bytes32 acceptanceSchema;

    address issuer = makeAddr("issuer");
    uint64 start;

    function _deployMandateLayer() internal {
        vm.warp(1_793_491_200); // 2026-11-01
        start = uint64(block.timestamp);

        registry = new SchemaRegistry();
        eas = new EAS(registry);

        // A schema UID includes its resolver's address, so each resolver comes first.
        mandateResolver = new MandateResolver(eas);
        mandateSchema = registry.register(MandateSchemas.MANDATE, ISchemaResolver(address(mandateResolver)), true);
        acceptanceResolver = new AcceptanceResolver(eas, mandateSchema);
        acceptanceSchema =
            registry.register(MandateSchemas.ACCEPTANCE, ISchemaResolver(address(acceptanceResolver)), true);
        verifier = new EASMandateVerifier(eas, acceptanceResolver, acceptanceSchema);
    }

    function _mandateData(address servicer_, bytes32 role, uint64 validFrom, bytes32 agreement)
        internal
        pure
        returns (bytes memory)
    {
        return MandateSchemas.encodeMandate(
            MandateSchemas.Mandate({
                partyId: "LEI:5493001KJTIIGC8Y1R12",
                assetId: "ISIN:XS1234567890",
                servicer: servicer_,
                role: role,
                validFrom: validFrom,
                agreementHash: agreement
            })
        );
    }

    function _attest(
        address attester,
        bytes32 schema,
        address recipient,
        uint64 expiry,
        bool revocable,
        bytes32 ref,
        bytes memory data
    ) internal returns (bytes32) {
        vm.prank(attester);
        return eas.attest(
            AttestationRequest({
                schema: schema,
                data: AttestationRequestData({
                    recipient: recipient,
                    expirationTime: expiry,
                    revocable: revocable,
                    refUID: ref,
                    data: data,
                    value: 0
                })
            })
        );
    }

    /// @dev Issuer appoints `who` as `role` on `servicer_` for one year from `validFrom`.
    function _appoint(address who, address servicer_, bytes32 role, uint64 validFrom) internal returns (bytes32) {
        return _attest(
            issuer,
            mandateSchema,
            who,
            validFrom + 365 days,
            true,
            bytes32(0),
            _mandateData(servicer_, role, validFrom, AGREEMENT)
        );
    }

    /// @dev `who` counter-attests the mandate (acceptance is addressed back to the issuer).
    function _accept(address who, bytes32 mandateUid) internal returns (bytes32) {
        return _attest(who, acceptanceSchema, issuer, 0, true, mandateUid, MandateSchemas.encodeAcceptance(AGREEMENT));
    }

    function _appointAndAccept(address who, address servicer_, bytes32 role) internal returns (bytes32 mandateUid) {
        mandateUid = _appoint(who, servicer_, role, start);
        _accept(who, mandateUid);
    }

    function _revoke(address who, bytes32 schema, bytes32 uid) internal {
        vm.prank(who);
        eas.revoke(RevocationRequest({schema: schema, data: RevocationRequestData({uid: uid, value: 0})}));
    }
}
