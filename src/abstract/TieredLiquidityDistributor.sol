// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud, toUD60x18, fromUD60x18, intoSD59x18 } from "prb-math/UD60x18.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";

import { UD34x4, fromUD60x18 as fromUD60x18toUD34x4, intoUD60x18 as fromUD34x4toUD60x18, toUD34x4 } from "../libraries/UD34x4.sol";
import { TierCalculationLib } from "../libraries/TierCalculationLib.sol";

/// @notice Struct that tracks tier liquidity information
struct Tier {
  uint16 drawId;
  uint96 prizeSize;
  UD34x4 prizeTokenPerShare;
}

/// @notice Emitted when the number of tiers is less than the minimum number of tiers
/// @param numTiers The invalid number of tiers
error NumberOfTiersLessThanMinimum(uint8 numTiers);

/// @notice Emitted when there is insufficient liquidity to consume.
/// @param requestedLiquidity The requested amount of liquidity
error InsufficientLiquidity(uint104 requestedLiquidity);

/// @title Tiered Liquidity Distributor
/// @author PoolTogether Inc.
/// @notice A contract that distributes liquidity according to PoolTogether V5 distribution rules.
contract TieredLiquidityDistributor {
  uint8 internal constant MINIMUM_NUMBER_OF_TIERS = 3;

  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_2_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_3_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_4_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_5_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_6_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_7_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_8_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_9_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_10_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_11_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_12_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_13_TIERS;
  UD60x18 internal immutable CANARY_PRIZE_COUNT_FOR_14_TIERS;

  //////////////////////// START GENERATED CONSTANTS ////////////////////////
  // Constants are precomputed using the script/generateConstants.s.sol script.

  /// @notice The number of draws that should statistically occur between grand prizes.
  uint16 internal constant GRAND_PRIZE_PERIOD_DRAWS = 365;

  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS = 4;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS = 16;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS = 66;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS = 270;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS = 1108;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS = 4517;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS = 18358;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS = 74435;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS = 301239;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS = 1217266;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS = 4912619;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS = 19805536;
  uint32 internal constant ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS = 79777187;

  SD59x18 internal constant TIER_ODDS_0_3 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_3 = SD59x18.wrap(52342392259021369);
  SD59x18 internal constant TIER_ODDS_2_3 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_4 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_4 = SD59x18.wrap(19579642462506911);
  SD59x18 internal constant TIER_ODDS_2_4 = SD59x18.wrap(139927275620255366);
  SD59x18 internal constant TIER_ODDS_3_4 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_5 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_5 = SD59x18.wrap(11975133168707466);
  SD59x18 internal constant TIER_ODDS_2_5 = SD59x18.wrap(52342392259021369);
  SD59x18 internal constant TIER_ODDS_3_5 = SD59x18.wrap(228784597949733865);
  SD59x18 internal constant TIER_ODDS_4_5 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_6 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_6 = SD59x18.wrap(8915910667410451);
  SD59x18 internal constant TIER_ODDS_2_6 = SD59x18.wrap(29015114005673871);
  SD59x18 internal constant TIER_ODDS_3_6 = SD59x18.wrap(94424100034951094);
  SD59x18 internal constant TIER_ODDS_4_6 = SD59x18.wrap(307285046878222004);
  SD59x18 internal constant TIER_ODDS_5_6 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_7 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_7 = SD59x18.wrap(7324128348251604);
  SD59x18 internal constant TIER_ODDS_2_7 = SD59x18.wrap(19579642462506911);
  SD59x18 internal constant TIER_ODDS_3_7 = SD59x18.wrap(52342392259021369);
  SD59x18 internal constant TIER_ODDS_4_7 = SD59x18.wrap(139927275620255366);
  SD59x18 internal constant TIER_ODDS_5_7 = SD59x18.wrap(374068544013333694);
  SD59x18 internal constant TIER_ODDS_6_7 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_8 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_8 = SD59x18.wrap(6364275529026907);
  SD59x18 internal constant TIER_ODDS_2_8 = SD59x18.wrap(14783961098420314);
  SD59x18 internal constant TIER_ODDS_3_8 = SD59x18.wrap(34342558671878193);
  SD59x18 internal constant TIER_ODDS_4_8 = SD59x18.wrap(79776409602255901);
  SD59x18 internal constant TIER_ODDS_5_8 = SD59x18.wrap(185317453770221528);
  SD59x18 internal constant TIER_ODDS_6_8 = SD59x18.wrap(430485137687959592);
  SD59x18 internal constant TIER_ODDS_7_8 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_9 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_9 = SD59x18.wrap(5727877794074876);
  SD59x18 internal constant TIER_ODDS_2_9 = SD59x18.wrap(11975133168707466);
  SD59x18 internal constant TIER_ODDS_3_9 = SD59x18.wrap(25036116265717087);
  SD59x18 internal constant TIER_ODDS_4_9 = SD59x18.wrap(52342392259021369);
  SD59x18 internal constant TIER_ODDS_5_9 = SD59x18.wrap(109430951602859902);
  SD59x18 internal constant TIER_ODDS_6_9 = SD59x18.wrap(228784597949733865);
  SD59x18 internal constant TIER_ODDS_7_9 = SD59x18.wrap(478314329651259628);
  SD59x18 internal constant TIER_ODDS_8_9 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_10 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_10 = SD59x18.wrap(5277233889074595);
  SD59x18 internal constant TIER_ODDS_2_10 = SD59x18.wrap(10164957094799045);
  SD59x18 internal constant TIER_ODDS_3_10 = SD59x18.wrap(19579642462506911);
  SD59x18 internal constant TIER_ODDS_4_10 = SD59x18.wrap(37714118749773489);
  SD59x18 internal constant TIER_ODDS_5_10 = SD59x18.wrap(72644572330454226);
  SD59x18 internal constant TIER_ODDS_6_10 = SD59x18.wrap(139927275620255366);
  SD59x18 internal constant TIER_ODDS_7_10 = SD59x18.wrap(269526570731818992);
  SD59x18 internal constant TIER_ODDS_8_10 = SD59x18.wrap(519159484871285957);
  SD59x18 internal constant TIER_ODDS_9_10 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_11 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_11 = SD59x18.wrap(4942383282734483);
  SD59x18 internal constant TIER_ODDS_2_11 = SD59x18.wrap(8915910667410451);
  SD59x18 internal constant TIER_ODDS_3_11 = SD59x18.wrap(16084034459031666);
  SD59x18 internal constant TIER_ODDS_4_11 = SD59x18.wrap(29015114005673871);
  SD59x18 internal constant TIER_ODDS_5_11 = SD59x18.wrap(52342392259021369);
  SD59x18 internal constant TIER_ODDS_6_11 = SD59x18.wrap(94424100034951094);
  SD59x18 internal constant TIER_ODDS_7_11 = SD59x18.wrap(170338234127496669);
  SD59x18 internal constant TIER_ODDS_8_11 = SD59x18.wrap(307285046878222004);
  SD59x18 internal constant TIER_ODDS_9_11 = SD59x18.wrap(554332974734700411);
  SD59x18 internal constant TIER_ODDS_10_11 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_12 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_12 = SD59x18.wrap(4684280039134314);
  SD59x18 internal constant TIER_ODDS_2_12 = SD59x18.wrap(8009005012036743);
  SD59x18 internal constant TIER_ODDS_3_12 = SD59x18.wrap(13693494143591795);
  SD59x18 internal constant TIER_ODDS_4_12 = SD59x18.wrap(23412618868232833);
  SD59x18 internal constant TIER_ODDS_5_12 = SD59x18.wrap(40030011078337707);
  SD59x18 internal constant TIER_ODDS_6_12 = SD59x18.wrap(68441800379112721);
  SD59x18 internal constant TIER_ODDS_7_12 = SD59x18.wrap(117019204165776974);
  SD59x18 internal constant TIER_ODDS_8_12 = SD59x18.wrap(200075013628233217);
  SD59x18 internal constant TIER_ODDS_9_12 = SD59x18.wrap(342080698323914461);
  SD59x18 internal constant TIER_ODDS_10_12 = SD59x18.wrap(584876652230121477);
  SD59x18 internal constant TIER_ODDS_11_12 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_13 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_13 = SD59x18.wrap(4479520628784180);
  SD59x18 internal constant TIER_ODDS_2_13 = SD59x18.wrap(7324128348251604);
  SD59x18 internal constant TIER_ODDS_3_13 = SD59x18.wrap(11975133168707466);
  SD59x18 internal constant TIER_ODDS_4_13 = SD59x18.wrap(19579642462506911);
  SD59x18 internal constant TIER_ODDS_5_13 = SD59x18.wrap(32013205494981721);
  SD59x18 internal constant TIER_ODDS_6_13 = SD59x18.wrap(52342392259021369);
  SD59x18 internal constant TIER_ODDS_7_13 = SD59x18.wrap(85581121447732876);
  SD59x18 internal constant TIER_ODDS_8_13 = SD59x18.wrap(139927275620255366);
  SD59x18 internal constant TIER_ODDS_9_13 = SD59x18.wrap(228784597949733866);
  SD59x18 internal constant TIER_ODDS_10_13 = SD59x18.wrap(374068544013333694);
  SD59x18 internal constant TIER_ODDS_11_13 = SD59x18.wrap(611611432212751966);
  SD59x18 internal constant TIER_ODDS_12_13 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_14 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_14 = SD59x18.wrap(4313269422986724);
  SD59x18 internal constant TIER_ODDS_2_14 = SD59x18.wrap(6790566987074365);
  SD59x18 internal constant TIER_ODDS_3_14 = SD59x18.wrap(10690683906783196);
  SD59x18 internal constant TIER_ODDS_4_14 = SD59x18.wrap(16830807002169641);
  SD59x18 internal constant TIER_ODDS_5_14 = SD59x18.wrap(26497468900426949);
  SD59x18 internal constant TIER_ODDS_6_14 = SD59x18.wrap(41716113674084931);
  SD59x18 internal constant TIER_ODDS_7_14 = SD59x18.wrap(65675485708038160);
  SD59x18 internal constant TIER_ODDS_8_14 = SD59x18.wrap(103395763485663166);
  SD59x18 internal constant TIER_ODDS_9_14 = SD59x18.wrap(162780431564813557);
  SD59x18 internal constant TIER_ODDS_10_14 = SD59x18.wrap(256272288217119098);
  SD59x18 internal constant TIER_ODDS_11_14 = SD59x18.wrap(403460570024895441);
  SD59x18 internal constant TIER_ODDS_12_14 = SD59x18.wrap(635185461125249183);
  SD59x18 internal constant TIER_ODDS_13_14 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_15 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_15 = SD59x18.wrap(4175688124417637);
  SD59x18 internal constant TIER_ODDS_2_15 = SD59x18.wrap(6364275529026907);
  SD59x18 internal constant TIER_ODDS_3_15 = SD59x18.wrap(9699958857683993);
  SD59x18 internal constant TIER_ODDS_4_15 = SD59x18.wrap(14783961098420314);
  SD59x18 internal constant TIER_ODDS_5_15 = SD59x18.wrap(22532621938542004);
  SD59x18 internal constant TIER_ODDS_6_15 = SD59x18.wrap(34342558671878193);
  SD59x18 internal constant TIER_ODDS_7_15 = SD59x18.wrap(52342392259021369);
  SD59x18 internal constant TIER_ODDS_8_15 = SD59x18.wrap(79776409602255901);
  SD59x18 internal constant TIER_ODDS_9_15 = SD59x18.wrap(121589313257458259);
  SD59x18 internal constant TIER_ODDS_10_15 = SD59x18.wrap(185317453770221528);
  SD59x18 internal constant TIER_ODDS_11_15 = SD59x18.wrap(282447180198804430);
  SD59x18 internal constant TIER_ODDS_12_15 = SD59x18.wrap(430485137687959592);
  SD59x18 internal constant TIER_ODDS_13_15 = SD59x18.wrap(656113662171395111);
  SD59x18 internal constant TIER_ODDS_14_15 = SD59x18.wrap(1000000000000000000);
  SD59x18 internal constant TIER_ODDS_0_16 = SD59x18.wrap(2739726027397260);
  SD59x18 internal constant TIER_ODDS_1_16 = SD59x18.wrap(4060005854625059);
  SD59x18 internal constant TIER_ODDS_2_16 = SD59x18.wrap(6016531351950262);
  SD59x18 internal constant TIER_ODDS_3_16 = SD59x18.wrap(8915910667410451);
  SD59x18 internal constant TIER_ODDS_4_16 = SD59x18.wrap(13212507070785166);
  SD59x18 internal constant TIER_ODDS_5_16 = SD59x18.wrap(19579642462506911);
  SD59x18 internal constant TIER_ODDS_6_16 = SD59x18.wrap(29015114005673871);
  SD59x18 internal constant TIER_ODDS_7_16 = SD59x18.wrap(42997559448512061);
  SD59x18 internal constant TIER_ODDS_8_16 = SD59x18.wrap(63718175229875027);
  SD59x18 internal constant TIER_ODDS_9_16 = SD59x18.wrap(94424100034951094);
  SD59x18 internal constant TIER_ODDS_10_16 = SD59x18.wrap(139927275620255366);
  SD59x18 internal constant TIER_ODDS_11_16 = SD59x18.wrap(207358528757589475);
  SD59x18 internal constant TIER_ODDS_12_16 = SD59x18.wrap(307285046878222004);
  SD59x18 internal constant TIER_ODDS_13_16 = SD59x18.wrap(455366367617975795);
  SD59x18 internal constant TIER_ODDS_14_16 = SD59x18.wrap(674808393262840052);
  SD59x18 internal constant TIER_ODDS_15_16 = SD59x18.wrap(1000000000000000000);

  //////////////////////// END GENERATED CONSTANTS ////////////////////////

  /// @notice The Tier liquidity data
  mapping(uint8 => Tier) internal _tiers;

  /// @notice The number of shares to allocate to each prize tier
  uint8 public immutable tierShares;

  /// @notice The number of shares to allocate to the canary tier
  uint8 public immutable canaryShares;

  /// @notice The number of shares to allocate to the reserve
  uint8 public immutable reserveShares;

  /// @notice The current number of prize tokens per share
  UD34x4 public prizeTokenPerShare;

  /// @notice The number of tiers for the last completed draw. The last tier is the canary tier.
  uint8 public numberOfTiers;

  /// @notice The draw id of the last completed draw
  uint16 internal lastCompletedDrawId;

  /// @notice The amount of available reserve
  uint104 internal _reserve;

  /**
   * @notice Constructs a new Prize Pool
   * @param _numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
   * @param _tierShares The number of shares to allocate to each tier
   * @param _canaryShares The number of shares to allocate to the canary tier.
   * @param _reserveShares The number of shares to allocate to the reserve.
   */
  constructor(uint8 _numberOfTiers, uint8 _tierShares, uint8 _canaryShares, uint8 _reserveShares) {
    numberOfTiers = _numberOfTiers;
    tierShares = _tierShares;
    canaryShares = _canaryShares;
    reserveShares = _reserveShares;

    CANARY_PRIZE_COUNT_FOR_2_TIERS = TierCalculationLib.canaryPrizeCount(
      2,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_3_TIERS = TierCalculationLib.canaryPrizeCount(
      3,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_4_TIERS = TierCalculationLib.canaryPrizeCount(
      4,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_5_TIERS = TierCalculationLib.canaryPrizeCount(
      5,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_6_TIERS = TierCalculationLib.canaryPrizeCount(
      6,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_7_TIERS = TierCalculationLib.canaryPrizeCount(
      7,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_8_TIERS = TierCalculationLib.canaryPrizeCount(
      8,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_9_TIERS = TierCalculationLib.canaryPrizeCount(
      9,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_10_TIERS = TierCalculationLib.canaryPrizeCount(
      10,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_11_TIERS = TierCalculationLib.canaryPrizeCount(
      11,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_12_TIERS = TierCalculationLib.canaryPrizeCount(
      12,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_13_TIERS = TierCalculationLib.canaryPrizeCount(
      13,
      _canaryShares,
      _reserveShares,
      _tierShares
    );
    CANARY_PRIZE_COUNT_FOR_14_TIERS = TierCalculationLib.canaryPrizeCount(
      14,
      _canaryShares,
      _reserveShares,
      _tierShares
    );

    if (_numberOfTiers < MINIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersLessThanMinimum(_numberOfTiers);
    }
  }

  /// @notice Adjusts the number of tiers and distributes new liquidity
  /// @param _nextNumberOfTiers The new number of tiers. Must be greater than minimum
  /// @param _prizeTokenLiquidity The amount of fresh liquidity to distribute across the tiers and reserve
  function _nextDraw(uint8 _nextNumberOfTiers, uint96 _prizeTokenLiquidity) internal {
    if (_nextNumberOfTiers < MINIMUM_NUMBER_OF_TIERS) {
      revert NumberOfTiersLessThanMinimum(_nextNumberOfTiers);
    }

    uint8 numTiers = numberOfTiers;
    UD60x18 _prizeTokenPerShare = fromUD34x4toUD60x18(prizeTokenPerShare);
    (
      uint16 completedDrawId,
      uint104 newReserve,
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
        drawId: completedDrawId,
        prizeTokenPerShare: prizeTokenPerShare,
        prizeSize: uint96(
          _computePrizeSize(i, _nextNumberOfTiers, _prizeTokenPerShare, newPrizeTokenPerShare)
        )
      });
    }

    prizeTokenPerShare = fromUD60x18toUD34x4(newPrizeTokenPerShare);
    numberOfTiers = _nextNumberOfTiers;
    lastCompletedDrawId = completedDrawId;
    _reserve += newReserve;
  }

  /// @notice Computes the liquidity that will be distributed for the next draw given the next number of tiers and prize liquidity.
  /// @param _numberOfTiers The current number of tiers
  /// @param _nextNumberOfTiers The next number of tiers to use to compute distribution
  /// @param _prizeTokenLiquidity The amount of fresh liquidity to distribute across the tiers and reserve
  /// @return completedDrawId The drawId that this is for
  /// @return newReserve The amount of liquidity that will be added to the reserve
  /// @return newPrizeTokenPerShare The new prize token per share
  function _computeNewDistributions(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    uint256 _prizeTokenLiquidity
  )
    internal
    view
    returns (uint16 completedDrawId, uint104 newReserve, UD60x18 newPrizeTokenPerShare)
  {
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
  /// @return completedDrawId The drawId that this is for
  /// @return newReserve The amount of liquidity that will be added to the reserve
  /// @return newPrizeTokenPerShare The new prize token per share
  function _computeNewDistributions(
    uint8 _numberOfTiers,
    uint8 _nextNumberOfTiers,
    UD60x18 _currentPrizeTokenPerShare,
    uint _prizeTokenLiquidity
  )
    internal
    view
    returns (uint16 completedDrawId, uint104 newReserve, UD60x18 newPrizeTokenPerShare)
  {
    completedDrawId = lastCompletedDrawId + 1;
    uint256 totalShares = _getTotalShares(_nextNumberOfTiers);
    UD60x18 deltaPrizeTokensPerShare = (toUD60x18(_prizeTokenLiquidity).div(toUD60x18(totalShares)))
      .floor();

    newPrizeTokenPerShare = _currentPrizeTokenPerShare.add(deltaPrizeTokensPerShare);

    uint reclaimed = _getTierLiquidityToReclaim(
      _numberOfTiers,
      _nextNumberOfTiers,
      _currentPrizeTokenPerShare
    );
    uint computedLiquidity = fromUD60x18(deltaPrizeTokensPerShare.mul(toUD60x18(totalShares)));
    uint remainder = (_prizeTokenLiquidity - computedLiquidity);

    newReserve = uint104(
      fromUD60x18(deltaPrizeTokensPerShare.mul(toUD60x18(reserveShares))) + // reserve portion
        reclaimed + // reclaimed liquidity from tiers
        remainder // remainder
    );
  }

  /// @notice Returns the prize size for the given tier
  /// @param _tier The tier to retrieve
  /// @return The prize size for the tier
  function getTierPrizeSize(uint8 _tier) external view returns (uint96) {
    return _getTier(_tier, numberOfTiers).prizeSize;
  }

  /// @notice Returns the estimated number of prizes for the given tier
  /// @param _tier The tier to retrieve
  /// @return The estimated number of prizes
  function getTierPrizeCount(uint8 _tier) external view returns (uint32) {
    return _getTierPrizeCount(_tier, numberOfTiers);
  }

  /// @notice Returns the estimated number of prizes for the given tier and number of tiers
  /// @param _tier The tier to retrieve
  /// @param _numberOfTiers The number of tiers, should match the current number of tiers
  /// @return The estimated number of prizes
  function getTierPrizeCount(uint8 _tier, uint8 _numberOfTiers) external view returns (uint32) {
    return _getTierPrizeCount(_tier, _numberOfTiers);
  }

  /// @notice Returns the number of available prizes for the given tier
  /// @param _tier The tier to retrieve
  /// @param _numberOfTiers The number of tiers, should match the current number of tiers
  /// @return The number of available prizes
  function _getTierPrizeCount(uint8 _tier, uint8 _numberOfTiers) internal view returns (uint32) {
    return
      _isCanaryTier(_tier, _numberOfTiers)
        ? _canaryPrizeCount(_numberOfTiers)
        : uint32(TierCalculationLib.prizeCount(_tier));
  }

  /// @notice Retrieves an up-to-date Tier struct for the given tier
  /// @param _tier The tier to retrieve
  /// @param _numberOfTiers The number of tiers, should match the current. Passed explicitly as an optimization
  /// @return An up-to-date Tier struct; if the prize is outdated then it is recomputed based on available liquidity and the draw id updated.
  function _getTier(uint8 _tier, uint8 _numberOfTiers) internal view returns (Tier memory) {
    Tier memory tier = _tiers[_tier];
    uint16 _lastCompletedDrawId = lastCompletedDrawId;
    if (tier.drawId != _lastCompletedDrawId) {
      tier.drawId = _lastCompletedDrawId;
      tier.prizeSize = uint96(
        _computePrizeSize(
          _tier,
          _numberOfTiers,
          fromUD34x4toUD60x18(tier.prizeTokenPerShare),
          fromUD34x4toUD60x18(prizeTokenPerShare)
        )
      );
    }
    return tier;
  }

  /// @notice Computes the total shares in the system. That is `(number of tiers * tier shares) + canary shares + reserve shares`
  /// @return The total shares
  function getTotalShares() external view returns (uint256) {
    return _getTotalShares(numberOfTiers);
  }

  /// @notice Computes the total shares in the system given the number of tiers. That is `(number of tiers * tier shares) + canary shares + reserve shares`
  /// @param _numberOfTiers The number of tiers to calculate the total shares for
  /// @return The total shares
  function _getTotalShares(uint8 _numberOfTiers) internal view returns (uint256) {
    return
      uint256(_numberOfTiers - 1) *
      uint256(tierShares) +
      uint256(canaryShares) +
      uint256(reserveShares);
  }

  /// @notice Computes the number of shares for the given tier. If the tier is the canary tier, then the canary shares are returned.  Normal tier shares otherwise.
  /// @param _tier The tier to request share for
  /// @param _numTiers The number of tiers. Passed explicitly as an optimization
  /// @return The number of shares for the given tier
  function _computeShares(uint8 _tier, uint8 _numTiers) internal view returns (uint8) {
    return _isCanaryTier(_tier, _numTiers) ? canaryShares : tierShares;
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
    uint8 _shares = _computeShares(_tier, numberOfTiers);
    uint104 remainingLiquidity = uint104(
      fromUD60x18(
        _getTierRemainingLiquidity(
          _shares,
          fromUD34x4toUD60x18(_tierStruct.prizeTokenPerShare),
          fromUD34x4toUD60x18(prizeTokenPerShare)
        )
      )
    );
    if (_liquidity > remainingLiquidity) {
      uint104 excess = _liquidity - remainingLiquidity;
      if (excess > _reserve) {
        revert InsufficientLiquidity(_liquidity);
      }
      _reserve -= excess;
      _tierStruct.prizeTokenPerShare = prizeTokenPerShare;
    } else {
      UD34x4 delta = fromUD60x18toUD34x4(toUD60x18(_liquidity).div(toUD60x18(_shares)));
      _tierStruct.prizeTokenPerShare = UD34x4.wrap(
        UD34x4.unwrap(_tierStruct.prizeTokenPerShare) + UD34x4.unwrap(delta)
      );
    }
    _tiers[_tier] = _tierStruct;
    return _tierStruct;
  }

  /// @notice Computes the prize size of the given tier
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
  ) internal view returns (uint256) {
    assert(_tier < _numberOfTiers);
    uint256 prizeSize;
    if (_prizeTokenPerShare.gt(_tierPrizeTokenPerShare)) {
      if (_isCanaryTier(_tier, _numberOfTiers)) {
        prizeSize = _computePrizeSize(
          _tierPrizeTokenPerShare,
          _prizeTokenPerShare,
          _canaryPrizeCountFractional(_numberOfTiers),
          canaryShares
        );
      } else {
        prizeSize = _computePrizeSize(
          _tierPrizeTokenPerShare,
          _prizeTokenPerShare,
          toUD60x18(TierCalculationLib.prizeCount(_tier)),
          tierShares
        );
      }
    }
    return prizeSize;
  }

  /// @notice Computes the prize size with the given parameters
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
      fromUD60x18(
        _prizeTokenPerShare.sub(_tierPrizeTokenPerShare).mul(toUD60x18(_shares)).div(
          _fractionalPrizeCount
        )
      );
  }

  function _isCanaryTier(uint8 _tier, uint8 _numberOfTiers) internal pure returns (bool) {
    return _tier == _numberOfTiers - 1;
  }

  /// @notice Reclaims liquidity from tiers, starting at the highest tier
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
    // if we are expanding, need to reset the canary tier and all of the new tiers
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
      uint8 shares = _computeShares(i, _numberOfTiers);
      UD60x18 liq = _getTierRemainingLiquidity(
        shares,
        fromUD34x4toUD60x18(tierLiquidity.prizeTokenPerShare),
        _prizeTokenPerShare
      );
      reclaimedLiquidity = reclaimedLiquidity.add(liq);
    }
    return fromUD60x18(reclaimedLiquidity);
  }

  /// @notice Computes the remaining liquidity available to a tier
  /// @param _tier The tier to compute the liquidity for
  /// @return The remaining liquidity
  function getTierRemainingLiquidity(uint8 _tier) external view returns (uint256) {
    uint8 _numTiers = numberOfTiers;
    return
      fromUD60x18(
        _getTierRemainingLiquidity(
          _computeShares(_tier, _numTiers),
          fromUD34x4toUD60x18(_getTier(_tier, _numTiers).prizeTokenPerShare),
          fromUD34x4toUD60x18(prizeTokenPerShare)
        )
      );
  }

  /// @notice Computes the remaining tier liquidity
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
    return delta.mul(toUD60x18(_shares));
  }

  /// @notice Retrieves the id of the next draw to be completed.
  /// @return The next draw id
  function getNextDrawId() external view returns (uint16) {
    return lastCompletedDrawId + 1;
  }

  /// @notice Estimates the number of prizes that will be awarded
  /// @return The estimated prize count
  function estimatedPrizeCount() external view returns (uint32) {
    return _estimatedPrizeCount(numberOfTiers);
  }

  /// @notice Estimates the number of prizes that will be awarded given a number of tiers.
  /// @param numTiers The number of tiers
  /// @return The estimated prize count for the given number of tiers
  function estimatedPrizeCount(uint8 numTiers) external pure returns (uint32) {
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
  function _estimatedPrizeCount(uint8 numTiers) internal pure returns (uint32) {
    if (numTiers == 3) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS;
    } else if (numTiers == 4) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
    } else if (numTiers == 5) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
    } else if (numTiers == 6) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
    } else if (numTiers == 7) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
    } else if (numTiers == 8) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
    } else if (numTiers == 9) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
    } else if (numTiers == 10) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
    } else if (numTiers == 11) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
    } else if (numTiers == 12) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;
    } else if (numTiers == 13) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS;
    } else if (numTiers == 14) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS;
    } else if (numTiers == 15) {
      return ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS;
    }
    return 0;
  }

  /// @notice Computes the canary prize count for the given number of tiers
  /// @param numTiers The number of prize tiers
  /// @return The fractional canary prize count
  function _canaryPrizeCountFractional(uint8 numTiers) internal view returns (UD60x18) {
    if (numTiers == 3) {
      return CANARY_PRIZE_COUNT_FOR_2_TIERS;
    } else if (numTiers == 4) {
      return CANARY_PRIZE_COUNT_FOR_3_TIERS;
    } else if (numTiers == 5) {
      return CANARY_PRIZE_COUNT_FOR_4_TIERS;
    } else if (numTiers == 6) {
      return CANARY_PRIZE_COUNT_FOR_5_TIERS;
    } else if (numTiers == 7) {
      return CANARY_PRIZE_COUNT_FOR_6_TIERS;
    } else if (numTiers == 8) {
      return CANARY_PRIZE_COUNT_FOR_7_TIERS;
    } else if (numTiers == 9) {
      return CANARY_PRIZE_COUNT_FOR_8_TIERS;
    } else if (numTiers == 10) {
      return CANARY_PRIZE_COUNT_FOR_9_TIERS;
    } else if (numTiers == 11) {
      return CANARY_PRIZE_COUNT_FOR_10_TIERS;
    } else if (numTiers == 12) {
      return CANARY_PRIZE_COUNT_FOR_11_TIERS;
    } else if (numTiers == 13) {
      return CANARY_PRIZE_COUNT_FOR_12_TIERS;
    } else if (numTiers == 14) {
      return CANARY_PRIZE_COUNT_FOR_13_TIERS;
    } else if (numTiers == 15) {
      return CANARY_PRIZE_COUNT_FOR_14_TIERS;
    }
    return ud(0);
  }

  /// @notice Computes the odds for a tier given the number of tiers
  /// @param _tier The tier to compute odds for
  /// @param _numTiers The number of prize tiers
  /// @return The odds of the tier
  function getTierOdds(uint8 _tier, uint8 _numTiers) external pure returns (SD59x18) {
    return _tierOdds(_tier, _numTiers);
  }

  /// @notice Computes the odds for a tier given the number of tiers
  /// @param _tier The tier to compute odds for
  /// @param _numTiers The number of prize tiers
  /// @return The odds of the tier
  function _tierOdds(uint8 _tier, uint8 _numTiers) internal pure returns (SD59x18) {
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
    } else if (_numTiers == 11) {
      if (_tier == 0) return TIER_ODDS_0_11;
      else if (_tier == 1) return TIER_ODDS_1_11;
      else if (_tier == 2) return TIER_ODDS_2_11;
      else if (_tier == 3) return TIER_ODDS_3_11;
      else if (_tier == 4) return TIER_ODDS_4_11;
      else if (_tier == 5) return TIER_ODDS_5_11;
      else if (_tier == 6) return TIER_ODDS_6_11;
      else if (_tier == 7) return TIER_ODDS_7_11;
      else if (_tier == 8) return TIER_ODDS_8_11;
      else if (_tier == 9) return TIER_ODDS_9_11;
      else if (_tier == 10) return TIER_ODDS_10_11;
    } else if (_numTiers == 12) {
      if (_tier == 0) return TIER_ODDS_0_12;
      else if (_tier == 1) return TIER_ODDS_1_12;
      else if (_tier == 2) return TIER_ODDS_2_12;
      else if (_tier == 3) return TIER_ODDS_3_12;
      else if (_tier == 4) return TIER_ODDS_4_12;
      else if (_tier == 5) return TIER_ODDS_5_12;
      else if (_tier == 6) return TIER_ODDS_6_12;
      else if (_tier == 7) return TIER_ODDS_7_12;
      else if (_tier == 8) return TIER_ODDS_8_12;
      else if (_tier == 9) return TIER_ODDS_9_12;
      else if (_tier == 10) return TIER_ODDS_10_12;
      else if (_tier == 11) return TIER_ODDS_11_12;
    } else if (_numTiers == 13) {
      if (_tier == 0) return TIER_ODDS_0_13;
      else if (_tier == 1) return TIER_ODDS_1_13;
      else if (_tier == 2) return TIER_ODDS_2_13;
      else if (_tier == 3) return TIER_ODDS_3_13;
      else if (_tier == 4) return TIER_ODDS_4_13;
      else if (_tier == 5) return TIER_ODDS_5_13;
      else if (_tier == 6) return TIER_ODDS_6_13;
      else if (_tier == 7) return TIER_ODDS_7_13;
      else if (_tier == 8) return TIER_ODDS_8_13;
      else if (_tier == 9) return TIER_ODDS_9_13;
      else if (_tier == 10) return TIER_ODDS_10_13;
      else if (_tier == 11) return TIER_ODDS_11_13;
      else if (_tier == 12) return TIER_ODDS_12_13;
    } else if (_numTiers == 14) {
      if (_tier == 0) return TIER_ODDS_0_14;
      else if (_tier == 1) return TIER_ODDS_1_14;
      else if (_tier == 2) return TIER_ODDS_2_14;
      else if (_tier == 3) return TIER_ODDS_3_14;
      else if (_tier == 4) return TIER_ODDS_4_14;
      else if (_tier == 5) return TIER_ODDS_5_14;
      else if (_tier == 6) return TIER_ODDS_6_14;
      else if (_tier == 7) return TIER_ODDS_7_14;
      else if (_tier == 8) return TIER_ODDS_8_14;
      else if (_tier == 9) return TIER_ODDS_9_14;
      else if (_tier == 10) return TIER_ODDS_10_14;
      else if (_tier == 11) return TIER_ODDS_11_14;
      else if (_tier == 12) return TIER_ODDS_12_14;
      else if (_tier == 13) return TIER_ODDS_13_14;
    } else if (_numTiers == 15) {
      if (_tier == 0) return TIER_ODDS_0_15;
      else if (_tier == 1) return TIER_ODDS_1_15;
      else if (_tier == 2) return TIER_ODDS_2_15;
      else if (_tier == 3) return TIER_ODDS_3_15;
      else if (_tier == 4) return TIER_ODDS_4_15;
      else if (_tier == 5) return TIER_ODDS_5_15;
      else if (_tier == 6) return TIER_ODDS_6_15;
      else if (_tier == 7) return TIER_ODDS_7_15;
      else if (_tier == 8) return TIER_ODDS_8_15;
      else if (_tier == 9) return TIER_ODDS_9_15;
      else if (_tier == 10) return TIER_ODDS_10_15;
      else if (_tier == 11) return TIER_ODDS_11_15;
      else if (_tier == 12) return TIER_ODDS_12_15;
      else if (_tier == 13) return TIER_ODDS_13_15;
      else if (_tier == 14) return TIER_ODDS_14_15;
    } else if (_numTiers == 16) {
      if (_tier == 0) return TIER_ODDS_0_16;
      else if (_tier == 1) return TIER_ODDS_1_16;
      else if (_tier == 2) return TIER_ODDS_2_16;
      else if (_tier == 3) return TIER_ODDS_3_16;
      else if (_tier == 4) return TIER_ODDS_4_16;
      else if (_tier == 5) return TIER_ODDS_5_16;
      else if (_tier == 6) return TIER_ODDS_6_16;
      else if (_tier == 7) return TIER_ODDS_7_16;
      else if (_tier == 8) return TIER_ODDS_8_16;
      else if (_tier == 9) return TIER_ODDS_9_16;
      else if (_tier == 10) return TIER_ODDS_10_16;
      else if (_tier == 11) return TIER_ODDS_11_16;
      else if (_tier == 12) return TIER_ODDS_12_16;
      else if (_tier == 13) return TIER_ODDS_13_16;
      else if (_tier == 14) return TIER_ODDS_14_16;
      else if (_tier == 15) return TIER_ODDS_15_16;
    }
    return sd(0);
  }
}
