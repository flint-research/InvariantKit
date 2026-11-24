// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626Conversion} from "../../src/erc4626/ERC4626Conversion.sol";
import {ERC4626Flow} from "../../src/erc4626/ERC4626Flow.sol";
import {ERC4626Preview} from "../../src/erc4626/ERC4626Preview.sol";
import {CommonBase} from "forge-std/Base.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

contract VaultHandler is CommonBase {
    uint256 public constant ACTOR_COUNT = 3;
    uint256 private constant MAX_ACTION = 1_000 ether;

    IERC4626 private immutable vault;
    IERC20 private immutable asset;

    mapping(address => uint256) public expectedAssets;
    mapping(address => uint256) public expectedShares;
    mapping(bytes4 => uint256) public successes;
    mapping(bytes4 => uint256) public skips;
    uint256 public expectedManagedAssets;
    uint256 public thirdPartyEntries;
    uint256 public delegatedExits;

    constructor(IERC4626 vault_, uint256 startingAssets) {
        vault = vault_;
        asset = IERC20(vault_.asset());
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            expectedAssets[actor(i)] = startingAssets;
        }
    }

    function actor(uint256 seed) public pure returns (address) {
        return address(uint160(0xA1100 + seed % ACTOR_COUNT));
    }

    function deposit(uint256 seed, uint256 payerSeed, uint256 receiverSeed) external {
        address payer = actor(payerSeed);
        address receiver = actor(receiverSeed);
        uint256 limit = _min(vault.maxDeposit(receiver), asset.balanceOf(payer));
        uint256 assets = _amount(seed, limit, this.deposit.selector);
        if (assets == 0) return;

        ERC4626Flow.Balances memory beforeAction = _balances(payer, receiver);
        vm.prank(payer);
        uint256 preview = vault.previewDeposit(assets);
        vm.prank(payer);
        uint256 shares = vault.deposit(assets, receiver);

        ERC4626Preview.checkDeposit(preview, shares);
        ERC4626Flow.check(ERC4626Preview.Operation.Deposit, beforeAction, _balances(payer, receiver), assets, shares);
        _recordEntry(payer, receiver, assets, shares, this.deposit.selector);
    }

    function mint(uint256 seed, uint256 payerSeed, uint256 receiverSeed) external {
        address payer = actor(payerSeed);
        address receiver = actor(receiverSeed);
        uint256 shares = _amount(seed, vault.maxMint(receiver), this.mint.selector);
        if (shares == 0) return;

        vm.prank(payer);
        uint256 preview = vault.previewMint(shares);
        if (preview > asset.balanceOf(payer)) {
            ++skips[this.mint.selector];
            return;
        }
        ERC4626Flow.Balances memory beforeAction = _balances(payer, receiver);
        vm.prank(payer);
        uint256 assets = vault.mint(shares, receiver);

        ERC4626Preview.checkMint(preview, assets);
        ERC4626Flow.check(ERC4626Preview.Operation.Mint, beforeAction, _balances(payer, receiver), assets, shares);
        _recordEntry(payer, receiver, assets, shares, this.mint.selector);
    }

    function withdraw(uint256 seed, uint256 callerSeed, uint256 ownerSeed, uint256 receiverSeed) external {
        address owner = actor(ownerSeed);
        address receiver = actor(receiverSeed);
        uint256 assets = _amount(seed, vault.maxWithdraw(owner), this.withdraw.selector);
        if (assets == 0) return;

        ERC4626Flow.Balances memory beforeAction = _balances(receiver, owner);
        address caller = actor(callerSeed);
        vm.prank(caller);
        uint256 preview = vault.previewWithdraw(assets);
        vm.prank(caller);
        uint256 shares = vault.withdraw(assets, receiver, owner);

        ERC4626Preview.checkWithdraw(preview, shares);
        ERC4626Flow.check(ERC4626Preview.Operation.Withdraw, beforeAction, _balances(receiver, owner), assets, shares);
        _recordExit(caller, receiver, owner, assets, shares, this.withdraw.selector);
    }

    function redeem(uint256 seed, uint256 callerSeed, uint256 ownerSeed, uint256 receiverSeed) external {
        address owner = actor(ownerSeed);
        uint256 shares = _amount(seed, vault.maxRedeem(owner), this.redeem.selector);
        if (shares != 0) _redeem(actor(callerSeed), actor(receiverSeed), owner, shares);
    }

    function donate(uint256 seed, uint256 donorSeed) external {
        address donor = actor(donorSeed);
        uint256 assets = _amount(seed, _min(100 ether, asset.balanceOf(donor)), this.donate.selector);
        if (assets == 0) return;

        vm.prank(donor);
        require(asset.transfer(address(vault), assets));
        expectedAssets[donor] -= assets;
        expectedManagedAssets += assets;
        ++successes[this.donate.selector];
    }

    function checkConversions(uint256 seed, uint256 callerSeed) external {
        uint256 input = 1 + (seed % MAX_ACTION);
        address first = actor(callerSeed);
        address second = actor((callerSeed % ACTOR_COUNT) + 1);

        vm.prank(first);
        uint256 firstShares = vault.convertToShares(input);
        vm.prank(second);
        uint256 secondShares = vault.convertToShares(input);
        ERC4626Conversion.checkCallerIndependence(IERC4626.convertToShares.selector, input, firstShares, secondShares);

        vm.prank(first);
        uint256 firstAssets = vault.convertToAssets(input);
        vm.prank(second);
        uint256 secondAssets = vault.convertToAssets(input);
        ERC4626Conversion.checkCallerIndependence(IERC4626.convertToAssets.selector, input, firstAssets, secondAssets);

        ++successes[this.checkConversions.selector];
    }

    function closePositions() external {
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            address owner = actor(i);
            uint256 shares = vault.maxRedeem(owner);
            if (shares != 0) _redeem(owner, owner, owner, shares);
        }
    }

    function _redeem(address caller, address receiver, address owner, uint256 shares) private {
        ERC4626Flow.Balances memory beforeAction = _balances(receiver, owner);
        vm.prank(caller);
        uint256 preview = vault.previewRedeem(shares);
        vm.prank(caller);
        uint256 assets = vault.redeem(shares, receiver, owner);

        ERC4626Preview.checkRedeem(preview, assets);
        ERC4626Flow.check(ERC4626Preview.Operation.Redeem, beforeAction, _balances(receiver, owner), assets, shares);
        _recordExit(caller, receiver, owner, assets, shares, this.redeem.selector);
    }

    function _recordEntry(address payer, address receiver, uint256 assets, uint256 shares, bytes4 action) private {
        expectedAssets[payer] -= assets;
        expectedShares[receiver] += shares;
        expectedManagedAssets += assets;
        ++successes[action];
        if (payer != receiver && shares != 0) ++thirdPartyEntries;
    }

    function _recordExit(address caller, address receiver, address owner, uint256 assets, uint256 shares, bytes4 action)
        private
    {
        expectedAssets[receiver] += assets;
        expectedShares[owner] -= shares;
        expectedManagedAssets -= assets;
        ++successes[action];
        if (caller != owner) ++delegatedExits;
    }

    function _balances(address assetHolder, address shareHolder) private view returns (ERC4626Flow.Balances memory) {
        return ERC4626Flow.Balances(asset.balanceOf(assetHolder), vault.balanceOf(shareHolder));
    }

    function _amount(uint256 seed, uint256 limit, bytes4 action) private returns (uint256) {
        if (limit == 0) {
            ++skips[action];
            return 0;
        }
        uint256 capped = _min(limit, MAX_ACTION);
        if (seed % 8 == 0) return 1;
        if (seed % 8 == 1) return capped;
        return 1 + (seed % capped);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
