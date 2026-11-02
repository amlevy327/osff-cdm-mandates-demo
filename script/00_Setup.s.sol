// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Base} from "./Base.s.sol";

/// @notice Step 00: show the actors, and have the issuer top up the three agents with gas money,
///         so only the issuer needs a faucet.
contract Setup is Base {
    uint256 constant AGENT_GAS_FLOAT = 0.01 ether;

    function run() external {
        _step("00 Setup: actors (derived from MNEMONIC) and gas top-up");
        address issuer = _addr(IDX_ISSUER);
        console2.log("Issuer        ", issuer, issuer.balance);
        console2.log("Registrar     ", _addr(IDX_REGISTRAR));
        console2.log("Calc Agent    ", _addr(IDX_CALC_AGENT));
        console2.log("Paying Agent  ", _addr(IDX_PAYING_AGENT));
        (address[] memory holders,) = _holders();
        for (uint256 i; i < holders.length; ++i) {
            console2.log("Holder        ", holders[i]);
        }

        uint32[3] memory agents = [IDX_REGISTRAR, IDX_CALC_AGENT, IDX_PAYING_AGENT];
        vm.startBroadcast(_key(IDX_ISSUER));
        for (uint256 i; i < agents.length; ++i) {
            address a = _addr(agents[i]);
            if (a.balance < AGENT_GAS_FLOAT) {
                uint256 topUp = AGENT_GAS_FLOAT - a.balance;
                payable(a).transfer(topUp);
                console2.log("Topped up", a, topUp);
            }
        }
        vm.stopBroadcast();
    }
}
