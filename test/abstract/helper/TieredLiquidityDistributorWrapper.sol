// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { TieredLiquidityDistributor, Tier, fromUD34x4toUD60x18, convert } from "../../../src/abstract/TieredLiquidityDistributor.sol";
import { UD60x18 } from "prb-math/UD60x18.sol";

contract TieredLiquidityDistributorWrapper is TieredLiquidityDistributor {
  constructor(
    uint8 _numberOfTiers,
    uint8 _tierShares,
    uint8 _reserveShares,
    uint24 _grandPrizePeriodDraws
  )
    TieredLiquidityDistributor(_numberOfTiers, _tierShares, _reserveShares, _grandPrizePeriodDraws)
  {}

  function awardDraw(uint8 _nextNumTiers, uint256 liquidity) external {
    _awardDraw(_lastAwardedDrawId + 1, _nextNumTiers, liquidity);
  }

  function consumeLiquidity(uint8 _tier, uint96 _liquidity) external {
    Tier memory _tierData = _getTier(_tier, numberOfTiers);
    _consumeLiquidity(_tierData, _tier, _liquidity);
  }

  function remainingTierLiquidity(uint8 _tier) external view returns (uint112) {
    return uint112(getTierRemainingLiquidity(_tier));
    // uint8 shares = tierShares;
    // Tier memory tier = _getTier(_tier, numberOfTiers);
    // return
    //   uint112(
    //     convert(
    //       _getTierRemainingLiquidity(
    //         fromUD34x4toUD60x18(tier.prizeTokenPerShare),
    //         fromUD34x4toUD60x18(prizeTokenPerShare)
    //       )
    //     )
    //   );
  }

  function computeNewDistributions(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    UD60x18 _currentPrizeTokenPerShare,
    uint256 _prizeTokenLiquidity
  ) external view returns (uint96, UD60x18) {
    (uint96 newReserve, UD60x18 newPrizeTokenPerShare) = _computeNewDistributions(
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
