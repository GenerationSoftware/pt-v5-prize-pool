// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { TieredLiquidityDistributorWrapper } from "test/abstract/helper/TieredLiquidityDistributorWrapper.sol";
import { UD60x18, NumberOfTiersLessThanMinimum, NumberOfTiersGreaterThanMaximum, InsufficientLiquidity, fromUD34x4toUD60x18, toUD60x18, fromUD60x18, SD59x18, fromSD59x18 } from "../../src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorTest is Test {
  TieredLiquidityDistributorWrapper public distributor;

  uint16 grandPrizePeriodDraws;
  uint8 numberOfTiers;
  uint8 tierShares;
  uint8 canaryShares;
  uint8 reserveShares;

  function setUp() external {
    numberOfTiers = 3;
    tierShares = 100;
    canaryShares = 10;
    reserveShares = 10;

    distributor = new TieredLiquidityDistributorWrapper(
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

  function testConstructor_numberOfTiersTooLarge() public {
    vm.expectRevert(abi.encodeWithSelector(NumberOfTiersGreaterThanMaximum.selector, 16));
    new TieredLiquidityDistributorWrapper(
      16,
      tierShares,
      canaryShares,
      reserveShares
    );
  }

  function testConstructor_numberOfTiersTooSmall() public {
    vm.expectRevert(abi.encodeWithSelector(NumberOfTiersLessThanMinimum.selector, 1));
    new TieredLiquidityDistributorWrapper(
      1,
      tierShares,
      canaryShares,
      reserveShares
    );
  }

  function testRemainingTierLiquidity() public {
    distributor.nextDraw(3, 220e18);
    assertEq(distributor.remainingTierLiquidity(0), 100e18);
    assertEq(distributor.remainingTierLiquidity(1), 100e18);
    assertEq(distributor.remainingTierLiquidity(2), 10e18);
  }

  function testConsumeLiquidity_partial() public {
    distributor.nextDraw(3, 220e18);
    distributor.consumeLiquidity(1, 50e18); // consume full liq for tier 1
    assertEq(distributor.remainingTierLiquidity(1), 50e18);
  }

  function testConsumeLiquidity_full() public {
    distributor.nextDraw(3, 220e18);
    distributor.consumeLiquidity(1, 100e18); // consume full liq for tier 1
    assertEq(distributor.remainingTierLiquidity(1), 0);
  }

  function testConsumeLiquidity_and_empty_reserve() public {
    distributor.nextDraw(3, 220e18); // reserve should be 10e18
    uint256 reserve = distributor.reserve();
    distributor.consumeLiquidity(1, 110e18); // consume full liq for tier 1 and reserve
    assertEq(distributor.remainingTierLiquidity(1), 0);
    assertEq(distributor.reserve(), 0);
    assertLt(distributor.reserve(), reserve);
  }

  function testConsumeLiquidity_and_partial_reserve() public {
    distributor.nextDraw(3, 220e18); // reserve should be 10e18
    uint256 reserve = distributor.reserve();
    distributor.consumeLiquidity(1, 105e18); // consume full liq for tier 1 and reserve
    assertEq(distributor.remainingTierLiquidity(1), 0);
    assertEq(distributor.reserve(), 5e18);
    assertLt(distributor.reserve(), reserve);
  }

  function testConsumeLiquidity_insufficient() public {
    distributor.nextDraw(3, 220e18); // reserve should be 10e18
    vm.expectRevert(abi.encodeWithSelector(InsufficientLiquidity.selector, 120e18));
    distributor.consumeLiquidity(1, 120e18);
  }

  function testGetTierPrizeSize_noDraw() public {
    assertEq(distributor.getTierPrizeSize(4), 0);
  }

  function testGetTierPrizeSize_grandPrize() public {
    distributor.nextDraw(3, 220e18);
    assertEq(distributor.getTierPrizeSize(0), 100e18);
  }

  function testGetRemainingTierLiquidity() public {
    distributor.nextDraw(3, 220e18);
    assertEq(distributor.getTierRemainingLiquidity(0), 100e18);
  }

  function testGetTierRemainingLiquidity() public {
    distributor.nextDraw(3, 220e18);
    assertEq(distributor.getTierRemainingLiquidity(0), 100e18);
  }

  function testReclaimLiquidity_canary_tier() public {
    distributor.nextDraw(4, 320e18);
    // should be 10e18 in the canary tier

    // reclaiming same num tiers should take back canary tier
    assertEq(distributor.getTierLiquidityToReclaim(4), 10e18);
  }

  function testReclaimLiquidity_canary_tier_plus_one() public {
    distributor.nextDraw(4, 320e18);
    // should be 10e18 in the canary tier

    // reclaiming same num tiers should take back canary tier
    assertEq(distributor.getTierLiquidityToReclaim(3), 110e18);
  }

  function testReclaimLiquidity_canary_tier_plus_two() public {
    distributor.nextDraw(5, 420e18);
    // should be 10e18 in the canary tier

    // reclaiming same num tiers should take back canary tier
    assertEq(distributor.getTierLiquidityToReclaim(3), 210e18);
  }

  function testExpansionTierLiquidity() public {
    distributor.nextDraw(3, 220e18); // canary gets 10e18
    assertEq(distributor.getTierRemainingLiquidity(2), 10e18, "canary initial liquidity");
    distributor.nextDraw(5, 420e18); // should be 420 distributed

    assertEq(distributor.getTierRemainingLiquidity(3), 100e18, "new tier liquidity");
    assertEq(distributor.getTierRemainingLiquidity(4), 10e18, "canary liquidity");
  }

  function testExpansionTierLiquidity_max() public {
    uint96 amount = 79228162514264337593543950333;
    // uint96 amount = 100e18;
    distributor.nextDraw(15, amount);

    UD60x18 prizeTokenPerShare = fromUD34x4toUD60x18(distributor.prizeTokenPerShare());
    uint256 total = fromUD60x18(
      prizeTokenPerShare.mul(toUD60x18(distributor.getTotalShares() - distributor.reserveShares()))
    ) + distributor.reserve();
    assertEq(total, amount, "prize token per share against total shares");

    uint256 summed;
    for (uint8 t = 0; t < distributor.numberOfTiers(); t++) {
      summed += distributor.getTierRemainingLiquidity(t);
    }
    summed += distributor.reserve();

    assertEq(summed, amount, "summed amount across prize tiers");
  }

  function testTierOdds_Accuracy() public {
    SD59x18 odds = distributor.getTierOdds(0, 3);
    assertEq(SD59x18.unwrap(odds), 2739726027397260);
    odds = distributor.getTierOdds(3, 7);
    assertEq(SD59x18.unwrap(odds), 52342392259021369);
    odds = distributor.getTierOdds(14, 15);
    assertEq(SD59x18.unwrap(odds), 1000000000000000000, "checking accuracy for last tier");
  }

  function testTierOdds_AllAvailable() public {
    SD59x18 odds;
    for (uint8 numTiers = 3; numTiers < 16; numTiers++) {
      for (uint8 tier = 0; tier < numTiers; tier++) {
        odds = distributor.getTierOdds(tier, numTiers);
        assertGt(SD59x18.unwrap(odds), 0);
        assertLe(SD59x18.unwrap(odds), 1000000000000000000, "checking accuracy for highest available");
      }
    }
  }

  function testGetTierPrizeCount() public {
    assertEq(distributor.getTierPrizeCount(0, 3), 1);
    assertEq(distributor.getTierPrizeCount(1, 3), 4);
    assertEq(distributor.getTierPrizeCount(2, 3), 2); // canary tier
  }

  function testTierOdds_zero_when_outside_bounds() public {
    SD59x18 odds;
    for (uint8 numTiers = 3; numTiers < 16; numTiers++) {
      odds = distributor.getTierOdds(numTiers, numTiers);
      assertGt(SD59x18.unwrap(odds), 0);
    }
  }

  function testEstimatedPrizesPerDraw_AllAvailable() public {
    uint32 prizeCount;
    for (uint8 numTiers = 3; numTiers <= 15; numTiers++) {
      prizeCount = distributor.estimatedPrizeCount(numTiers);
      assertGt(prizeCount, 0);
      assertLe(prizeCount, 79777187);
    }
  }

  function testExpansionTierLiquidity_regression() public {
    uint96 amount1 = 253012247290373118207;
    uint96 amount2 = 99152290762372054017;
    uint96 amount3 = 79228162514264337593543950333;
    uint total = amount1 + amount2 + uint(amount3);

    distributor.nextDraw(3, amount1);

    assertEq(summedLiquidity(), amount1, "after amount1");

    distributor.nextDraw(3, amount2);

    assertEq(summedLiquidity(), amount1 + uint(amount2), "after amount2");

    distributor.nextDraw(15, amount3);

    assertEq(summedLiquidity(), total, "after amount3");
  }

  function summedLiquidity() public view returns (uint256) {
    uint256 summed;
    for (uint8 t = 0; t < distributor.numberOfTiers(); t++) {
      summed += distributor.getTierRemainingLiquidity(t);
    }
    summed += distributor.reserve();
    return summed;
  }
}
