// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessChecks} from "../../src/access/AccessChecks.sol";
import {Test} from "forge-std/Test.sol";

contract AccessChecksTest is Test {
    address private constant ACTOR = address(0xA11CE);
    address private constant OTHER = address(0xB0B);
    bytes4 private constant ACTION = bytes4(keccak256("setLimit(uint96)"));
    bytes32 private constant ROLE = keccak256("OPERATOR");
    bytes32 private constant ADMIN_ROLE = keccak256("OPERATOR_ADMIN");

    function test_deniedWithUnchangedStatePasses() public pure {
        AccessChecks.checkDenied(AccessChecks.Attempt(ACTOR, ACTION, false, ROLE, ROLE));
    }

    function test_acceptanceFailsEvenIfProtectedStateIsUnchanged() public {
        vm.expectRevert(abi.encodeWithSelector(AccessChecks.UnexpectedAcceptance.selector, ACTOR, ACTION));
        this.checkDenied(AccessChecks.Attempt(ACTOR, ACTION, true, ROLE, ROLE));
    }

    function test_rejectionWithChangedStateFails() public {
        vm.expectRevert(
            abi.encodeWithSelector(AccessChecks.ProtectedStateChanged.selector, ACTOR, ACTION, ROLE, ADMIN_ROLE)
        );
        this.checkDenied(AccessChecks.Attempt(ACTOR, ACTION, false, ROLE, ADMIN_ROLE));
    }

    function test_authorityChecksReportDistinctMismatches() public {
        vm.expectRevert(abi.encodeWithSelector(AccessChecks.OwnerMismatch.selector, ACTOR, OTHER));
        this.checkOwner(ACTOR, OTHER);
        vm.expectRevert(abi.encodeWithSelector(AccessChecks.RoleMembershipMismatch.selector, ROLE, ACTOR, false, true));
        this.checkRole(ROLE, ACTOR, false, true);
        vm.expectRevert(abi.encodeWithSelector(AccessChecks.RoleAdminMismatch.selector, ROLE, ADMIN_ROLE, bytes32(0)));
        this.checkRoleAdmin(ROLE, ADMIN_ROLE, bytes32(0));
    }

    function checkDenied(AccessChecks.Attempt calldata attempt) external pure {
        AccessChecks.checkDenied(attempt);
    }

    function checkOwner(address expected, address observed) external pure {
        AccessChecks.checkOwner(expected, observed);
    }

    function checkRole(bytes32 role, address account, bool expected, bool observed) external pure {
        AccessChecks.checkRole(role, account, expected, observed);
    }

    function checkRoleAdmin(bytes32 role, bytes32 expected, bytes32 observed) external pure {
        AccessChecks.checkRoleAdmin(role, expected, observed);
    }
}
