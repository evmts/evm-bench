// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;

import "./ERC20.sol";

contract ERC20Transfer is ERC20 {
    constructor() public ERC20("ERC20Transfer", "E20T") {}

    function Benchmark() external {
        _mint(_msgSender(), 10000 * 10**uint256(decimals()));
        for (uint256 i = 0; i < 5000; i++) {
            transfer(address(1), i);
        }
    }
}
