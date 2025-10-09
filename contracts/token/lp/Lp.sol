// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LpToken is ERC20 {
    address public immutable minter;

    constructor(string memory name_, string memory symbol_, address minter_) ERC20(name_, symbol_) {
        require(minter_ != address(0), "LpToken: minter zero");
        minter = minter_;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "LpToken: not minter");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == minter, "LpToken: not minter");
        _burn(from, amount);
    }
}


