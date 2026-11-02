// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Base} from "./Base.s.sol";
import {EASMandateVerifier} from "../src/mandates/EASMandateVerifier.sol";

/// @notice Step 09: read everything back from the chain, link it, and check the CDM hashes.
///         Read-only, and needs no keys: parties come from the deployment file, holders from the chain.
///         Anyone can run it against a deployment file (ours is deployments/sepolia.json).
contract Trace is Base {
    function run() external view {
        uint256 period = _period();
        Deployment memory d = _load();

        _step("09 Trace: contracts");
        _link("MockUSDC          ", address(d.usdc));
        _link("MandateResolver   ", address(d.mandateResolver));
        _link("AcceptanceResolver", address(d.acceptanceResolver));
        _link("EASMandateVerifier", address(d.verifier));
        _link("CouponServicer    ", address(d.servicer));
        console2.log("Mandate schema     ", string.concat(_easscan(), "/schema/view/", vm.toString(d.mandateSchema)));
        console2.log("Acceptance schema  ", string.concat(_easscan(), "/schema/view/", vm.toString(d.acceptanceSchema)));

        _step("09 Trace: mandates (appointment + acceptance + status now)");
        _mandate(d, "Registrar   ", _party("registrar"), REGISTRAR);
        _mandate(d, "Calc Agent  ", _party("calcAgent"), CALC_AGENT);
        _mandate(d, "Paying Agent", _party("payingAgent"), PAYING_AGENT);
        console2.log("agreementHash in mandates must equal keccak256 of", AGREEMENT_FILE);
        console2.logBytes32(_hashFile(AGREEMENT_FILE));

        _step(string.concat("09 Trace: coupon for period ", vm.toString(period)));
        console2.log("Record date         ", d.servicer.recordDateOf(period));
        console2.log("Total units         ", d.servicer.totalUnitsOf(period));
        console2.log("Rate (0.0001%)      ", d.servicer.rateOf(period));
        console2.log("Amount per unit     ", d.servicer.amountPerUnitOf(period));
        console2.log("Total due           ", d.servicer.totalDueOf(period));
        console2.log("Paid                ", d.servicer.isPaid(period));
        _checkHash("resetHash   ", d.servicer.resetHashOf(period), _cdmFile("reset.json"));
        _checkHash("transferHash", d.servicer.transferHashOf(period), _cdmFile("transfer.json"));
        address[] memory holders = d.servicer.holdersOf(period);
        for (uint256 i; i < holders.length; ++i) {
            console2.log("Holder", holders[i]);
            console2.log("   units", d.servicer.holdingAt(period, holders[i]), " mUSDC balance", d.usdc.balanceOf(holders[i]));
        }
    }

    function _link(string memory label, address a) internal view {
        console2.log(label, string.concat(_explorer(), "/address/", vm.toString(a)));
    }

    function _mandate(Deployment memory d, string memory label, address agent, bytes32 role) internal view {
        bytes32 appointed = d.mandateResolver.appointmentOf(agent, address(d.servicer), role);
        bytes32 accepted = d.acceptanceResolver.acceptanceOf(appointed);
        (EASMandateVerifier.Status s,) = d.verifier.status(agent, address(d.servicer), role);
        console2.log("");
        console2.log(label, agent, _statusName(s));
        console2.log("   mandate   ", string.concat(_easscan(), "/attestation/view/", vm.toString(appointed)));
        console2.log("   acceptance", string.concat(_easscan(), "/attestation/view/", vm.toString(accepted)));
    }

    function _checkHash(string memory label, bytes32 onChain, string memory file) internal view {
        bytes32 local = _hashFile(file);
        console2.log(label, onChain == local ? "MATCHES" : "DOES NOT MATCH", file);
        console2.logBytes32(onChain);
    }
}
