// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../../src/accounting/AssetAccounting.sol";
import {AssetBoundary, IBalanceSource} from "../../src/crosscontract/AssetBoundary.sol";
import {ERC4626Flow} from "../../src/erc4626/ERC4626Flow.sol";
import {ERC4626Preview} from "../../src/erc4626/ERC4626Preview.sol";
import {FeeTreasury, StrategyVault} from "../fixtures/StrategyVault.sol";
import {TestAsset} from "../fixtures/TestERC20.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Test} from "forge-std/Test.sol";

contract VaultStrategyTreasuryInvariantTest is Test {
    uint256 private constant STARTING_ASSETS = 1_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant MANAGER = address(0xAD01);
    address private constant FEE_RECIPIENT = address(0xFEE);

    TestAsset private asset;
    FeeTreasury private treasury;
    StrategyVault private vault;
    CustodyHandler private handler;
    address[] private managedHolders;
    address[] private systemHolders;
    AssetBoundary.Snapshot private initialManaged;
    AssetBoundary.Snapshot private initialSystem;

    function setUp() public {
        asset = new TestAsset();
        treasury = new FeeTreasury(asset, MANAGER, FEE_RECIPIENT);
        vault = new StrategyVault(asset, treasury, MANAGER);
        _fundActor(ALICE);
        _fundActor(BOB);
        handler = new CustodyHandler(vault, MANAGER, ALICE, BOB);

        managedHolders.push(address(vault));
        managedHolders.push(address(vault.strategy()));
        _sort(managedHolders);
        systemHolders = managedHolders;
        systemHolders.push(address(treasury));
        _sort(systemHolders);
        _save(initialManaged, _capture(managedHolders));
        _save(initialSystem, _capture(systemHolders));

        targetContract(address(handler));
    }

    function invariant_assetsReconcileAcrossContracts() public view {
        AssetBoundary.Snapshot memory managed = _capture(managedHolders);
        AssetBoundary.Snapshot memory system = _capture(systemHolders);

        AssetBoundary.checkConservation(
            initialSystem, system, handler.deposited(), handler.withdrawn() + handler.distributed(), 0
        );
        AssetBoundary.checkConservation(
            initialManaged, managed, handler.deposited(), handler.withdrawn() + handler.entryFees(), 0
        );
        AssetBoundary.checkReportedAssets(address(vault.asset()), vault.totalAssets(), managed, 0);

        assertEq(asset.balanceOf(address(vault)), handler.expectedIdle());
        assertEq(asset.balanceOf(address(vault.strategy())), handler.expectedStrategy());
        assertEq(asset.balanceOf(address(treasury)), handler.entryFees() - handler.distributed());
        assertEq(asset.balanceOf(FEE_RECIPIENT), handler.distributed());
        assertEq(vault.totalSupply(), vault.balanceOf(ALICE) + vault.balanceOf(BOB));

        assertEq(
            AssetBoundary.total(system) + asset.balanceOf(ALICE) + asset.balanceOf(BOB)
                + asset.balanceOf(FEE_RECIPIENT),
            asset.totalSupply()
        );
        assertEq(asset.totalSupply(), 2 * STARTING_ASSETS);
    }

    function afterInvariant() public view {
        assertGt(handler.deposited(), 0, "no deposits");
        assertGt(handler.withdrawn(), 0, "no withdrawals");
        assertGt(handler.allocated(), 0, "no strategy allocation");
        assertGt(handler.recalled(), 0, "no strategy recall");
        assertGt(handler.distributed(), 0, "no treasury distribution");
    }

    function test_withdrawalRecallsInvestedFunds() public {
        handler.deposit(999, true);
        handler.allocate(989);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(vault.totalAssets(), 990);

        handler.withdraw(97, true);
        assertEq(handler.recalledForWithdrawal(), 98);
        assertEq(asset.balanceOf(address(vault.strategy())), 892);
        assertEq(vault.totalAssets(), 892);
        invariant_assetsReconcileAcrossContracts();
    }

    function test_treasuryFeesAreOutsideManagedAssets() public {
        handler.deposit(999, true);
        AssetBoundary.Snapshot memory system = _capture(systemHolders);
        assertEq(AssetBoundary.total(system), 1_000);
        assertEq(vault.totalAssets(), 990);

        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.BalanceMismatch.selector, 1_000, 990, 0));
        this.checkReportedAgainstSystem();

        handler.distribute(9);
        assertEq(asset.balanceOf(FEE_RECIPIENT), 10);
        assertEq(vault.totalAssets(), 990);
        invariant_assetsReconcileAcrossContracts();
    }

    function checkReportedAgainstSystem() external view {
        AssetBoundary.checkReportedAssets(address(vault.asset()), vault.totalAssets(), _capture(systemHolders), 0);
    }

    function _capture(address[] storage holders) private view returns (AssetBoundary.Snapshot memory) {
        return AssetBoundary.capture(IBalanceSource(address(asset)), holders);
    }

    function _save(AssetBoundary.Snapshot storage stored, AssetBoundary.Snapshot memory snapshot) private {
        stored.asset = snapshot.asset;
        for (uint256 i; i < snapshot.balances.length; ++i) {
            stored.balances.push(snapshot.balances[i]);
        }
    }

    function _sort(address[] storage holders) private {
        for (uint256 i = 1; i < holders.length; ++i) {
            for (uint256 j = i; j > 0 && uint160(holders[j]) < uint160(holders[j - 1]); --j) {
                (holders[j - 1], holders[j]) = (holders[j], holders[j - 1]);
            }
        }
    }

    function _fundActor(address user) private {
        asset.fund(user, STARTING_ASSETS);
        vm.prank(user);
        require(asset.approve(address(vault), type(uint256).max));
    }
}

