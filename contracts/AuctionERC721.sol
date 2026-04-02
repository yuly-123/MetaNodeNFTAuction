// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract AuctionERC721 is ERC721
{
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
        
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
