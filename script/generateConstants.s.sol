// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";

import { TierCalculationLib } from "src/libraries/TierCalculationLib.sol";

contract GenerateConstants is Script {
  function run() public {
    uint16 GRAND_PRIZE_PERIOD_DRAWS = 365;

    console.log(
      "/// @notice The number of draws that should statistically occur between grand prizes."
    );
    console.log(
      "uint16 internal constant GRAND_PRIZE_PERIOD_DRAWS = %d;",
      GRAND_PRIZE_PERIOD_DRAWS
    );
    console.log("\n");

    uint8 MIN_TIERS = 2;
    uint8 MAX_TIERS = 14;
    // Precompute the prizes per draw
    for (uint8 numTiers = MIN_TIERS; numTiers <= MAX_TIERS; numTiers++) {
      console.log(
        "uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_%d_TIERS = %d;",
        uint256(numTiers),
        uint256(TierCalculationLib.estimatedClaimCount(numTiers, GRAND_PRIZE_PERIOD_DRAWS))
      );
    }

    console.log("\n");
    MIN_TIERS = 3;
    MAX_TIERS = 16;
    // Precompute the odds for each tier
    for (uint8 numTiers = MIN_TIERS; numTiers <= MAX_TIERS; numTiers++) {
      for (uint8 tier = 0; tier < numTiers; tier++) {
        console.log(
          "SD59x18 internal constant TIER_ODDS_%d_%d = SD59x18.wrap(%d);",
          uint256(tier),
          uint256(numTiers),
          uint256(
            SD59x18.unwrap(TierCalculationLib.getTierOdds(tier, numTiers, GRAND_PRIZE_PERIOD_DRAWS))
          )
        );
      }
    }
  }
}
