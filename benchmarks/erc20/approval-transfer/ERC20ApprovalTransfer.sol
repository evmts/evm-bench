// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;

import "../ERC20.sol";

contract ERC20ApprovalTransfer is ERC20 {
    constructor() public ERC20("ERC20ApprovalTransfer", "E20AT") {}

    function Benchmark() external {
        _mint(msg.sender, 1000000000 * 10**uint256(decimals()));
        for (uint256 i = 1; i < 1000; i++) {
            require(
                allowance(msg.sender, msg.sender) == 0,
                "non-zero allowance to start"
            );
            approve(msg.sender, i);
            require(
                allowance(msg.sender, msg.sender) == i,
                "didn't give allowance"
            );
            transferFrom(msg.sender, msg.sender, i);
            require(
                allowance(msg.sender, msg.sender) == 0,
                "non-zero allowance to end"
            );
        }
    }
}
