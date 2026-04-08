// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AuctionERC20 is ERC20, AggregatorV3Interface
{
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {

    }

    function mint(address account, uint256 value) external {
        _mint(account, value);
    }

    // AggregatorV3Interface 接口实现，返回固定值，方便测试。
    function decimals() public pure override(ERC20, AggregatorV3Interface) returns(uint8) {
        return 18;
    }

    // AggregatorV3Interface 接口实现，返回固定值，方便测试。
    function description() external pure override(AggregatorV3Interface) returns(string memory) {
        return "AuctionERC20";
    }

    // AggregatorV3Interface 接口实现，返回固定值，方便测试。
    function version() external pure returns(uint256) {
        return 1;
    }

    // AggregatorV3Interface 接口实现，返回固定值，方便测试。
    function getRoundData(uint80 _roundId) external view returns(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (_roundId, 1e8, block.timestamp, block.timestamp, uint80(1));
    }

    // AggregatorV3Interface 接口实现，返回固定值，方便测试。
    function latestRoundData() external view returns(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (uint80(1), 1e8, block.timestamp, block.timestamp, uint80(1));
    }
}
