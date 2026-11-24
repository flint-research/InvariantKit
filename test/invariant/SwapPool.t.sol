// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../../src/accounting/AssetAccounting.sol";
import {ConstantProduct} from "../../src/amm/ConstantProduct.sol";
import {V2Reserves} from "../../src/amm/V2Reserves.sol";
import {SwapPool} from "../fixtures/SwapPool.sol";
import {TestAsset} from "../fixtures/TestERC20.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Test} from "forge-std/Test.sol";

contract SwapPoolInvariantTest is Test {
    uint256 private constant TRADER_BALANCE = 1_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    TestAsset private token0;
    TestAsset private token1;
    SwapPool private pool;
    SwapHandler private handler;

    function setUp() public {
        token0 = new TestAsset();
        token1 = new TestAsset();
        pool = new SwapPool(token0, token1, 50_000 ether, 80_000 ether);
        _fundTrader(ALICE);
        _fundTrader(BOB);
        handler = new SwapHandler(pool, ALICE, BOB);
        targetContract(address(handler));
    }

    function invariant_reservesMatchCustodyAndTokenSupply() public view {
        ConstantProduct.Reserves memory reserves = V2Reserves.read(pool);
        ConstantProduct.checkReserves(reserves, token0.balanceOf(address(pool)), token1.balanceOf(address(pool)));
        _checkSupply(token0);
        _checkSupply(token1);
    }

    function afterInvariant() public view {
        assertGt(handler.zeroForOneSwaps(), 0, "no token0-to-token1 swap");
        assertGt(handler.oneForZeroSwaps(), 0, "no token1-to-token0 swap");
    }

    function _fundTrader(address trader) private {
        token0.fund(trader, TRADER_BALANCE);
        token1.fund(trader, TRADER_BALANCE);
        vm.prank(trader);
        require(token0.approve(address(pool), type(uint256).max));
        vm.prank(trader);
        require(token1.approve(address(pool), type(uint256).max));
    }

    function _checkSupply(TestAsset token) private view {
        uint256[] memory balances = new uint256[](3);
        balances[0] = token.balanceOf(ALICE);
        balances[1] = token.balanceOf(BOB);
        balances[2] = token.balanceOf(address(pool));
        AssetAccounting.checkSupply(token.totalSupply(), balances);
    }
}

contract SwapHandler is CommonBase {
    uint256 private constant MIN_ACTION = 1 ether;
    uint256 private constant MAX_ACTION = 1_000 ether;

    SwapPool private immutable pool;
    TestAsset private immutable token0;
    TestAsset private immutable token1;
    address private immutable alice;
    address private immutable bob;

    uint256 public zeroForOneSwaps;
    uint256 public oneForZeroSwaps;

    constructor(SwapPool pool_, address alice_, address bob_) {
        pool = pool_;
        token0 = pool_.token0();
        token1 = pool_.token1();
        alice = alice_;
        bob = bob_;
    }

    function swap(uint256 seed, bool zeroForOne, bool useAlice) external {
        address trader = useAlice ? alice : bob;
        (TestAsset input, TestAsset output) = zeroForOne ? (token0, token1) : (token1, token0);
        uint256 inputBefore = input.balanceOf(trader);
        if (inputBefore < MIN_ACTION) return;

        uint256 limit = inputBefore < MAX_ACTION ? inputBefore : MAX_ACTION;
        uint112 amountIn = uint112(MIN_ACTION + (seed % (limit - MIN_ACTION + 1)));
        uint256 outputBefore = output.balanceOf(trader);
        ConstantProduct.Reserves memory beforeSwap = V2Reserves.read(pool);

        vm.prank(trader);
        uint112 amountOut = pool.swap(zeroForOne, amountIn);
        ConstantProduct.checkSwap(
            beforeSwap, V2Reserves.read(pool), ConstantProduct.Swap(amountIn, amountOut, zeroForOne), 30
        );

        AssetAccounting.checkBalance(
            AssetAccounting.BalanceChange(inputBefore, input.balanceOf(trader), 0, amountIn), 0
        );
        AssetAccounting.checkBalance(
            AssetAccounting.BalanceChange(outputBefore, output.balanceOf(trader), amountOut, 0), 0
        );

        if (zeroForOne) ++zeroForOneSwaps;
        else ++oneForZeroSwaps;
    }
}
