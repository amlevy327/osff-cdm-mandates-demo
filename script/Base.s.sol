// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {IEAS} from "@eas/IEAS.sol";
import {ISchemaRegistry} from "@eas/ISchemaRegistry.sol";

import {CouponServicer} from "../src/CouponServicer.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MandateResolver} from "../src/mandates/MandateResolver.sol";
import {AcceptanceResolver} from "../src/mandates/AcceptanceResolver.sol";
import {EASMandateVerifier} from "../src/mandates/EASMandateVerifier.sol";

/// @notice Shared config for every numbered script: who the actors are, where EAS lives,
///         where the deployment file is, and the demo bond's numbers.
/// @dev Environment (see .env.example):
///        MNEMONIC     one mnemonic; actors are derived from it (never commit it)
///        DEPLOYMENT   name of the file in deployments/ (default "sepolia")
///        PERIOD       coupon period the coupon scripts act on (default 1)
///        EAS / SCHEMA_REGISTRY   override for chains other than Sepolia
abstract contract Base is Script {
    // ---- EAS on Sepolia (from the EAS repo's deployments/sepolia) ----
    address constant SEPOLIA_EAS = 0xC2679fBD37d54388Ce493F1DB75320D236e1815e;
    address constant SEPOLIA_SCHEMA_REGISTRY = 0x0a7E2Ff54e76B8E6659aedc9103FB21c038050D0;

    // ---- Servicing roles ----
    bytes32 constant REGISTRAR = keccak256("REGISTRAR");
    bytes32 constant CALC_AGENT = keccak256("CALC_AGENT");
    bytes32 constant PAYING_AGENT = keccak256("PAYING_AGENT");

    // ---- The demo bond: 1,000 units, 5.20% annual, semi-annual, 26.00 per unit per period ----
    string constant ASSET_ID = "ISIN:XS1234567890";
    uint256 constant RATE = 52_000; // units of 0.0001%
    uint256 constant AMOUNT_PER_UNIT = 26_000_000; // 26.00 mUSDC (6 decimals)
    string constant AGREEMENT_FILE = "cdm/paying-agency-agreement.json";

    // ---- Actors: mnemonic index => role ----
    uint32 constant IDX_ISSUER = 0;
    uint32 constant IDX_REGISTRAR = 1;
    uint32 constant IDX_CALC_AGENT = 2;
    uint32 constant IDX_PAYING_AGENT = 3;
    uint32 constant IDX_FIRST_HOLDER = 4; // holders 4, 5, 6: addresses only, they never sign

    // ---------------------------------------------------------------
    // Keys and addresses
    // ---------------------------------------------------------------

    function _key(uint32 index) internal view returns (uint256) {
        return vm.deriveKey(vm.envString("MNEMONIC"), index);
    }

    function _addr(uint32 index) internal view returns (address) {
        return vm.addr(_key(index));
    }

    /// @dev A party's address as recorded in the deployment file (keys: issuer, registrar, calcAgent,
    ///      payingAgent). Read-only scripts use this instead of the mnemonic, so anyone can trace
    ///      someone else's deployment without their keys.
    function _party(string memory key) internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(_deploymentFile()), string.concat(".", key));
    }

    function _holders() internal view returns (address[] memory holders, uint256[] memory units) {
        holders = new address[](3);
        units = new uint256[](3);
        for (uint32 i; i < 3; ++i) {
            holders[i] = _addr(IDX_FIRST_HOLDER + i);
        }
        (units[0], units[1], units[2]) = (100, 250, 650);
    }

    // ---------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------

    function _period() internal view returns (uint256) {
        return vm.envOr("PERIOD", uint256(1));
    }

    function _eas() internal view returns (IEAS) {
        return IEAS(vm.envOr("EAS", SEPOLIA_EAS));
    }

    function _schemaRegistry() internal view returns (ISchemaRegistry) {
        return ISchemaRegistry(vm.envOr("SCHEMA_REGISTRY", SEPOLIA_SCHEMA_REGISTRY));
    }

    function _deploymentFile() internal view returns (string memory) {
        return string.concat("deployments/", vm.envOr("DEPLOYMENT", string("sepolia")), ".json");
    }

    /// @dev keccak256 over the exact bytes of a CDM file. Not a canonical CDM serialization (see README).
    function _hashFile(string memory path) internal view returns (bytes32) {
        return keccak256(vm.readFileBinary(path));
    }

    function _cdmFile(string memory name) internal view returns (string memory) {
        return string.concat("cdm/period-", vm.toString(_period()), "/", name);
    }

    // ---------------------------------------------------------------
    // Deployment file (written by 01_Deploy, read by everything after)
    // ---------------------------------------------------------------

    struct Deployment {
        IEAS eas;
        ISchemaRegistry schemaRegistry;
        MockUSDC usdc;
        MandateResolver mandateResolver;
        AcceptanceResolver acceptanceResolver;
        EASMandateVerifier verifier;
        CouponServicer servicer;
        bytes32 mandateSchema;
        bytes32 acceptanceSchema;
    }

    function _save(Deployment memory d) internal {
        string memory k = "deployment";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeAddress(k, "eas", address(d.eas));
        vm.serializeAddress(k, "schemaRegistry", address(d.schemaRegistry));
        vm.serializeAddress(k, "mockUSDC", address(d.usdc));
        vm.serializeAddress(k, "mandateResolver", address(d.mandateResolver));
        vm.serializeAddress(k, "acceptanceResolver", address(d.acceptanceResolver));
        vm.serializeAddress(k, "easMandateVerifier", address(d.verifier));
        vm.serializeAddress(k, "couponServicer", address(d.servicer));
        vm.serializeBytes32(k, "mandateSchema", d.mandateSchema);
        vm.serializeBytes32(k, "acceptanceSchema", d.acceptanceSchema);
        vm.serializeAddress(k, "issuer", _addr(IDX_ISSUER));
        vm.serializeAddress(k, "registrar", _addr(IDX_REGISTRAR));
        vm.serializeAddress(k, "calcAgent", _addr(IDX_CALC_AGENT));
        string memory json = vm.serializeAddress(k, "payingAgent", _addr(IDX_PAYING_AGENT));
        vm.writeJson(json, _deploymentFile());
    }

    function _load() internal view returns (Deployment memory d) {
        string memory json = vm.readFile(_deploymentFile());
        d.eas = IEAS(vm.parseJsonAddress(json, ".eas"));
        d.schemaRegistry = ISchemaRegistry(vm.parseJsonAddress(json, ".schemaRegistry"));
        d.usdc = MockUSDC(vm.parseJsonAddress(json, ".mockUSDC"));
        d.mandateResolver = MandateResolver(payable(vm.parseJsonAddress(json, ".mandateResolver")));
        d.acceptanceResolver = AcceptanceResolver(payable(vm.parseJsonAddress(json, ".acceptanceResolver")));
        d.verifier = EASMandateVerifier(vm.parseJsonAddress(json, ".easMandateVerifier"));
        d.servicer = CouponServicer(vm.parseJsonAddress(json, ".couponServicer"));
        d.mandateSchema = vm.parseJsonBytes32(json, ".mandateSchema");
        d.acceptanceSchema = vm.parseJsonBytes32(json, ".acceptanceSchema");
    }

    // ---------------------------------------------------------------
    // Output helpers
    // ---------------------------------------------------------------

    function _step(string memory title) internal pure {
        console2.log("");
        console2.log("==================================================================");
        console2.log(title);
        console2.log("==================================================================");
    }

    function _statusName(EASMandateVerifier.Status s) internal pure returns (string memory) {
        if (s == EASMandateVerifier.Status.Active) return "Active";
        if (s == EASMandateVerifier.Status.NoMandate) return "NoMandate";
        if (s == EASMandateVerifier.Status.MandateRevoked) return "MandateRevoked";
        if (s == EASMandateVerifier.Status.NotYetInForce) return "NotYetInForce";
        if (s == EASMandateVerifier.Status.Expired) return "Expired";
        return "Resigned";
    }

    function _roleName(bytes32 role) internal pure returns (string memory) {
        if (role == REGISTRAR) return "REGISTRAR";
        if (role == CALC_AGENT) return "CALC_AGENT";
        if (role == PAYING_AGENT) return "PAYING_AGENT";
        return "UNKNOWN";
    }

    function _easscan() internal view returns (string memory) {
        return vm.envOr("EASSCAN_URL", string("https://sepolia.easscan.org"));
    }

    function _explorer() internal view returns (string memory) {
        return vm.envOr("EXPLORER_URL", string("https://sepolia.etherscan.io"));
    }
}
