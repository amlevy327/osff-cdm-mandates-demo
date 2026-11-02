// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Base} from "./Base.s.sol";

/// @notice Step 05: the Calc Agent records the coupon CDM computed off-chain, plus the hash of its CDM Reset.
contract SetCoupon is Base {
    function run() external {
        uint256 period = _period();
        _step(string.concat("05 Set coupon: calc agent records the fixing for period ", vm.toString(period)));
        Deployment memory d = _load();
        string memory resetFile = _cdmFile("reset.json");
        bytes32 resetHash = _hashFile(resetFile);

        vm.startBroadcast(_key(IDX_CALC_AGENT));
        d.servicer.setCoupon(period, RATE, AMOUNT_PER_UNIT, resetHash);
        vm.stopBroadcast();

        console2.log("Rate (0.0001%)  ", RATE);
        console2.log("Amount per unit ", AMOUNT_PER_UNIT);
        console2.log("resetHash = keccak256 of", resetFile);
        console2.logBytes32(resetHash);
    }
}
