// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../../src/accounting/AssetAccounting.sol";
import {LendingChecks} from "../../src/lending/LendingChecks.sol";
import {Test} from "forge-std/Test.sol";

contract LendingChecksTest is Test {
    function test_borrowLimitUsesValueUnits() public {
        vm.expectRevert(abi.encodeWithSelector(LendingChecks.BorrowLimitExceeded.selector, 50, 49));
        this.checkBorrow(20, LendingChecks.Position(25, 50, 49), 5, 0);
    }

    function test_borrowAcceptsExactCapacityAndDebtTolerance() public pure {
        LendingChecks.checkBorrow(20, LendingChecks.Position(24, 48, 48), 5, 1);
    }

    function test_debtToleranceDoesNotRelaxTheBorrowLimit() public {
        vm.expectRevert(abi.encodeWithSelector(LendingChecks.BorrowLimitExceeded.selector, 48, 47));
        this.checkBorrow(20, LendingChecks.Position(24, 48, 47), 5, 1);
    }

    function test_reportsUnbookedDebtEvenWithinTheBorrowLimit() public {
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.BalanceMismatch.selector, 25, 20, 0));
        this.checkBorrow(20, LendingChecks.Position(20, 40, 50), 5, 0);
    }

    function test_repayChecksActualDebtDecrease() public {
        LendingChecks.checkRepayment(20, 15, 5, 0);
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.BalanceMismatch.selector, 15, 18, 0));
        this.checkRepayment(20, 18, 5);
    }

    function test_reportsMissingDebtInClosedBorrowerSet() public {
        uint256[] memory debts = new uint256[](2);
        debts[0] = 11;
        debts[1] = 12;
        LendingChecks.checkTotalDebt(23, debts);
        vm.expectRevert(abi.encodeWithSelector(LendingChecks.TotalDebtMismatch.selector, 25, 23));
        this.checkTotalDebt(25, debts);
    }

    function checkBorrow(
        uint256 beforeDebt,
        LendingChecks.Position calldata afterBorrow,
        uint256 incurred,
        uint256 tolerance
    ) external pure {
        LendingChecks.checkBorrow(beforeDebt, afterBorrow, incurred, tolerance);
    }

    function checkRepayment(uint256 beforeDebt, uint256 afterDebt, uint256 repaid) external pure {
        LendingChecks.checkRepayment(beforeDebt, afterDebt, repaid, 0);
    }

    function checkTotalDebt(uint256 reported, uint256[] calldata debts) external pure {
        LendingChecks.checkTotalDebt(reported, debts);
    }
}
