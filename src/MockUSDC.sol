// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice TESTNET ONLY. The cash leg of the coupon: a 6-decimal stablecoin stand-in that anyone can mint.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Open mint, so anyone following the demo can fund their own servicer.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
