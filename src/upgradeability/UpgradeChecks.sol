// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpgradeChecks {
    error StateMismatch(bytes32 expected, bytes32 observed);
    error InvalidVersionAdvance(uint64 beforeVersion, uint64 expectedVersion);
    error VersionMismatch(uint64 expected, uint64 observed);

    function checkPreservedState(bytes32 beforeState, bytes32 afterState) internal pure {
        if (beforeState != afterState) revert StateMismatch(beforeState, afterState);
    }

    function checkInitializationVersion(uint64 expected, uint64 observed) internal pure {
        if (expected != observed) revert VersionMismatch(expected, observed);
    }

    function checkVersionAdvance(uint64 beforeVersion, uint64 expectedVersion, uint64 observedVersion) internal pure {
        if (expectedVersion <= beforeVersion) revert InvalidVersionAdvance(beforeVersion, expectedVersion);
        checkInitializationVersion(expectedVersion, observedVersion);
    }
}
