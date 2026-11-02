// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMandateVerifier
/// @notice The one question a servicing contract asks before a party acts:
///         "is this party mandated for this role on this contract, right now?"
/// @dev This is the whole interface on purpose. The servicing contract depends only on it,
///      so the proof source behind it (EAS attestations here; ONCHAINID claims, vLEI or a
///      registry elsewhere) can change without changing the servicing contract.
interface IMandateVerifier {
    /// @return True if `agent` holds an in-force, accepted mandate for `role` on `servicer`.
    function isMandated(address agent, address servicer, bytes32 role) external view returns (bool);
}
