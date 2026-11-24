// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626Preview} from "../../src/erc4626/ERC4626Preview.sol";
import {Test} from "forge-std/Test.sol";

contract ERC4626PreviewTest is Test {
    function test_conservativePreviewsPass() public pure {
        ERC4626Preview.checkDeposit(0, type(uint256).max);
        ERC4626Preview.checkMint(type(uint256).max, 0);
        ERC4626Preview.checkWithdraw(type(uint256).max, 0);
        ERC4626Preview.checkRedeem(0, type(uint256).max);
    }

    function test_depositOverquoteFails() public {
        _expectDirection(ERC4626Preview.Operation.Deposit, 2, 1);
        this.checkPreview(ERC4626Preview.Operation.Deposit, 2, 1);
    }

    function test_mintUnderquoteFails() public {
        _expectDirection(ERC4626Preview.Operation.Mint, 1, 2);
        this.checkPreview(ERC4626Preview.Operation.Mint, 1, 2);
    }

    function test_withdrawUnderquoteFails() public {
        _expectDirection(ERC4626Preview.Operation.Withdraw, 1, 2);
        this.checkPreview(ERC4626Preview.Operation.Withdraw, 1, 2);
    }

    function test_redeemOverquoteFails() public {
        _expectDirection(ERC4626Preview.Operation.Redeem, 2, 1);
        this.checkPreview(ERC4626Preview.Operation.Redeem, 2, 1);
    }

    function checkPreview(ERC4626Preview.Operation operation, uint256 preview, uint256 actual) external pure {
        if (operation == ERC4626Preview.Operation.Deposit) ERC4626Preview.checkDeposit(preview, actual);
        else if (operation == ERC4626Preview.Operation.Mint) ERC4626Preview.checkMint(preview, actual);
        else if (operation == ERC4626Preview.Operation.Withdraw) ERC4626Preview.checkWithdraw(preview, actual);
        else ERC4626Preview.checkRedeem(preview, actual);
    }

    function _expectDirection(ERC4626Preview.Operation operation, uint256 preview, uint256 actual) private {
        vm.expectRevert(abi.encodeWithSelector(ERC4626Preview.PreviewDirection.selector, operation, preview, actual));
    }
}
