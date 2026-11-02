// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MandateSchemas
/// @notice The two EAS schemas and how their data is encoded and decoded.
/// @dev Field sources (see README): everything except the signer and the revocation comes
///      from CDM. Expiry and revocation use EAS's own `expirationTime` and `revocationTime`.
library MandateSchemas {
    /// @notice Written by the issuer (attester) to the agent (recipient).
    ///         partyId:       the agent's legal identifier, e.g. "LEI:5493001KJTIIGC8Y1R12"
    ///         assetId:       the instrument, e.g. "ISIN:XS1234567890"
    ///         servicer:      the servicing contract the mandate applies to
    ///         role:          keccak256 of the role name, e.g. keccak256("PAYING_AGENT")
    ///         validFrom:     when the mandate comes into force (agreement effective date)
    ///         agreementHash: hash of the legal agreement that grants the mandate
    string internal constant MANDATE =
        "string partyId, string assetId, address servicer, bytes32 role, uint64 validFrom, bytes32 agreementHash";

    /// @notice Written by the agent (attester), with refUID = the mandate it accepts.
    ///         agreementHash: must equal the mandate's, so the agent confirms the same agreement.
    string internal constant ACCEPTANCE = "bytes32 agreementHash";

    struct Mandate {
        string partyId;
        string assetId;
        address servicer;
        bytes32 role;
        uint64 validFrom;
        bytes32 agreementHash;
    }

    function encodeMandate(Mandate memory m) internal pure returns (bytes memory) {
        return abi.encode(m.partyId, m.assetId, m.servicer, m.role, m.validFrom, m.agreementHash);
    }

    function decodeMandate(bytes memory data) internal pure returns (Mandate memory m) {
        (m.partyId, m.assetId, m.servicer, m.role, m.validFrom, m.agreementHash) =
            abi.decode(data, (string, string, address, bytes32, uint64, bytes32));
    }

    function encodeAcceptance(bytes32 agreementHash) internal pure returns (bytes memory) {
        return abi.encode(agreementHash);
    }

    function decodeAcceptance(bytes memory data) internal pure returns (bytes32) {
        return abi.decode(data, (bytes32));
    }
}
