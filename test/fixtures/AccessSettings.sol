// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OwnedSettings {
    error NotOwner();
    error InvalidOwner();

    address public owner;
    uint96 public limit;

    constructor(address owner_) {
        if (owner_ == address(0)) revert InvalidOwner();
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert InvalidOwner();
        owner = nextOwner;
    }

    function setLimit(uint96 value) external onlyOwner {
        limit = value;
    }
}

contract RoleSettings {
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant OPERATOR_ADMIN_ROLE = keccak256("OPERATOR_ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    error MissingRole(bytes32 role, address account);

    mapping(bytes32 => mapping(address => bool)) public hasRole;
    mapping(bytes32 => bytes32) public getRoleAdmin;
    uint96 public limit;

    constructor(address root, address operatorAdmin) {
        hasRole[DEFAULT_ADMIN_ROLE][root] = true;
        hasRole[OPERATOR_ADMIN_ROLE][operatorAdmin] = true;
        getRoleAdmin[OPERATOR_ROLE] = OPERATOR_ADMIN_ROLE;
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole[role][msg.sender]) revert MissingRole(role, msg.sender);
        _;
    }

    function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin[role]) {
        hasRole[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin[role]) {
        hasRole[role][account] = false;
    }

    function setLimit(uint96 value) external onlyRole(OPERATOR_ROLE) {
        limit = value;
    }
}
