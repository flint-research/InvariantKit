// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626Preview} from "./ERC4626Preview.sol";

library ERC4626Flow {
    struct Balances {
        uint256 assets;
        uint256 shares;
    }

    enum Unit {
        Assets,
        Shares
    }

    error BalanceDelta(
        ERC4626Preview.Operation operation, Unit unit, uint256 beforeBalance, uint256 afterBalance, uint256 expected
    );

    function check(
        ERC4626Preview.Operation operation,
        Balances memory beforeAction,
        Balances memory afterAction,
        uint256 assets,
        uint256 shares
    ) internal pure {
        bool entry = operation == ERC4626Preview.Operation.Deposit || operation == ERC4626Preview.Operation.Mint;
        if (!_matches(beforeAction.assets, afterAction.assets, assets, !entry)) {
            revert BalanceDelta(operation, Unit.Assets, beforeAction.assets, afterAction.assets, assets);
        }
        if (!_matches(beforeAction.shares, afterAction.shares, shares, entry)) {
            revert BalanceDelta(operation, Unit.Shares, beforeAction.shares, afterAction.shares, shares);
        }
    }

    function _matches(uint256 beforeBalance, uint256 afterBalance, uint256 expected, bool increase)
        private
        pure
        returns (bool)
    {
        if (increase) return afterBalance >= beforeBalance && afterBalance - beforeBalance == expected;
        return beforeBalance >= afterBalance && beforeBalance - afterBalance == expected;
    }
}
