// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../../src/accounting/AssetAccounting.sol";
import {AssetBoundary, IBalanceSource} from "../../src/crosscontract/AssetBoundary.sol";
import {Test} from "forge-std/Test.sol";

contract AssetBoundaryTest is Test {
    address private constant TOKEN = address(0xA55E7);
    address private constant FIRST = address(0x1001);
    address private constant SECOND = address(0x1002);
    address private constant THIRD = address(0x1003);

    function test_internalMovementDoesNotChangeTheBoundaryTotal() public pure {
        AssetBoundary.checkConservation(_snapshot(TOKEN, SECOND, 10, 20), _snapshot(TOKEN, SECOND, 18, 12), 0, 0, 0);
    }

    function test_externalFlowsAndToleranceAreExplicit() public pure {
        AssetBoundary.checkConservation(_snapshot(TOKEN, SECOND, 10, 20), _snapshot(TOKEN, SECOND, 18, 14), 5, 2, 1);
    }

    function test_equalTotalsDoNotPermitReplacingAHolder() public {
        vm.expectRevert(abi.encodeWithSelector(AssetBoundary.HolderMismatch.selector, 1, SECOND, THIRD));
        this.checkConservation(_snapshot(TOKEN, SECOND, 10, 20), _snapshot(TOKEN, THIRD, 10, 20));
    }

    function test_equalTotalsDoNotPermitDifferentAssets() public {
        address otherToken = address(0xA55E8);
        vm.expectRevert(abi.encodeWithSelector(AssetBoundary.AssetMismatch.selector, TOKEN, otherToken));
        this.checkConservation(_snapshot(TOKEN, SECOND, 10, 20), _snapshot(otherToken, SECOND, 10, 20));
    }

    function test_matchingReportedAmountStillRequiresTheSameToken() public {
        address otherToken = address(0xA55E8);
        vm.expectRevert(abi.encodeWithSelector(AssetBoundary.AssetMismatch.selector, otherToken, TOKEN));
        this.checkReportedAssets(otherToken, 30, _snapshot(TOKEN, SECOND, 10, 20));
    }

    function test_duplicateAndUnsortedHoldersAreRejected() public {
        vm.expectRevert(abi.encodeWithSelector(AssetBoundary.HoldersOutOfOrder.selector, 1, FIRST, FIRST));
        this.total(_snapshot(TOKEN, FIRST, 10, 20));

        vm.expectRevert(abi.encodeWithSelector(AssetBoundary.HoldersOutOfOrder.selector, 1, FIRST, address(1)));
        this.total(_snapshot(TOKEN, address(1), 10, 20));
    }

    function test_emptyOrIncompleteSnapshotsAreRejected() public {
        AssetBoundary.Snapshot memory empty = AssetBoundary.Snapshot(TOKEN, new AssetBoundary.Balance[](0));
        vm.expectRevert(AssetBoundary.EmptyBoundary.selector);
        this.checkConservation(empty, empty);

        vm.expectRevert(abi.encodeWithSelector(AssetBoundary.BoundarySizeMismatch.selector, 2, 0));
        this.checkConservation(_snapshot(TOKEN, SECOND, 10, 20), empty);
    }

    function test_sumOverflowUsesTheAccountingError() public {
        uint256 maximum = type(uint256).max;
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.BalanceSumOverflow.selector, 1, maximum, 1));
        this.total(_snapshot(TOKEN, SECOND, maximum, 1));
    }

    function test_captureKeepsIdentityWithObservedBalances() public view {
        address[] memory holders = new address[](2);
        holders[0] = FIRST;
        holders[1] = SECOND;
        AssetBoundary.Snapshot memory snapshot = AssetBoundary.capture(IBalanceSource(address(this)), holders);
        assertEq(snapshot.asset, address(this));
        assertEq(snapshot.balances[0].holder, FIRST);
        assertEq(snapshot.balances[1].holder, SECOND);
        assertEq(snapshot.balances[0].amount, 10);
        assertEq(snapshot.balances[1].amount, 20);
    }

    function checkReportedAssets(address asset, uint256 reported, AssetBoundary.Snapshot calldata custody)
        external
        pure
    {
        AssetBoundary.checkReportedAssets(asset, reported, custody, 0);
    }

    function total(AssetBoundary.Snapshot calldata snapshot) external pure returns (uint256) {
        return AssetBoundary.total(snapshot);
    }

    function checkConservation(
        AssetBoundary.Snapshot calldata beforeSnapshot,
        AssetBoundary.Snapshot calldata afterSnapshot
    ) external pure {
        AssetBoundary.checkConservation(beforeSnapshot, afterSnapshot, 0, 0, 0);
    }

    function balanceOf(address holder) external pure returns (uint256) {
        return holder == FIRST ? 10 : 20;
    }

    function _snapshot(address token, address second, uint256 firstAmount, uint256 secondAmount)
        private
        pure
        returns (AssetBoundary.Snapshot memory snapshot)
    {
        snapshot.asset = token;
        snapshot.balances = new AssetBoundary.Balance[](2);
        snapshot.balances[0] = AssetBoundary.Balance(FIRST, firstAmount);
        snapshot.balances[1] = AssetBoundary.Balance(second, secondAmount);
    }
}
