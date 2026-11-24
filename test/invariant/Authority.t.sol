// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessChecks} from "../../src/access/AccessChecks.sol";
import {OwnedSettings, RoleSettings} from "../fixtures/AccessSettings.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Test} from "forge-std/Test.sol";

contract AuthorityInvariantTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant ROOT = address(0xAD01);
    address private constant OPERATOR_ADMIN = address(0xAD02);

    OwnedSettings private owned;
    RoleSettings private roles;
    AuthorityHandler private handler;
    bytes32 private operatorRole;
    bytes32 private operatorAdminRole;

    function setUp() public {
        owned = new OwnedSettings(ALICE);
        roles = new RoleSettings(ROOT, OPERATOR_ADMIN);
        operatorRole = roles.OPERATOR_ROLE();
        operatorAdminRole = roles.OPERATOR_ADMIN_ROLE();
        vm.prank(OPERATOR_ADMIN);
        roles.grantRole(operatorRole, ALICE);

        handler = new AuthorityHandler(owned, roles, ALICE, BOB, OPERATOR_ADMIN);
        targetContract(address(handler));
    }

    function invariant_authorityAndSettingsMatchPolicy() public view {
        AccessChecks.checkOwner(handler.expectedOwner(), owned.owner());
        AccessChecks.checkRoleAdmin(operatorRole, operatorAdminRole, roles.getRoleAdmin(operatorRole));
        AccessChecks.checkRoleAdmin(operatorAdminRole, bytes32(0), roles.getRoleAdmin(operatorAdminRole));
        _checkActorRoles(ROOT);
        _checkActorRoles(OPERATOR_ADMIN);
        _checkActorRoles(ALICE);
        _checkActorRoles(BOB);
        assertEq(owned.limit(), handler.expectedOwnedLimit());
        assertEq(roles.limit(), handler.expectedRoleLimit());
    }

    function afterInvariant() public view {
        assertGt(handler.transfers(), 0, "no ownership transfer");
        assertGt(handler.grants(), 0, "no role grant");
        assertGt(handler.revocations(), 0, "no role revocation");
        assertGt(handler.ownerWrites(), 0, "no owner action");
        assertGt(handler.operatorWrites(), 0, "no operator action");
    }

    function test_formerOwnerCannotWriteAfterTransfer() public {
        handler.rotateOwner();
        bytes32 beforeState = _ownedState();
        bool accepted;

        vm.prank(ALICE);
        try owned.setLimit(11) {
            accepted = true;
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(OwnedSettings.NotOwner.selector));
        }

        AccessChecks.checkDenied(
            AccessChecks.Attempt(ALICE, OwnedSettings.setLimit.selector, accepted, beforeState, _ownedState())
        );
        handler.setOwnedLimit(11);
        assertEq(owned.limit(), 11);
    }

    function test_revokedOperatorCannotWriteSettings() public {
        handler.revokeOperator(true);
        bytes32 beforeState = _roleState();
        bool accepted;

        vm.prank(ALICE);
        try roles.setLimit(11) {
            accepted = true;
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(RoleSettings.MissingRole.selector, operatorRole, ALICE));
        }

        AccessChecks.checkDenied(
            AccessChecks.Attempt(ALICE, RoleSettings.setLimit.selector, accepted, beforeState, _roleState())
        );
        AccessChecks.checkRole(operatorRole, ALICE, false, roles.hasRole(operatorRole, ALICE));
    }

    function test_roleAdminIsDistinguishedFromDefaultAdmin() public {
        bytes32 beforeState = _roleState();
        bool accepted;

        vm.prank(ROOT);
        try roles.grantRole(operatorRole, BOB) {
            accepted = true;
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(RoleSettings.MissingRole.selector, operatorAdminRole, ROOT));
        }

        AccessChecks.checkDenied(
            AccessChecks.Attempt(ROOT, RoleSettings.grantRole.selector, accepted, beforeState, _roleState())
        );
        handler.grantOperator(false);
        AccessChecks.checkRole(operatorRole, BOB, true, roles.hasRole(operatorRole, BOB));
    }

    function _checkActorRoles(address account) private view {
        AccessChecks.checkRole(bytes32(0), account, account == ROOT, roles.hasRole(bytes32(0), account));
        AccessChecks.checkRole(
            operatorAdminRole, account, account == OPERATOR_ADMIN, roles.hasRole(operatorAdminRole, account)
        );
        AccessChecks.checkRole(
            operatorRole, account, handler.expectedOperator(account), roles.hasRole(operatorRole, account)
        );
    }

    function _ownedState() private view returns (bytes32) {
        return keccak256(abi.encode(owned.owner(), owned.limit()));
    }

    function _roleState() private view returns (bytes32) {
        return
            keccak256(abi.encode(roles.limit(), roles.hasRole(operatorRole, ALICE), roles.hasRole(operatorRole, BOB)));
    }
}

contract AuthorityHandler is CommonBase {
    OwnedSettings private immutable owned;
    RoleSettings private immutable roles;
    address private immutable alice;
    address private immutable bob;
    address private immutable operatorAdmin;
    bytes32 private immutable operatorRole;

    address public expectedOwner;
    mapping(address => bool) public expectedOperator;
    uint96 public expectedOwnedLimit;
    uint96 public expectedRoleLimit;
    uint256 public transfers;
    uint256 public grants;
    uint256 public revocations;
    uint256 public ownerWrites;
    uint256 public operatorWrites;

    constructor(OwnedSettings owned_, RoleSettings roles_, address alice_, address bob_, address operatorAdmin_) {
        owned = owned_;
        roles = roles_;
        alice = alice_;
        bob = bob_;
        operatorAdmin = operatorAdmin_;
        operatorRole = roles_.OPERATOR_ROLE();
        expectedOwner = alice_;
        expectedOperator[alice_] = true;
    }

    function rotateOwner() external {
        address nextOwner = expectedOwner == alice ? bob : alice;

        vm.prank(expectedOwner);
        owned.transferOwnership(nextOwner);
        expectedOwner = nextOwner;
        ++transfers;
    }

    function grantOperator(bool toAlice) external {
        address account = toAlice ? alice : bob;
        if (expectedOperator[account]) return;

        vm.prank(operatorAdmin);
        roles.grantRole(operatorRole, account);
        expectedOperator[account] = true;
        ++grants;
    }

    function revokeOperator(bool fromAlice) external {
        address account = fromAlice ? alice : bob;
        if (!expectedOperator[account]) return;

        vm.prank(operatorAdmin);
        roles.revokeRole(operatorRole, account);
        expectedOperator[account] = false;
        ++revocations;
    }

    function setOwnedLimit(uint96 value) external {
        vm.prank(expectedOwner);
        owned.setLimit(value);
        expectedOwnedLimit = value;
        ++ownerWrites;
    }

    function setRoleLimit(bool useAlice, uint96 value) external {
        address account = useAlice ? alice : bob;
        if (!expectedOperator[account]) return;

        vm.prank(account);
        roles.setLimit(value);
        expectedRoleLimit = value;
        ++operatorWrites;
    }
}
