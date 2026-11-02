// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Base} from "./Base.s.sol";

/// @notice Step 04: the Registrar records who holds the bond at the record date (PERIOD, default 1).
/// @dev In production this comes from the token register (e.g. ERC-3643). Here it is entered by hand.
contract Snapshot is Base {
    function run() external {
        uint256 period = _period();
        _step(string.concat("04 Snapshot: registrar records holders for period ", vm.toString(period)));
        Deployment memory d = _load();
        (address[] memory holders, uint256[] memory units) = _holders();

        vm.startBroadcast(_key(IDX_REGISTRAR));
        d.servicer.recordSnapshot(period, uint64(block.timestamp), holders, units);
        vm.stopBroadcast();

        for (uint256 i; i < holders.length; ++i) {
            console2.log("Holder", holders[i], "units", units[i]);
        }
    }
}
