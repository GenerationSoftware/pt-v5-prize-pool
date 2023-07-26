// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import {
  TieredLiquidityDistributor,
  Tier,
  fromUD34x4toUD60x18,
  convert
} from "../../../src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorFuzzHarness is TieredLiquidityDistributor {
  uint256 public totalAdded;
  uint256 public totalConsumed;

  constructor() TieredLiquidityDistributor(3, 100, 10, 10) {}

  function nextDraw(uint8 _nextNumTiers, uint96 liquidity) external {
    uint8 nextNumTiers = _nextNumTiers / 16; // map to [0, 15]
    nextNumTiers = nextNumTiers < 3 ? 3 : nextNumTiers; // ensure min tiers
    totalAdded += liquidity;
    // console2.log("nextDraw", nextNumTiers, liquidity);
    _nextDraw(nextNumTiers, liquidity);
  }

  function net() external view returns (uint256) {
    return totalAdded - totalConsumed;
  }

  function accountedLiquidity() external view returns (uint256) {
    uint256 availableLiquidity;
    for (uint8 i = 0; i < numberOfTiers; i++) {
      Tier memory tier = _getTier(i, numberOfTiers);
      availableLiquidity += convert(
        _getTierRemainingLiquidity(
          _computeShares(i, numberOfTiers),
          fromUD34x4toUD60x18(tier.prizeTokenPerShare),
          fromUD34x4toUD60x18(prizeTokenPerShare)
        )
      );
    }
    // console2.log("reserve ", _reserve);
    availableLiquidity += _reserve;
    // console2.log("SUM", availableLiquidity);
    return availableLiquidity;
  }

  function consumeLiquidity(uint8 _tier) external {
    uint8 tier = _tier % numberOfTiers;

    Tier memory tier_ = _getTier(tier, numberOfTiers);
    uint8 shares = _computeShares(tier, numberOfTiers);
    uint112 liq = uint112(
      convert(
        _getTierRemainingLiquidity(
          shares,
          fromUD34x4toUD60x18(tier_.prizeTokenPerShare),
          fromUD34x4toUD60x18(prizeTokenPerShare)
        )
      )
    );

    // half the time consume only half
    if (_tier > 128) {
      liq += _reserve / 2;
    }

    totalConsumed += liq;
    tier_ = _consumeLiquidity(tier_, tier, uint104(liq));
  }
}
