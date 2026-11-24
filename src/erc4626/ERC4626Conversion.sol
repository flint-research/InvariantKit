// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ERC4626Conversion {
    error CallerDependentQuote(bytes4 method, uint256 input, uint256 firstQuote, uint256 secondQuote);

    function checkCallerIndependence(bytes4 method, uint256 input, uint256 firstQuote, uint256 secondQuote)
        internal
        pure
    {
        if (firstQuote != secondQuote) revert CallerDependentQuote(method, input, firstQuote, secondQuote);
    }
}
