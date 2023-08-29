// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { TierCalculationLibWrapper } from "../wrappers/TierCalculationLibWrapper.sol";
import { SD59x18, sd, wrap, unwrap, convert } from "prb-math/SD59x18.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

contract TierCalculationLibTest is Test {
  TierCalculationLibWrapper wrapper;

  function setUp() public {
    wrapper = new TierCalculationLibWrapper();
  }

  function testGetTierOdds() public {
    assertEq(unwrap(wrapper.getTierOdds(0, 4, 365)), 2739726027397260);
    assertEq(unwrap(wrapper.getTierOdds(1, 4, 365)), 19579642462506911);
    assertEq(unwrap(wrapper.getTierOdds(2, 4, 365)), 139927275620255364);
    assertEq(unwrap(wrapper.getTierOdds(3, 4, 365)), 1e18);
  }

  function testEstimatePrizeFrequencyInDraws() public {
    assertEq(
      TierCalculationLib.estimatePrizeFrequencyInDraws(TierCalculationLib.getTierOdds(0, 4, 365)),
      366
    );
    assertEq(
      TierCalculationLib.estimatePrizeFrequencyInDraws(TierCalculationLib.getTierOdds(1, 4, 365)),
      52
    );
    assertEq(
      TierCalculationLib.estimatePrizeFrequencyInDraws(TierCalculationLib.getTierOdds(2, 4, 365)),
      8
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

  function testCanaryPrizeCount() public {
    assertEq(wrapper.canaryPrizeCount(2, 10, 0, 100).unwrap(), 2361904761904761904);
    assertEq(wrapper.canaryPrizeCount(3, 10, 0, 100).unwrap(), 8464516129032258048);
    assertEq(wrapper.canaryPrizeCount(4, 10, 0, 100).unwrap(), 31843902439024390144);
    assertEq(wrapper.canaryPrizeCount(5, 10, 0, 100).unwrap(), 122478431372549018624);
    assertEq(wrapper.canaryPrizeCount(6, 10, 0, 100).unwrap(), 476747540983606554624);
    assertEq(wrapper.canaryPrizeCount(7, 10, 0, 100).unwrap(), 1869160563380281688064);
    assertEq(wrapper.canaryPrizeCount(8, 10, 0, 100).unwrap(), 7362686419753086418944);
    assertEq(wrapper.canaryPrizeCount(9, 10, 0, 100).unwrap(), 29095103296703296700416);
    assertEq(wrapper.canaryPrizeCount(10, 10, 0, 100).unwrap(), 115239540594059404902400);
    assertEq(wrapper.canaryPrizeCount(11, 10, 0, 100).unwrap(), 457216922522522522484736);
    assertEq(wrapper.canaryPrizeCount(12, 10, 0, 100).unwrap(), 1816376277685950406983680);
    assertEq(wrapper.canaryPrizeCount(13, 10, 0, 100).unwrap(), 7223167804580152605671424);
    assertEq(wrapper.canaryPrizeCount(14, 10, 0, 100).unwrap(), 28747343160283687758594048);
    assertEq(wrapper.canaryPrizeCount(15, 10, 0, 100).unwrap(), 114485055406622515774095360);
  }

  function testIsWinner_WinsAll() external {
    uint8 tier = 5;
    uint8 numberOfTiers = 6;
    vm.assume(tier < numberOfTiers);
    uint16 grandPrizePeriod = 365;
    SD59x18 tierOdds = TierCalculationLib.getTierOdds(tier, numberOfTiers, grandPrizePeriod);
    // console2.log("tierOdds", SD59x18.unwrap(tierOdds));
    uint32 prizeCount = uint32(TierCalculationLib.prizeCount(tier));
    SD59x18 vaultContribution = convert(int256(1));
    // console2.log("vaultContribution", SD59x18.unwrap(vaultContribution));

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
    // console2.log("tierOdds", SD59x18.unwrap(tierOdds));
    uint32 prizeCount = uint32(TierCalculationLib.prizeCount(tier));
    SD59x18 vaultContribution = convert(int256(1));
    // console2.log("vaultContribution", SD59x18.unwrap(vaultContribution));

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
