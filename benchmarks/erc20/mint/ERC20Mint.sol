// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;

import "../ERC20.sol";

contract ERC20Mint is ERC20 {
    constructor() public ERC20("ERC20Mint", "E20M") {}

    function Benchmark() external {
        for (uint256 i = 0; i < 5000; i++) {
            _mint(_msgSender(), i);
        }
    }
}
