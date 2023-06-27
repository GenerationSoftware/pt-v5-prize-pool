// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { TierCalculationLib } from "src/libraries/TierCalculationLib.sol";
import { TierCalculationLibWrapper } from "test/wrappers/TierCalculationLibWrapper.sol";
import { SD59x18, sd, unwrap, toSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

contract TierCalculationLibTest is Test {
  TierCalculationLibWrapper wrapper;

  function setUp() public {
    wrapper = new TierCalculationLibWrapper();
  }

  function testGetTierOdds() public {
    assertEq(unwrap(TierCalculationLib.getTierOdds(0, 4, 365)), 2739726027397260);
    assertEq(unwrap(TierCalculationLib.getTierOdds(1, 4, 365)), 19579642462506911);
    assertEq(unwrap(TierCalculationLib.getTierOdds(2, 4, 365)), 139927275620255366);
    assertEq(unwrap(TierCalculationLib.getTierOdds(3, 4, 365)), 1e18);
  }

  function testEstimatePrizeFrequencyInDraws() public {
    assertEq(TierCalculationLib.estimatePrizeFrequencyInDraws(0, 4, 365), 366);
    assertEq(TierCalculationLib.estimatePrizeFrequencyInDraws(1, 4, 365), 52);
    assertEq(TierCalculationLib.estimatePrizeFrequencyInDraws(2, 4, 365), 8);
    assertEq(TierCalculationLib.estimatePrizeFrequencyInDraws(3, 4, 365), 1);
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

  function testEstimatedClaimCount() public {
    // 2: 4.002739726
    // 3: 16.2121093
    // 4: 66.31989471
    // 5: 271.5303328
    // 6: 1109.21076
    // 7: 4518.562795
    // 8: 18359.91762
    // 9: 74437.0802
    // 10: 301242.1839
    // 11: 1217269.1
    // 12: 4912623.73
    // 13: 19805539.61
    // 14: 79777192.14
    // 15: 321105957.4
    // 16: 1291645055

    assertEq(wrapper.estimatedClaimCount(2, 365), 4);
    assertEq(wrapper.estimatedClaimCount(3, 365), 16);
    assertEq(wrapper.estimatedClaimCount(4, 365), 66);
    assertEq(wrapper.estimatedClaimCount(5, 365), 270);
    assertEq(wrapper.estimatedClaimCount(6, 365), 1108);
    assertEq(wrapper.estimatedClaimCount(7, 365), 4517);
    assertEq(wrapper.estimatedClaimCount(8, 365), 18358);
    assertEq(wrapper.estimatedClaimCount(9, 365), 74435);
    assertEq(wrapper.estimatedClaimCount(10, 365), 301239);
    assertEq(wrapper.estimatedClaimCount(11, 365), 1217266);
    assertEq(wrapper.estimatedClaimCount(12, 365), 4912619);
    assertEq(wrapper.estimatedClaimCount(13, 365), 19805536);
    assertEq(wrapper.estimatedClaimCount(14, 365), 79777187);
    assertEq(wrapper.estimatedClaimCount(15, 365), 321105952);
    assertEq(wrapper.estimatedClaimCount(16, 365), 1291645048);
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
    SD59x18 vaultContribution = toSD59x18(int256(1));
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
    SD59x18 vaultContribution = toSD59x18(int256(1));
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
}
