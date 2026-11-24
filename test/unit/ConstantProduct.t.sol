// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ConstantProduct} from "../../src/amm/ConstantProduct.sol";
import {Test} from "forge-std/Test.sol";

contract ConstantProductTest is Test {
    function testFuzz_acceptsRoundedSwapAcrossConfiguredFees(uint112 rawIn, uint112 rawOut, uint16 rawFee) public pure {
        uint112 reserveIn = uint112(bound(rawIn, 1, type(uint112).max / 2));
        uint112 reserveOut = uint112(bound(rawOut, 20_000, type(uint112).max));
        uint16 fee = uint16(bound(rawFee, 0, 9_999));
        uint256 effectiveInput = uint256(reserveIn) * (10_000 - fee);
        uint112 output = uint112(uint256(reserveOut) * effectiveInput / (uint256(reserveIn) * 10_000 + effectiveInput));

        ConstantProduct.checkSwap(
            ConstantProduct.Reserves(reserveIn, reserveOut),
            ConstantProduct.Reserves(reserveIn * 2, reserveOut - output),
            ConstantProduct.Swap(reserveIn, output, true),
            fee
        );
    }

    function test_reverseDirectionUsesTokenOneAsInput() public pure {
        ConstantProduct.checkSwap(
            ConstantProduct.Reserves(1_500, 1_000),
            ConstantProduct.Reserves(1_365, 1_100),
            ConstantProduct.Swap(100, 135, false),
            30
        );
    }

    function test_feeAdjustedCheckRejectsNoFeeTransition() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ConstantProduct.FeeAdjustedProductDecreased.selector, 100_000_000_000_000, 99_850_000_000_000
            )
        );
        this.checkSwap(
            ConstantProduct.Reserves(1_000, 1_000),
            ConstantProduct.Reserves(2_000, 500),
            ConstantProduct.Swap(1_000, 500, true),
            30
        );
    }

    function test_exactSwapFlowRequiredBeforeProductCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(ConstantProduct.ReserveDeltaMismatch.selector, 1_000, 1_099, 1_000, 910, 100, 90)
        );
        this.checkSwap(
            ConstantProduct.Reserves(1_000, 1_000),
            ConstantProduct.Reserves(1_099, 910),
            ConstantProduct.Swap(100, 90, true),
            30
        );
    }

    function test_productFitsAtTheReserveLimit() public pure {
        uint112 maximum = type(uint112).max;
        ConstantProduct.checkSwap(
            ConstantProduct.Reserves(maximum - 1, maximum),
            ConstantProduct.Reserves(maximum, maximum - 1),
            ConstantProduct.Swap(1, 1, true),
            0
        );
    }

    function test_rejectsFullInputFee() public {
        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.InvalidFee.selector, 10_000));
        this.checkSwap(
            ConstantProduct.Reserves(1, 2), ConstantProduct.Reserves(2, 1), ConstantProduct.Swap(1, 1, true), 10_000
        );
    }

    function test_reserveComparisonKeepsFullBalanceWidth() public {
        uint256 actual = uint256(type(uint112).max) + 7;
        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.ReserveBalanceMismatch.selector, 6, 2, actual, 2));
        this.checkReserves(ConstantProduct.Reserves(6, 2), actual, 2);
    }

    function checkSwap(
        ConstantProduct.Reserves calldata beforeSwap,
        ConstantProduct.Reserves calldata afterSwap,
        ConstantProduct.Swap calldata swap,
        uint16 feeBps
    ) external pure {
        ConstantProduct.checkSwap(beforeSwap, afterSwap, swap, feeBps);
    }

    function checkReserves(ConstantProduct.Reserves calldata reserves, uint256 balance0, uint256 balance1)
        external
        pure
    {
        ConstantProduct.checkReserves(reserves, balance0, balance1);
    }
}
