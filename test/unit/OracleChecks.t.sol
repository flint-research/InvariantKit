// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainlinkFeed} from "../../src/oracle/ChainlinkFeed.sol";
import {OracleChecks} from "../../src/oracle/OracleChecks.sol";
import {MockChainlinkFeed} from "../fixtures/MockChainlinkFeed.sol";
import {Test} from "forge-std/Test.sol";

contract OracleChecksTest is Test {
    uint256 private constant OBSERVED_AT = 10_000;
    uint256 private constant MAX_AGE = 60;
    int256 private constant MIN_PRICE = 100e8;
    int256 private constant MAX_PRICE = 10_000e8;

    MockChainlinkFeed private feed;

    function setUp() public {
        feed = new MockChainlinkFeed(8);
    }

    function test_chainlinkReadUsesUpdatedAt() public {
        feed.publish(2_000e8, 1, OBSERVED_AT - MAX_AGE);
        OracleChecks.Observation memory observation = ChainlinkFeed.read(feed);
        assertEq(observation.answer, 2_000e8);
        assertEq(observation.updatedAt, OBSERVED_AT - MAX_AGE);
        assertEq(observation.decimals, 8);

        OracleChecks.check(observation, _pricePolicy(), OBSERVED_AT);
    }

    function test_chainlinkReadPropagatesMissingRoundError() public {
        vm.expectRevert(MockChainlinkFeed.NoData.selector);
        this.checkFeed(OBSERVED_AT);
    }

    function test_chainlinkRejectsAnUpdateOneSecondPastTheLimit() public {
        feed.publish(MAX_PRICE, 1, OBSERVED_AT - MAX_AGE - 1);
        vm.expectRevert(abi.encodeWithSelector(OracleChecks.StaleUpdate.selector, MAX_AGE + 1, MAX_AGE));
        this.checkFeed(OBSERVED_AT);
    }

    function test_zeroTimestampIsMissingEvenAtTimeZero() public {
        vm.expectRevert(OracleChecks.MissingUpdate.selector);
        this.checkObservation(OracleChecks.Observation(MIN_PRICE, 0, 8), _pricePolicy(), 0);
    }

    function test_futureTimestampRejectedBeforeAgeArithmetic() public {
        uint256 future = type(uint256).max;
        vm.expectRevert(abi.encodeWithSelector(OracleChecks.FutureUpdate.selector, future, OBSERVED_AT));
        this.checkObservation(OracleChecks.Observation(MIN_PRICE, future, 8), _pricePolicy(), OBSERVED_AT);
    }

    function test_rejectsUnexpectedDecimals() public {
        feed = new MockChainlinkFeed(18);
        feed.publish(MIN_PRICE, OBSERVED_AT, OBSERVED_AT);

        vm.expectRevert(abi.encodeWithSelector(OracleChecks.UnexpectedDecimals.selector, 8, 18));
        this.checkFeed(OBSERVED_AT);
    }

    function test_positivePricePolicyRejectsNegativeAnswer() public {
        vm.expectRevert(
            abi.encodeWithSelector(OracleChecks.AnswerOutOfRange.selector, int256(-1), MIN_PRICE, MAX_PRICE)
        );
        this.checkObservation(OracleChecks.Observation(-1, OBSERVED_AT, 8), _pricePolicy(), OBSERVED_AT);
    }

    function test_signedPolicyAllowsEitherEndpoint() public pure {
        OracleChecks.Policy memory policy = OracleChecks.Policy(-100, -1, 0, 3);
        OracleChecks.check(OracleChecks.Observation(-100, OBSERVED_AT, 3), policy, OBSERVED_AT);
        OracleChecks.check(OracleChecks.Observation(-1, OBSERVED_AT, 3), policy, OBSERVED_AT);
    }

    function test_rejectsInvertedAnswerRange() public {
        vm.expectRevert(abi.encodeWithSelector(OracleChecks.InvalidAnswerRange.selector, int256(1), int256(0)));
        this.checkObservation(OracleChecks.Observation(0, OBSERVED_AT, 8), OracleChecks.Policy(1, 0, 0, 8), OBSERVED_AT);
    }

    function testFuzz_maxAgeIsInclusive(uint128 timestamp, uint128 age) public pure {
        uint256 updatedAt = uint256(timestamp) + 1;
        OracleChecks.Policy memory policy = OracleChecks.Policy(MIN_PRICE, MAX_PRICE, age, 8);
        OracleChecks.check(OracleChecks.Observation(MAX_PRICE, updatedAt, 8), policy, updatedAt + age);
    }

    function checkFeed(uint256 observedAt) external view {
        OracleChecks.check(ChainlinkFeed.read(feed), _pricePolicy(), observedAt);
    }

    function checkObservation(
        OracleChecks.Observation calldata observation,
        OracleChecks.Policy calldata policy,
        uint256 observedAt
    ) external pure {
        OracleChecks.check(observation, policy, observedAt);
    }

    function _pricePolicy() private pure returns (OracleChecks.Policy memory) {
        return OracleChecks.Policy(MIN_PRICE, MAX_PRICE, MAX_AGE, 8);
    }
}
