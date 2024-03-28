// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { MINIMUM_NUMBER_OF_TIERS, MAXIMUM_NUMBER_OF_TIERS } from "../../src/abstract/TieredLiquidityDistributor.sol";
import { TierCalculationLibWrapper } from "../wrappers/TierCalculationLibWrapper.sol";
import { SD59x18, sd, wrap, unwrap, convert } from "prb-math/SD59x18.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

contract TierCalculationLibTest is Test {
  TierCalculationLibWrapper wrapper;

  function setUp() public {
    wrapper = new TierCalculationLibWrapper();
  }

  function testGetTierOdds_grandPrizeOdds() public {
    for (uint8 i = MINIMUM_NUMBER_OF_TIERS - 1; i <= MAXIMUM_NUMBER_OF_TIERS; i++) {
      // grand prize is always 1/365
      assertEq(unwrap(wrapper.getTierOdds(0, i, 365)), 2739726027397260);
    }
  }

  function testGetTierOdds_tier4() public {
    assertEq(unwrap(wrapper.getTierOdds(0, 4, 365)), 2739726027397260);
    assertEq(unwrap(wrapper.getTierOdds(1, 4, 365)), 8089033552608040);
    assertEq(unwrap(wrapper.getTierOdds(2, 4, 365)), 33163436331078433);
    assertEq(unwrap(wrapper.getTierOdds(3, 4, 365)), 1e18);
  }

  function testEstimatePrizeFrequencyInDraws() public {
    assertEq(
      TierCalculationLib.estimatePrizeFrequencyInDraws(TierCalculationLib.getTierOdds(0, 4, 365)),
      366
    );
    assertEq(
      TierCalculationLib.estimatePrizeFrequencyInDraws(TierCalculationLib.getTierOdds(1, 4, 365)),
      124
    );
    assertEq(
      TierCalculationLib.estimatePrizeFrequencyInDraws(TierCalculationLib.getTierOdds(2, 4, 365)),
      31
    );
    assertEq(
      TierCalculationLib.estimatePrizeFrequencyInDraws(TierCalculationLib.getTierOdds(3, 4, 365)),
      1
    );
  }

  function testPrizeCount() public {
    assertEq(TierCalculationLib.prizeCount(0), 1);
  }

  function testCalculateWinningZoneWithTierOdds() public {
    assertEq(TierCalculationLib.calculateWinningZone(1000, sd(0.333e18), sd(1e18)), 333);
  }

  function testCalculateWinningZoneWithVaultPortion() public {
    assertEq(TierCalculationLib.calculateWinningZone(1000, sd(1e18), sd(0.444e18)), 444);
  }

  function testCalculateWinningZoneWithPrizeCount() public {
    assertEq(TierCalculationLib.calculateWinningZone(1000, sd(1e18), sd(1e18)), 1000);
  }

  function testIsWinner_WinsAll() external {
    uint8 tier = 5;
    uint8 numberOfTiers = 6;
    vm.assume(tier < numberOfTiers);
    uint16 grandPrizePeriod = 365;
    SD59x18 tierOdds = TierCalculationLib.getTierOdds(tier, numberOfTiers, grandPrizePeriod);
    uint32 prizeCount = uint32(TierCalculationLib.prizeCount(tier));
    SD59x18 vaultContribution = convert(int256(1));

    uint wins;
    for (uint i = 0; i < prizeCount; i++) {
      if (
        TierCalculationLib.isWinner(
          uint256(keccak256(abi.encode(i))),
          1000,
          1000,
          vaultContribution,
          tierOdds
        )
      ) {
        wins++;
      }
    }

    assertApproxEqAbs(wins, prizeCount, 0);
  }

  function testIsWinner_HalfLiquidity() external {
    uint8 tier = 5;
    uint8 numberOfTiers = 6;
    vm.assume(tier < numberOfTiers);
    uint16 grandPrizePeriod = 365;
    SD59x18 tierOdds = TierCalculationLib.getTierOdds(tier, numberOfTiers, grandPrizePeriod);
    uint32 prizeCount = uint32(TierCalculationLib.prizeCount(tier));
    SD59x18 vaultContribution = convert(int256(1));

    uint wins;
    for (uint i = 0; i < prizeCount; i++) {
      if (
        TierCalculationLib.isWinner(
          uint256(keccak256(abi.encode(i))),
          500,
          1000,
          vaultContribution,
          tierOdds
        )
      ) {
        wins++;
      }
    }

    assertApproxEqAbs(wins, prizeCount / 2, 20);
  }

  function testTierPrizeCountPerDraw() public {
    assertEq(wrapper.tierPrizeCountPerDraw(3, wrap(0.5e18)), 32);
  }
}
