// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { SD59x18, sd } from "prb-math/SD59x18.sol";
import { UD60x18, convert } from "prb-math/UD60x18.sol";

import { TierCalculationLib } from "../libraries/TierCalculationLib.sol";

/// @notice Struct that tracks tier liquidity information.
/// @param drawId The draw ID that the tier was last updated for
/// @param prizeSize The size of the prize for the tier at the drawId
/// @param prizeTokenPerShare The total prize tokens per share that have already been consumed for this tier.
struct Tier {
  uint24 drawId;
  uint104 prizeSize;
  uint128 prizeTokenPerShare;
}

/// @notice Thrown when the number of tiers is less than the minimum number of tiers.
/// @param numTiers The invalid number of tiers
error NumberOfTiersLessThanMinimum(uint8 numTiers);

/// @notice Thrown when the number of tiers is greater than the max tiers
/// @param numTiers The invalid number of tiers
error NumberOfTiersGreaterThanMaximum(uint8 numTiers);

/// @notice Thrown when the tier liquidity utilization rate is greater than 1.
error TierLiquidityUtilizationRateGreaterThanOne();

/// @notice Thrown when the tier liquidity utilization rate is 0.
error TierLiquidityUtilizationRateCannotBeZero();

/// @notice Thrown when there is insufficient liquidity to consume.
/// @param requestedLiquidity The requested amount of liquidity
error InsufficientLiquidity(uint104 requestedLiquidity);

uint8 constant MINIMUM_NUMBER_OF_TIERS = 4;
uint8 constant MAXIMUM_NUMBER_OF_TIERS = 11;
uint8 constant NUMBER_OF_CANARY_TIERS = 2;

