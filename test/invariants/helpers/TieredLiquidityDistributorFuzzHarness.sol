// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
  TieredLiquidityDistributor,
  Tier,
  convert,
  MINIMUM_NUMBER_OF_TIERS
} from "../../../src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorFuzzHarness is TieredLiquidityDistributor {
  uint256 public totalAdded;
  uint256 public totalConsumed;

  constructor() TieredLiquidityDistributor(1e18, MINIMUM_NUMBER_OF_TIERS, 100, 5, 10, 365) {}

  function awardDraw(uint8 _nextNumTiers, uint96 liquidity) external {
    uint8 nextNumTiers = _nextNumTiers / 16; // map to [0, 15]
    nextNumTiers = nextNumTiers < MINIMUM_NUMBER_OF_TIERS ? MINIMUM_NUMBER_OF_TIERS : nextNumTiers; // ensure min tiers
    totalAdded += liquidity;
    _awardDraw(_lastAwardedDrawId + 1, nextNumTiers, liquidity);
  }

  function net() external view returns (uint256) {
    return totalAdded - totalConsumed;
  }

  function accountedLiquidity() external view returns (uint256) {
    uint256 availableLiquidity;

    for (uint8 i = 0; i < numberOfTiers; i++) {
      Tier memory tier = _getTier(i, numberOfTiers);
      availableLiquidity += _getTierRemainingLiquidity(
        tier.prizeTokenPerShare,
        prizeTokenPerShare,
        _numShares(i, numberOfTiers)
      );
    }

    availableLiquidity += _reserve;

    return availableLiquidity;
  }

  function consumeLiquidity(uint8 _tier) external {
    uint8 tier = _tier % numberOfTiers;

    Tier memory tier_ = _getTier(tier, numberOfTiers);
    uint104 liq = uint104(
      _getTierRemainingLiquidity(
        tier_.prizeTokenPerShare,
        prizeTokenPerShare,
        _numShares(_tier, numberOfTiers)
      )
    );

    // half the time consume only half
    if (_tier > 128) {
      liq += _reserve / 2;
    }

    totalConsumed += liq;
    _consumeLiquidity(tier_, tier, liq);
  }
}
