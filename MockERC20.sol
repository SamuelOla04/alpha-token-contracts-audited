// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../token/ERC20.sol";
import "../access/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
