// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract MockUSDC is MockERC20 {
    constructor() {
        initialize("USD Coin", "USDC", 6);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
