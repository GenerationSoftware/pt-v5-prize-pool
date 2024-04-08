// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { TieredLiquidityDistributor, Tier } from "../../../src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorWrapper is TieredLiquidityDistributor {
  constructor(
    uint256 _tierLiquidityUtilizationRate,
    uint8 _numberOfTiers,
    uint8 _tierShares,
    uint8 _canaryShares,
    uint8 _reserveShares,
    uint24 _grandPrizePeriodDraws
  )
    TieredLiquidityDistributor(_tierLiquidityUtilizationRate, _numberOfTiers, _tierShares, _canaryShares, _reserveShares, _grandPrizePeriodDraws)
  {}

  function awardDraw(uint8 _nextNumTiers, uint256 liquidity) external {
    _awardDraw(_lastAwardedDrawId + 1, _nextNumTiers, liquidity);
  }

  function consumeLiquidity(uint8 _tier, uint96 _liquidity) external {
    Tier memory _tierData = _getTier(_tier, numberOfTiers);
    _consumeLiquidity(_tierData, _tier, _liquidity);
  }

  function computeNewDistributions(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    uint128 _currentPrizeTokenPerShare,
    uint256 _prizeTokenLiquidity
  ) external view returns (uint96, uint128) {
    (uint96 newReserve, uint128 newPrizeTokenPerShare) = _computeNewDistributions(
      _numberOfTiers,
      _nextNumberOfTiers,
      _currentPrizeTokenPerShare,
      _prizeTokenLiquidity
    );
    return (newReserve, newPrizeTokenPerShare);
  }

  function estimateNumberOfTiersUsingPrizeCountPerDraw(
    uint32 _prizeCount
  ) external view returns (uint8) {
    uint8 result = _estimateNumberOfTiersUsingPrizeCountPerDraw(_prizeCount);
    return result;
  }

  function sumTierPrizeCounts(uint8 _numTiers) external view returns (uint32) {
    uint32 result = _sumTierPrizeCounts(_numTiers);
    return result;
  }
}
