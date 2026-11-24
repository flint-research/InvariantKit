// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library OracleChecks {
    struct Observation {
        int256 answer;
        uint256 updatedAt;
        uint8 decimals;
    }

    struct Policy {
        int256 minAnswer;
        int256 maxAnswer;
        uint256 maxAge;
        uint8 expectedDecimals;
    }

    error InvalidAnswerRange(int256 minimum, int256 maximum);
    error MissingUpdate();
    error FutureUpdate(uint256 updatedAt, uint256 observedAt);
    error StaleUpdate(uint256 age, uint256 maximumAge);
    error UnexpectedDecimals(uint8 expected, uint8 observed);
    error AnswerOutOfRange(int256 answer, int256 minimum, int256 maximum);

    function check(Observation memory observation, Policy memory policy, uint256 observedAt) internal pure {
        if (policy.minAnswer > policy.maxAnswer) revert InvalidAnswerRange(policy.minAnswer, policy.maxAnswer);
        if (observation.updatedAt == 0) revert MissingUpdate();
        if (observation.updatedAt > observedAt) revert FutureUpdate(observation.updatedAt, observedAt);

        uint256 age = observedAt - observation.updatedAt;
        if (age > policy.maxAge) revert StaleUpdate(age, policy.maxAge);
        if (observation.decimals != policy.expectedDecimals) {
            revert UnexpectedDecimals(policy.expectedDecimals, observation.decimals);
        }
        if (observation.answer < policy.minAnswer || observation.answer > policy.maxAnswer) {
            revert AnswerOutOfRange(observation.answer, policy.minAnswer, policy.maxAnswer);
        }
    }
}
