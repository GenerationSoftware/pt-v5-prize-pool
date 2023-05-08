// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { TieredLiquidityDistributorWrapper } from "test/abstract/helper/TieredLiquidityDistributorWrapper.sol";
import { NumberOfTiersLessThanMinimum, InsufficientLiquidity } from "src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorTest is Test {

    TieredLiquidityDistributorWrapper public distributor;

    uint32 grandPrizePeriodDraws;
    uint8 numberOfTiers;
    uint8 tierShares;
    uint8 canaryShares;
    uint8 reserveShares;

    function setUp() external {
        grandPrizePeriodDraws = 10;
        numberOfTiers = 2;
        tierShares = 100;
        canaryShares = 10;
        reserveShares = 10;

        distributor = new TieredLiquidityDistributorWrapper(
            grandPrizePeriodDraws,
            numberOfTiers,
            tierShares,
            canaryShares,
            reserveShares
        );
    }

    function testNextDraw_invalid_num_tiers() public {
        vm.expectRevert(abi.encodeWithSelector(NumberOfTiersLessThanMinimum.selector, 1));
        distributor.nextDraw(1, 100);
    }

    function testRemainingTierLiquidity() public {
        distributor.nextDraw(2, 220e18);
        assertEq(distributor.remainingTierLiquidity(0), 100e18);
        assertEq(distributor.remainingTierLiquidity(1), 100e18);
        assertEq(distributor.remainingTierLiquidity(2), 10e18);
    }

    function testConsumeLiquidity_partial() public {
        distributor.nextDraw(2, 220e18);
        distributor.consumeLiquidity(1, 50e18); // consume full liq for tier 1
        assertEq(distributor.remainingTierLiquidity(1), 50e18);
    }

    function testConsumeLiquidity_full() public {
        distributor.nextDraw(2, 220e18);
        distributor.consumeLiquidity(1, 100e18); // consume full liq for tier 1
        assertEq(distributor.remainingTierLiquidity(1), 0);
    }

    function testConsumeLiquidity_and_empty_reserve() public {
        distributor.nextDraw(2, 220e18); // reserve should be 10e18
        distributor.consumeLiquidity(1, 110e18); // consume full liq for tier 1 and reserve
        assertEq(distributor.remainingTierLiquidity(1), 0);
        assertEq(distributor.reserve(), 0);
    }

    function testConsumeLiquidity_and_partial_reserve() public {
        distributor.nextDraw(2, 220e18); // reserve should be 10e18
        distributor.consumeLiquidity(1, 105e18); // consume full liq for tier 1 and reserve
        assertEq(distributor.remainingTierLiquidity(1), 0);
        assertEq(distributor.reserve(), 5e18);
    }

    function testConsumeLiquidity_insufficient() public {
        distributor.nextDraw(2, 220e18); // reserve should be 10e18
        vm.expectRevert(abi.encodeWithSelector(InsufficientLiquidity.selector, 120e18));
        distributor.consumeLiquidity(1, 120e18);
    }
}
