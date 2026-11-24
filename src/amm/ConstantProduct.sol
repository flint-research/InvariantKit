// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ConstantProduct {
    uint256 private constant BPS = 10_000;

    struct Reserves {
        uint112 token0;
        uint112 token1;
    }

    struct Swap {
        uint112 amountIn;
        uint112 amountOut;
        bool zeroForOne;
    }

    error InvalidFee(uint16 feeBps);
    error EmptyReserves();
    error EmptySwap();
    error ReserveDeltaMismatch(
        uint256 beforeIn, uint256 afterIn, uint256 beforeOut, uint256 afterOut, uint112 amountIn, uint112 amountOut
    );
    error FeeAdjustedProductDecreased(uint256 beforeProduct, uint256 afterProduct);
    error ReserveBalanceMismatch(uint112 reserve0, uint112 reserve1, uint256 balance0, uint256 balance1);

    function checkSwap(Reserves memory beforeSwap, Reserves memory afterSwap, Swap memory swap, uint16 feeBps)
        internal
        pure
    {
        if (feeBps >= BPS) revert InvalidFee(feeBps);
        if (swap.amountIn == 0 || swap.amountOut == 0) revert EmptySwap();

        (uint256 beforeIn, uint256 beforeOut) = _inOut(beforeSwap, swap.zeroForOne);
        (uint256 afterIn, uint256 afterOut) = _inOut(afterSwap, swap.zeroForOne);
        if (beforeIn == 0 || beforeOut == 0) revert EmptyReserves();
        if (afterIn != beforeIn + swap.amountIn || afterOut + swap.amountOut != beforeOut) {
            revert ReserveDeltaMismatch(beforeIn, afterIn, beforeOut, afterOut, swap.amountIn, swap.amountOut);
        }

        uint256 adjustedIn = afterIn * BPS - uint256(swap.amountIn) * feeBps;
        uint256 afterProduct = adjustedIn * (afterOut * BPS);
        uint256 beforeProduct = (beforeIn * BPS) * (beforeOut * BPS);
        if (afterProduct < beforeProduct) revert FeeAdjustedProductDecreased(beforeProduct, afterProduct);
    }

    function checkReserves(Reserves memory reported, uint256 balance0, uint256 balance1) internal pure {
        if (reported.token0 != balance0 || reported.token1 != balance1) {
            revert ReserveBalanceMismatch(reported.token0, reported.token1, balance0, balance1);
        }
    }

    function _inOut(Reserves memory reserves, bool zeroForOne) private pure returns (uint256, uint256) {
        return zeroForOne ? (reserves.token0, reserves.token1) : (reserves.token1, reserves.token0);
    }
}
