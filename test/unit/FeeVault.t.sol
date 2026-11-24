// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FixedRateVault} from "../fixtures/FixedRateVault.sol";
import {FeeVault} from "../fixtures/FeeVault.sol";
import {TestAsset} from "../fixtures/TestERC20.sol";

contract FeeVaultTest is Test {
    FeeVault private vault;

    function setUp() public {
        TestAsset asset = new TestAsset();
        vault = new FeeVault(asset);
        asset.fund(address(this), 10_000 ether);
        require(asset.approve(address(vault), type(uint256).max));

        assertEq(vault.deposit(100 ether, address(this)), 99 ether);
        require(asset.transfer(address(vault), 49 ether));
    }

    function test_feeRoundingAtThreeAssetsForTwoShares() public view {
        assertEq(vault.convertToShares(5), 3);
        assertEq(vault.convertToAssets(3), 4);
        assertEq(vault.previewDeposit(99), 65);
        assertEq(vault.previewMint(3), 6);
        assertEq(vault.previewWithdraw(6), 5);
        assertEq(vault.previewRedeem(3), 3);
    }

    function testFuzz_conversionsRoundDownAtNonIntegralPrice(uint256 input) public view {
        input = bound(input, 1, 1_000_000 ether);
        uint256 shares = vault.convertToShares(input);
        uint256 assets = vault.convertToAssets(input);

        assertLe(shares * 3, input * 2);
        assertGt((shares + 1) * 3, input * 2);
        assertLe(assets * 2, input * 3);
        assertGt((assets + 1) * 2, input * 3);
    }

    function testFuzz_feeQuotesRoundInTheVaultsFavor(uint256 input) public view {
        input = bound(input, 1, 1_000_000 ether);

        uint256 depositShares = vault.previewDeposit(input);
        uint256 netDeposit = input * 99 / 100;
        assertLe(depositShares * 3, netDeposit * 2);
        assertGt((depositShares + 1) * 3, netDeposit * 2);

        uint256 mintCost = vault.previewMint(input);
        assertGe((mintCost * 99 / 100) * 2, input * 3);
        assertLt(((mintCost - 1) * 99 / 100) * 2, input * 3);

        uint256 withdrawShares = vault.previewWithdraw(input);
        assertGe((withdrawShares * 3 / 2) * 98 / 100, input);
        assertLt(((withdrawShares - 1) * 3 / 2) * 98 / 100, input);

        uint256 redeemAssets = vault.previewRedeem(input);
        uint256 grossRedeem = input * 3 / 2;
        assertLe(redeemAssets * 100, grossRedeem * 98);
        assertGt((redeemAssets + 1) * 100, grossRedeem * 98);
    }

    function test_previewDepositQuotesAboveCapAndActionEnforcesCap() public {
        uint256 cap = vault.maxDeposit(address(this));
        assertGt(vault.previewDeposit(cap + 1), 0);
        vm.expectRevert(abi.encodeWithSelector(FixedRateVault.DepositLimit.selector, cap + 1, cap));
        vault.deposit(cap + 1, address(this));
        assertGt(vault.deposit(cap, address(this)), 0);
    }

    function test_previewMintQuotesAboveCapAndActionEnforcesCap() public {
        uint256 cap = vault.maxMint(address(this));
        assertGt(vault.previewMint(cap + 1), vault.maxDeposit(address(this)));
        vm.expectRevert(abi.encodeWithSelector(FixedRateVault.MintLimit.selector, cap + 1, cap));
        vault.mint(cap + 1, address(this));
        assertLe(vault.mint(cap, address(this)), vault.maxDeposit(address(this)));
    }

    function test_maxWithdrawCanBeExecutedWithFees() public {
        uint256 maxAssets = vault.maxWithdraw(address(this));
        uint256 shares = vault.balanceOf(address(this));
        assertGt(maxAssets, 0);
        assertLe(vault.withdraw(maxAssets, address(this), address(this)), shares);
    }
}
