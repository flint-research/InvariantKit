// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../accounting/AssetAccounting.sol";

interface IBalanceSource {
    function balanceOf(address holder) external view returns (uint256);
}

library AssetBoundary {
    struct Balance {
        address holder;
        uint256 amount;
    }

    struct Snapshot {
        address asset;
        Balance[] balances;
    }

    error EmptyBoundary();
    error HoldersOutOfOrder(uint256 index, address previous, address current);
    error AssetMismatch(address expectedAsset, address observedAsset);
    error BoundarySizeMismatch(uint256 beforeCount, uint256 afterCount);
    error HolderMismatch(uint256 index, address beforeHolder, address afterHolder);

    function capture(IBalanceSource asset, address[] memory holders) internal view returns (Snapshot memory snapshot) {
        if (holders.length == 0) revert EmptyBoundary();
        snapshot.asset = address(asset);
        snapshot.balances = new Balance[](holders.length);
        for (uint256 i; i < holders.length; ++i) {
            if (i != 0) _checkOrder(i, holders[i - 1], holders[i]);
            snapshot.balances[i] = Balance(holders[i], asset.balanceOf(holders[i]));
        }
    }

    function total(Snapshot memory snapshot) internal pure returns (uint256 amount) {
        Balance[] memory balances = snapshot.balances;
        if (balances.length == 0) revert EmptyBoundary();
        for (uint256 i; i < balances.length; ++i) {
            Balance memory balance = balances[i];
            if (i != 0) _checkOrder(i, balances[i - 1].holder, balance.holder);
            if (balance.amount > type(uint256).max - amount) {
                revert AssetAccounting.BalanceSumOverflow(i, amount, balance.amount);
            }
            amount += balance.amount;
        }
    }

    function checkConservation(
        Snapshot memory beforeSnapshot,
        Snapshot memory afterSnapshot,
        uint256 inflow,
        uint256 outflow,
        uint256 tolerance
    ) internal pure {
        if (beforeSnapshot.asset != afterSnapshot.asset) {
            revert AssetMismatch(beforeSnapshot.asset, afterSnapshot.asset);
        }
        uint256 count = beforeSnapshot.balances.length;
        if (count != afterSnapshot.balances.length) {
            revert BoundarySizeMismatch(count, afterSnapshot.balances.length);
        }
        for (uint256 i; i < count; ++i) {
            address beforeHolder = beforeSnapshot.balances[i].holder;
            address afterHolder = afterSnapshot.balances[i].holder;
            if (beforeHolder != afterHolder) revert HolderMismatch(i, beforeHolder, afterHolder);
        }

        AssetAccounting.checkBalance(
            AssetAccounting.BalanceChange(total(beforeSnapshot), total(afterSnapshot), inflow, outflow), tolerance
        );
    }

    function checkReportedAssets(address reportedAsset, uint256 reported, Snapshot memory custody, uint256 tolerance)
        internal
        pure
    {
        if (reportedAsset != custody.asset) revert AssetMismatch(reportedAsset, custody.asset);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(total(custody), reported, 0, 0), tolerance);
    }

    function _checkOrder(uint256 index, address previous, address current) private pure {
        if (uint160(previous) >= uint160(current)) revert HoldersOutOfOrder(index, previous, current);
    }
}
