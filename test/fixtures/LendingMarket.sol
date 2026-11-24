// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILendingAdapter, LendingChecks} from "../../src/lending/LendingChecks.sol";
import {TestAsset} from "./TestERC20.sol";

contract LendingMarket {
    TestAsset public immutable collateralAsset;
    TestAsset public immutable debtAsset;

    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;
    uint256 public totalDebt;

    constructor(TestAsset collateralAsset_, TestAsset debtAsset_) {
        collateralAsset = collateralAsset_;
        debtAsset = debtAsset_;
    }

    function supply(uint256 amount) external {
        require(collateralAsset.transferFrom(msg.sender, address(this), amount));
        collateralOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        collateralOf[msg.sender] -= amount;
        require(2 * debtOf[msg.sender] <= borrowLimit(msg.sender));
        require(collateralAsset.transfer(msg.sender, amount));
    }

    function borrow(uint256 amount) external {
        uint256 newDebt = debtOf[msg.sender] + amount;
        require(2 * newDebt <= borrowLimit(msg.sender));
        debtOf[msg.sender] = newDebt;
        totalDebt += amount;
        require(debtAsset.transfer(msg.sender, amount));
    }

    function repay(uint256 amount) external {
        require(debtAsset.transferFrom(msg.sender, address(this), amount));
        debtOf[msg.sender] -= amount;
        totalDebt -= amount;
    }

    function borrowLimit(address borrower) public view returns (uint256) {
        uint256 collateralValue = 3 * collateralOf[borrower];
        return collateralValue * 60 / 100;
    }
}

contract FixedPriceLendingAdapter is ILendingAdapter {
    LendingMarket private immutable market;

    constructor(LendingMarket market_) {
        market = market_;
    }

    function position(address borrower) external view returns (LendingChecks.Position memory) {
        uint256 debt = market.debtOf(borrower);
        return LendingChecks.Position(debt, 2 * debt, market.borrowLimit(borrower));
    }

    function totalDebt() external view returns (uint256) {
        return market.totalDebt();
    }
}
