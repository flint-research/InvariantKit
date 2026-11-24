// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626Conversion} from "../../src/erc4626/ERC4626Conversion.sol";
import {ERC4626Flow} from "../../src/erc4626/ERC4626Flow.sol";
import {ERC4626Preview} from "../../src/erc4626/ERC4626Preview.sol";
import {FeeVault} from "../fixtures/FeeVault.sol";
import {FixedRateVault, BrokenPreviewVault} from "../fixtures/FixedRateVault.sol";
import {TestAsset} from "../fixtures/TestERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {VaultHandler} from "./VaultHandler.sol";

abstract contract VaultCampaign is Test {
    uint256 internal constant STARTING_ASSETS = 1_000_000 ether;

    error InsufficientActionCoverage(bytes4 action, uint256 skips);
    error InsufficientRoleCoverage(uint256 thirdPartyEntries, uint256 delegatedExits);

    TestAsset internal asset;
    IERC4626 internal vault;
    VaultHandler internal handler;
    bytes4[] private requiredActions;

    function _start(FixedRateVault fixture, bool enableDonation) internal {
        vault = IERC4626(address(fixture));
        asset = TestAsset(vault.asset());
        handler = _fundedHandler(fixture);

        requiredActions = new bytes4[](enableDonation ? 6 : 5);
        requiredActions[0] = handler.deposit.selector;
        requiredActions[1] = handler.mint.selector;
        requiredActions[2] = handler.withdraw.selector;
        requiredActions[3] = handler.redeem.selector;
        requiredActions[4] = handler.checkConversions.selector;
        if (enableDonation) requiredActions[5] = handler.donate.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: requiredActions}));
    }

    function invariant_vaultAccounting() public view {
        uint256 actorAssets;
        uint256 totalShares;
        uint256 actorCount = handler.ACTOR_COUNT();
        for (uint256 i; i < actorCount; ++i) {
            address user = handler.actor(i);
            uint256 assets = asset.balanceOf(user);
            uint256 shares = vault.balanceOf(user);
            assertEq(assets, handler.expectedAssets(user));
            assertEq(shares, handler.expectedShares(user));
            actorAssets += assets;
            totalShares += shares;
        }
        uint256 managedAssets = asset.balanceOf(address(vault));
        assertEq(vault.totalAssets(), managedAssets);
        assertEq(managedAssets, handler.expectedManagedAssets());
        assertEq(vault.totalSupply(), totalShares);
        assertEq(managedAssets + actorAssets, STARTING_ASSETS * actorCount);
    }

    function afterInvariant() public {
        for (uint256 i; i < requiredActions.length; ++i) {
            bytes4 action = requiredActions[i];
            if (handler.successes(action) == 0) revert InsufficientActionCoverage(action, handler.skips(action));
        }

        uint256 entries = handler.thirdPartyEntries();
        uint256 exits = handler.delegatedExits();
        if (entries == 0 || exits == 0) revert InsufficientRoleCoverage(entries, exits);

        handler.closePositions();
        assertEq(vault.totalSupply(), 0);
        invariant_vaultAccounting();
    }

    function _fundedHandler(FixedRateVault fixture) internal returns (VaultHandler funded) {
        funded = new VaultHandler(IERC4626(address(fixture)), STARTING_ASSETS);
        TestAsset token = TestAsset(address(fixture.asset()));
        uint256 actorCount = funded.ACTOR_COUNT();
        for (uint256 i; i < actorCount; ++i) {
            address user = funded.actor(i);
            token.fund(user, STARTING_ASSETS);
            vm.prank(user);
            require(token.approve(address(fixture), type(uint256).max));
            for (uint256 j; j < actorCount; ++j) {
                if (i == j) continue;
                address delegate = funded.actor(j);
                vm.prank(user);
                require(fixture.approve(delegate, type(uint256).max));
            }
        }
    }
}

