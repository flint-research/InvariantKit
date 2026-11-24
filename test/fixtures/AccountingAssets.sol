// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestAsset} from "./TestERC20.sol";

contract FeeAccountingAsset is TestAsset {
    address public immutable treasury;

    constructor(address treasury_) {
        treasury = treasury_;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 fee = amount / 50;
        super._transfer(from, to, amount - fee);
        if (fee != 0) super._transfer(from, treasury, fee);
    }
}

contract RebasingAccountingAsset is TestAsset {
    address[2] private holders;

    constructor(address first, address second) {
        holders = [first, second];
    }

    function rebase(bool increase) external {
        for (uint256 i; i < holders.length; ++i) {
            address holder = holders[i];
            uint256 adjustment = balanceOf[holder] / 10;
            if (increase) _mint(holder, adjustment);
            else _burn(holder, adjustment);
        }
    }
}

contract FalseReturnAsset is TestAsset {
    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }
}
