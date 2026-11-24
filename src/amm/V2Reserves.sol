// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ConstantProduct} from "./ConstantProduct.sol";

interface IV2ReserveSource {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

library V2Reserves {
    function read(IV2ReserveSource source) internal view returns (ConstantProduct.Reserves memory reserves) {
        (reserves.token0, reserves.token1,) = source.getReserves();
    }
}
