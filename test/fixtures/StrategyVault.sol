// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FeeVault} from "./FeeVault.sol";
import {TestERC20} from "./TestERC20.sol";

contract CustodyStrategy {
    error NotVault();

    TestERC20 private immutable asset;
    address private immutable vault;

    constructor(TestERC20 asset_) {
        asset = asset_;
        vault = msg.sender;
    }

    function returnAssets(uint256 amount) external {
        if (msg.sender != vault) revert NotVault();
        require(asset.transfer(vault, amount));
    }
}

contract FeeTreasury {
    error NotManager();

    TestERC20 private immutable asset;
    address private immutable manager;
    address private immutable recipient;

    constructor(TestERC20 asset_, address manager_, address recipient_) {
        asset = asset_;
        manager = manager_;
        recipient = recipient_;
    }

    function distribute(uint256 amount) external {
        if (msg.sender != manager) revert NotManager();
        require(asset.transfer(recipient, amount));
    }
}

contract StrategyVault is FeeVault {
    error NotManager();

    CustodyStrategy public immutable strategy;
    FeeTreasury public immutable treasury;
    address private immutable manager;

    constructor(TestERC20 asset_, FeeTreasury treasury_, address manager_) FeeVault(asset_) {
        strategy = new CustodyStrategy(asset_);
        treasury = treasury_;
        manager = manager_;
    }

    function allocate(uint256 assets) external {
        if (msg.sender != manager) revert NotManager();
        require(asset.transfer(address(strategy), assets));
    }

    function recall(uint256 assets) external {
        if (msg.sender != manager) revert NotManager();
        strategy.returnAssets(assets);
    }

    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() + asset.balanceOf(address(strategy));
    }

    function _enter(address receiver, uint256 assets, uint256 shares) internal override {
        super._enter(receiver, assets, shares);
        uint256 fee = assets - _netEntryAssets(assets);
        if (fee != 0) require(asset.transfer(address(treasury), fee));
    }

    function _exit(address receiver, address owner, uint256 assets, uint256 shares) internal override {
        uint256 idle = asset.balanceOf(address(this));
        if (assets > idle) strategy.returnAssets(assets - idle);
        super._exit(receiver, owner, assets, shares);
    }
}
