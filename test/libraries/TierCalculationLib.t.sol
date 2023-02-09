// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { TierCalculationLib } from "src/libraries/TierCalculationLib.sol";
import { SD59x18, sd, unwrap } from "prb-math/SD59x18.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

contract TierCalculationLibTest is Test {

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
        assertEq(TierCalculationLib.calculateWinningZone(1000, sd(0.333e18), sd(1e18), 1), 333);
    }

    function testCalculateWinningZoneWithVaultPortion() public {
        assertEq(TierCalculationLib.calculateWinningZone(1000, sd(1e18), sd(0.444e18), 1), 444);
    }

    function testCalculateWinningZoneWithPrizeCount() public {
        assertEq(TierCalculationLib.calculateWinningZone(1000, sd(1e18), sd(1e18), 5), 5000);
    }

    function testComputeNextExchangeRateDelta() public {
        (UD60x18 deltaExchangeRate, uint256 remainder) = TierCalculationLib.computeNextExchangeRateDelta(900, 7);
        assertEq(UD60x18.unwrap(deltaExchangeRate), 7777777777777777);
        assertEq(remainder, 1);
    }

}
