// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { TierCalculationFuzzHarness } from "./helpers/TierCalculationFuzzHarness.sol";
import { SD59x18, unwrap, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";

contract TierCalculationInvariants is Test {
  TierCalculationFuzzHarness harness;

  function setUp() public {
    harness = new TierCalculationFuzzHarness();
  }

  function test_it() public {
    // uint iterations = 100;

    // for (uint i = 0; i < iterations; i++) {
    //     console2.log("drawPrizes", harness.nextDraw(uint256(keccak256(abi.encode(i)))));
    // }

    if (harness.draws() > 0) {
      uint estimatedPrizeCount = TierCalculationLib.estimatedClaimCount(
        harness.numberOfTiers(),
        harness.grandPrizePeriod()
      );
      uint bounds = 30;
      assertApproxEqAbs(
        harness.averagePrizesPerDraw(),
        estimatedPrizeCount,
        bounds,
        "estimated prizes match reality"
      );
    }
  }
}
