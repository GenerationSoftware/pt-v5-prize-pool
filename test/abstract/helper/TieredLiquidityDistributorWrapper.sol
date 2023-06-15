// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { TieredLiquidityDistributor, Tier } from "src/abstract/TieredLiquidityDistributor.sol";

contract TieredLiquidityDistributorWrapper is TieredLiquidityDistributor {

    constructor (
        uint32 _grandPrizePeriodDraws,
        uint8 _numberOfTiers,
        uint8 _tierShares,
        uint8 _canaryShares,
        uint8 _reserveShares
    ) TieredLiquidityDistributor(_grandPrizePeriodDraws, _numberOfTiers, _tierShares, _canaryShares, _reserveShares) {}

    function nextDraw(uint8 _nextNumTiers, uint96 liquidity) external {
        _nextDraw(_nextNumTiers, liquidity);
    }

    function consumeLiquidity(uint8 _tier, uint104 _liquidity) external returns (Tier memory) {
        return _consumeLiquidity(_tier, _liquidity);
    }

    function remainingTierLiquidity(uint8 _tier) external view returns (uint112) {
        uint8 shares = _computeShares(_tier, numberOfTiers);
        Tier memory tier = _getTier(_tier, numberOfTiers);
        return _remainingTierLiquidity(tier, shares);
    }

}
