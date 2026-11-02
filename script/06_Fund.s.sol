// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Base} from "./Base.s.sol";

/// @notice Step 06: the issuer funds the coupon. It mints mock cash to itself (testnet only),
///         then transfers exactly the amount due into the servicer, ahead of payment.
contract Fund is Base {
    function run() external {
        uint256 period = _period();
        _step(string.concat("06 Fund: issuer moves the coupon cash into the servicer for period ", vm.toString(period)));
        Deployment memory d = _load();
        uint256 due = d.servicer.totalDueOf(period);
        require(due != 0, "nothing due: run 04_Snapshot and 05_SetCoupon first");
        uint256 have = d.usdc.balanceOf(address(d.servicer));
        uint256 needed = due > have ? due - have : 0;

        vm.startBroadcast(_key(IDX_ISSUER));
        if (needed != 0) {
            d.usdc.mint(_addr(IDX_ISSUER), needed);
            d.usdc.transfer(address(d.servicer), needed);
        }
        vm.stopBroadcast();
        console2.log("Due (mUSDC, 6 decimals)", due);
        console2.log("Transferred            ", needed);
    }
}
