// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedRateVault} from "./FixedRateVault.sol";
import {TestERC20} from "./TestERC20.sol";

contract FeeVault is FixedRateVault {
    uint256 private constant BPS = 10_000;
    uint256 private constant ENTRY_NET_BPS = 9_900;
    uint256 private constant EXIT_NET_BPS = 9_800;
    uint256 private constant VIRTUAL_OFFSET = 1 ether;
    uint256 private constant DEPOSIT_CAP = 2_000 ether;

    constructor(TestERC20 asset_) FixedRateVault(asset_) {}

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return assets * _effectiveShares() / _effectiveAssets();
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return shares * _effectiveAssets() / _effectiveShares();
    }

    function maxDeposit(address) public pure override returns (uint256) {
        return DEPOSIT_CAP;
    }

    function maxMint(address) public view override returns (uint256) {
        return _depositShares(DEPOSIT_CAP);
    }

    function _depositShares(uint256 assets) internal view override returns (uint256) {
        return convertToShares(_netEntryAssets(assets));
    }

    function _mintAssets(uint256 shares) internal view override returns (uint256) {
        uint256 net = _ceilDiv(shares * _effectiveAssets(), _effectiveShares());
        return _ceilDiv(net * BPS, ENTRY_NET_BPS);
    }

    function _withdrawShares(uint256 assets) internal view override returns (uint256) {
        uint256 gross = _ceilDiv(assets * BPS, EXIT_NET_BPS);
        return _ceilDiv(gross * _effectiveShares(), _effectiveAssets());
    }

    function _redeemAssets(uint256 shares) internal view override returns (uint256) {
        return convertToAssets(shares) * EXIT_NET_BPS / BPS;
    }

    function _netEntryAssets(uint256 assets) internal pure returns (uint256) {
        return assets * ENTRY_NET_BPS / BPS;
    }

    function _effectiveAssets() private view returns (uint256) {
        return totalAssets() + VIRTUAL_OFFSET;
    }

    function _effectiveShares() private view returns (uint256) {
        return totalSupply + VIRTUAL_OFFSET;
    }

    function _ceilDiv(uint256 value, uint256 denominator) private pure returns (uint256) {
        return value == 0 ? 0 : 1 + (value - 1) / denominator;
    }
}
