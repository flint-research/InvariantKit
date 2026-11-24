// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ERC4626Preview {
    enum Operation {
        Deposit,
        Mint,
        Withdraw,
        Redeem
    }

    error PreviewDirection(Operation operation, uint256 preview, uint256 actual);

    function checkDeposit(uint256 preview, uint256 actual) internal pure {
        if (preview > actual) revert PreviewDirection(Operation.Deposit, preview, actual);
    }

    function checkMint(uint256 preview, uint256 actual) internal pure {
        if (preview < actual) revert PreviewDirection(Operation.Mint, preview, actual);
    }

    function checkWithdraw(uint256 preview, uint256 actual) internal pure {
        if (preview < actual) revert PreviewDirection(Operation.Withdraw, preview, actual);
    }

    function checkRedeem(uint256 preview, uint256 actual) internal pure {
        if (preview > actual) revert PreviewDirection(Operation.Redeem, preview, actual);
    }
}
