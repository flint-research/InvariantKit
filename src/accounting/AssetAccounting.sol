// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library AssetAccounting {
    struct BalanceChange {
        uint256 beforeBalance;
        uint256 afterBalance;
        uint256 credits;
        uint256 debits;
    }

    error InvalidBalanceTransition(uint256 beforeBalance, uint256 credits, uint256 debits);
    error BalanceMismatch(uint256 expected, uint256 observed, uint256 tolerance);
    error BalanceSumOverflow(uint256 index, uint256 subtotal, uint256 balance);
    error SupplyMismatch(uint256 reported, uint256 accounted);

    function checkBalance(BalanceChange memory change, uint256 tolerance) internal pure {
        uint256 expected;
        if (change.credits >= change.debits) {
            uint256 increase = change.credits - change.debits;
            if (increase > type(uint256).max - change.beforeBalance) {
                revert InvalidBalanceTransition(change.beforeBalance, change.credits, change.debits);
            }
            expected = change.beforeBalance + increase;
        } else {
            uint256 decrease = change.debits - change.credits;
            if (decrease > change.beforeBalance) {
                revert InvalidBalanceTransition(change.beforeBalance, change.credits, change.debits);
            }
            expected = change.beforeBalance - decrease;
        }

        uint256 observed = change.afterBalance;
        uint256 difference = expected >= observed ? expected - observed : observed - expected;
        if (difference > tolerance) revert BalanceMismatch(expected, observed, tolerance);
    }

    function checkSupply(uint256 reported, uint256[] memory balances) internal pure {
        uint256 accounted = sumBalances(balances);
        if (accounted != reported) revert SupplyMismatch(reported, accounted);
    }

    function sumBalances(uint256[] memory balances) internal pure returns (uint256 accounted) {
        for (uint256 i; i < balances.length; ++i) {
            uint256 balance = balances[i];
            if (balance > type(uint256).max - accounted) revert BalanceSumOverflow(i, accounted, balance);
            accounted += balance;
        }
    }
}
