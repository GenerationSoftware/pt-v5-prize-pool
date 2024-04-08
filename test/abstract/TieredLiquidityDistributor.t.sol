// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { TieredLiquidityDistributorWrapper } from "./helper/TieredLiquidityDistributorWrapper.sol";
import {
  UD60x18,
  NumberOfTiersLessThanMinimum,
  NumberOfTiersGreaterThanMaximum,
  TierLiquidityUtilizationRateGreaterThanOne,
  TierLiquidityUtilizationRateCannotBeZero,
  InsufficientLiquidity,
  convert,
  SD59x18,
  sd,
  MAXIMUM_NUMBER_OF_TIERS,
  MINIMUM_NUMBER_OF_TIERS,
  NUMBER_OF_CANARY_TIERS
} from "../../src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorTest is Test {
  
  event ReserveConsumed(uint256 amount);

  TieredLiquidityDistributorWrapper public distributor;

  uint24 grandPrizePeriodDraws;
  uint8 numberOfTiers;
  uint8 tierShares;
  uint8 canaryShares;
  uint8 reserveShares;
  uint256 tierLiquidityUtilizationRate;

  function setUp() external {
    numberOfTiers = MINIMUM_NUMBER_OF_TIERS;
    tierShares = 100;
    canaryShares = 5;
    reserveShares = 10;
    grandPrizePeriodDraws = 365;
    tierLiquidityUtilizationRate = 1e18;

    distributor = new TieredLiquidityDistributorWrapper(
      tierLiquidityUtilizationRate,
      numberOfTiers,
      tierShares,
      canaryShares,
      reserveShares,
      grandPrizePeriodDraws
    );
  }

  function testAwardDraw_invalid_num_tiers() public {
    vm.expectRevert(abi.encodeWithSelector(NumberOfTiersLessThanMinimum.selector, 1));
    distributor.awardDraw(1, 100);
  }

  function testAwardDraw() public {
    uint liq1 = 320e18;
    distributor.awardDraw(5, liq1);
    assertEq(distributor.getTierRemainingLiquidity(0), uint(tierShares) * 1e18, "tier 0 accrued fully");
    assertEq(distributor.getTierRemainingLiquidity(1), uint(tierShares) * 1e18, "daily tier");
    assertEq(distributor.getTierRemainingLiquidity(2), uint(tierShares) * 1e18, "canary accrued one draw 1");
    assertEq(distributor.getTierRemainingLiquidity(3), uint(canaryShares) * 1e18, "canary accrued one draw 2");
    assertEq(distributor.getTierRemainingLiquidity(4), uint(canaryShares) * 1e18, "reduced tier has nothing");
    assertEq(distributor.reserve(), uint(reserveShares) * 1e18, "reserve");
    assertEq(_computeLiquidity(), liq1, "total");
  }

  function testAwardDraw_liquidity_shrinkTiers1() public {
    uint liq1 = 320e18; //distributor.computeTotalShares(5) * 1e18; // 5 tiers => 3 normal, 2 canary.  => 320e18 total funds.
    distributor.awardDraw(5, liq1);

    assertEq(distributor.getTierRemainingLiquidity(0), uint(tierShares) * 1e18, "tier 0");
    assertEq(distributor.getTierRemainingLiquidity(1), uint(tierShares) * 1e18, "tier 1");
    assertEq(distributor.getTierRemainingLiquidity(2), uint(tierShares) * 1e18, "daily tier");
    assertEq(distributor.getTierRemainingLiquidity(3), uint(canaryShares) * 1e18, "canary 1");
    assertEq(distributor.getTierRemainingLiquidity(4), uint(canaryShares) * 1e18, "canary 2");
    assertEq(distributor.getTierRemainingLiquidity(5), 0, "nothing beyond");

    // we are shrinking, so we'll recoup the two canaries = 110e18
    uint liq2 = 110e18;
    distributor.awardDraw(4, liq2);
    assertEq(distributor.getTierRemainingLiquidity(0), uint(tierShares) * 2e18, "tier 0 accrued fully");
    assertEq(distributor.getTierRemainingLiquidity(1), uint(tierShares) * 2e18, "daily tier");
    assertEq(distributor.getTierRemainingLiquidity(2), uint(canaryShares) * 1e18, "canary accrued one draw 1");
    assertEq(distributor.getTierRemainingLiquidity(3), uint(canaryShares) * 1e18, "canary accrued one draw 2");
    assertEq(distributor.getTierRemainingLiquidity(4), 0, "reduced tier has nothing");
    assertEq(distributor.reserve(), uint(reserveShares) * 2e18, "reserve");
    assertEq(_computeLiquidity(), liq1 + liq2, "total");
  }

  function testAwardDraw_liquidity_shrinkTiers2() public {
    distributor.awardDraw(7, 520e18); // 5 normal, 2 canary and reserve
    // reclaim 2 canary and 2 regs => 210e18 reclaimed
    distributor.awardDraw(5, 110e18); // 3 normal, 2 canary

    assertEq(distributor.getTierRemainingLiquidity(0), 200e18, "tier 0");
    assertEq(distributor.getTierRemainingLiquidity(1), 200e18, "tier 1");
    assertEq(distributor.getTierRemainingLiquidity(2), 200e18, "daily");
    assertEq(distributor.getTierRemainingLiquidity(3), 5e18, "canary 1");
    assertEq(distributor.getTierRemainingLiquidity(4), 5e18, "canary 2");
    assertEq(distributor.getTierRemainingLiquidity(5), 0);
    assertEq(distributor.reserve(), 20e18, "reserve");

    assertEq(_computeLiquidity(), 630e18, "total liquidity");
  }

  function testAwardDraw_liquidity_sameTiers() public {
    distributor.awardDraw(5, 100e18);
    distributor.awardDraw(5, 100e18);
    assertEq(_computeLiquidity(), 200e18);
  }

  function testAwardDraw_liquidity_growTiers1() public {
    distributor.awardDraw(5, 320e18);
    assertEq(_computeLiquidity(), 320e18, "total liquidity for first draw");
    distributor.awardDraw(6, 420e18);
    assertEq(_computeLiquidity(), 740e18, "total liquidity for second draw");
  }

  function testAwardDraw_liquidity_growTiers2() public {
    distributor.awardDraw(5, 320e18); // 3 tiers and 2 canary.  3 tiers stay, canaries reclaimed.
    // reclaimed 10e18
    distributor.awardDraw(7, 510e18); // 5 tiers and 2 canary

    assertEq(distributor.getTierRemainingLiquidity(0), 200e18, "old tier 0 continues to accrue");
    assertEq(distributor.getTierRemainingLiquidity(1), 200e18, "old tier 1 continues to accrue");
    assertEq(distributor.getTierRemainingLiquidity(2), 200e18, "old tier 2 continues to accrue");
    assertEq(distributor.getTierRemainingLiquidity(3), 100e18, "old tier 3 continues to accrue");
    assertEq(distributor.getTierRemainingLiquidity(4), 100e18, "old canary gets reclaimed");
    assertEq(distributor.getTierRemainingLiquidity(5), 5e18, "new tier who dis 1");
    assertEq(distributor.getTierRemainingLiquidity(6), 5e18, "new tier who dis 2");
    assertEq(distributor.reserve(), 20e18, "reserve");
    assertEq(_computeLiquidity(), 830e18, "total liquidity");
  }

  function testConstructor_numberOfTiersTooLarge() public {
    vm.expectRevert(abi.encodeWithSelector(NumberOfTiersGreaterThanMaximum.selector, 16));
    new TieredLiquidityDistributorWrapper(tierLiquidityUtilizationRate, 16, tierShares, canaryShares, reserveShares, 365);
  }

  function testConstructor_numberOfTiersTooSmall() public {
    vm.expectRevert(abi.encodeWithSelector(NumberOfTiersLessThanMinimum.selector, 1));
    new TieredLiquidityDistributorWrapper(tierLiquidityUtilizationRate, 1, tierShares, canaryShares, reserveShares, 365);
  }

  function testConstructor_tierLiquidityUtilizationRate_gt_1() public {
    vm.expectRevert(abi.encodeWithSelector(TierLiquidityUtilizationRateGreaterThanOne.selector));
    new TieredLiquidityDistributorWrapper(1e18 + 1, MINIMUM_NUMBER_OF_TIERS, tierShares, canaryShares, reserveShares, 365);
  }

  function testConstructor_tierLiquidityUtilizationRate_zero() public {
    vm.expectRevert(abi.encodeWithSelector(TierLiquidityUtilizationRateCannotBeZero.selector));
    new TieredLiquidityDistributorWrapper(0, MINIMUM_NUMBER_OF_TIERS, tierShares, canaryShares, reserveShares, 365);
  }

  function testRemainingTierLiquidity() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, distributor.getTotalShares() * 1e18);
    assertEq(distributor.getTierRemainingLiquidity(0), 100e18, "tier 0");
    assertEq(distributor.getTierRemainingLiquidity(1), 100e18, "tier 1");
    assertEq(distributor.getTierRemainingLiquidity(2), 5e18, "tier 2");
    assertEq(distributor.getTierRemainingLiquidity(3), 5e18, "tier 3");
  }

  // regression test to see if there are any unaccounted rounding errors on consumeLiquidity
  function testConsumeLiquidity_roundingErrors() public {
    distributor = new TieredLiquidityDistributorWrapper(
      tierLiquidityUtilizationRate,
      numberOfTiers,
      100,
      9,
      0,
      grandPrizePeriodDraws
    );
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 218e18); // 100 for each tier + 9 for each canary

    uint256 reserveBefore = distributor.reserve();

    // There is 9e18 liquidity available for tier 3.
    // Each time we consume 1 liquidity we will lose 0.00001 to rounding errors in
    // the tier.prizeTokenPerShare value. Over time, this will accumulate and lead 
    // to the tier thinking is has more remainingLiquidity than it actually does.
    for (uint i = 1; i <= 10000; i++) {
      distributor.consumeLiquidity(3, 1);
      assertEq(distributor.getTierRemainingLiquidity(3) + (distributor.reserve() - reserveBefore), 9e18 - i);
    }

    // Test that we can still consume the rest of the liquidity even it if dips in the reserve
    assertEq(distributor.getTierRemainingLiquidity(3), 9e18 - 90000); // 10000 consumed + 10000 rounding errors, rounding up by 8 each time
    assertEq(distributor.reserve(), 80000);
    vm.expectEmit();
    emit ReserveConsumed(80000); // equal to the rounding errors (8 for each one)
    distributor.consumeLiquidity(3, 9e18 - 10000); // we only consumed 10000, so we should still be able to consume the rest by dipping into reserve
    assertEq(distributor.getTierRemainingLiquidity(3), 0);
  }

  function testConsumeLiquidity_partial() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    distributor.consumeLiquidity(1, 50e18); // consume full liq for tier 1
    assertEq(distributor.getTierRemainingLiquidity(1), 50e18);
  }

  function testConsumeLiquidity_full() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    distributor.consumeLiquidity(1, 100e18); // consume full liq for tier 1
    assertEq(distributor.getTierRemainingLiquidity(1), 0);
  }

  function testConsumeLiquidity_and_empty_reserve() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18); // reserve should be 10e18
    uint256 reserve = distributor.reserve();
    distributor.consumeLiquidity(1, 110e18); // consume full liq for tier 1 and reserve
    assertEq(distributor.getTierRemainingLiquidity(1), 0);
    assertEq(distributor.reserve(), 0);
    assertLt(distributor.reserve(), reserve);
  }

  function testConsumeLiquidity_and_partial_reserve() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18); // reserve should be 10e18
    uint256 reserve = distributor.reserve();
    distributor.consumeLiquidity(1, 105e18); // consume full liq for tier 1 and reserve
    assertEq(distributor.getTierRemainingLiquidity(1), 0);
    assertEq(distributor.reserve(), 5e18);
    assertLt(distributor.reserve(), reserve);
  }

  function testConsumeLiquidity_insufficient() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18); // reserve should be 10e18
    vm.expectRevert(abi.encodeWithSelector(InsufficientLiquidity.selector, 120e18));
    distributor.consumeLiquidity(1, 120e18);
  }

  function testGetTierPrizeSize_noDraw() public {
    assertEq(distributor.getTierPrizeSize(4), 0);
  }

  function testGetTierPrizeSize_invalid() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    assertEq(distributor.getTierPrizeSize(4), 0);
  }

  function testGetTierPrizeSize_grandPrize() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    assertEq(distributor.getTierPrizeSize(0), 100e18);
  }

  function testGetTierPrizeSize_grandPrize_utilizationLower() public {
    tierLiquidityUtilizationRate = 0.5e18;
    distributor = new TieredLiquidityDistributorWrapper(tierLiquidityUtilizationRate, numberOfTiers, tierShares, canaryShares, reserveShares, grandPrizePeriodDraws);
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    assertEq(distributor.getTierPrizeSize(0), 50e18);
    assertEq(distributor.getTierRemainingLiquidity(0), 100e18);
  }

  function testGetTierPrizeSize_overflow() public {
    distributor = new TieredLiquidityDistributorWrapper(tierLiquidityUtilizationRate, numberOfTiers, tierShares, canaryShares, 0, 365);

    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, type(uint104).max);
    distributor.awardDraw(4, type(uint104).max);
    distributor.awardDraw(5, type(uint104).max);
    distributor.awardDraw(6, type(uint104).max);

    assertEq(distributor.getTierPrizeSize(0), type(uint104).max);
  }

  function testGetRemainingTierLiquidity() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    assertEq(distributor.getTierRemainingLiquidity(0), 100e18);
  }

  function testGetTierRemainingLiquidity() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    assertEq(distributor.getTierRemainingLiquidity(0), 100e18);
  }

  function testGetTierRemainingLiquidity_invalid() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, 220e18);
    assertEq(distributor.getTierRemainingLiquidity(5), 0);
  }

  function testIsCanaryTier() public {
    assertEq(distributor.isCanaryTier(0), false, "grand prize");
    assertEq(distributor.isCanaryTier(1), false, "daily tier");
    assertEq(distributor.isCanaryTier(2), true, "canary 1");
    assertEq(distributor.isCanaryTier(3), true, "canary 2");
  }

  function testExpansionTierLiquidity() public {
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, distributor.getTotalShares() * 1e18); // canary gets 100e18
    assertEq(distributor.getTierRemainingLiquidity(0), 100e18, "grand prize liquidity");
    assertEq(distributor.getTierRemainingLiquidity(1), 100e18, "tier 1 liquidity");
    assertEq(distributor.getTierRemainingLiquidity(2), 5e18, "canary 1 liquidity");
    assertEq(distributor.getTierRemainingLiquidity(3), 5e18, "canary 2 liquidity");
    assertEq(distributor.reserve(), 10e18, "reserve liquidity");

    // canary will be reclaimed
    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS+1, 310e18); // total will be 200e18 + 210e18 = 410e18

    assertEq(distributor.getTierRemainingLiquidity(0), 200e18, "grand prize liquidity");
    assertEq(distributor.getTierRemainingLiquidity(1), 200e18, "tier 1 liquidity");
    assertEq(distributor.getTierRemainingLiquidity(2), 100e18, "tier 2 liquidity");
    assertEq(distributor.getTierRemainingLiquidity(3), 5e18, "tier 3 liquidity");
    assertEq(distributor.getTierRemainingLiquidity(4), 5e18, "last tier out");
  }

  function testExpansionTierLiquidity_max() public {
    uint96 amount = 79228162514264337593543950333;
    // uint96 amount = 100e18;
    distributor.awardDraw(15, amount);

    uint128 prizeTokenPerShare = distributor.prizeTokenPerShare();
    uint256 total = (
      prizeTokenPerShare * (distributor.getTotalShares() - distributor.reserveShares())
    ) + distributor.reserve();
    assertEq(total, amount, "prize token per share against total shares");

    uint256 summed;
    for (uint8 t = 0; t < distributor.numberOfTiers(); t++) {
      summed += distributor.getTierRemainingLiquidity(t);
    }
    summed += distributor.reserve();

    assertEq(summed, amount, "summed amount across prize tiers");
  }

  function testGetTierOdds_AllAvailable() public {
    SD59x18 odds;
    grandPrizePeriodDraws = distributor.grandPrizePeriodDraws();
    for (
      uint8 numTiers = MINIMUM_NUMBER_OF_TIERS;
      numTiers <= MAXIMUM_NUMBER_OF_TIERS;
      numTiers++
    ) {
      for (uint8 tier = 0; tier < numTiers; tier++) {
        odds = distributor.getTierOdds(tier, numTiers);
      }
    }
  }

  function testGetTierPrizeCount() public {
    assertEq(distributor.getTierPrizeCount(0), 1);
    assertEq(distributor.getTierPrizeCount(1), 4);
    assertEq(distributor.getTierPrizeCount(2), 16);
  }

  function testGetTierOdds_grandPrize() public {
    for (uint8 i = MINIMUM_NUMBER_OF_TIERS; i <= MAXIMUM_NUMBER_OF_TIERS; i++) {
      assertEq(distributor.getTierOdds(0, i).unwrap(), int(1e18)/int(365), string.concat("grand for num tiers ", string(abi.encode(i))));
    }
  }

  function testGetTierOdds_dailyCanary() public {
    // 3 - 10
    for (uint8 i = MINIMUM_NUMBER_OF_TIERS - 1; i <= MAXIMUM_NUMBER_OF_TIERS; i++) {
      // last tier (canary 2)
      assertEq(distributor.getTierOdds(i-1, i).unwrap(), 1e18, string.concat("canary 2 for num tiers ", string(abi.encode(i))));
      // third to last (daily)
      assertEq(distributor.getTierOdds(i-2, i).unwrap(), 1e18, string.concat("canary 1 for num tiers ", string(abi.encode(i))));
      if (i > 3) {
        // second to last tier (canary 1)
        assertEq(distributor.getTierOdds(i-3, i).unwrap(), 1e18, string.concat("daily for num tiers ", string(abi.encode(i))));
      }
    }
  }

  function testGetTierOdds_zero_when_outside_bounds() public {
    SD59x18 odds;
    for (
      uint8 numTiers = MINIMUM_NUMBER_OF_TIERS - 1;
      numTiers <= MAXIMUM_NUMBER_OF_TIERS;
      numTiers++
    ) {
      odds = distributor.getTierOdds(numTiers, numTiers);
      assertEq(SD59x18.unwrap(odds), 0);
    }
  }

  function testEstimateNumberOfTiersUsingPrizeCountPerDraw_allTiers() public {
    uint32 prizeCount;
    for (
      uint8 numTiers = MINIMUM_NUMBER_OF_TIERS;
      numTiers <= MAXIMUM_NUMBER_OF_TIERS;
      numTiers++
    ) {
      prizeCount = distributor.estimatedPrizeCount(numTiers);
      assertEq(
        distributor.estimateNumberOfTiersUsingPrizeCountPerDraw(prizeCount - 1),
        numTiers,
        "slightly under"
      );
      assertEq(
        distributor.estimateNumberOfTiersUsingPrizeCountPerDraw(prizeCount),
        numTiers,
        "match"
      );
      assertEq(
        distributor.estimateNumberOfTiersUsingPrizeCountPerDraw(prizeCount + 1),
        numTiers,
        "slightly over"
      );
    }

    assertEq(distributor.estimatedPrizeCount(12), 0, "exceeds bounds");
  }

  function testEstimateNumberOfTiersUsingPrizeCountPerDraw_loose() public {
    // 270 prizes for num tiers = 5
    assertEq(
      distributor.estimateNumberOfTiersUsingPrizeCountPerDraw(250),
      6,
      "matches slightly under"
    );
    assertEq(
      distributor.estimateNumberOfTiersUsingPrizeCountPerDraw(270),
      6,
      "matches exact"
    );
    assertEq(
      distributor.estimateNumberOfTiersUsingPrizeCountPerDraw(280),
      6,
      "matches slightly over"
    );
    assertEq(
      distributor.estimateNumberOfTiersUsingPrizeCountPerDraw(540),
      6,
      "matches significantly over"
    );
  }

  function testEstimatedPrizeCount_noParam() public {
    assertEq(distributor.estimatedPrizeCount(), 20);
  }

  function testEstimatedPrizeCount_allTiers() public {
    assertEq(distributor.estimatedPrizeCount(4), 20, "num tiers 4");
    assertEq(distributor.estimatedPrizeCount(5), 80, "num tiers 5");
    assertEq(distributor.estimatedPrizeCount(6), 320, "num tiers 6");
    assertEq(distributor.estimatedPrizeCount(7), 1283, "num tiers 7");
    assertEq(distributor.estimatedPrizeCount(8), 5139, "num tiers 8");
    assertEq(distributor.estimatedPrizeCount(9), 20580, "num tiers 9");
    assertEq(distributor.estimatedPrizeCount(10), 82408, "num tiers 10");
    assertEq(distributor.estimatedPrizeCount(11), 329958, "num tiers 11");
    assertEq(distributor.estimatedPrizeCount(12), 0, "num tiers 12");
  }

  function testEstimatedPrizeCountWithBothCanaries_allTiers() public {
    assertEq(distributor.estimatedPrizeCountWithBothCanaries(3), 0, "num tiers 3");
    assertEq(distributor.estimatedPrizeCountWithBothCanaries(4), 20 + 4**3, "num tiers 4");
    assertEq(distributor.estimatedPrizeCountWithBothCanaries(5), 80 + 4**4, "num tiers 5");
    assertEq(distributor.estimatedPrizeCountWithBothCanaries(6), 320 + 4**5, "num tiers 6");
    assertEq(distributor.estimatedPrizeCountWithBothCanaries(7), 1283 + 4**6, "num tiers 7");
    assertEq(distributor.estimatedPrizeCountWithBothCanaries(12), 0, "num tiers 12");
  }

  function testEstimatedPrizeCountWithBothCanaries() public {
    assertEq(distributor.estimatedPrizeCountWithBothCanaries(), 20 + 4**3, "num tiers 4");
  }

  function testSumTierPrizeCounts() public {
    // 16 canary 1 daily + 64 canary 2 daily = 80
    assertEq(distributor.sumTierPrizeCounts(5), 80, "num tiers 5");
    // 64 + 256 = ~320
    assertEq(distributor.sumTierPrizeCounts(6), 320, "num tiers 6");
    // 256 + 1024 = ~1280
    assertEq(distributor.sumTierPrizeCounts(7), 1283, "num tiers 7");
    // 1024 + 4096 = ~5120 (plus a few prizes from non-daily tiers)
    assertEq(distributor.sumTierPrizeCounts(8), 5139, "num tiers 8");
    assertEq(distributor.sumTierPrizeCounts(9), 20580, "num tiers 9");
    assertEq(distributor.sumTierPrizeCounts(10), 82408, "num tiers 10");
    assertEq(distributor.sumTierPrizeCounts(11), 329958, "num tiers 11");
    assertEq(distributor.sumTierPrizeCounts(12), 0, "num tiers 12");
  }

  function testExpansionTierLiquidity_regression() public {
    uint96 amount1 = 253012247290373118207;
    uint96 amount2 = 99152290762372054017;
    uint96 amount3 = 79228162514264337593543950333;
    uint total = amount1 + amount2 + uint(amount3);

    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, amount1);

    assertEq(summedLiquidity(), amount1, "after amount1");

    distributor.awardDraw(MINIMUM_NUMBER_OF_TIERS, amount2);

    assertEq(summedLiquidity(), amount1 + uint(amount2), "after amount2");

    distributor.awardDraw(15, amount3);

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

  function _computeLiquidity() internal view returns (uint256) {
    // console2.log("test _computeLiquidity, distributor.numberOfTiers()", distributor.numberOfTiers());
    uint256 liquidity = _getTotalTierRemainingLiquidity(distributor.numberOfTiers());
    liquidity += distributor.reserve();
    return liquidity;
  }

  function _getTotalTierRemainingLiquidity(uint8 _numberOfTiers) internal view returns (uint256) {
    uint256 liquidity = 0;
    for (uint8 i = 0; i < _numberOfTiers; i++) {
      liquidity += distributor.getTierRemainingLiquidity(i);
    }
    return liquidity;
  }
}
