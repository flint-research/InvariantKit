// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetAccounting} from "../../src/accounting/AssetAccounting.sol";
import {FeeAccountingAsset} from "../fixtures/AccountingAssets.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Test} from "forge-std/Test.sol";

contract TokenAccountingInvariantTest is Test {
    uint256 private constant STARTING_BALANCE = 100_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant TREASURY = address(0xFEE);

    FeeAccountingAsset private asset;
    TokenAccountingHandler private handler;

    function setUp() public {
        asset = new FeeAccountingAsset(TREASURY);
        asset.fund(ALICE, STARTING_BALANCE);
        asset.fund(BOB, STARTING_BALANCE);
        handler = new TokenAccountingHandler(asset, ALICE, BOB, STARTING_BALANCE);
        targetContract(address(handler));
    }

    function invariant_accountedBalancesAndSupply() public view {
        uint256[] memory balances = new uint256[](3);
        balances[0] = asset.balanceOf(ALICE);
        balances[1] = asset.balanceOf(BOB);
        balances[2] = asset.balanceOf(TREASURY);
        assertEq(balances[0], handler.expectedBalance(ALICE));
        assertEq(balances[1], handler.expectedBalance(BOB));
        assertEq(balances[2], handler.expectedBalance(TREASURY));

        uint256 supply = asset.totalSupply();
        AssetAccounting.checkSupply(supply, balances);
        AssetAccounting.checkBalance(
            AssetAccounting.BalanceChange(2 * STARTING_BALANCE, supply, handler.minted(), handler.burned()), 0
        );
    }

    function afterInvariant() public view {
        assertGt(handler.feeTransfers(), 0, "no fee-bearing transfers");
        assertGt(handler.minted(), 0, "no minting");
        assertGt(handler.burned(), 0, "no burning");
    }
}

contract TokenAccountingHandler is CommonBase {
    uint256 private constant MAX_ACTION = 1_000 ether;

    FeeAccountingAsset private immutable asset;
    address private immutable alice;
    address private immutable bob;
    address private immutable treasury;

    mapping(address => uint256) public expectedBalance;
    uint256 public minted;
    uint256 public burned;
    uint256 public feeTransfers;

    constructor(FeeAccountingAsset asset_, address alice_, address bob_, uint256 startingBalance) {
        asset = asset_;
        alice = alice_;
        bob = bob_;
        treasury = asset_.treasury();
        expectedBalance[alice_] = startingBalance;
        expectedBalance[bob_] = startingBalance;
    }

    function transfer(uint256 seed, bool fromAlice) external {
        address from = fromAlice ? alice : bob;
        address to = fromAlice ? bob : alice;
        uint256 amount = _boundedAmount(seed, from);
        if (amount == 0) return;

        vm.prank(from);
        require(asset.transfer(to, amount));
        uint256 fee = amount * 2 / 100;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount - fee;
        expectedBalance[treasury] += fee;
        if (fee != 0) ++feeTransfers;
    }

    function mint(uint256 seed, bool toAlice) external {
        address receiver = toAlice ? alice : bob;
        uint256 amount = 1 + (seed % MAX_ACTION);
        asset.fund(receiver, amount);
        expectedBalance[receiver] += amount;
        minted += amount;
    }

    function burn(uint256 seed, bool fromAlice) external {
        address owner = fromAlice ? alice : bob;
        uint256 amount = _boundedAmount(seed, owner);
        if (amount == 0) return;

        vm.prank(owner);
        asset.burn(amount);
        expectedBalance[owner] -= amount;
        burned += amount;
    }

    function _boundedAmount(uint256 seed, address owner) private view returns (uint256) {
        uint256 balance = expectedBalance[owner];
        if (balance == 0) return 0;
        uint256 limit = balance < MAX_ACTION ? balance : MAX_ACTION;
        return 1 + (seed % limit);
    }
}
