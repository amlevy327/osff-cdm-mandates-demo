// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";

import {Base} from "./Base.s.sol";
import {MandateSchemas} from "../src/mandates/MandateSchemas.sol";

/// @notice Step 02: the issuer appoints the three agents, one Mandate attestation each.
///         Every mandate carries the hash of the same legal agreement (cdm/paying-agency-agreement.json).
contract Appoint is Base {
    function run() external {
        _step("02 Appoint: issuer attests 3 mandates");
        Deployment memory d = _load();
        bytes32 agreementHash = _hashFile(AGREEMENT_FILE);
        uint64 validFrom = uint64(block.timestamp); // in force from now
        uint64 expiry = validFrom + 365 days; // the agreement's one-year term

        vm.startBroadcast(_key(IDX_ISSUER));
        _appoint(d, _addr(IDX_REGISTRAR), "LEI:5493001KJTIIGC8Y1R01", REGISTRAR, validFrom, expiry, agreementHash);
        _appoint(d, _addr(IDX_CALC_AGENT), "LEI:5493001KJTIIGC8Y1R02", CALC_AGENT, validFrom, expiry, agreementHash);
        _appoint(d, _addr(IDX_PAYING_AGENT), "LEI:5493001KJTIIGC8Y1R12", PAYING_AGENT, validFrom, expiry, agreementHash);
        vm.stopBroadcast();

        console2.log("agreementHash (keccak256 of", AGREEMENT_FILE, ")");
        console2.logBytes32(agreementHash);
        console2.log("Mandate UIDs are read from MandateResolver.appointmentOf in step 03 and 09.");
    }

    function _appoint(
        Deployment memory d,
        address agent,
        string memory partyId,
        bytes32 role,
        uint64 validFrom,
        uint64 expiry,
        bytes32 agreementHash
    ) internal {
        bytes memory data = MandateSchemas.encodeMandate(
            MandateSchemas.Mandate({
                partyId: partyId,
                assetId: ASSET_ID,
                servicer: address(d.servicer),
                role: role,
                validFrom: validFrom,
                agreementHash: agreementHash
            })
        );
        d.eas.attest(
            AttestationRequest({
                schema: d.mandateSchema,
                data: AttestationRequestData({
                    recipient: agent,
                    expirationTime: expiry,
                    revocable: true,
                    refUID: bytes32(0),
                    data: data,
                    value: 0
                })
            })
        );
        console2.log("Appointed", agent, partyId);
    }
}
