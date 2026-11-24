// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library AccessChecks {
    struct Attempt {
        address caller;
        bytes4 selector;
        bool accepted;
        bytes32 stateBefore;
        bytes32 stateAfter;
    }

    error OwnerMismatch(address expected, address observed);
    error RoleMembershipMismatch(bytes32 role, address account, bool expected, bool observed);
    error RoleAdminMismatch(bytes32 role, bytes32 expected, bytes32 observed);
    error UnexpectedAcceptance(address caller, bytes4 selector);
    error ProtectedStateChanged(address caller, bytes4 selector, bytes32 beforeState, bytes32 afterState);

    function checkOwner(address expected, address observed) internal pure {
        if (expected != observed) revert OwnerMismatch(expected, observed);
    }

    function checkRole(bytes32 role, address account, bool expected, bool observed) internal pure {
        if (expected != observed) revert RoleMembershipMismatch(role, account, expected, observed);
    }

    function checkRoleAdmin(bytes32 role, bytes32 expected, bytes32 observed) internal pure {
        if (expected != observed) revert RoleAdminMismatch(role, expected, observed);
    }

    function checkDenied(Attempt memory attempt) internal pure {
        if (attempt.accepted) revert UnexpectedAcceptance(attempt.caller, attempt.selector);
        if (attempt.stateBefore != attempt.stateAfter) {
            revert ProtectedStateChanged(attempt.caller, attempt.selector, attempt.stateBefore, attempt.stateAfter);
        }
    }
}
