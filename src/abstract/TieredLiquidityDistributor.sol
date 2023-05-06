// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud, toUD60x18, fromUD60x18, intoSD59x18 } from "prb-math/UD60x18.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { UD34x4, fromUD60x18 as fromUD60x18toUD34x4, intoUD60x18 as fromUD34x4toUD60x18, toUD34x4 } from "src/libraries/UD34x4.sol";
import { TierCalculationLib } from "src/libraries/TierCalculationLib.sol";

struct Tier {
    uint32 drawId;
    uint96 prizeSize;
    UD34x4 prizeTokenPerShare;
}

contract TieredLiquidityDistributor {

    uint8 internal constant MINIMUM_NUMBER_OF_TIERS = 2;

    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS;

    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_2_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_3_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_4_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_5_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_6_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_7_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_8_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_9_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_10_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_11_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_12_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_13_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_14_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_15_TIERS;

    mapping(uint8 => Tier) internal _tiers;

    /// @notice The number of draws that should statistically occur between grand prizes.
    uint32 public immutable grandPrizePeriodDraws;

    /// @notice The number of shares to allocate to each prize tier
    uint8 public immutable tierShares;

    /// @notice The number of shares to allocate to the canary tier
    uint8 public immutable canaryShares;

    /// @notice The number of shares to allocate to the reserve
    uint8 public immutable reserveShares;

    /// @notice The current number of prize tokens per share
    UD34x4 public prizeTokenPerShare;

    /// @notice The number of tiers for the last completed draw
    uint8 public numberOfTiers;

    /// @notice The draw id of the last completed draw
    uint16 internal lastCompletedDrawId;

    /// @notice The amount of available reserve
    uint104 internal _reserve;

    /**
     * @notice Constructs a new Prize Pool
     * @param _grandPrizePeriodDraws The average number of draws between grand prizes. This determines the statistical frequency of grand prizes.
     * @param _numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
     * @param _tierShares The number of shares to allocate to each tier
     * @param _canaryShares The number of shares to allocate to the canary tier.
     * @param _reserveShares The number of shares to allocate to the reserve.
     */
    constructor (
        uint32 _grandPrizePeriodDraws,
        uint8 _numberOfTiers,
        uint8 _tierShares,
        uint8 _canaryShares,
        uint8 _reserveShares
    ) {
        grandPrizePeriodDraws = _grandPrizePeriodDraws;
        numberOfTiers = _numberOfTiers;
        tierShares = _tierShares;
        canaryShares = _canaryShares;
        reserveShares = _reserveShares;

        require(numberOfTiers >= MINIMUM_NUMBER_OF_TIERS, "num-tiers-gt-1");

        ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS = TierCalculationLib.estimatedClaimCount(2, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS = TierCalculationLib.estimatedClaimCount(3, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS = TierCalculationLib.estimatedClaimCount(4, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS = TierCalculationLib.estimatedClaimCount(5, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS = TierCalculationLib.estimatedClaimCount(6, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS = TierCalculationLib.estimatedClaimCount(7, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS = TierCalculationLib.estimatedClaimCount(8, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS = TierCalculationLib.estimatedClaimCount(9, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS = TierCalculationLib.estimatedClaimCount(10, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS = TierCalculationLib.estimatedClaimCount(11, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS = TierCalculationLib.estimatedClaimCount(12, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS = TierCalculationLib.estimatedClaimCount(13, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS = TierCalculationLib.estimatedClaimCount(14, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS = TierCalculationLib.estimatedClaimCount(15, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS = TierCalculationLib.estimatedClaimCount(16, _grandPrizePeriodDraws);

        CANARY_PRIZE_COUNT_FOR_2_TIERS = TierCalculationLib.canaryPrizeCount(2, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_3_TIERS = TierCalculationLib.canaryPrizeCount(3, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_4_TIERS = TierCalculationLib.canaryPrizeCount(4, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_5_TIERS = TierCalculationLib.canaryPrizeCount(5, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_6_TIERS = TierCalculationLib.canaryPrizeCount(6, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_7_TIERS = TierCalculationLib.canaryPrizeCount(7, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_8_TIERS = TierCalculationLib.canaryPrizeCount(8, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_9_TIERS = TierCalculationLib.canaryPrizeCount(9, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_10_TIERS = TierCalculationLib.canaryPrizeCount(10, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_11_TIERS = TierCalculationLib.canaryPrizeCount(11, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_12_TIERS = TierCalculationLib.canaryPrizeCount(12, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_13_TIERS = TierCalculationLib.canaryPrizeCount(13, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_14_TIERS = TierCalculationLib.canaryPrizeCount(14, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_15_TIERS = TierCalculationLib.canaryPrizeCount(15, _canaryShares, _reserveShares, _tierShares);
    }

    function _nextDraw(uint8 _nextNumberOfTiers, uint96 _prizeTokenLiquidity) internal {
        // console2.log("_nextDraw STARTING", _prizeTokenLiquidity);
        require(_nextNumberOfTiers >= MINIMUM_NUMBER_OF_TIERS, "num-tiers-gt-1");
        uint8 numTiers = numberOfTiers;
        uint16 completedDrawId = lastCompletedDrawId + 1;
        // console2.log("prizeTokenPerShare", UD34x4.unwrap(prizeTokenPerShare));
        UD60x18 _prizeTokenPerShare = fromUD34x4toUD60x18(prizeTokenPerShare);
        // console2.log("60x18 _prizeTokenPerShare", _prizeTokenPerShare.unwrap());
        uint256 totalShares = _getTotalShares(_nextNumberOfTiers);
        // console2.log("totalShares", totalShares);
        UD60x18 deltaPrizeTokensPerShare = toUD60x18(_prizeTokenLiquidity).div(toUD60x18(totalShares));

        // console2.log("deltaPrizeTokensPerShare", deltaPrizeTokensPerShare.unwrap());
        uint256 reclaimedLiquidity = _reclaimLiquidity(numTiers, _nextNumberOfTiers, _prizeTokenPerShare);
        // console2.log("reclaimedLiquidity", reclaimedLiquidity);
        UD60x18 newPrizeTokenPerShare = _prizeTokenPerShare.add(deltaPrizeTokensPerShare);
        // console2.log("newPrizeTokenPerShare", newPrizeTokenPerShare.unwrap());

        // if expanding, need to reset the new tier
        if (_nextNumberOfTiers > numTiers) {
            for (uint8 i = numTiers; i < _nextNumberOfTiers; i++) {
                _tiers[i] = Tier({
                    drawId: completedDrawId,
                    prizeTokenPerShare: prizeTokenPerShare,
                    prizeSize: uint96(_computePrizeSize(i, _nextNumberOfTiers, _prizeTokenPerShare, newPrizeTokenPerShare))
                });
            }
            // console2.log("computed expansion tier");
        }

        // Set canary tier
        _tiers[_nextNumberOfTiers] = Tier({
            drawId: completedDrawId,
            prizeTokenPerShare: prizeTokenPerShare,
            prizeSize: uint96(_computePrizeSize(_nextNumberOfTiers, _nextNumberOfTiers, _prizeTokenPerShare, newPrizeTokenPerShare))
        });

        // console2.log("set canary tier");

        uint256 remainder = _prizeTokenLiquidity - fromUD60x18(deltaPrizeTokensPerShare.mul(toUD60x18(totalShares)));
        
        uint256 reservePortion = fromUD60x18(deltaPrizeTokensPerShare.mul(toUD60x18(reserveShares)));

        uint256 total = fromUD60x18(deltaPrizeTokensPerShare.mul(toUD60x18(totalShares))) + remainder;
        // console2.log("total", total);

        // console2.log("reservePortion", reservePortion);

        prizeTokenPerShare = fromUD60x18toUD34x4(newPrizeTokenPerShare);
        numberOfTiers = _nextNumberOfTiers;
        lastCompletedDrawId = completedDrawId;
        _reserve += uint104(reservePortion + reclaimedLiquidity + remainder);
    }

    function _getTier(uint8 _tier, uint8 _numberOfTiers) internal view returns (Tier memory) {
        Tier memory tier = _tiers[_tier];
        uint32 _lastCompletedDrawId = lastCompletedDrawId;
        if (tier.drawId != _lastCompletedDrawId) {
            tier.drawId = _lastCompletedDrawId;
            tier.prizeSize = uint96(_computePrizeSize(_tier, _numberOfTiers, fromUD34x4toUD60x18(tier.prizeTokenPerShare), fromUD34x4toUD60x18(prizeTokenPerShare)));
        }
        return tier;
    }

    /// @notice Computes the total shares in the system given the number of tiers. That is `(number of tiers * tier shares) + canary shares + reserve shares`
    /// @param _numberOfTiers The number of tiers to calculate the total shares for
    /// @return The total shares
    function _getTotalShares(uint8 _numberOfTiers) internal view returns (uint256) {
        return uint256(_numberOfTiers) * uint256(tierShares) + uint256(canaryShares) + uint256(reserveShares);
    }

    function _consumeLiquidity(uint8 _tier, uint104 _liquidity) internal returns (Tier memory) {
        uint8 numTiers = numberOfTiers;
        uint8 shares = _computeShares(_tier, numTiers);
        Tier memory tier = _getTier(_tier, numberOfTiers);
        tier = _consumeLiquidity(tier, _tier, shares, _liquidity);
    }

    function _computeShares(uint8 _tier, uint8 _numTiers) internal view returns (uint8) {
        return _tier == numberOfTiers ? canaryShares : tierShares;
    }

    function _consumeLiquidity(Tier memory _tierStruct, uint8 _tier, uint8 _shares, uint104 _liquidity) internal returns (Tier memory) {
        uint104 remainingLiquidity = uint104(_remainingTierLiquidity(_tierStruct, _shares));
        if (_liquidity > remainingLiquidity) {
            uint104 excess = _liquidity - remainingLiquidity;
            if (excess > _reserve) {
                revert("insufficient liquidity");
            }
            _reserve -= excess;
            _tierStruct.prizeTokenPerShare = prizeTokenPerShare;
        } else {
            UD34x4 delta = fromUD60x18toUD34x4(
                toUD60x18(_liquidity).div(toUD60x18(_shares))
            );
            _tierStruct.prizeTokenPerShare = UD34x4.wrap(UD34x4.unwrap(_tierStruct.prizeTokenPerShare) + UD34x4.unwrap(delta));
        }
        _tiers[_tier] = _tierStruct;
        return _tierStruct;
    }

    /// @notice Computes the total liquidity available to a tier
    /// @param _tier The tier to compute the liquidity for
    /// @return The total liquidity
    function _remainingTierLiquidity(Tier memory _tier, uint8 _shares) internal view returns (uint112) {
        UD34x4 _prizeTokenPerShare = prizeTokenPerShare;
        if (UD34x4.unwrap(_tier.prizeTokenPerShare) >= UD34x4.unwrap(_prizeTokenPerShare)) {
            return 0;
        }
        UD60x18 delta = fromUD34x4toUD60x18(_prizeTokenPerShare).sub(fromUD34x4toUD60x18(_tier.prizeTokenPerShare));
        // delta max int size is (uMAX_UD34x4 / 1e4)
        // max share size is 256
        // result max = (uMAX_UD34x4 / 1e4) * 256
        return uint112(fromUD60x18(delta.mul(toUD60x18(_shares))));
    }

    function _computePrizeSize(uint8 _tier, uint8 _numberOfTiers, UD60x18 _tierPrizeTokenPerShare, UD60x18 _prizeTokenPerShare) internal view returns (uint256) {
        // console2.log("_computePrizeSize _tier", _tier);
        // console2.log("_computePrizeSize _numberOfTiers", _numberOfTiers);
        assert(_tier <= _numberOfTiers);
        uint256 prizeSize;
        if (_prizeTokenPerShare.gt(_tierPrizeTokenPerShare)) {
            UD60x18 delta = _prizeTokenPerShare.sub(_tierPrizeTokenPerShare);
            if (delta.unwrap() > 0) {
                if (_tier == _numberOfTiers) {
                    prizeSize = fromUD60x18(delta.mul(toUD60x18(canaryShares)).div(_canaryPrizeCountFractional(_numberOfTiers)));
                } else {
                    prizeSize = fromUD60x18(delta.mul(toUD60x18(tierShares)).div(toUD60x18(TierCalculationLib.prizeCount(_tier))));
                }
            }
        }
        return prizeSize;
    }

    /// @notice Reclaims liquidity from tiers, starting at the highest tier
    /// @param _numberOfTiers The existing number of tiers
    /// @param _nextNumberOfTiers The next number of tiers. Must be less than _numberOfTiers
    /// @return The total reclaimed liquidity
    function _reclaimLiquidity(uint8 _numberOfTiers, uint8 _nextNumberOfTiers, UD60x18 _prizeTokenPerShare) internal view returns (uint256) {
        UD60x18 reclaimedLiquidity;
        for (uint8 i = _nextNumberOfTiers; i < _numberOfTiers; i++) {
            Tier memory tierLiquidity = _tiers[i];
            reclaimedLiquidity = reclaimedLiquidity.add(_getRemainingTierLiquidity(i, tierShares, fromUD34x4toUD60x18(_tiers[i].prizeTokenPerShare), _prizeTokenPerShare));
        }
        reclaimedLiquidity = reclaimedLiquidity.add(_getRemainingTierLiquidity(_numberOfTiers, canaryShares, fromUD34x4toUD60x18(_tiers[_numberOfTiers].prizeTokenPerShare), _prizeTokenPerShare));
        return fromUD60x18(reclaimedLiquidity);
    }

    /// @notice Computes the remaining tier liquidity for the current draw
    /// @param _tier The tier to calculate liquidity for
    /// @param _shares The number of shares that the tier has (can be tierShares or canaryShares)
    /// @return The total available liquidity
    function _getRemainingTierLiquidity(uint8 _tier, uint256 _shares, UD60x18 _tierPrizeTokenPerShare, UD60x18 _prizeTokenPerShare) internal pure returns (UD60x18) {
        if (_tierPrizeTokenPerShare.gte(_prizeTokenPerShare)) {
            return ud(0);
        }
        UD60x18 delta = _prizeTokenPerShare.sub(_tierPrizeTokenPerShare);
        return delta.mul(toUD60x18(_shares));
    }

    /// @notice Computes the contributed liquidity vs number of shares for the last completed draw
    /// @return newPrizeTokensPerShare The number of prize tokens to distribute per share
    /// @return remainder The remainder of the exchange rate
    function _computeDrawDeltaExchangeRate(UD60x18 _totalShares, UD60x18 _totalContributed) internal view returns (UD60x18 newPrizeTokensPerShare, UD60x18 remainder) {
        newPrizeTokensPerShare = _totalContributed.div(_totalShares);
        remainder = _totalContributed.sub(_totalShares.mul(newPrizeTokensPerShare));
    }

    /// @notice Retrieves the id of the next draw to be completed.
    /// @return The next draw id
    function getNextDrawId() external view returns (uint256) {
        return uint256(lastCompletedDrawId) + 1;
    }

    /// @notice Estimates the number of prizes that will be awarded
    /// @return The estimated prize count
    function estimatedPrizeCount() external view returns (uint32) {
        return _estimatedPrizeCount(numberOfTiers);         
    }
    
    /// @notice Estimates the number of prizes that will be awarded given a number of tiers.
    /// @param numTiers The number of tiers
    /// @return The estimated prize count for the given number of tiers
    function estimatedPrizeCount(uint8 numTiers) external view returns (uint32) {
        return _estimatedPrizeCount(numTiers);
    }

    /// @notice Returns the number of canary prizes as a fraction. This allows the canary prize size to accurately represent the number of tiers + 1.
    /// @param numTiers The number of prize tiers
    /// @return The number of canary prizes
    function canaryPrizeCountFractional(uint8 numTiers) external view returns (UD60x18) {
        return _canaryPrizeCountFractional(numTiers);
    }

    /// @notice Computes the number of canary prizes for the last completed draw
    function canaryPrizeCount() external view returns (uint32) {
        return _canaryPrizeCount(numberOfTiers);
    }

    /// @notice Computes the number of canary prizes for the last completed draw
    function _canaryPrizeCount(uint8 _numberOfTiers) internal view returns (uint32) {
        return uint32(fromUD60x18(_canaryPrizeCountFractional(_numberOfTiers).floor()));
    }

    /// @notice Computes the number of canary prizes given the number of tiers.
    /// @param _numTiers The number of prize tiers
    /// @return The number of canary prizes
    function canaryPrizeCount(uint8 _numTiers) external view returns (uint32) {
        return _canaryPrizeCount(_numTiers);
    }

    /// @notice Returns the balance of the reserve
    /// @return The amount of tokens that have been reserved.
    function reserve() external view returns (uint256) {
        return _reserve;
    }

    /// @notice Estimates the prize count for the given tier
    /// @param numTiers The number of prize tiers
    /// @return The estimated total number of prizes
    function _estimatedPrizeCount(uint8 numTiers) internal view returns (uint32) {
        if (numTiers == 2) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS;
        } else if (numTiers == 3) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
        } else if (numTiers == 4) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
        } else if (numTiers == 5) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
        } else if (numTiers == 6) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
        } else if (numTiers == 7) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
        } else if (numTiers == 8) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
        } else if (numTiers == 9) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
        } else if (numTiers == 10) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
        } else if (numTiers == 11) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;
        } else if (numTiers == 12) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS;
        } else if (numTiers == 13) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS;
        } else if (numTiers == 14) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS;
        } else if (numTiers == 15) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS;
        } else if (numTiers == 16) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS;
        }
        return 0;
    }

    /// @notice Computes the canary prize count for the given number of tiers
    /// @param numTiers The number of prize tiers
    /// @return The fractional canary prize count
    function _canaryPrizeCountFractional(uint8 numTiers) internal view returns (UD60x18) {
        if (numTiers == 2) {
            return CANARY_PRIZE_COUNT_FOR_2_TIERS;
        } else if (numTiers == 3) {
            return CANARY_PRIZE_COUNT_FOR_3_TIERS;
        } else if (numTiers == 4) {
            return CANARY_PRIZE_COUNT_FOR_4_TIERS;
        } else if (numTiers == 5) {
            return CANARY_PRIZE_COUNT_FOR_5_TIERS;
        } else if (numTiers == 6) {
            return CANARY_PRIZE_COUNT_FOR_6_TIERS;
        } else if (numTiers == 7) {
            return CANARY_PRIZE_COUNT_FOR_7_TIERS;
        } else if (numTiers == 8) {
            return CANARY_PRIZE_COUNT_FOR_8_TIERS;
        } else if (numTiers == 9) {
            return CANARY_PRIZE_COUNT_FOR_9_TIERS;
        } else if (numTiers == 10) {
            return CANARY_PRIZE_COUNT_FOR_10_TIERS;
        } else if (numTiers == 11) {
            return CANARY_PRIZE_COUNT_FOR_11_TIERS;
        } else if (numTiers == 12) {
            return CANARY_PRIZE_COUNT_FOR_12_TIERS;
        } else if (numTiers == 13) {
            return CANARY_PRIZE_COUNT_FOR_13_TIERS;
        } else if (numTiers == 14) {
            return CANARY_PRIZE_COUNT_FOR_14_TIERS;
        } else if (numTiers == 15) {
            return CANARY_PRIZE_COUNT_FOR_15_TIERS;
        }
        return ud(0);
    }

}