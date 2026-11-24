// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../../src/accounting/AssetAccounting.sol";
import {FalseReturnAsset, RebasingAccountingAsset} from "../fixtures/AccountingAssets.sol";
import {Test} from "forge-std/Test.sol";

contract AssetAccountingTest is Test {
    function test_equalGrossFlowsDoNotOverflow() public pure {
        uint256 maximum = type(uint256).max;
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(maximum, maximum, maximum, maximum), 0);
    }

    function testFuzz_equalGrossFlowsCancel(uint128 balance, uint128 net, uint128 common) public pure {
        uint256 increased = uint256(balance) + net;
        uint256 largerFlow = uint256(net) + common;
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(balance, increased, largerFlow, common), 0);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(increased, balance, common, largerFlow), 0);
    }

    function test_toleranceUsesBaseUnitsAndIncludesTheBoundary() public {
        AssetAccounting.BalanceChange memory change = AssetAccounting.BalanceChange(100, 89, 10, 20);
        AssetAccounting.checkBalance(change, 1);
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.BalanceMismatch.selector, 90, 89, 0));
        this.checkBalance(change, 0);
    }

    function test_rejectsImpossibleCreditEvenWithTolerance() public {
        uint256 maximum = type(uint256).max;
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.InvalidBalanceTransition.selector, maximum, 1, 0));
        this.checkBalance(AssetAccounting.BalanceChange(maximum, maximum, 1, 0), 1);
    }

    function test_rejectsImpossibleDebitEvenWithTolerance() public {
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.InvalidBalanceTransition.selector, 5, 0, 6));
        this.checkBalance(AssetAccounting.BalanceChange(5, 0, 0, 6), 1);
    }

    function test_supplyReconciliationDetectsAnOmittedBalance() public {
        uint256[] memory balances = new uint256[](1);
        balances[0] = 60;
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.SupplyMismatch.selector, 100, 60));
        this.checkSupply(100, balances);
    }

    function test_supplyReconciliationReportsOverflow() public {
        uint256 maximum = type(uint256).max;
        uint256[] memory balances = new uint256[](2);
        balances[0] = maximum;
        balances[1] = 1;
        vm.expectRevert(abi.encodeWithSelector(AssetAccounting.BalanceSumOverflow.selector, 1, maximum, 1));
        this.checkSupply(maximum, balances);
    }

    function test_positiveAndNegativeRebasesReconcileRounding() public {
        address second = address(0xB0B);
        RebasingAccountingAsset asset = new RebasingAccountingAsset(address(this), second);
        asset.fund(address(this), 101);
        asset.fund(second, 39);

        asset.rebase(true);
        uint256[] memory balances = new uint256[](2);
        balances[0] = asset.balanceOf(address(this));
        balances[1] = asset.balanceOf(second);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(101, balances[0], 10, 0), 0);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(39, balances[1], 3, 0), 0);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(140, asset.totalSupply(), 13, 0), 0);
        AssetAccounting.checkSupply(asset.totalSupply(), balances);

        asset.rebase(false);
        balances[0] = asset.balanceOf(address(this));
        balances[1] = asset.balanceOf(second);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(111, balances[0], 0, 11), 0);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(42, balances[1], 0, 4), 0);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(153, asset.totalSupply(), 0, 15), 0);
        AssetAccounting.checkSupply(asset.totalSupply(), balances);
    }

    function test_falseReturnFixtureRecordsNoMovement() public {
        address recipient = address(0xB0B);
        FalseReturnAsset asset = new FalseReturnAsset();
        asset.fund(address(this), 100);

        assertFalse(asset.transfer(recipient, 10));
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(100, asset.balanceOf(address(this)), 0, 0), 0);
        AssetAccounting.checkBalance(AssetAccounting.BalanceChange(0, asset.balanceOf(recipient), 0, 0), 0);
    }

    function checkBalance(AssetAccounting.BalanceChange calldata change, uint256 tolerance) external pure {
        AssetAccounting.checkBalance(change, tolerance);
    }

    function checkSupply(uint256 reported, uint256[] calldata balances) external pure {
        AssetAccounting.checkSupply(reported, balances);
    }
}
