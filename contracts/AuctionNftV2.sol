// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./AuctionNftV1.sol";

contract AuctionNftV2 is AuctionNftV1
{
    function getVersion() external pure override returns (string memory) {
        return "AuctionNft V2";
    }

    function newFeature() external pure returns (string memory) {
        return "This is a new feature in UUPS V2";
    }
}