contract CustodyHandler is CommonBase {
    uint256 private constant MAX_ACTION = 1_000 ether;

    StrategyVault private immutable vault;
    FeeTreasury private immutable treasury;
    TestAsset private immutable asset;
    address private immutable manager;
    address private immutable alice;
    address private immutable bob;

    uint256 public expectedIdle;
    uint256 public expectedStrategy;
    uint256 public deposited;
    uint256 public withdrawn;
    uint256 public allocated;
    uint256 public recalled;
    uint256 public recalledForWithdrawal;
    uint256 public entryFees;
    uint256 public distributed;

    constructor(StrategyVault vault_, address manager_, address alice_, address bob_) {
        vault = vault_;
        treasury = vault_.treasury();
        asset = TestAsset(address(vault_.asset()));
        manager = manager_;
        alice = alice_;
        bob = bob_;
    }

    function deposit(uint256 seed, bool useAlice) external {
        address user = useAlice ? alice : bob;
        uint256 amount = _amount(seed, asset.balanceOf(user));
        if (amount == 0) return;

        ERC4626Flow.Balances memory beforeDeposit = _balances(user);
        vm.prank(user);
        uint256 preview = vault.previewDeposit(amount);
        vm.prank(user);
        uint256 shares = vault.deposit(amount, user);
        ERC4626Preview.checkDeposit(preview, shares);
        ERC4626Flow.check(ERC4626Preview.Operation.Deposit, beforeDeposit, _balances(user), amount, shares);

        uint256 fee = (amount + 99) / 100;
        expectedIdle += amount - fee;
        entryFees += fee;
        deposited += amount;
    }

    function withdraw(uint256 seed, bool useAlice) external {
        address user = useAlice ? alice : bob;
        uint256 amount = _amount(seed, vault.maxWithdraw(user));
        if (amount == 0) return;

        ERC4626Flow.Balances memory beforeWithdrawal = _balances(user);
        vm.prank(user);
        uint256 preview = vault.previewWithdraw(amount);
        vm.prank(user);
        uint256 shares = vault.withdraw(amount, user, user);
        ERC4626Preview.checkWithdraw(preview, shares);
        ERC4626Flow.check(ERC4626Preview.Operation.Withdraw, beforeWithdrawal, _balances(user), amount, shares);

        uint256 pulled = amount > expectedIdle ? amount - expectedIdle : 0;
        expectedStrategy -= pulled;
        expectedIdle = expectedIdle + pulled - amount;
        recalledForWithdrawal += pulled;
        withdrawn += amount;
    }

    function allocate(uint256 seed) external {
        uint256 amount = _amount(seed, expectedIdle);
        if (amount == 0) return;

        vm.prank(manager);
        vault.allocate(amount);
        expectedIdle -= amount;
        expectedStrategy += amount;
        allocated += amount;
    }

    function recall(uint256 seed) external {
        uint256 amount = _amount(seed, expectedStrategy);
        if (amount == 0) return;

        vm.prank(manager);
        vault.recall(amount);
        expectedStrategy -= amount;
        expectedIdle += amount;
        recalled += amount;
    }

    function distribute(uint256 seed) external {
        uint256 amount = _amount(seed, entryFees - distributed);
        if (amount == 0) return;

        vm.prank(manager);
        treasury.distribute(amount);
        distributed += amount;
    }

    function _balances(address user) private view returns (ERC4626Flow.Balances memory) {
        return ERC4626Flow.Balances(asset.balanceOf(user), vault.balanceOf(user));
    }

    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        if (limit == 0) return 0;
        uint256 capped = limit < MAX_ACTION ? limit : MAX_ACTION;
        return 1 + (seed % capped);
    }
}
