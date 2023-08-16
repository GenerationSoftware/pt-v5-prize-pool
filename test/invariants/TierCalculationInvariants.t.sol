// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { TierCalculationFuzzHarness } from "./helpers/TierCalculationFuzzHarness.sol";

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
      uint estimatePrizeCount = TierCalculationLib.estimatedClaimCount(
        harness.numberOfTiers(),
        harness.grandPrizePeriod()
      );
      uint bounds = 30;
      assertApproxEqAbs(
        harness.averagePrizesPerDraw(),
        estimatePrizeCount,
        bounds,
        "estimated prizes match reality"
      );
    }
  }
}
