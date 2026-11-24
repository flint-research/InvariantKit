// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../accounting/AssetAccounting.sol";

library LendingChecks {
    struct Position {
        uint256 debt;
        uint256 debtValue;
        uint256 borrowLimit;
    }

    error BorrowLimitExceeded(uint256 debtValue, uint256 borrowLimit);
    error TotalDebtMismatch(uint256 reported, uint256 accounted);

    function checkBorrow(uint256 beforeDebt, Position memory afterBorrow, uint256 debtIncurred, uint256 tolerance)
        internal
        pure
    {
        AssetAccounting.checkBalance(
            AssetAccounting.BalanceChange(beforeDebt, afterBorrow.debt, debtIncurred, 0), tolerance
        );
        checkBorrowLimit(afterBorrow);
    }

    function checkBorrowLimit(Position memory position) internal pure {
        if (position.debtValue > position.borrowLimit) {
            revert BorrowLimitExceeded(position.debtValue, position.borrowLimit);
        }
    }

    function checkRepayment(uint256 beforeDebt, uint256 afterDebt, uint256 debtRepaid, uint256 tolerance)
        internal
        pure
    {
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(beforeDebt, afterDebt, 0, debtRepaid), tolerance);
    }

    function checkTotalDebt(uint256 reported, uint256[] memory positionDebts) internal pure {
        uint256 accounted = AssetAccounting.sumBalances(positionDebts);
        if (accounted != reported) revert TotalDebtMismatch(reported, accounted);
    }
}

interface ILendingAdapter {
    function position(address borrower) external view returns (LendingChecks.Position memory);
    function totalDebt() external view returns (uint256);
}
