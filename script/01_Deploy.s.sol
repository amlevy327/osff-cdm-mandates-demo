// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {ISchemaResolver} from "@eas/resolver/ISchemaResolver.sol";

import {Base} from "./Base.s.sol";
import {CouponServicer} from "../src/CouponServicer.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MandateResolver} from "../src/mandates/MandateResolver.sol";
import {AcceptanceResolver} from "../src/mandates/AcceptanceResolver.sol";
import {EASMandateVerifier} from "../src/mandates/EASMandateVerifier.sol";
import {MandateSchemas} from "../src/mandates/MandateSchemas.sol";

/// @notice Step 01: the issuer deploys our 5 contracts and registers the 2 schemas on the existing EAS.
///         Order matters: a schema UID includes its resolver's address, so each resolver comes first.
contract Deploy is Base {
    function run() external {
        _step("01 Deploy: 5 contracts + 2 schemas (EAS itself is already deployed)");
        Deployment memory d;
        d.eas = _eas();
        d.schemaRegistry = _schemaRegistry();
        address issuer = _addr(IDX_ISSUER);

        vm.startBroadcast(_key(IDX_ISSUER));
        d.usdc = new MockUSDC();
        d.mandateResolver = new MandateResolver(d.eas);
        d.mandateSchema =
            d.schemaRegistry.register(MandateSchemas.MANDATE, ISchemaResolver(address(d.mandateResolver)), true);
        d.acceptanceResolver = new AcceptanceResolver(d.eas, d.mandateSchema);
        d.acceptanceSchema =
            d.schemaRegistry.register(MandateSchemas.ACCEPTANCE, ISchemaResolver(address(d.acceptanceResolver)), true);
        d.verifier = new EASMandateVerifier(d.eas, d.acceptanceResolver, d.acceptanceSchema);
        d.servicer = new CouponServicer(issuer, issuer, d.verifier, d.usdc); // admin = issuer in the demo
        vm.stopBroadcast();

        _save(d);
        console2.log("MockUSDC           ", address(d.usdc));
        console2.log("MandateResolver    ", address(d.mandateResolver));
        console2.log("AcceptanceResolver ", address(d.acceptanceResolver));
        console2.log("EASMandateVerifier ", address(d.verifier));
        console2.log("CouponServicer     ", address(d.servicer));
        console2.log("Mandate schema     ");
        console2.logBytes32(d.mandateSchema);
        console2.log("Acceptance schema  ");
        console2.logBytes32(d.acceptanceSchema);
        console2.log("Saved to", _deploymentFile());
    }
}
