// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Base} from "./Base.s.sol";
import {CouponServicer} from "../src/CouponServicer.sol";
import {EASMandateVerifier} from "../src/mandates/EASMandateVerifier.sol";

/// @notice Step 08: what happens when a party acts outside its mandate. SIMULATED ONLY: nothing is sent.
///         Needs no keys: parties come from the deployment file, holders from the chain.
///         (To put one real failed transaction on-chain, run `make fail-onchain`.)
contract FailureCases is Base {
    function run() external {
        uint256 period = _period();
        _step("08 Failure cases (simulated, nothing is broadcast)");
        Deployment memory d = _load();

        _try(d, "Calc Agent calls pay()", _party("calcAgent"), PAYING_AGENT,
            abi.encodeCall(CouponServicer.pay, (period, bytes32(0))));
        _try(d, "Registrar calls setCoupon()", _party("registrar"), CALC_AGENT,
            abi.encodeCall(CouponServicer.setCoupon, (period, RATE, AMOUNT_PER_UNIT, bytes32(0))));
        address[] memory holders = d.servicer.holdersOf(period);
        if (holders.length > 0) {
            _try(d, "A holder calls pay()", holders[0], PAYING_AGENT,
                abi.encodeCall(CouponServicer.pay, (period, bytes32(0))));
        }
        _try(d, "Issuer (admin) calls setCoupon()", _party("issuer"), CALC_AGENT,
            abi.encodeCall(CouponServicer.setCoupon, (period, RATE, AMOUNT_PER_UNIT, bytes32(0))));
    }

    function _try(Deployment memory d, string memory label, address caller, bytes32 role, bytes memory call) internal {
        (EASMandateVerifier.Status s,) = d.verifier.status(caller, address(d.servicer), role);
        vm.prank(caller);
        (bool ok, bytes memory err) = address(d.servicer).call(call);
        console2.log("");
        console2.log(label);
        console2.log("  caller           ", caller);
        console2.log("  needs mandate    ", _roleName(role));
        console2.log("  caller's status  ", _statusName(s));
        if (ok) {
            console2.log("  result            UNEXPECTED SUCCESS");
        } else if (bytes4(err) == CouponServicer.NotMandated.selector) {
            console2.log("  result            reverted NotMandated(caller, role)");
        } else {
            console2.log("  result            reverted (other reason)");
            console2.logBytes(err);
        }
    }
}
