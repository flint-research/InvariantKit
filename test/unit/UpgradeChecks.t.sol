// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Slots} from "../../src/upgradeability/ERC1967Slots.sol";
import {UpgradeChecks} from "../../src/upgradeability/UpgradeChecks.sol";
import {Test} from "forge-std/Test.sol";

contract UpgradeChecksTest is Test {
    function test_slotsMatchTheStandard() public pure {
        assertEq(ERC1967Slots.IMPLEMENTATION_SLOT, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertEq(ERC1967Slots.BEACON_SLOT, 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50);
        assertEq(ERC1967Slots.ADMIN_SLOT, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103);
    }

    function test_slotComparisonIncludesUpperBits() public {
        bytes32 expected = bytes32(uint256(1));
        bytes32 observed = bytes32((uint256(1) << 255) | 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC1967Slots.SlotMismatch.selector, ERC1967Slots.IMPLEMENTATION_SLOT, expected, observed
            )
        );
        this.checkSlots(ERC1967Slots.Snapshot(expected, 0, 0), ERC1967Slots.Snapshot(observed, 0, 0));
    }

    function test_beaconAndAdminMismatchIdentifyTheirSlots() public {
        bytes32 expected = bytes32(uint256(1));
        bytes32 observed = bytes32(uint256(2));
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Slots.SlotMismatch.selector, ERC1967Slots.BEACON_SLOT, expected, observed)
        );
        this.checkSlots(ERC1967Slots.Snapshot(0, expected, 0), ERC1967Slots.Snapshot(0, observed, 0));
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Slots.SlotMismatch.selector, ERC1967Slots.ADMIN_SLOT, expected, observed)
        );
        this.checkSlots(ERC1967Slots.Snapshot(0, 0, expected), ERC1967Slots.Snapshot(0, 0, observed));
    }

    function test_changedStateDigestFails() public {
        bytes32 beforeState = bytes32(uint256(1));
        bytes32 afterState = bytes32(uint256(2));
        vm.expectRevert(abi.encodeWithSelector(UpgradeChecks.StateMismatch.selector, beforeState, afterState));
        this.checkState(beforeState, afterState);
    }

    function test_initializerMustAdvanceToTheExpectedVersion() public {
        UpgradeChecks.checkVersionAdvance(1, 3, 3);
        vm.expectRevert(abi.encodeWithSelector(UpgradeChecks.InvalidVersionAdvance.selector, 2, 2));
        this.checkVersionAdvance(2, 2, 2);
        vm.expectRevert(abi.encodeWithSelector(UpgradeChecks.VersionMismatch.selector, 3, 2));
        this.checkVersionAdvance(1, 3, 2);
    }

    function checkSlots(ERC1967Slots.Snapshot calldata expected, ERC1967Slots.Snapshot calldata observed)
        external
        pure
    {
        ERC1967Slots.check(expected, observed);
    }

    function checkState(bytes32 beforeState, bytes32 afterState) external pure {
        UpgradeChecks.checkPreservedState(beforeState, afterState);
    }

    function checkVersionAdvance(uint64 beforeVersion, uint64 expectedVersion, uint64 observedVersion) external pure {
        UpgradeChecks.checkVersionAdvance(beforeVersion, expectedVersion, observedVersion);
    }
}