/// @title Tiered Liquidity Distributor
/// @author PoolTogether Inc.
/// @notice A contract that distributes liquidity according to PoolTogether V5 distribution rules.
contract TieredLiquidityDistributor {
  /* ============ Events ============ */

  /// @notice Emitted when the reserve is consumed due to insufficient prize liquidity.
  /// @param amount The amount to decrease by
  event ReserveConsumed(uint256 amount);

  /* ============ Constants ============ */

  /// @notice The odds for each tier and number of tiers pair. For n tiers, the last three tiers are always daily.
  SD59x18 internal immutable TIER_ODDS_0;
  SD59x18 internal immutable TIER_ODDS_EVERY_DRAW;
  SD59x18 internal immutable TIER_ODDS_1_5;
  SD59x18 internal immutable TIER_ODDS_1_6;
  SD59x18 internal immutable TIER_ODDS_2_6;
  SD59x18 internal immutable TIER_ODDS_1_7;
  SD59x18 internal immutable TIER_ODDS_2_7;
  SD59x18 internal immutable TIER_ODDS_3_7;
  SD59x18 internal immutable TIER_ODDS_1_8;
  SD59x18 internal immutable TIER_ODDS_2_8;
  SD59x18 internal immutable TIER_ODDS_3_8;
  SD59x18 internal immutable TIER_ODDS_4_8;
  SD59x18 internal immutable TIER_ODDS_1_9;
  SD59x18 internal immutable TIER_ODDS_2_9;
  SD59x18 internal immutable TIER_ODDS_3_9;
  SD59x18 internal immutable TIER_ODDS_4_9;
  SD59x18 internal immutable TIER_ODDS_5_9;
  SD59x18 internal immutable TIER_ODDS_1_10;
  SD59x18 internal immutable TIER_ODDS_2_10;
  SD59x18 internal immutable TIER_ODDS_3_10;
  SD59x18 internal immutable TIER_ODDS_4_10;
  SD59x18 internal immutable TIER_ODDS_5_10;
  SD59x18 internal immutable TIER_ODDS_6_10;
  SD59x18 internal immutable TIER_ODDS_1_11;
  SD59x18 internal immutable TIER_ODDS_2_11;
  SD59x18 internal immutable TIER_ODDS_3_11;
  SD59x18 internal immutable TIER_ODDS_4_11;
  SD59x18 internal immutable TIER_ODDS_5_11;
  SD59x18 internal immutable TIER_ODDS_6_11;
  SD59x18 internal immutable TIER_ODDS_7_11;

  /// @notice The estimated number of prizes given X tiers.
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
  uint32 internal immutable ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;

  /// @notice The Tier liquidity data.
  mapping(uint8 tierId => Tier tierData) internal _tiers;

  /// @notice The frequency of the grand prize
  uint24 public immutable grandPrizePeriodDraws;

  /// @notice The number of shares to allocate to each prize tier.
  uint8 public immutable tierShares;

  /// @notice The number of shares to allocate to each canary tier.
  uint8 public immutable canaryShares;

  /// @notice The number of shares to allocate to the reserve.
  uint8 public immutable reserveShares;

  /// @notice The percentage of tier liquidity to target for utilization.  
  UD60x18 public immutable tierLiquidityUtilizationRate;

  /// @notice The number of prize tokens that have accrued per share for all time.
  /// @dev This is an ever-increasing exchange rate that is used to calculate the prize liquidity for each tier.
  /// @dev Each tier holds a separate tierPrizeTokenPerShare; the delta between the tierPrizeTokenPerShare and
  /// the prizeTokenPerShare * tierShares is the available liquidity they have.
  uint128 public prizeTokenPerShare;

  /// @notice The number of tiers for the last awarded draw. The last tier is the canary tier.
  uint8 public numberOfTiers;

  /// @notice The draw id of the last awarded draw.
  uint24 internal _lastAwardedDrawId;

  /// @notice The timestamp at which the last awarded draw was awarded.
  uint48 public lastAwardedDrawAwardedAt;

  /// @notice The amount of available reserve.
  uint96 internal _reserve;

  /// @notice Constructs a new Prize Pool.
  /// @param _tierLiquidityUtilizationRate The target percentage of tier liquidity to utilize each draw
  /// @param _numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
  /// @param _tierShares The number of shares to allocate to each tier
  /// @param _canaryShares The number of shares to allocate to each canary tier
  /// @param _reserveShares The number of shares to allocate to the reserve.
  /// @param _grandPrizePeriodDraws The number of draws between grand prizes
  constructor(
    uint256 _tierLiquidityUtilizationRate,
    uint8 _numberOfTiers,
    uint8 _tierShares,
    uint8 _canaryShares,
    uint8 _reserveShares,
    uint24 _grandPrizePeriodDraws
  ) {
    if (_numberOfTiers < MINIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersLessThanMinimum(_numberOfTiers);
    }
    if (_numberOfTiers > MAXIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersGreaterThanMaximum(_numberOfTiers);
    }
    if (_tierLiquidityUtilizationRate > 1e18) {
      revert TierLiquidityUtilizationRateGreaterThanOne();
    }
    if (_tierLiquidityUtilizationRate == 0) {
      revert TierLiquidityUtilizationRateCannotBeZero();
    }

    tierLiquidityUtilizationRate = UD60x18.wrap(_tierLiquidityUtilizationRate);

    numberOfTiers = _numberOfTiers;
    tierShares = _tierShares;
    canaryShares = _canaryShares;
    reserveShares = _reserveShares;
    grandPrizePeriodDraws = _grandPrizePeriodDraws;

    TIER_ODDS_0 = sd(1).div(sd(int24(_grandPrizePeriodDraws)));
    TIER_ODDS_EVERY_DRAW = SD59x18.wrap(1000000000000000000);
    TIER_ODDS_1_5 = TierCalculationLib.getTierOdds(1, 3, _grandPrizePeriodDraws);
    TIER_ODDS_1_6 = TierCalculationLib.getTierOdds(1, 4, _grandPrizePeriodDraws);
    TIER_ODDS_2_6 = TierCalculationLib.getTierOdds(2, 4, _grandPrizePeriodDraws);
    TIER_ODDS_1_7 = TierCalculationLib.getTierOdds(1, 5, _grandPrizePeriodDraws);
    TIER_ODDS_2_7 = TierCalculationLib.getTierOdds(2, 5, _grandPrizePeriodDraws);
    TIER_ODDS_3_7 = TierCalculationLib.getTierOdds(3, 5, _grandPrizePeriodDraws);
    TIER_ODDS_1_8 = TierCalculationLib.getTierOdds(1, 6, _grandPrizePeriodDraws);
    TIER_ODDS_2_8 = TierCalculationLib.getTierOdds(2, 6, _grandPrizePeriodDraws);
    TIER_ODDS_3_8 = TierCalculationLib.getTierOdds(3, 6, _grandPrizePeriodDraws);
    TIER_ODDS_4_8 = TierCalculationLib.getTierOdds(4, 6, _grandPrizePeriodDraws);
    TIER_ODDS_1_9 = TierCalculationLib.getTierOdds(1, 7, _grandPrizePeriodDraws);
    TIER_ODDS_2_9 = TierCalculationLib.getTierOdds(2, 7, _grandPrizePeriodDraws);
    TIER_ODDS_3_9 = TierCalculationLib.getTierOdds(3, 7, _grandPrizePeriodDraws);
    TIER_ODDS_4_9 = TierCalculationLib.getTierOdds(4, 7, _grandPrizePeriodDraws);
    TIER_ODDS_5_9 = TierCalculationLib.getTierOdds(5, 7, _grandPrizePeriodDraws);
    TIER_ODDS_1_10 = TierCalculationLib.getTierOdds(1, 8, _grandPrizePeriodDraws);
    TIER_ODDS_2_10 = TierCalculationLib.getTierOdds(2, 8, _grandPrizePeriodDraws);
    TIER_ODDS_3_10 = TierCalculationLib.getTierOdds(3, 8, _grandPrizePeriodDraws);
    TIER_ODDS_4_10 = TierCalculationLib.getTierOdds(4, 8, _grandPrizePeriodDraws);
    TIER_ODDS_5_10 = TierCalculationLib.getTierOdds(5, 8, _grandPrizePeriodDraws);
    TIER_ODDS_6_10 = TierCalculationLib.getTierOdds(6, 8, _grandPrizePeriodDraws);
    TIER_ODDS_1_11 = TierCalculationLib.getTierOdds(1, 9, _grandPrizePeriodDraws);
    TIER_ODDS_2_11 = TierCalculationLib.getTierOdds(2, 9, _grandPrizePeriodDraws);
    TIER_ODDS_3_11 = TierCalculationLib.getTierOdds(3, 9, _grandPrizePeriodDraws);
    TIER_ODDS_4_11 = TierCalculationLib.getTierOdds(4, 9, _grandPrizePeriodDraws);
    TIER_ODDS_5_11 = TierCalculationLib.getTierOdds(5, 9, _grandPrizePeriodDraws);
    TIER_ODDS_6_11 = TierCalculationLib.getTierOdds(6, 9, _grandPrizePeriodDraws);
    TIER_ODDS_7_11 = TierCalculationLib.getTierOdds(7, 9, _grandPrizePeriodDraws);

    ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS = _sumTierPrizeCounts(4);
    ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS = _sumTierPrizeCounts(5);
    ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS = _sumTierPrizeCounts(6);
    ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS = _sumTierPrizeCounts(7);
    ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS = _sumTierPrizeCounts(8);
    ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS = _sumTierPrizeCounts(9);
    ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS = _sumTierPrizeCounts(10);
    ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS = _sumTierPrizeCounts(11);
  }

  /// @notice Adjusts the number of tiers and distributes new liquidity.
  /// @param _awardingDraw The ID of the draw that is being awarded
  /// @param _nextNumberOfTiers The new number of tiers. Must be greater than minimum
  /// @param _prizeTokenLiquidity The amount of fresh liquidity to distribute across the tiers and reserve
  function _awardDraw(
    uint24 _awardingDraw,
    uint8 _nextNumberOfTiers,
    uint256 _prizeTokenLiquidity
  ) internal {
    if (_nextNumberOfTiers < MINIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersLessThanMinimum(_nextNumberOfTiers);
    }

    uint8 numTiers = numberOfTiers;
    uint128 _prizeTokenPerShare = prizeTokenPerShare;
    (uint96 deltaReserve, uint128 newPrizeTokenPerShare) = _computeNewDistributions(
      numTiers,
      _nextNumberOfTiers,
      _prizeTokenPerShare,
      _prizeTokenLiquidity
    );

    uint8 start = _computeReclamationStart(numTiers, _nextNumberOfTiers);
    uint8 end = _nextNumberOfTiers;
    for (uint8 i = start; i < end; i++) {
      _tiers[i] = Tier({
        drawId: _awardingDraw,
        prizeTokenPerShare: _prizeTokenPerShare,
        prizeSize: _computePrizeSize(
          i,
          _nextNumberOfTiers,
          _prizeTokenPerShare,
          newPrizeTokenPerShare
        )
      });
    }

    prizeTokenPerShare = newPrizeTokenPerShare;
    numberOfTiers = _nextNumberOfTiers;
    _lastAwardedDrawId = _awardingDraw;
    lastAwardedDrawAwardedAt = uint48(block.timestamp);
    _reserve += deltaReserve;
  }

  /// @notice Computes the liquidity that will be distributed for the next awarded draw given the next number of tiers and prize liquidity.
  /// @param _numberOfTiers The current number of tiers
  /// @param _nextNumberOfTiers The next number of tiers to use to compute distribution
  /// @param _currentPrizeTokenPerShare The current prize token per share
  /// @param _prizeTokenLiquidity The amount of fresh liquidity to distribute across the tiers and reserve
  /// @return deltaReserve The amount of liquidity that will be added to the reserve
  /// @return newPrizeTokenPerShare The new prize token per share
  function _computeNewDistributions(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    uint128 _currentPrizeTokenPerShare,
    uint256 _prizeTokenLiquidity
  ) internal view returns (uint96 deltaReserve, uint128 newPrizeTokenPerShare) {
    uint256 reclaimedLiquidity;
    {
      // need to redistribute to the canary tier and any new tiers (if expanding)
      uint8 start = _computeReclamationStart(_numberOfTiers, _nextNumberOfTiers);
      uint8 end = _numberOfTiers;
      for (uint8 i = start; i < end; i++) {
        reclaimedLiquidity = reclaimedLiquidity + (
          _getTierRemainingLiquidity(
            _tiers[i].prizeTokenPerShare,
            _currentPrizeTokenPerShare,
            _numShares(i, _numberOfTiers)
          )
        );
      }
    }

    uint256 totalNewLiquidity = _prizeTokenLiquidity + reclaimedLiquidity;
    uint256 nextTotalShares = computeTotalShares(_nextNumberOfTiers);
    uint256 deltaPrizeTokensPerShare = totalNewLiquidity / nextTotalShares;

    newPrizeTokenPerShare = SafeCast.toUint128(_currentPrizeTokenPerShare + deltaPrizeTokensPerShare);

    deltaReserve = SafeCast.toUint96(
      // reserve portion of new liquidity
      deltaPrizeTokensPerShare *
        reserveShares +
        // remainder left over from shares
        totalNewLiquidity -
        deltaPrizeTokensPerShare *
        nextTotalShares
    );
  }

  /// @notice Returns the prize size for the given tier.
  /// @param _tier The tier to retrieve
  /// @return The prize size for the tier
  function getTierPrizeSize(uint8 _tier) external view returns (uint104) {
    uint8 _numTiers = numberOfTiers;

    return
      !TierCalculationLib.isValidTier(_tier, _numTiers) ? 0 : _getTier(_tier, _numTiers).prizeSize;
  }

  /// @notice Returns the estimated number of prizes for the given tier.
  /// @param _tier The tier to retrieve
  /// @return The estimated number of prizes
  function getTierPrizeCount(uint8 _tier) external pure returns (uint32) {
    return uint32(TierCalculationLib.prizeCount(_tier));
  }

  /// @notice Retrieves an up-to-date Tier struct for the given tier.
  /// @param _tier The tier to retrieve
  /// @param _numberOfTiers The number of tiers, should match the current. Passed explicitly as an optimization
  /// @return An up-to-date Tier struct; if the prize is outdated then it is recomputed based on available liquidity and the draw ID is updated.
  function _getTier(uint8 _tier, uint8 _numberOfTiers) internal view returns (Tier memory) {
    Tier memory tier = _tiers[_tier];
    uint24 lastAwardedDrawId_ = _lastAwardedDrawId;
    if (tier.drawId != lastAwardedDrawId_) {
      tier.drawId = lastAwardedDrawId_;
      tier.prizeSize = _computePrizeSize(
        _tier,
        _numberOfTiers,
        tier.prizeTokenPerShare,
        prizeTokenPerShare
      );
    }
    return tier;
  }

  /// @notice Computes the total shares in the system.
  /// @return The total shares
  function getTotalShares() external view returns (uint256) {
    return computeTotalShares(numberOfTiers);
  }

  /// @notice Computes the total shares in the system given the number of tiers.
  /// @param _numberOfTiers The number of tiers to calculate the total shares for
  /// @return The total shares
  function computeTotalShares(uint8 _numberOfTiers) public view returns (uint256) {
    return uint256(_numberOfTiers-2) * uint256(tierShares) + uint256(reserveShares) + uint256(canaryShares) * 2;
  }

  /// @notice Determines at which tier we need to start reclaiming liquidity.
  /// @param _numberOfTiers The current number of tiers
  /// @param _nextNumberOfTiers The next number of tiers
  /// @return The tier to start reclaiming liquidity from
  function _computeReclamationStart(uint8 _numberOfTiers, uint8 _nextNumberOfTiers) internal pure returns (uint8) {
    // We must always reset the canary tiers, both old and new. 
    // If the next num is less than the num tiers, then the first canary tiers to reset are the last of the next tiers.
    // Otherwise, the canary tiers to reset are the last of the current tiers.
    return (_nextNumberOfTiers > _numberOfTiers ? _numberOfTiers : _nextNumberOfTiers) - NUMBER_OF_CANARY_TIERS;
  }

  /// @notice Consumes liquidity from the given tier.
  /// @param _tierStruct The tier to consume liquidity from
  /// @param _tier The tier number
  /// @param _liquidity The amount of liquidity to consume
  function _consumeLiquidity(Tier memory _tierStruct, uint8 _tier, uint104 _liquidity) internal {
    uint8 _tierShares = _numShares(_tier, numberOfTiers);
    uint104 remainingLiquidity = SafeCast.toUint104(
      _getTierRemainingLiquidity(
        _tierStruct.prizeTokenPerShare,
        prizeTokenPerShare,
        _tierShares
      )
    );

    if (_liquidity > remainingLiquidity) {
      uint96 excess = SafeCast.toUint96(_liquidity - remainingLiquidity);

      if (excess > _reserve) {
        revert InsufficientLiquidity(_liquidity);
      }

      unchecked {
        _reserve -= excess;
      }

      emit ReserveConsumed(excess);
      _tierStruct.prizeTokenPerShare = prizeTokenPerShare;
    } else {
      uint8 _remainder = uint8(_liquidity % _tierShares);
      uint8 _roundUpConsumption = _remainder == 0 ? 0 : _tierShares - _remainder;
      if (_roundUpConsumption > 0) {
        // We must round up our tier prize token per share value to ensure we don't over-award the tier's
        // liquidity, but any extra rounded up consumption can be contributed to the reserve so every wei
        // is accounted for.
        _reserve += _roundUpConsumption;
      }

      // We know that the rounded up `liquidity` won't exceed the `remainingLiquidity` since the `remainingLiquidity`
      // is an integer multiple of `_tierShares` and we check above that `_liquidity <= remainingLiquidity`.
      _tierStruct.prizeTokenPerShare += SafeCast.toUint104(uint256(_liquidity) + _roundUpConsumption) / _tierShares;
    }

    _tiers[_tier] = _tierStruct;
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
    uint128 _tierPrizeTokenPerShare,
    uint128 _prizeTokenPerShare
  ) internal view returns (uint104) {
    uint256 prizeCount = TierCalculationLib.prizeCount(_tier);
    uint256 remainingTierLiquidity = _getTierRemainingLiquidity(
      _tierPrizeTokenPerShare,
      _prizeTokenPerShare,
      _numShares(_tier, _numberOfTiers)
    );

    uint256 prizeSize = convert(
      convert(remainingTierLiquidity).mul(tierLiquidityUtilizationRate).div(convert(prizeCount))
    );

    return prizeSize > type(uint104).max ? type(uint104).max : uint104(prizeSize);
  }

  /// @notice Returns whether the given tier is a canary tier
  /// @param _tier The tier to check
  /// @return True if the passed tier is a canary tier, false otherwise
  function isCanaryTier(uint8 _tier) public view returns (bool) {
    return _tier >= numberOfTiers - NUMBER_OF_CANARY_TIERS;
  }

  /// @notice Returns the number of shares for the given tier and number of tiers.
  /// @param _tier The tier to compute the number of shares for
  /// @param _numberOfTiers The number of tiers
  /// @return The number of shares
  function _numShares(uint8 _tier, uint8 _numberOfTiers) internal view returns (uint8) {
    uint8 result = _tier > _numberOfTiers - 3 ? canaryShares : tierShares;
    return result;
  }

  /// @notice Computes the remaining liquidity available to a tier.
  /// @param _tier The tier to compute the liquidity for
  /// @return The remaining liquidity
  function getTierRemainingLiquidity(uint8 _tier) public view returns (uint256) {
    uint8 _numTiers = numberOfTiers;
    if (TierCalculationLib.isValidTier(_tier, _numTiers)) {
      return _getTierRemainingLiquidity(
        _getTier(_tier, _numTiers).prizeTokenPerShare,
        prizeTokenPerShare,
        _numShares(_tier, _numTiers)
      );
    } else {
      return 0;
    }
  }

  /// @notice Computes the remaining tier liquidity.
  /// @param _tierPrizeTokenPerShare The prizeTokenPerShare of the Tier struct
  /// @param _prizeTokenPerShare The global prizeTokenPerShare
  /// @param _tierShares The number of shares for the tier
  /// @return The remaining available liquidity
  function _getTierRemainingLiquidity(
    uint128 _tierPrizeTokenPerShare,
    uint128 _prizeTokenPerShare,
    uint8 _tierShares
  ) internal pure returns (uint256) {
    uint256 result =
      _tierPrizeTokenPerShare >= _prizeTokenPerShare
        ? 0
        : uint256(_prizeTokenPerShare - _tierPrizeTokenPerShare) * _tierShares;
    return result;
  }

  /// @notice Estimates the number of prizes for the current number of tiers, including the first canary tier
  /// @return The estimated number of prizes including the canary tier
  function estimatedPrizeCount() external view returns (uint32) {
    return estimatedPrizeCount(numberOfTiers);
  }

  /// @notice Estimates the number of prizes for the current number of tiers, including both canary tiers
  /// @return The estimated number of prizes including both canary tiers
  function estimatedPrizeCountWithBothCanaries() external view returns (uint32) {
    return estimatedPrizeCountWithBothCanaries(numberOfTiers);
  }

  /// @notice Returns the balance of the reserve.
  /// @return The amount of tokens that have been reserved.
  function reserve() external view returns (uint96) {
    return _reserve;
  }

  /// @notice Estimates the prize count for the given number of tiers, including the first canary tier. It expects no prizes are claimed for the last canary tier
  /// @param numTiers The number of prize tiers
  /// @return The estimated total number of prizes
  function estimatedPrizeCount(
    uint8 numTiers
  ) public view returns (uint32) {
    if (numTiers == 4) {
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
    }
    return 0;
  }

  /// @notice Estimates the prize count for the given tier, including BOTH canary tiers
  /// @param numTiers The number of tiers
  /// @return The estimated prize count across all tiers, including both canary tiers.
  function estimatedPrizeCountWithBothCanaries(
    uint8 numTiers
  ) public view returns (uint32) {
    if (numTiers >= MINIMUM_NUMBER_OF_TIERS && numTiers <= MAXIMUM_NUMBER_OF_TIERS) {
      return estimatedPrizeCount(numTiers) + uint32(TierCalculationLib.prizeCount(numTiers - 1));
    } else {
      return 0;
    }
  }

  /// @notice Estimates the number of tiers for the given prize count.
  /// @param _prizeCount The number of prizes that were claimed
  /// @return The estimated tier
  function _estimateNumberOfTiersUsingPrizeCountPerDraw(
    uint32 _prizeCount
  ) internal view returns (uint8) {
    // the prize count is slightly more than 4x for each higher tier. i.e. 16, 66, 270, 1108, etc
    // by doubling the measured count, we create a safe margin for error.
    uint32 _adjustedPrizeCount = _prizeCount * 2;
    if (_adjustedPrizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS) {
      return 4;
    } else if (_adjustedPrizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS) {
      return 5;
    } else if (_adjustedPrizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS) {
      return 6;
    } else if (_adjustedPrizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS) {
      return 7;
    } else if (_adjustedPrizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS) {
      return 8;
    } else if (_adjustedPrizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS) {
      return 9;
    } else if (_adjustedPrizeCount < ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS) {
      return 10;
    } else {
      return 11;
    }
  }

  /// @notice Computes the expected number of prizes for a given number of tiers.
  /// @dev Includes the first canary tier prizes, but not the second since the first is expected to
  /// be claimed.
  /// @param _numTiers The number of tiers, including canaries
  /// @return The expected number of prizes, first canary included.
  function _sumTierPrizeCounts(uint8 _numTiers) internal view returns (uint32) {
    uint32 prizeCount;
    uint8 i = 0;
    do {
      prizeCount += TierCalculationLib.tierPrizeCountPerDraw(i, getTierOdds(i, _numTiers));
      i++;
    } while (i < _numTiers - 1);
    return prizeCount;
  }

  /// @notice Computes the odds for a tier given the number of tiers.
  /// @param _tier The tier to compute odds for
  /// @param _numTiers The number of prize tiers
  /// @return The odds of the tier
  function getTierOdds(uint8 _tier, uint8 _numTiers) public view returns (SD59x18) {
    if (_tier == 0) return TIER_ODDS_0;
    if (_numTiers == 3) {
      if (_tier <= 2) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 4) {
      if (_tier <= 3) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 5) {
      if (_tier == 1) return TIER_ODDS_1_5;
      else if (_tier <= 4) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 6) {
      if (_tier == 1) return TIER_ODDS_1_6;
      else if (_tier == 2) return TIER_ODDS_2_6;
      else if (_tier <= 5) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 7) {
      if (_tier == 1) return TIER_ODDS_1_7;
      else if (_tier == 2) return TIER_ODDS_2_7;
      else if (_tier == 3) return TIER_ODDS_3_7;
      else if (_tier <= 6) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 8) {
      if (_tier == 1) return TIER_ODDS_1_8;
      else if (_tier == 2) return TIER_ODDS_2_8;
      else if (_tier == 3) return TIER_ODDS_3_8;
      else if (_tier == 4) return TIER_ODDS_4_8;
      else if (_tier <= 7) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 9) {
      if (_tier == 1) return TIER_ODDS_1_9;
      else if (_tier == 2) return TIER_ODDS_2_9;
      else if (_tier == 3) return TIER_ODDS_3_9;
      else if (_tier == 4) return TIER_ODDS_4_9;
      else if (_tier == 5) return TIER_ODDS_5_9;
      else if (_tier <= 8) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 10) {
      if (_tier == 1) return TIER_ODDS_1_10;
      else if (_tier == 2) return TIER_ODDS_2_10;
      else if (_tier == 3) return TIER_ODDS_3_10;
      else if (_tier == 4) return TIER_ODDS_4_10;
      else if (_tier == 5) return TIER_ODDS_5_10;
      else if (_tier == 6) return TIER_ODDS_6_10;
      else if (_tier <= 9) return TIER_ODDS_EVERY_DRAW;
    } else if (_numTiers == 11) {
      if (_tier == 1) return TIER_ODDS_1_11;
      else if (_tier == 2) return TIER_ODDS_2_11;
      else if (_tier == 3) return TIER_ODDS_3_11;
      else if (_tier == 4) return TIER_ODDS_4_11;
      else if (_tier == 5) return TIER_ODDS_5_11;
      else if (_tier == 6) return TIER_ODDS_6_11;
      else if (_tier == 7) return TIER_ODDS_7_11;
      else if (_tier <= 10) return TIER_ODDS_EVERY_DRAW;
    }
    return sd(0);
  }
}
