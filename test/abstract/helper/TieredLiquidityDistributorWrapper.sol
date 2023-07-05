// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { TieredLiquidityDistributor, Tier, fromUD34x4toUD60x18, fromUD60x18 } from "../../../src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorWrapper is TieredLiquidityDistributor {
  constructor(
    uint8 _numberOfTiers,
    uint8 _tierShares,
    uint8 _canaryShares,
    uint8 _reserveShares
  ) TieredLiquidityDistributor(_numberOfTiers, _tierShares, _canaryShares, _reserveShares) {}

  function nextDraw(uint8 _nextNumTiers, uint96 liquidity) external {
    _nextDraw(_nextNumTiers, liquidity);
  }

  function consumeLiquidity(uint8 _tier, uint104 _liquidity) external returns (Tier memory) {
    Tier memory _tierData = _getTier(_tier, numberOfTiers);
    return _consumeLiquidity(_tierData, _tier, _liquidity);
  }

  function remainingTierLiquidity(uint8 _tier) external view returns (uint112) {
    uint8 shares = _computeShares(_tier, numberOfTiers);
    Tier memory tier = _getTier(_tier, numberOfTiers);
    return
      uint112(
        fromUD60x18(
          _getTierRemainingLiquidity(
            shares,
            fromUD34x4toUD60x18(tier.prizeTokenPerShare),
            fromUD34x4toUD60x18(prizeTokenPerShare)
          )
        )
      );
  }

  function getTierLiquidityToReclaim(uint8 _nextNumberOfTiers) external view returns (uint256) {
    return
      _getTierLiquidityToReclaim(
        numberOfTiers,
        _nextNumberOfTiers,
        fromUD34x4toUD60x18(prizeTokenPerShare)
      );
  }
}
