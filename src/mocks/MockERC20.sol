// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 __decimals;
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        __decimals = _decimals;

        _mint(msg.sender, 100000000 ether);
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
