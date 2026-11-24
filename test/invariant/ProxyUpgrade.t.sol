// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Slots} from "../../src/upgradeability/ERC1967Slots.sol";
import {UpgradeChecks} from "../../src/upgradeability/UpgradeChecks.sol";
import {SettingsProxy, UpgradeableSettingsV1, UpgradeableSettingsV2} from "../fixtures/UpgradeableSettings.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Test} from "forge-std/Test.sol";

contract ProxyUpgradeInvariantTest is Test {
    address private constant ADMIN = address(0xAD01);
    address private constant OWNER = address(0xA11CE);
    uint256 private constant INITIAL_LIMIT = 100;

    UpgradeableSettingsV1 private first;
    UpgradeableSettingsV2 private second;
    SettingsProxy private proxy;
    UpgradeableSettingsV1 private settings;
    ProxyUpgradeHandler private handler;

    function setUp() public {
        first = new UpgradeableSettingsV1();
        second = new UpgradeableSettingsV2();
        proxy = new SettingsProxy(address(first), ADMIN, OWNER, INITIAL_LIMIT);
        settings = UpgradeableSettingsV1(address(proxy));
        handler = new ProxyUpgradeHandler(proxy, ADMIN, OWNER, address(first), address(second), INITIAL_LIMIT);
        targetContract(address(handler));
    }

    function invariant_proxySlotsAndInitializedStateMatchModel() public view {
        address implementation = handler.expectedImplementation();
        ERC1967Slots.check(
            ERC1967Slots.Snapshot(bytes32(uint256(uint160(implementation))), 0, bytes32(uint256(uint160(ADMIN)))),
            handler.readSlots()
        );
        assertEq(settings.owner(), OWNER);
        assertEq(settings.limit(), handler.expectedLimit());
        assertEq(settings.revision(), implementation == address(first) ? 1 : 2);
        UpgradeChecks.checkInitializationVersion(1, settings.initializedVersion());
    }

    function afterInvariant() public view {
        assertGt(handler.writes(), 0, "no settings update");
        assertGt(handler.upgrades(), 0, "no implementation change");
    }

    function test_proxyInitializesWhileBothImplementationsStayLocked() public view {
        UpgradeChecks.checkInitializationVersion(1, settings.initializedVersion());
        UpgradeChecks.checkInitializationVersion(type(uint64).max, first.initializedVersion());
        UpgradeChecks.checkInitializationVersion(type(uint64).max, second.initializedVersion());
    }

    function test_repeatedInitializationPreservesProxyState() public {
        bytes32 state = handler.stateDigest();
        ERC1967Slots.Snapshot memory slots = handler.readSlots();

        vm.expectRevert(abi.encodeWithSelector(UpgradeableSettingsV1.UnexpectedInitializationVersion.selector, 1));
        vm.prank(OWNER);
        settings.initialize(OWNER, INITIAL_LIMIT);

        UpgradeChecks.checkPreservedState(state, handler.stateDigest());
        ERC1967Slots.check(slots, handler.readSlots());
    }

    function test_proxyAdminAndApplicationOwnerHaveDistinctAuthority() public {
        bytes32 state = handler.stateDigest();
        ERC1967Slots.Snapshot memory slots = handler.readSlots();

        vm.expectRevert(SettingsProxy.NotAdmin.selector);
        vm.prank(OWNER);
        proxy.upgradeTo(address(second));

        vm.expectRevert(UpgradeableSettingsV1.NotOwner.selector);
        vm.prank(ADMIN);
        settings.setLimit(999);

        UpgradeChecks.checkPreservedState(state, handler.stateDigest());
        ERC1967Slots.check(slots, handler.readSlots());
    }

    function test_upgradeThenInitializeNewStorageOnce() public {
        handler.setLimit(200);
        handler.upgrade();
        UpgradeableSettingsV2 upgraded = UpgradeableSettingsV2(address(proxy));
        uint64 beforeVersion = upgraded.initializedVersion();
        bytes32 configuration = keccak256(abi.encode(upgraded.owner(), upgraded.limit()));
        ERC1967Slots.Snapshot memory slots = handler.readSlots();

        vm.prank(OWNER);
        upgraded.initializeV2(30);
        UpgradeChecks.checkVersionAdvance(beforeVersion, 2, upgraded.initializedVersion());
        UpgradeChecks.checkPreservedState(configuration, keccak256(abi.encode(upgraded.owner(), upgraded.limit())));
        assertEq(upgraded.cooldown(), 30);

        vm.expectRevert(abi.encodeWithSelector(UpgradeableSettingsV1.UnexpectedInitializationVersion.selector, 2));
        vm.prank(OWNER);
        upgraded.initializeV2(31);

        UpgradeChecks.checkInitializationVersion(2, upgraded.initializedVersion());
        assertEq(upgraded.cooldown(), 30);
        ERC1967Slots.check(slots, handler.readSlots());
    }
}

contract ProxyUpgradeHandler is CommonBase {
    SettingsProxy private immutable proxy;
    UpgradeableSettingsV1 private immutable settings;
    address private immutable admin;
    address private immutable owner;
    address private immutable first;
    address private immutable second;

    address public expectedImplementation;
    uint256 public expectedLimit;
    uint256 public writes;
    uint256 public upgrades;

    constructor(SettingsProxy proxy_, address admin_, address owner_, address first_, address second_, uint256 limit_) {
        proxy = proxy_;
        settings = UpgradeableSettingsV1(address(proxy_));
        admin = admin_;
        owner = owner_;
        first = first_;
        second = second_;
        expectedImplementation = first_;
        expectedLimit = limit_;
    }

    function setLimit(uint256 value) external {
        vm.prank(owner);
        settings.setLimit(value);
        expectedLimit = value;
        ++writes;
    }

    function upgrade() external {
        address next = expectedImplementation == first ? second : first;
        ERC1967Slots.Snapshot memory expected = readSlots();
        expected.implementation = bytes32(uint256(uint160(next)));
        bytes32 state = stateDigest();

        vm.prank(admin);
        proxy.upgradeTo(next);
        ERC1967Slots.check(expected, readSlots());
        UpgradeChecks.checkPreservedState(state, stateDigest());
        expectedImplementation = next;
        ++upgrades;
    }

    function readSlots() public view returns (ERC1967Slots.Snapshot memory) {
        address target = address(proxy);
        return ERC1967Slots.Snapshot(
            vm.load(target, ERC1967Slots.IMPLEMENTATION_SLOT),
            vm.load(target, ERC1967Slots.BEACON_SLOT),
            vm.load(target, ERC1967Slots.ADMIN_SLOT)
        );
    }

    function stateDigest() public view returns (bytes32) {
        return keccak256(abi.encode(settings.owner(), settings.limit(), settings.initializedVersion()));
    }
}