contract VaultInvariantTest is VaultCampaign {
    function setUp() public {
        _start(new FixedRateVault(new TestAsset()), false);
    }

    function test_brokenDepositPreviewFailsAtTheHandler() public {
        VaultHandler broken = _fundedHandler(new BrokenPreviewVault(new TestAsset()));
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Preview.PreviewDirection.selector, ERC4626Preview.Operation.Deposit, 2, 1)
        );
        broken.deposit(0, 0, 0);
    }

    function test_misreportedDepositFailsEvenWhenPreviewBoundHolds() public {
        VaultHandler broken = _fundedHandler(new MisreportedDepositVault(new TestAsset()));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Flow.BalanceDelta.selector, ERC4626Preview.Operation.Deposit, ERC4626Flow.Unit.Shares, 0, 1, 2
            )
        );
        broken.deposit(0, 0, 1);
    }

    function test_callerDependentConversionFailsAtTheHandler() public {
        VaultHandler broken = _fundedHandler(new CallerDependentVault(new TestAsset(), handler.actor(0)));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Conversion.CallerDependentQuote.selector, IERC4626.convertToShares.selector, 1, 2, 1
            )
        );
        broken.checkConversions(0, 0);
    }

    function test_skippedActionDoesNotCountAsSuccessful() public {
        handler.withdraw(0, 0, 0, 0);
        assertEq(handler.skips(handler.withdraw.selector), 1);
        assertEq(handler.successes(handler.withdraw.selector), 0);

        handler.deposit(0, 0, 0);
        handler.mint(0, 1, 1);
        handler.redeem(0, 1, 1, 1);
        handler.checkConversions(0, 0);
        vm.expectRevert(abi.encodeWithSelector(InsufficientActionCoverage.selector, handler.withdraw.selector, 1));
        this.afterInvariant();
    }

    function test_nonDelegatedActionsDoNotSatisfyRoleCoverage() public {
        handler.deposit(0, 0, 0);
        handler.mint(0, 1, 1);
        handler.withdraw(0, 0, 0, 0);
        handler.redeem(0, 1, 1, 1);
        handler.checkConversions(0, 0);

        vm.expectRevert(abi.encodeWithSelector(InsufficientRoleCoverage.selector, 0, 0));
        this.afterInvariant();
    }

    function test_closeoutCannotSatisfyMissingRedeemCoverage() public {
        handler.deposit(1, 0, 1);
        handler.mint(0, 1, 1);
        handler.withdraw(0, 0, 1, 2);
        handler.checkConversions(0, 0);
        assertGt(vault.balanceOf(handler.actor(1)), 0);

        vm.expectRevert(abi.encodeWithSelector(InsufficientActionCoverage.selector, handler.redeem.selector, 0));
        this.afterInvariant();
    }

    function test_delegatedWithdrawalPaysReceiverAndBurnsOwnerShares() public {
        handler.deposit(1, 0, 1);
        address owner = handler.actor(1);
        address delegate = handler.actor(0);
        vm.prank(owner);
        require(vault.approve(delegate, 3));

        handler.withdraw(0, 0, 1, 2);

        assertEq(vault.allowance(owner, delegate), 2);
        assertEq(handler.thirdPartyEntries(), 1);
        assertEq(handler.delegatedExits(), 1);
        assertEq(vault.balanceOf(handler.actor(1)), 1_000 ether - 1);
        assertEq(asset.balanceOf(handler.actor(2)), STARTING_ASSETS + 1);
        invariant_vaultAccounting();
    }
}

contract FeeVaultInvariantTest is VaultCampaign {
    function setUp() public {
        _start(new FeeVault(new TestAsset()), true);
    }

    function test_dustDepositDoesNotCountAsThirdPartyEntry() public {
        handler.deposit(0, 0, 1);

        assertEq(handler.successes(handler.deposit.selector), 1);
        assertEq(vault.balanceOf(handler.actor(1)), 0);
        assertEq(handler.thirdPartyEntries(), 0);
        invariant_vaultAccounting();
    }
}

contract MisreportedDepositVault is FixedRateVault {
    constructor(TestAsset asset_) FixedRateVault(asset_) {}

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        return super.deposit(assets, receiver) + 1;
    }
}

contract CallerDependentVault is FixedRateVault {
    address private immutable specialCaller;

    constructor(TestAsset asset_, address specialCaller_) FixedRateVault(asset_) {
        specialCaller = specialCaller_;
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return msg.sender == specialCaller ? assets + 1 : assets;
    }
}
