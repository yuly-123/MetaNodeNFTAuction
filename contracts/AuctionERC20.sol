// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AuctionERC20 is ERC20
{
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {

    }

    function mint(address account, uint256 value) external {
        _mint(account, value);
    }
}
