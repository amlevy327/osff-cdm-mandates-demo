// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMandatedContract
/// @notice What a contract that is serviced under mandates tells the mandate layer about itself.
/// @dev The MandateResolver reads this when a mandate is written, so one resolver can serve
///      any servicing contract (a coupon servicer, a redemption servicer, and so on).
interface IMandatedContract {
    /// @notice The party entitled to appoint agents for this contract (for a bond, the issuer).
    function issuer() external view returns (address);

    /// @notice True if `role` is a servicing role this contract recognizes.
    function isMandateRole(bytes32 role) external view returns (bool);
}
