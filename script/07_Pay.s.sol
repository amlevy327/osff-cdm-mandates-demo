// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Base} from "./Base.s.sol";

/// @notice Step 07: the Paying Agent pays every entitled holder, recording the hash of its CDM Transfer.
///         The contract emits CouponPaid with both the Transfer hash and the Reset hash it relied on.
contract Pay is Base {
    function run() external {
        uint256 period = _period();
        _step(string.concat("07 Pay: paying agent pays holders for period ", vm.toString(period)));
        Deployment memory d = _load();
        string memory transferFile = _cdmFile("transfer.json");
        bytes32 transferHash = _hashFile(transferFile);

        vm.startBroadcast(_key(IDX_PAYING_AGENT));
        d.servicer.pay(period, transferHash);
        vm.stopBroadcast();

        (address[] memory holders,) = _holders();
        for (uint256 i; i < holders.length; ++i) {
            console2.log("Holder", holders[i], "mUSDC balance", d.usdc.balanceOf(holders[i]));
        }
        console2.log("transferHash = keccak256 of", transferFile);
        console2.logBytes32(transferHash);
    }
}
