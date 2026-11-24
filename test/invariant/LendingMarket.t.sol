// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../../src/accounting/AssetAccounting.sol";
import {ILendingAdapter, LendingChecks} from "../../src/lending/LendingChecks.sol";
import {LendingMarket, FixedPriceLendingAdapter} from "../fixtures/LendingMarket.sol";
import {TestAsset} from "../fixtures/TestERC20.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Test} from "forge-std/Test.sol";

contract LendingMarketInvariantTest is Test {
    uint256 private constant INITIAL_CASH = 1_000_000 ether;
    uint256 private constant ACTOR_COLLATERAL = 100_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    TestAsset private collateralAsset;
    TestAsset private debtAsset;
    LendingMarket private market;
    ILendingAdapter private adapter;
    LendingHandler private handler;

    function setUp() public {
        collateralAsset = new TestAsset();
        debtAsset = new TestAsset();
        market = new LendingMarket(collateralAsset, debtAsset);
        adapter = new FixedPriceLendingAdapter(market);
        debtAsset.fund(address(market), INITIAL_CASH);
        _fundActor(ALICE);
        _fundActor(BOB);
        handler = new LendingHandler(market, adapter, ALICE, BOB);
        targetContract(address(handler));
    }

    function invariant_debtAndCollateralReconcile() public view {
        uint256[] memory debts = new uint256[](2);
        debts[0] = _checkActor(ALICE);
        debts[1] = _checkActor(BOB);
        LendingChecks.checkTotalDebt(adapter.totalDebt(), debts);

        uint256 postedCollateral = handler.expectedCollateral(ALICE) + handler.expectedCollateral(BOB);
        assertEq(collateralAsset.balanceOf(address(market)), postedCollateral);
        AssetAccounting.checkBalance(
            AssetAccounting.BalanceChange(
                INITIAL_CASH, debtAsset.balanceOf(address(market)), handler.repaid(), handler.borrowed()
            ),
            0
        );
    }

    function afterInvariant() public view {
        assertGt(handler.supplied(), 0, "no collateral supplied");
        assertGt(handler.released(), 0, "no collateral released");
        assertGt(handler.borrowed(), 0, "no borrowing");
        assertGt(handler.repaid(), 0, "no repayment");
    }

    function test_borrowAtNormalizedCapacityAndClosePosition() public {
        handler.supply(99, true);
        handler.borrow(89, true);
        LendingChecks.Position memory position = adapter.position(ALICE);
        assertEq(position.debt, 90);
        assertEq(position.debtValue, 180);
        assertEq(position.borrowLimit, 180);

        handler.repay(89, true);
        handler.withdraw(99, true);
        assertEq(adapter.totalDebt(), 0);
        assertEq(market.collateralOf(ALICE), 0);
        invariant_debtAndCollateralReconcile();
    }

    function _checkActor(address borrower) private view returns (uint256) {
        uint256 collateral = handler.expectedCollateral(borrower);
        LendingChecks.Position memory position = adapter.position(borrower);
        assertEq(market.collateralOf(borrower), collateral);
        assertEq(collateralAsset.balanceOf(borrower), ACTOR_COLLATERAL - collateral);
        assertEq(position.debt, handler.expectedDebt(borrower));
        assertEq(position.debt, debtAsset.balanceOf(borrower));
        assertEq(position.debtValue, position.debt * 2);
        assertEq(position.borrowLimit, collateral * 9 / 5);
        LendingChecks.checkBorrowLimit(position);
        return position.debt;
    }

    function _fundActor(address borrower) private {
        collateralAsset.fund(borrower, ACTOR_COLLATERAL);
        vm.prank(borrower);
        require(collateralAsset.approve(address(market), type(uint256).max));
        vm.prank(borrower);
        require(debtAsset.approve(address(market), type(uint256).max));
    }
}

contract LendingHandler is CommonBase {
    uint256 private constant MAX_ACTION = 1_000 ether;

    LendingMarket private immutable market;
    ILendingAdapter private immutable adapter;
    TestAsset private immutable collateralAsset;
    TestAsset private immutable debtAsset;
    address private immutable alice;
    address private immutable bob;

    mapping(address => uint256) public expectedCollateral;
    mapping(address => uint256) public expectedDebt;
    uint256 public supplied;
    uint256 public released;
    uint256 public borrowed;
    uint256 public repaid;

    constructor(LendingMarket market_, ILendingAdapter adapter_, address alice_, address bob_) {
        market = market_;
        adapter = adapter_;
        collateralAsset = market_.collateralAsset();
        debtAsset = market_.debtAsset();
        alice = alice_;
        bob = bob_;
    }

    function supply(uint256 seed, bool useAlice) external {
        address borrower = useAlice ? alice : bob;
        uint256 amount = _amount(seed, collateralAsset.balanceOf(borrower));
        if (amount == 0) return;

        vm.prank(borrower);
        market.supply(amount);
        expectedCollateral[borrower] += amount;
        supplied += amount;
    }

    function withdraw(uint256 seed, bool useAlice) external {
        address borrower = useAlice ? alice : bob;
        uint256 requiredCollateral = (expectedDebt[borrower] * 10 + 8) / 9;
        uint256 amount = _amount(seed, expectedCollateral[borrower] - requiredCollateral);
        if (amount == 0) return;

        vm.prank(borrower);
        market.withdraw(amount);
        expectedCollateral[borrower] -= amount;
        released += amount;
        LendingChecks.checkBorrowLimit(adapter.position(borrower));
    }

    function borrow(uint256 seed, bool useAlice) external {
        address borrower = useAlice ? alice : bob;
        uint256 headroom = expectedCollateral[borrower] * 9 / 10 - expectedDebt[borrower];
        uint256 cash = debtAsset.balanceOf(address(market));
        uint256 amount = _amount(seed, cash < headroom ? cash : headroom);
        if (amount == 0) return;

        uint256 beforeDebt = adapter.position(borrower).debt;
        vm.prank(borrower);
        market.borrow(amount);
        LendingChecks.checkBorrow(beforeDebt, adapter.position(borrower), amount, 0);
        expectedDebt[borrower] += amount;
        borrowed += amount;
    }

    function repay(uint256 seed, bool useAlice) external {
        address borrower = useAlice ? alice : bob;
        uint256 amount = _amount(seed, expectedDebt[borrower]);
        if (amount == 0) return;

        uint256 beforeDebt = adapter.position(borrower).debt;
        vm.prank(borrower);
        market.repay(amount);
        LendingChecks.checkRepayment(beforeDebt, adapter.position(borrower).debt, amount, 0);
        expectedDebt[borrower] -= amount;
        repaid += amount;
    }

    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        if (limit == 0) return 0;
        uint256 capped = limit < MAX_ACTION ? limit : MAX_ACTION;
        return 1 + (seed % capped);
    }
}
