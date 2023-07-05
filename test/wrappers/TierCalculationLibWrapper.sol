// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { TierCalculationLib } from "../../src/libraries/TierCalculationLib.sol";
import { UD60x18 } from "prb-math/UD60x18.sol";

// Note: Need to store the results from the library in a variable to be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086
contract TierCalculationLibWrapper {
  function canaryPrizeCount(
    uint8 _numberOfTiers,
    uint8 _canaryShares,
    uint8 _reserveShares,
    uint8 _tierShares
  ) external pure returns (UD60x18) {
    UD60x18 result = TierCalculationLib.canaryPrizeCount(
      _numberOfTiers,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    return result;
  }

  function estimatedClaimCount(
    uint8 _numberOfTiers,
    uint16 _grandPrizePeriod
  ) external pure returns (uint32) {
    uint32 result = TierCalculationLib.estimatedClaimCount(_numberOfTiers, _grandPrizePeriod);
    return result;
  }
}
