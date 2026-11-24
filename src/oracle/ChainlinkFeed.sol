// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OracleChecks} from "./OracleChecks.sol";

interface IChainlinkFeed {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

library ChainlinkFeed {
    function read(IChainlinkFeed feed) internal view returns (OracleChecks.Observation memory observation) {
        (, observation.answer,, observation.updatedAt,) = feed.latestRoundData();
        observation.decimals = feed.decimals();
    }
}
