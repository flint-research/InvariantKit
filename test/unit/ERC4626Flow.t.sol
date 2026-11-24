// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC4626Flow} from "../../src/erc4626/ERC4626Flow.sol";
import {ERC4626Preview} from "../../src/erc4626/ERC4626Preview.sol";

contract ERC4626FlowTest is Test {
    function test_depositAcceptsZeroSharesWithExactAssetDebit() public pure {
        ERC4626Flow.check(
            ERC4626Preview.Operation.Deposit, ERC4626Flow.Balances(8, 3), ERC4626Flow.Balances(5, 3), 3, 0
        );
    }

    function test_withdrawRejectsAssetMovementInWrongDirection() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Flow.BalanceDelta.selector, ERC4626Preview.Operation.Withdraw, ERC4626Flow.Unit.Assets, 8, 4, 4
            )
        );
        this.checkWithdraw(ERC4626Flow.Balances(8, 3), ERC4626Flow.Balances(4, 2));
    }

    function checkWithdraw(ERC4626Flow.Balances calldata beforeAction, ERC4626Flow.Balances calldata afterAction)
        external
        pure
    {
        ERC4626Flow.check(ERC4626Preview.Operation.Withdraw, beforeAction, afterAction, 4, 1);
    }
}
