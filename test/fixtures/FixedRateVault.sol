// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestERC20} from "./TestERC20.sol";

contract FixedRateVault is TestERC20 {
    TestERC20 public immutable asset;

    error DepositLimit(uint256 requested, uint256 limit);
    error MintLimit(uint256 requested, uint256 limit);

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    constructor(TestERC20 asset_) TestERC20("Test Vault Share", "SHARE") {
        asset = asset_;
    }

    function totalAssets() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return assets;
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return shares;
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return _redeemAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf[owner];
    }

    function previewDeposit(uint256 assets) external view virtual returns (uint256) {
        return _depositShares(assets);
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return _mintAssets(shares);
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return _withdrawShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return _redeemAssets(shares);
    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        uint256 limit = maxDeposit(receiver);
        if (assets > limit) revert DepositLimit(assets, limit);
        shares = _depositShares(assets);
        _enter(receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        uint256 limit = maxMint(receiver);
        if (shares > limit) revert MintLimit(shares, limit);
        assets = _mintAssets(shares);
        _enter(receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = _withdrawShares(assets);
        _exit(receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = _redeemAssets(shares);
        _exit(receiver, owner, assets, shares);
    }

    function _depositShares(uint256 assets) internal view virtual returns (uint256) {
        return assets;
    }

    function _mintAssets(uint256 shares) internal view virtual returns (uint256) {
        return shares;
    }

    function _withdrawShares(uint256 assets) internal view virtual returns (uint256) {
        return assets;
    }

    function _redeemAssets(uint256 shares) internal view virtual returns (uint256) {
        return shares;
    }

    function _enter(address receiver, uint256 assets, uint256 shares) internal virtual {
        require(asset.transferFrom(msg.sender, address(this), assets));
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _exit(address receiver, address owner, uint256 assets, uint256 shares) internal virtual {
        if (owner != msg.sender) _spendAllowance(owner, shares);
        _burn(owner, shares);
        require(asset.transfer(receiver, assets));
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }
}

contract BrokenPreviewVault is FixedRateVault {
    constructor(TestERC20 asset_) FixedRateVault(asset_) {}

    function previewDeposit(uint256 assets) external pure override returns (uint256) {
        return assets + 1;
    }
}
