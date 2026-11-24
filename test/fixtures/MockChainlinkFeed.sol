// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IChainlinkFeed} from "../../src/oracle/ChainlinkFeed.sol";

contract MockChainlinkFeed is IChainlinkFeed {
    error NoData();

    uint8 public immutable decimals;
    uint80 private round;
    int256 private answer;
    uint256 private startedAt;
    uint256 private updatedAt;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function publish(int256 answer_, uint256 startedAt_, uint256 updatedAt_) external {
        ++round;
        answer = answer_;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (round == 0) revert NoData();
        return (round, answer, startedAt, updatedAt, round);
    }
}
