// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ERC1967Slots {
    bytes32 internal constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    bytes32 internal constant BEACON_SLOT = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
    bytes32 internal constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    struct Snapshot {
        bytes32 implementation;
        bytes32 beacon;
        bytes32 admin;
    }

    error SlotMismatch(bytes32 slot, bytes32 expected, bytes32 observed);

    function check(Snapshot memory expected, Snapshot memory observed) internal pure {
        _check(IMPLEMENTATION_SLOT, expected.implementation, observed.implementation);
        _check(BEACON_SLOT, expected.beacon, observed.beacon);
        _check(ADMIN_SLOT, expected.admin, observed.admin);
    }

    function _check(bytes32 slot, bytes32 expected, bytes32 observed) private pure {
        if (expected != observed) revert SlotMismatch(slot, expected, observed);
    }
}
