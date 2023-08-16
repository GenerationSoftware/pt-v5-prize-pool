// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { E, SD59x18, sd } from "prb-math/SD59x18.sol";
import { UD60x18, ud, convert, intoSD59x18 } from "prb-math/UD60x18.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";

import { UD34x4, fromUD60x18 as fromUD60x18toUD34x4, intoUD60x18 as fromUD34x4toUD60x18, toUD34x4 } from "../libraries/UD34x4.sol";
import { TierCalculationLib } from "../libraries/TierCalculationLib.sol";

/// @notice Struct that tracks tier liquidity information.
struct Tier {
  uint24 drawId;
  uint104 prizeSize;
  UD34x4 prizeTokenPerShare;
}

/// @notice Emitted when the number of tiers is less than the minimum number of tiers.
/// @param numTiers The invalid number of tiers
error NumberOfTiersLessThanMinimum(uint8 numTiers);

/// @notice Emitted when the number of tiers is greater than the max tiers
/// @param numTiers The invalid number of tiers
error NumberOfTiersGreaterThanMaximum(uint8 numTiers);

/// @notice Emitted when there is insufficient liquidity to consume.
/// @param requestedLiquidity The requested amount of liquidity
error InsufficientLiquidity(uint104 requestedLiquidity);

uint8 constant MINIMUM_NUMBER_OF_TIERS = 3;
uint8 constant MAXIMUM_NUMBER_OF_TIERS = 10;

