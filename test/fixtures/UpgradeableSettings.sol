// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Slots} from "../../src/upgradeability/ERC1967Slots.sol";

contract UpgradeableSettingsV1 {
    error NotOwner();
    error InvalidOwner();
    error UnexpectedInitializationVersion(uint64 observed);

    address public owner;
    uint64 public initializedVersion;
    uint256 public limit;

    constructor() {
        initializedVersion = type(uint64).max;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function initialize(address owner_, uint256 limit_) external {
        if (initializedVersion != 0) revert UnexpectedInitializationVersion(initializedVersion);
        if (owner_ == address(0)) revert InvalidOwner();
        initializedVersion = 1;
        owner = owner_;
        limit = limit_;
    }

    function setLimit(uint256 value) external onlyOwner {
        limit = value;
    }

    function revision() external pure virtual returns (uint256) {
        return 1;
    }
}

contract UpgradeableSettingsV2 is UpgradeableSettingsV1 {
    uint256 public cooldown;

    function initializeV2(uint256 cooldown_) external onlyOwner {
        if (initializedVersion != 1) revert UnexpectedInitializationVersion(initializedVersion);
        initializedVersion = 2;
        cooldown = cooldown_;
    }

    function revision() external pure override returns (uint256) {
        return 2;
    }
}

contract SettingsProxy {
    error InvalidAdmin();
    error InvalidImplementation(address implementation);
    error NotAdmin();
    error InitializationFailed();

    constructor(address initialImplementation, address admin, address owner, uint256 limit) {
        if (admin == address(0)) revert InvalidAdmin();
        bytes32 adminSlot = ERC1967Slots.ADMIN_SLOT;
        assembly {
            sstore(adminSlot, admin)
        }
        _setImplementation(initialImplementation);
        (bool initialized,) =
            initialImplementation.delegatecall(abi.encodeCall(UpgradeableSettingsV1.initialize, (owner, limit)));
        if (!initialized) revert InitializationFailed();
    }

    function upgradeTo(address nextImplementation) external {
        bytes32 slot = ERC1967Slots.ADMIN_SLOT;
        address admin;
        assembly {
            admin := sload(slot)
        }
        if (msg.sender != admin) revert NotAdmin();
        _setImplementation(nextImplementation);
    }

    fallback() external {
        bytes32 slot = ERC1967Slots.IMPLEMENTATION_SLOT;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), sload(slot), 0, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(0, 0, size)
            if iszero(success) { revert(0, size) }
            return(0, size)
        }
    }

    function _setImplementation(address implementation) private {
        if (implementation.code.length == 0) revert InvalidImplementation(implementation);
        bytes32 slot = ERC1967Slots.IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, implementation)
        }
    }
}
