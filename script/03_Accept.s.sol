// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";

import {Base} from "./Base.s.sol";
import {MandateSchemas} from "../src/mandates/MandateSchemas.sol";

/// @notice Step 03: each agent finds its pending mandate on-chain and counter-attests (accepts) it.
///         Until this step, no agent is mandated.
contract Accept is Base {
    function run() external {
        _step("03 Accept: each agent counter-attests its mandate");
        Deployment memory d = _load();
        bytes32 agreementHash = _hashFile(AGREEMENT_FILE);

        _accept(d, IDX_REGISTRAR, REGISTRAR, agreementHash);
        _accept(d, IDX_CALC_AGENT, CALC_AGENT, agreementHash);
        _accept(d, IDX_PAYING_AGENT, PAYING_AGENT, agreementHash);
    }

    function _accept(Deployment memory d, uint32 idx, bytes32 role, bytes32 agreementHash) internal {
        address agent = _addr(idx);
        bytes32 mandateUid = d.mandateResolver.appointmentOf(agent, address(d.servicer), role);
        require(mandateUid != bytes32(0), "no pending mandate: run 02_Appoint first");

        vm.startBroadcast(_key(idx));
        d.eas.attest(
            AttestationRequest({
                schema: d.acceptanceSchema,
                data: AttestationRequestData({
                    recipient: _addr(IDX_ISSUER), // addressed back to the appointer
                    expirationTime: 0,
                    revocable: true, // revoking it later = resigning
                    refUID: mandateUid,
                    data: MandateSchemas.encodeAcceptance(agreementHash),
                    value: 0
                })
            })
        );
        vm.stopBroadcast();
        console2.log("Accepted by", agent);
        console2.logBytes32(mandateUid);
    }
}