/// @title Tiered Liquidity Distributor
/// @author PoolTogether Inc.
/// @notice A contract that distributes liquidity according to PoolTogether V5 distribution rules.
contract TieredLiquidityDistributor {

  /* ============ Events ============ */

  /// @notice Emitted when the reserve is consumed due to insufficient prize liquidity.
  /// @param amount The amount to decrease by
  event ReserveConsumed(uint256 amount);

  /* ============ Constants ============ */

  /// @notice The odds for each tier and number of tiers pair.
  SD59x18 internal immutable TIER_ODDS_0_3;
  SD59x18 internal immutable TIER_ODDS_1_3;
  SD59x18 internal immutable TIER_ODDS_2_3;
  SD59x18 internal immutable TIER_ODDS_0_4;
  SD59x18 internal immutable TIER_ODDS_1_4;
  SD59x18 internal immutable TIER_ODDS_2_4;
  SD59x18 internal immutable TIER_ODDS_3_4;
  SD59x18 internal immutable TIER_ODDS_0_5;
  SD59x18 internal immutable TIER_ODDS_1_5;
  SD59x18 internal immutable TIER_ODDS_2_5;
  SD59x18 internal immutable TIER_ODDS_3_5;
  SD59x18 internal immutable TIER_ODDS_4_5;
  SD59x18 internal immutable TIER_ODDS_0_6;
  SD59x18 internal immutable TIER_ODDS_1_6;
  SD59x18 internal immutable TIER_ODDS_2_6;
  SD59x18 internal immutable TIER_ODDS_3_6;
  SD59x18 internal immutable TIER_ODDS_4_6;
  SD59x18 internal immutable TIER_ODDS_5_6;
  SD59x18 internal immutable TIER_ODDS_0_7;
  SD59x18 internal immutable TIER_ODDS_1_7;
  SD59x18 internal immutable TIER_ODDS_2_7;
  SD59x18 internal immutable TIER_ODDS_3_7;
  SD59x18 internal immutable TIER_ODDS_4_7;
  SD59x18 internal immutable TIER_ODDS_5_7;
  SD59x18 internal immutable TIER_ODDS_6_7;
  SD59x18 internal immutable TIER_ODDS_0_8;
  SD59x18 internal immutable TIER_ODDS_1_8;
  SD59x18 internal immutable TIER_ODDS_2_8;
  SD59x18 internal immutable TIER_ODDS_3_8;
  SD59x18 internal immutable TIER_ODDS_4_8;
  SD59x18 internal immutable TIER_ODDS_5_8;
  SD59x18 internal immutable TIER_ODDS_6_8;
  SD59x18 internal immutable TIER_ODDS_7_8;
  SD59x18 internal immutable TIER_ODDS_0_9;
  SD59x18 internal immutable TIER_ODDS_1_9;
  SD59x18 internal immutable TIER_ODDS_2_9;
  SD59x18 internal immutable TIER_ODDS_3_9;
  SD59x18 internal immutable TIER_ODDS_4_9;
  SD59x18 internal immutable TIER_ODDS_5_9;
  SD59x18 internal immutable TIER_ODDS_6_9;
  SD59x18 internal immutable TIER_ODDS_7_9;
  SD59x18 internal immutable TIER_ODDS_8_9;
  SD59x18 internal immutable TIER_ODDS_0_10;
  SD59x18 internal immutable TIER_ODDS_1_10;
  SD59x18 internal immutable TIER_ODDS_2_10;
  SD59x18 internal immutable TIER_ODDS_3_10;
  SD59x18 internal immutable TIER_ODDS_4_10;
  SD59x18 internal immutable TIER_ODDS_5_10;
  SD59x18 internal immutable TIER_ODDS_6_10;
  SD59x18 internal immutable TIER_ODDS_7_10;
  SD59x18 internal immutable TIER_ODDS_8_10;
  SD59x18 internal immutable TIER_ODDS_9_10;

  /// @notice The estimated number of prizes given X tiers.
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;

  /// @notice The Tier liquidity data.
  mapping(uint8 => Tier) internal _tiers;

  /// @notice The frequency of the grand prize
  uint24 public immutable grandPrizePeriodDraws;

  /// @notice The number of shares to allocate to each prize tier.
  uint8 public immutable tierShares;

  /// @notice The number of shares to allocate to the reserve.
  uint8 public immutable reserveShares;

  /// @notice The current number of prize tokens per share.
  UD34x4 public prizeTokenPerShare;

  /// @notice The number of tiers for the last closed draw. The last tier is the canary tier.
  uint8 public numberOfTiers;

  /// @notice The draw id of the last closed draw.
  uint24 internal lastClosedDrawId;

  /// @notice The amount of available reserve.
  uint96 internal _reserve;

  /**
   * @notice Constructs a new Prize Pool.
   * @param _numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
   * @param _tierShares The number of shares to allocate to each tier
   * @param _reserveShares The number of shares to allocate to the reserve.
   */
  constructor(uint8 _numberOfTiers, uint8 _tierShares, uint8 _reserveShares, uint24 _grandPrizePeriodDraws) {
    numberOfTiers = _numberOfTiers;
    tierShares = _tierShares;
    reserveShares = _reserveShares;
    grandPrizePeriodDraws = _grandPrizePeriodDraws;

    if (_numberOfTiers < MINIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersLessThanMinimum(_numberOfTiers);
    }
    if (_numberOfTiers > MAXIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersGreaterThanMaximum(_numberOfTiers);
    }

    // Off by one because the canary tier isn't expected to produce prizes.
    ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS = TierCalculationLib.estimatedClaimCount(2, _grandPrizePeriodDraws);
    ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS = TierCalculationLib.estimatedClaimCount(3, _grandPrizePeriodDraws);
    ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS = TierCalculationLib.estimatedClaimCount(4, _grandPrizePeriodDraws);
    ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS = TierCalculationLib.estimatedClaimCount(5, _grandPrizePeriodDraws);
    ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS = TierCalculationLib.estimatedClaimCount(6, _grandPrizePeriodDraws);
    ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS = TierCalculationLib.estimatedClaimCount(7, _grandPrizePeriodDraws);
    ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS = TierCalculationLib.estimatedClaimCount(8, _grandPrizePeriodDraws);
    ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS = TierCalculationLib.estimatedClaimCount(9, _grandPrizePeriodDraws);

    TIER_ODDS_0_3 = TierCalculationLib.getTierOdds(0, 2, _grandPrizePeriodDraws);
    TIER_ODDS_1_3 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_2_3 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_0_4 = TierCalculationLib.getTierOdds(0, 3, _grandPrizePeriodDraws);
    TIER_ODDS_1_4 = TierCalculationLib.getTierOdds(1, 3, _grandPrizePeriodDraws);
    TIER_ODDS_2_4 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_3_4 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_0_5 = TierCalculationLib.getTierOdds(0, 4, _grandPrizePeriodDraws);
    TIER_ODDS_1_5 = TierCalculationLib.getTierOdds(1, 4, _grandPrizePeriodDraws);
    TIER_ODDS_2_5 = TierCalculationLib.getTierOdds(2, 4, _grandPrizePeriodDraws);
    TIER_ODDS_3_5 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_4_5 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_0_6 = TierCalculationLib.getTierOdds(0, 5, _grandPrizePeriodDraws);
    TIER_ODDS_1_6 = TierCalculationLib.getTierOdds(1, 5, _grandPrizePeriodDraws);
    TIER_ODDS_2_6 = TierCalculationLib.getTierOdds(2, 5, _grandPrizePeriodDraws);
    TIER_ODDS_3_6 = TierCalculationLib.getTierOdds(3, 5, _grandPrizePeriodDraws);
    TIER_ODDS_4_6 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_5_6 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_0_7 = TierCalculationLib.getTierOdds(0, 6, _grandPrizePeriodDraws);
    TIER_ODDS_1_7 = TierCalculationLib.getTierOdds(1, 6, _grandPrizePeriodDraws);
    TIER_ODDS_2_7 = TierCalculationLib.getTierOdds(2, 6, _grandPrizePeriodDraws);
    TIER_ODDS_3_7 = TierCalculationLib.getTierOdds(3, 6, _grandPrizePeriodDraws);
    TIER_ODDS_4_7 = TierCalculationLib.getTierOdds(4, 6, _grandPrizePeriodDraws);
    TIER_ODDS_5_7 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_6_7 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_0_8 = TierCalculationLib.getTierOdds(0, 7, _grandPrizePeriodDraws);
    TIER_ODDS_1_8 = TierCalculationLib.getTierOdds(1, 7, _grandPrizePeriodDraws);
    TIER_ODDS_2_8 = TierCalculationLib.getTierOdds(2, 7, _grandPrizePeriodDraws);
    TIER_ODDS_3_8 = TierCalculationLib.getTierOdds(3, 7, _grandPrizePeriodDraws);
    TIER_ODDS_4_8 = TierCalculationLib.getTierOdds(4, 7, _grandPrizePeriodDraws);
    TIER_ODDS_5_8 = TierCalculationLib.getTierOdds(5, 7, _grandPrizePeriodDraws);
    TIER_ODDS_6_8 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_7_8 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_0_9 = TierCalculationLib.getTierOdds(0, 8, _grandPrizePeriodDraws);
    TIER_ODDS_1_9 = TierCalculationLib.getTierOdds(1, 8, _grandPrizePeriodDraws);
    TIER_ODDS_2_9 = TierCalculationLib.getTierOdds(2, 8, _grandPrizePeriodDraws);
    TIER_ODDS_3_9 = TierCalculationLib.getTierOdds(3, 8, _grandPrizePeriodDraws);
    TIER_ODDS_4_9 = TierCalculationLib.getTierOdds(4, 8, _grandPrizePeriodDraws);
    TIER_ODDS_5_9 = TierCalculationLib.getTierOdds(5, 8, _grandPrizePeriodDraws);
    TIER_ODDS_6_9 = TierCalculationLib.getTierOdds(6, 8, _grandPrizePeriodDraws);
    TIER_ODDS_7_9 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_8_9 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_0_10 = TierCalculationLib.getTierOdds(0, 9, _grandPrizePeriodDraws);
    TIER_ODDS_1_10 = TierCalculationLib.getTierOdds(1, 9, _grandPrizePeriodDraws);
    TIER_ODDS_2_10 = TierCalculationLib.getTierOdds(2, 9, _grandPrizePeriodDraws);
    TIER_ODDS_3_10 = TierCalculationLib.getTierOdds(3, 9, _grandPrizePeriodDraws);
    TIER_ODDS_4_10 = TierCalculationLib.getTierOdds(4, 9, _grandPrizePeriodDraws);
    TIER_ODDS_5_10 = TierCalculationLib.getTierOdds(5, 9, _grandPrizePeriodDraws);
    TIER_ODDS_6_10 = TierCalculationLib.getTierOdds(6, 9, _grandPrizePeriodDraws);
    TIER_ODDS_7_10 = TierCalculationLib.getTierOdds(7, 9, _grandPrizePeriodDraws);
    TIER_ODDS_8_10 = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_9_10 = SD59x18.wrap(1000000000000000000);
  }

  /// @notice Adjusts the number of tiers and distributes new liquidity.
  /// @param _nextNumberOfTiers The new number of tiers. Must be greater than minimum
  /// @param _prizeTokenLiquidity The amount of fresh liquidity to distribute across the tiers and reserve
  function _nextDraw(uint8 _nextNumberOfTiers, uint256 _prizeTokenLiquidity) internal {
    if (_nextNumberOfTiers < MINIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersLessThanMinimum(_nextNumberOfTiers);
    }

    uint8 numTiers = numberOfTiers;
    UD60x18 _prizeTokenPerShare = fromUD34x4toUD60x18(prizeTokenPerShare);
    (
      uint24 closedDrawId,
      uint96 newReserve,
      UD60x18 newPrizeTokenPerShare
    ) = _computeNewDistributions(
        numTiers,
        _nextNumberOfTiers,
        _prizeTokenPerShare,
        _prizeTokenLiquidity
      );

    // need to redistribute to the canary tier and any new tiers (if expanding)
    uint8 start;
    uint8 end;
    // if we are expanding, need to reset the canary tier and all of the new tiers
    if (_nextNumberOfTiers > numTiers) {
      start = numTiers - 1;
      end = _nextNumberOfTiers;
    } else {
      // just reset the canary tier
      start = _nextNumberOfTiers - 1;
      end = _nextNumberOfTiers;
    }
    for (uint8 i = start; i < end; i++) {
      _tiers[i] = Tier({
        drawId: closedDrawId,
        prizeTokenPerShare: prizeTokenPerShare,
        prizeSize: _computePrizeSize(i, _nextNumberOfTiers, _prizeTokenPerShare, newPrizeTokenPerShare)
      });
    }

    prizeTokenPerShare = fromUD60x18toUD34x4(newPrizeTokenPerShare);
    numberOfTiers = _nextNumberOfTiers;
    lastClosedDrawId = closedDrawId;
    _reserve += newReserve;
  }

  /// @notice Computes the liquidity that will be distributed for the next draw given the next number of tiers and prize liquidity.
  /// @param _numberOfTiers The current number of tiers
  /// @param _nextNumberOfTiers The next number of tiers to use to compute distribution
  /// @param _prizeTokenLiquidity The amount of fresh liquidity to distribute across the tiers and reserve
  /// @return closedDrawId The drawId that this is for
  /// @return newReserve The amount of liquidity that should be added to the reserve
  /// @return newPrizeTokenPerShare The new prize token per share
  function _computeNewDistributions(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    uint256 _prizeTokenLiquidity
  ) internal view returns (uint24 closedDrawId, uint96 newReserve, UD60x18 newPrizeTokenPerShare) {
    return
      _computeNewDistributions(
        _numberOfTiers,
        _nextNumberOfTiers,
        fromUD34x4toUD60x18(prizeTokenPerShare),
        _prizeTokenLiquidity
      );
  }

  /// @notice Computes the liquidity that will be distributed for the next draw given the next number of tiers and prize liquidity.
  /// @param _numberOfTiers The current number of tiers
  /// @param _nextNumberOfTiers The next number of tiers to use to compute distribution
  /// @param _currentPrizeTokenPerShare The current prize token per share
  /// @param _prizeTokenLiquidity The amount of fresh liquidity to distribute across the tiers and reserve
  /// @return closedDrawId The drawId that this is for
  /// @return newReserve The amount of liquidity that will be added to the reserve
  /// @return newPrizeTokenPerShare The new prize token per share
  function _computeNewDistributions(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    UD60x18 _currentPrizeTokenPerShare,
    uint _prizeTokenLiquidity
  ) internal view returns (uint24 closedDrawId, uint96 newReserve, UD60x18 newPrizeTokenPerShare) {
    closedDrawId = lastClosedDrawId + 1;

    uint reclaimedLiquidity = _getTierLiquidityToReclaim(
      _numberOfTiers,
      _nextNumberOfTiers,
      _currentPrizeTokenPerShare
    );

    uint totalNewLiquidity = _prizeTokenLiquidity + reclaimedLiquidity;
    uint256 nextTotalShares = _getTotalShares(_nextNumberOfTiers);
    UD60x18 deltaPrizeTokensPerShare = (convert(totalNewLiquidity).div(convert(nextTotalShares))).floor();
    
    newPrizeTokenPerShare = _currentPrizeTokenPerShare.add(deltaPrizeTokensPerShare);

    newReserve = SafeCast.toUint96(
      // reserve portion of new liquidity
      convert(deltaPrizeTokensPerShare.mul(convert(reserveShares))) + 
      // remainder left over from shares
      (
        totalNewLiquidity - convert(deltaPrizeTokensPerShare.mul(convert(nextTotalShares)))
      )
    );
  }

  /// @notice Returns the prize size for the given tier.
  /// @param _tier The tier to retrieve
  /// @return The prize size for the tier
  function getTierPrizeSize(uint8 _tier) external view returns (uint104) {
    return _getTier(_tier, numberOfTiers).prizeSize;
  }

  /// @notice Returns the estimated number of prizes for the given tier.
  /// @param _tier The tier to retrieve
  /// @return The estimated number of prizes
  function getTierPrizeCount(uint8 _tier) external view returns (uint32) {
    return uint32(TierCalculationLib.prizeCount(_tier));
  }

  /// @notice Retrieves an up-to-date Tier struct for the given tier.
  /// @param _tier The tier to retrieve
  /// @param _numberOfTiers The number of tiers, should match the current. Passed explicitly as an optimization
  /// @return An up-to-date Tier struct; if the prize is outdated then it is recomputed based on available liquidity and the draw id updated.
  function _getTier(uint8 _tier, uint8 _numberOfTiers) internal view returns (Tier memory) {
    Tier memory tier = _tiers[_tier];
    uint24 _lastClosedDrawId = lastClosedDrawId;
    if (tier.drawId != _lastClosedDrawId) {
      tier.drawId = _lastClosedDrawId;
      tier.prizeSize = _computePrizeSize(
        _tier,
        _numberOfTiers,
        fromUD34x4toUD60x18(tier.prizeTokenPerShare),
        fromUD34x4toUD60x18(prizeTokenPerShare)
      );
    }
    return tier;
  }

  /// @notice Computes the total shares in the system. That is `(number of tiers * tier shares) + reserve shares`.
  /// @return The total shares
  function getTotalShares() external view returns (uint256) {
    return _getTotalShares(numberOfTiers);
  }

  /// @notice Computes the total shares in the system given the number of tiers. That is `(number of tiers * tier shares) + reserve shares`.
  /// @param _numberOfTiers The number of tiers to calculate the total shares for
  /// @return The total shares
  function _getTotalShares(uint8 _numberOfTiers) internal view returns (uint256) {
    return
      uint256(_numberOfTiers) *
      uint256(tierShares) +
      uint256(reserveShares);
  }

  /// @notice Consumes liquidity from the given tier.
  /// @param _tierStruct The tier to consume liquidity from
  /// @param _tier The tier number
  /// @param _liquidity The amount of liquidity to consume
  /// @return An updated Tier struct after consumption
  function _consumeLiquidity(
    Tier memory _tierStruct,
    uint8 _tier,
    uint104 _liquidity
  ) internal returns (Tier memory) {
    uint8 _shares = tierShares;
    uint104 remainingLiquidity = SafeCast.toUint104(
      convert(
        _getTierRemainingLiquidity(
          _shares,
          fromUD34x4toUD60x18(_tierStruct.prizeTokenPerShare),
          fromUD34x4toUD60x18(prizeTokenPerShare)
        )
      )
    );
    if (_liquidity > remainingLiquidity) {
      uint96 excess = SafeCast.toUint96(_liquidity - remainingLiquidity);
      if (excess > _reserve) {
        revert InsufficientLiquidity(_liquidity);
      }
      _reserve -= excess;
      emit ReserveConsumed(excess);
      _tierStruct.prizeTokenPerShare = prizeTokenPerShare;
    } else {
      UD34x4 delta = fromUD60x18toUD34x4(convert(_liquidity).div(convert(_shares)));
      _tierStruct.prizeTokenPerShare = UD34x4.wrap(
        UD34x4.unwrap(_tierStruct.prizeTokenPerShare) + UD34x4.unwrap(delta)
      );
    }
    _tiers[_tier] = _tierStruct;
    return _tierStruct;
  }

  /// @notice Computes the prize size of the given tier.
  /// @param _tier The tier to compute the prize size of
  /// @param _numberOfTiers The current number of tiers
  /// @param _tierPrizeTokenPerShare The prizeTokenPerShare of the Tier struct
  /// @param _prizeTokenPerShare The global prizeTokenPerShare
  /// @return The prize size
  function _computePrizeSize(
    uint8 _tier,
    uint8 _numberOfTiers,
    UD60x18 _tierPrizeTokenPerShare,
    UD60x18 _prizeTokenPerShare
  ) internal view returns (uint104) {
    uint256 prizeSize;
    if (_prizeTokenPerShare.gt(_tierPrizeTokenPerShare)) {
      prizeSize = _computePrizeSize(
        _tierPrizeTokenPerShare,
        _prizeTokenPerShare,
        convert(TierCalculationLib.prizeCount(_tier)),
        tierShares
      );
      bool canExpand = _numberOfTiers < MAXIMUM_NUMBER_OF_TIERS;
      if (canExpand && _isCanaryTier(_tier, _numberOfTiers)) {
        // make canary prizes smaller to account for reduction in shares for next number of tiers
        prizeSize = (prizeSize * _getTotalShares(_numberOfTiers)) / _getTotalShares(_numberOfTiers + 1);
      }
    }
    if (prizeSize > type(uint104).max) {
      return type(uint104).max;
    } else {
      return uint104(prizeSize);
    }
  }

  /// @notice Computes the prize size with the given parameters.
  /// @param _tierPrizeTokenPerShare The prizeTokenPerShare of the Tier struct
  /// @param _prizeTokenPerShare The global prizeTokenPerShare
  /// @param _fractionalPrizeCount The prize count as UD60x18
  /// @param _shares The number of shares that the tier has
  /// @return The prize size
  function _computePrizeSize(
    UD60x18 _tierPrizeTokenPerShare,
    UD60x18 _prizeTokenPerShare,
    UD60x18 _fractionalPrizeCount,
    uint8 _shares
  ) internal pure returns (uint256) {
    return
      convert(
        _prizeTokenPerShare.sub(_tierPrizeTokenPerShare).mul(convert(_shares)).div(
          _fractionalPrizeCount
        )
      );
  }

  function _isCanaryTier(uint8 _tier, uint8 _numberOfTiers) internal pure returns (bool) {
    return _tier == _numberOfTiers - 1;
  }

  /// @notice Reclaims liquidity from tiers, starting at the highest tier.
  /// @param _numberOfTiers The existing number of tiers
  /// @param _nextNumberOfTiers The next number of tiers. Must be less than _numberOfTiers
  /// @return The total reclaimed liquidity
  function _getTierLiquidityToReclaim(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    UD60x18 _prizeTokenPerShare
  ) internal view returns (uint256) {
    UD60x18 reclaimedLiquidity;
    // need to redistribute to the canary tier and any new tiers (if expanding)
    uint8 start;
    uint8 end;
    // if we are shrinking, we need to reclaim including the new canary tier
    if (_nextNumberOfTiers < _numberOfTiers) {
      start = _nextNumberOfTiers - 1;
      end = _numberOfTiers;
    } else {
      // just reset the canary tier
      start = _numberOfTiers - 1;
      end = _numberOfTiers;
    }
    for (uint8 i = start; i < end; i++) {
      Tier memory tierLiquidity = _tiers[i];
      uint8 shares = tierShares;
      UD60x18 liq = _getTierRemainingLiquidity(
        shares,
        fromUD34x4toUD60x18(tierLiquidity.prizeTokenPerShare),
        _prizeTokenPerShare
      );
      reclaimedLiquidity = reclaimedLiquidity.add(liq);
    }
    return convert(reclaimedLiquidity);
  }

  /// @notice Computes the remaining liquidity available to a tier.
  /// @param _tier The tier to compute the liquidity for
  /// @return The remaining liquidity
  function getTierRemainingLiquidity(uint8 _tier) external view returns (uint256) {
    uint8 _numTiers = numberOfTiers;
    return
      convert(
        _getTierRemainingLiquidity(
          tierShares,
          fromUD34x4toUD60x18(_getTier(_tier, _numTiers).prizeTokenPerShare),
          fromUD34x4toUD60x18(prizeTokenPerShare)
        )
      );
  }

  /// @notice Computes the remaining tier liquidity.
  /// @param _shares The number of shares that the tier has (can be tierShares or canaryShares)
  /// @param _tierPrizeTokenPerShare The prizeTokenPerShare of the Tier struct
  /// @param _prizeTokenPerShare The global prizeTokenPerShare
  /// @return The remaining available liquidity
  function _getTierRemainingLiquidity(
    uint256 _shares,
    UD60x18 _tierPrizeTokenPerShare,
    UD60x18 _prizeTokenPerShare
  ) internal pure returns (UD60x18) {
    if (_tierPrizeTokenPerShare.gte(_prizeTokenPerShare)) {
      return ud(0);
    }
    UD60x18 delta = _prizeTokenPerShare.sub(_tierPrizeTokenPerShare);
    return delta.mul(convert(_shares));
  }

  /// @notice Retrieves the id of the next draw to be closed.
  /// @return The next draw id
  function getOpenDrawId() external view returns (uint24) {
    return lastClosedDrawId + 1;
  }

  /// @notice Estimates the number of prizes that will be awarded.
  /// @return The estimated prize count
  function estimatedPrizeCount() external view returns (uint32) {
    return _estimatePrizeCountPerDrawUsingNumberOfTiers(numberOfTiers);
  }

  /// @notice Estimates the number of prizes that will be awarded given a number of tiers.
  /// @param numTiers The number of tiers
  /// @return The estimated prize count for the given number of tiers
  function estimatedPrizeCount(uint8 numTiers) external view returns (uint32) {
    return _estimatePrizeCountPerDrawUsingNumberOfTiers(numTiers);
  }

  /// @notice Returns the balance of the reserve.
  /// @return The amount of tokens that have been reserved.
  function reserve() external view returns (uint96) {
    return _reserve;
  }

  /// @notice Estimates the prize count for the given tier.
  /// @param numTiers The number of prize tiers
  /// @return The estimated total number of prizes
  function _estimatePrizeCountPerDrawUsingNumberOfTiers(uint8 numTiers) internal view returns (uint32) {
    if (numTiers == 3) {
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
    }
    return 0;
  }

  /// @notice Estimates the number of tiers for the given prize count.
  /// @param _prizeCount The number of prizes that were claimed
  /// @return The estimated tier
  function _estimateNumberOfTiersUsingPrizeCountPerDraw(uint32 _prizeCount) internal view returns (uint8) {
    if (_prizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS) {
      return 3;
    } else if (_prizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS) {
      return 4;
    } else if (_prizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS) {
      return 5;
    } else if (_prizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS) {
      return 6;
    } else if (_prizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS) {
      return 7;
    } else if (_prizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS) {
      return 8;
    } else if (_prizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS) {
      return 9;
    }
    return 10;
  }

  /// @notice Computes the odds for a tier given the number of tiers.
  /// @param _tier The tier to compute odds for
  /// @param _numTiers The number of prize tiers
  /// @return The odds of the tier
  function getTierOdds(uint8 _tier, uint8 _numTiers) external view returns (SD59x18) {
    return _tierOdds(_tier, _numTiers);
  }

  /// @notice Computes the odds for a tier given the number of tiers.
  /// @param _tier The tier to compute odds for
  /// @param _numTiers The number of prize tiers
  /// @return The odds of the tier
  function _tierOdds(uint8 _tier, uint8 _numTiers) internal view returns (SD59x18) {
    if (_numTiers == 3) {
      if (_tier == 0) return TIER_ODDS_0_3;
      else if (_tier == 1) return TIER_ODDS_1_3;
      else if (_tier == 2) return TIER_ODDS_2_3;
    } else if (_numTiers == 4) {
      if (_tier == 0) return TIER_ODDS_0_4;
      else if (_tier == 1) return TIER_ODDS_1_4;
      else if (_tier == 2) return TIER_ODDS_2_4;
      else if (_tier == 3) return TIER_ODDS_3_4;
    } else if (_numTiers == 5) {
      if (_tier == 0) return TIER_ODDS_0_5;
      else if (_tier == 1) return TIER_ODDS_1_5;
      else if (_tier == 2) return TIER_ODDS_2_5;
      else if (_tier == 3) return TIER_ODDS_3_5;
      else if (_tier == 4) return TIER_ODDS_4_5;
    } else if (_numTiers == 6) {
      if (_tier == 0) return TIER_ODDS_0_6;
      else if (_tier == 1) return TIER_ODDS_1_6;
      else if (_tier == 2) return TIER_ODDS_2_6;
      else if (_tier == 3) return TIER_ODDS_3_6;
      else if (_tier == 4) return TIER_ODDS_4_6;
      else if (_tier == 5) return TIER_ODDS_5_6;
    } else if (_numTiers == 7) {
      if (_tier == 0) return TIER_ODDS_0_7;
      else if (_tier == 1) return TIER_ODDS_1_7;
      else if (_tier == 2) return TIER_ODDS_2_7;
      else if (_tier == 3) return TIER_ODDS_3_7;
      else if (_tier == 4) return TIER_ODDS_4_7;
      else if (_tier == 5) return TIER_ODDS_5_7;
      else if (_tier == 6) return TIER_ODDS_6_7;
    } else if (_numTiers == 8) {
      if (_tier == 0) return TIER_ODDS_0_8;
      else if (_tier == 1) return TIER_ODDS_1_8;
      else if (_tier == 2) return TIER_ODDS_2_8;
      else if (_tier == 3) return TIER_ODDS_3_8;
      else if (_tier == 4) return TIER_ODDS_4_8;
      else if (_tier == 5) return TIER_ODDS_5_8;
      else if (_tier == 6) return TIER_ODDS_6_8;
      else if (_tier == 7) return TIER_ODDS_7_8;
    } else if (_numTiers == 9) {
      if (_tier == 0) return TIER_ODDS_0_9;
      else if (_tier == 1) return TIER_ODDS_1_9;
      else if (_tier == 2) return TIER_ODDS_2_9;
      else if (_tier == 3) return TIER_ODDS_3_9;
      else if (_tier == 4) return TIER_ODDS_4_9;
      else if (_tier == 5) return TIER_ODDS_5_9;
      else if (_tier == 6) return TIER_ODDS_6_9;
      else if (_tier == 7) return TIER_ODDS_7_9;
      else if (_tier == 8) return TIER_ODDS_8_9;
    } else if (_numTiers == 10) {
      if (_tier == 0) return TIER_ODDS_0_10;
      else if (_tier == 1) return TIER_ODDS_1_10;
      else if (_tier == 2) return TIER_ODDS_2_10;
      else if (_tier == 3) return TIER_ODDS_3_10;
      else if (_tier == 4) return TIER_ODDS_4_10;
      else if (_tier == 5) return TIER_ODDS_5_10;
      else if (_tier == 6) return TIER_ODDS_6_10;
      else if (_tier == 7) return TIER_ODDS_7_10;
      else if (_tier == 8) return TIER_ODDS_8_10;
      else if (_tier == 9) return TIER_ODDS_9_10;
    }
    return sd(0);
  }
}
