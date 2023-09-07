// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18 } from "prb-math/UD60x18.sol";

// Note: Need to store the results from the library in a variable to be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086
contract TierCalculationLibWrapper {
  function tierPrizeCountPerDraw(uint8 _tier, SD59x18 _odds) external pure returns (uint32) {
    uint32 result = TierCalculationLib.tierPrizeCountPerDraw(_tier, _odds);
    return result;
  }

  function getTierOdds(
    uint8 _tier,
    uint8 _numberOfTiers,
    uint24 _grandPrizePeriod
  ) external pure returns (SD59x18) {
    SD59x18 result = TierCalculationLib.getTierOdds(_tier, _numberOfTiers, _grandPrizePeriod);
    return result;
  }
}
