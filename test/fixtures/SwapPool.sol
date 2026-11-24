// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IV2ReserveSource} from "../../src/amm/V2Reserves.sol";
import {TestAsset} from "./TestERC20.sol";

contract SwapPool is IV2ReserveSource {
    TestAsset public immutable token0;
    TestAsset public immutable token1;
    uint112 private reserve0;
    uint112 private reserve1;

    constructor(TestAsset token0_, TestAsset token1_, uint112 initial0, uint112 initial1) {
        token0 = token0_;
        token1 = token1_;
        token0_.fund(address(this), initial0);
        token1_.fund(address(this), initial1);
        reserve0 = initial0;
        reserve1 = initial1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }

    function swap(bool zeroForOne, uint112 amountIn) external returns (uint112 amountOut) {
        uint256 netInput = uint256(amountIn) * 997;
        uint256 reserveIn = zeroForOne ? reserve0 : reserve1;
        uint256 reserveOut = zeroForOne ? reserve1 : reserve0;
        amountOut = uint112(reserveOut * netInput / (reserveIn * 1_000 + netInput));
        require(amountOut != 0);

        if (zeroForOne) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
            require(token0.transferFrom(msg.sender, address(this), amountIn));
            require(token1.transfer(msg.sender, amountOut));
        } else {
            reserve0 -= amountOut;
            reserve1 += amountIn;
            require(token1.transferFrom(msg.sender, address(this), amountIn));
            require(token0.transfer(msg.sender, amountOut));
        }
    }
}
