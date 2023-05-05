// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { Multicall } from "openzeppelin/utils/Multicall.sol";
import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud, toUD60x18, fromUD60x18, intoSD59x18 } from "prb-math/UD60x18.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { Manageable } from "owner-manager-contracts/Manageable.sol";
import { Ownable } from "owner-manager-contracts/Ownable.sol";
import { UD34x4, fromUD60x18 as fromUD60x18toUD34x4, intoUD60x18 as fromUD34x4toUD60x18, toUD34x4 } from "./libraries/UD34x4.sol";

import { TwabController } from "v5-twab-controller/TwabController.sol";
import { DrawAccumulatorLib, Observation } from "./libraries/DrawAccumulatorLib.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";
import { BitLib } from "./libraries/BitLib.sol";

/**
 * @title PoolTogether V5 Prize Pool
 * @author PoolTogether Inc Team
 * @notice The Prize Pool holds the prize liquidity and allows vaults to claim prizes.
 */
contract PrizePool is Manageable, Multicall {

    /// @notice Emitted when someone tries to withdraw too many rewards
    error InsufficientRewardsError(uint256 requested, uint256 available);

    struct ClaimRecord {
        uint32 drawId;
        uint8 claimedTiers;
    }

    /// @notice Emitted when a prize is claimed.
    /// @param drawId The draw ID of the draw that was claimed.
    /// @param vault The address of the vault that claimed the prize.
    /// @param winner The address of the winner
    /// @param tier The prize tier that was claimed.
    /// @param payout The amount of prize tokens that were paid out to the winner
    /// @param to The address that the prize tokens were sent to
    /// @param fee The amount of prize tokens that were paid to the claimer
    /// @param feeRecipient The address that the claim fee was sent to
    event ClaimedPrize(
        uint32 indexed drawId,
        address indexed vault,
        address indexed winner,
        uint8 tier,
        uint152 payout,
        address to,
        uint96 fee,
        address feeRecipient
    );

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

    /// @notice The DrawAccumulator that tracks the exponential moving average of the contributions by a vault
    mapping(address => DrawAccumulatorLib.Accumulator) internal vaultAccumulator;

    struct TierLiquidity {
        uint32 drawId;
        uint96 prizeSize;
        UD34x4 prizeTokenPerShare;
    }

    mapping(uint8 => TierLiquidity) internal _tierLiquidity;

    /// @notice Records the claim record for a winner
    mapping(address => ClaimRecord) internal claimRecords;

    /// @notice Tracks the total fees accrued to each claimer
    mapping(address => uint256) internal claimerRewards;

    /// @notice The degree of POOL contribution smoothing. 0 = no smoothing, ~1 = max smoothing. Smoothing spreads out vault contribution over multiple draws; the higher the smoothing the more draws.
    SD1x18 public immutable smoothing;

    /// @notice The token that is being contributed and awarded as prizes
    IERC20 public immutable prizeToken;

    /// @notice The number of draws that should statistically occur between grand prizes.
    uint32 public immutable grandPrizePeriodDraws;

    /// @notice The Twab Controller to use to retrieve historic balances.
    TwabController public immutable twabController;

    /// @notice The number of shares to allocate to each prize tier
    uint8 public immutable tierShares;

    /// @notice The number of shares to allocate to the canary tier
    uint8 public immutable canaryShares;

    /// @notice The number of shares to allocate to the reserve
    uint8 public immutable reserveShares;

    /// @notice The number of seconds between draws
    uint32 public immutable drawPeriodSeconds;

    // percentage of prizes that must be claimed to bump the number of tiers
    // 64 bits
    UD2x18 public immutable claimExpansionThreshold;

    uint256 internal _totalClaimedPrizes;

    /// @notice The current number of prize tokens per share
    UD34x4 public prizeTokenPerShare;

    /// @notice The amount of available reserve
    uint256 internal _reserve;

    /// @notice The winner random number for the last completed draw
    uint256 internal _winningRandomNumber;

    /// @notice The number of tiers for the last completed draw
    uint8 public numberOfTiers;

    /// @notice The number of prize claims for the last completed draw
    uint32 public claimCount;

    /// @notice The number of canary prize claims for the last completed draw
    uint32 public canaryClaimCount;

    /// @notice The largest tier claimed so far for the last completed draw
    uint8 public largestTierClaimed;

    /// @notice The exponential weighted average of all vault contributions
    DrawAccumulatorLib.Accumulator internal totalAccumulator;

    /// @notice The draw id of the last completed draw
    uint32 internal lastCompletedDrawId;

    /// @notice The timestamp at which the last completed draw started
    uint64 internal lastCompletedDrawStartedAt_;

    /**
     * @notice Constructs a new Prize Pool
     * @param _prizeToken The token to use for prizes
     * @param _twabController The Twab Controller retrieve time-weighted average balances from
     * @param _grandPrizePeriodDraws The average number of draws between grand prizes. This determines the statistical frequency of grand prizes.
     * @param _drawPeriodSeconds The number of seconds between draws. E.g. a Prize Pool with a daily draw should have a draw period of 86400 seconds.
     * @param nextDrawStartsAt_ The timestamp at which the first draw will start.
     * @param _numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
     * @param _tierShares The number of shares to allocate to each tier
     * @param _canaryShares The number of shares to allocate to the canary tier.
     * @param _reserveShares The number of shares to allocate to the reserve.
     * @param _claimExpansionThreshold The percentage of prizes that must be claimed to bump the number of tiers. This threshold is used for both standard prizes and canary prizes.
     * @param _smoothing The amount of smoothing to apply to vault contributions. Must be less than 1. A value of 0 is no smoothing, while greater values smooth until approaching infinity
     */
    constructor (
        IERC20 _prizeToken,
        TwabController _twabController,
        uint32 _grandPrizePeriodDraws,
        uint32 _drawPeriodSeconds,
        uint64 nextDrawStartsAt_,
        uint8 _numberOfTiers,
        uint8 _tierShares,
        uint8 _canaryShares,
        uint8 _reserveShares,
        UD2x18 _claimExpansionThreshold,
        SD1x18 _smoothing
    ) Ownable(msg.sender) {
        prizeToken = _prizeToken;
        twabController = _twabController;
        grandPrizePeriodDraws = _grandPrizePeriodDraws;
        numberOfTiers = _numberOfTiers;
        tierShares = _tierShares;
        canaryShares = _canaryShares;
        reserveShares = _reserveShares;
        smoothing = _smoothing;
        claimExpansionThreshold = _claimExpansionThreshold;
        drawPeriodSeconds = _drawPeriodSeconds;
        lastCompletedDrawStartedAt_ = nextDrawStartsAt_;

        require(numberOfTiers >= MINIMUM_NUMBER_OF_TIERS, "num-tiers-gt-1");
        require(unwrap(_smoothing) < unwrap(UNIT), "smoothing-lt-1");

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

    /// @notice Returns the winning random number for the last completed draw
    /// @return The winning random number
    function getWinningRandomNumber() external view returns (uint256) {
        return _winningRandomNumber;
    }

    /// @notice Returns the last completed draw id
    /// @return The last completed draw id
    function getLastCompletedDrawId() external view returns (uint256) {
        return lastCompletedDrawId;
    }

    /// @notice Returns the total prize tokens contributed between the given draw ids, inclusive. Note that this is after smoothing is applied.
    /// @return The total prize tokens contributed by all vaults
    function getTotalContributedBetween(uint32 _startDrawIdInclusive, uint32 _endDrawIdInclusive) external view returns (uint256) {
        return DrawAccumulatorLib.getDisbursedBetween(totalAccumulator, _startDrawIdInclusive, _endDrawIdInclusive, smoothing.intoSD59x18());
    }

    /// @notice Returns the total prize tokens contributed by a particular vault between the given draw ids, inclusive. Note that this is after smoothing is applied.
    /// @return The total prize tokens contributed by the given vault
    function getContributedBetween(address _vault, uint32 _startDrawIdInclusive, uint32 _endDrawIdInclusive) external view returns (uint256) {
        return DrawAccumulatorLib.getDisbursedBetween(vaultAccumulator[_vault], _startDrawIdInclusive, _endDrawIdInclusive, smoothing.intoSD59x18());
    }

    /// @notice Returns the 
    /// @return The number of draws 
    function getTierAccrualDurationInDraws(uint8 _tier) external view returns (uint32) {
        return uint32(TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriodDraws));
    }

    /// @notice Returns the estimated number of prizes for the given tier
    /// @return The estimated number of prizes
    function getTierPrizeCount(uint8 _tier) external pure returns (uint256) {
        return TierCalculationLib.prizeCount(_tier);
    }

    /// @notice Contributes prize tokens on behalf of the given vault. The tokens should have already been transferred to the prize pool.
    /// The prize pool balance will be checked to ensure there is at least the given amount to deposit.
    /// @return The amount of available prize tokens prior to the contribution.
    function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns(uint256) {
        uint256 _deltaBalance = prizeToken.balanceOf(address(this)) - _accountedBalance();
        require(_deltaBalance >=  _amount, "PP/deltaBalance-gte-amount");
        DrawAccumulatorLib.add(vaultAccumulator[_prizeVault], _amount, lastCompletedDrawId + 1, smoothing.intoSD59x18());
        DrawAccumulatorLib.add(totalAccumulator, _amount, lastCompletedDrawId + 1, smoothing.intoSD59x18());
        return _deltaBalance;
    }

    /// @notice Computes how many tokens have been accounted for
    /// @return The balance of tokens that have been accounted for
    function _accountedBalance() internal view returns (uint256) {
        Observation memory obs = DrawAccumulatorLib.newestObservation(totalAccumulator);
        return (obs.available + obs.disbursed) - _totalClaimedPrizes;
    }

    /// @notice The total amount of prize tokens that have been claimed for all time
    /// @return The total amount of prize tokens that have been claimed for all time
    function totalClaimedPrizes() external view returns (uint256) {
        return _totalClaimedPrizes;
    }

    /// @notice Computes how many tokens have been accounted for
    /// @return The balance of tokens that have been accounted for
    function accountedBalance() external view returns (uint256) {
        return _accountedBalance();
    }

    /// @notice Retrieves the id of the next draw to be completed.
    /// @return The next draw id
    function getNextDrawId() external view returns (uint256) {
        return uint256(lastCompletedDrawId) + 1;
    }

    /// @notice Returns the start time of the last completed draw. If there was no completed draw, then it will be zero.
    /// @return The start time of the last completed draw
    function lastCompletedDrawStartedAt() external view returns (uint64) {
        if (lastCompletedDrawId != 0) {
            return lastCompletedDrawStartedAt_;
        } else {
            return 0;
        }
    }

    /// @notice Returns the balance of the reserve
    /// @return The amount of tokens that have been reserved.
    function reserve() external view returns (uint256) {
        return _reserve;
    }

    /// @notice Allows the Manager to withdraw tokens from the reserve
    /// @param _to The address to send the tokens to
    /// @param _amount The amount of tokens to withdraw
    function withdrawReserve(address _to, uint256 _amount) external onlyManager {
        require(_amount <= _reserve, "insuff");
        _reserve -= _amount;
        prizeToken.transfer(_to, _amount);
    }

    /// @notice Returns whether the next draw has finished
    function hasNextDrawFinished() external view returns (bool) {
        return block.timestamp >= _nextDrawEndsAt();
    }

    /// @notice Returns the start time of the draw for the next successful completeAndStartNextDraw
    function nextDrawStartsAt() external view returns (uint64) {
        return _nextDrawStartsAt();
    }

    /// @notice Returns the time at which the next draw ends
    function nextDrawEndsAt() external view returns (uint64) {
        return _nextDrawEndsAt();
    }

    /// @notice Returns the start time of the draw for the next successful completeAndStartNextDraw
    function _nextDrawStartsAt() internal view returns (uint64) {
        if (lastCompletedDrawId != 0) {
            return lastCompletedDrawStartedAt_ + drawPeriodSeconds;
        } else {
            return lastCompletedDrawStartedAt_;
        }
    }

    /// @notice Returns the time at which the next draw end.
    function _nextDrawEndsAt() internal view returns (uint64) {
        if (lastCompletedDrawId != 0) {
            return lastCompletedDrawStartedAt_ + 2 * drawPeriodSeconds;
        } else {
            return lastCompletedDrawStartedAt_ + drawPeriodSeconds;
        }
    }

    function _computeNextNumberOfTiers(uint8 _numTiers) internal returns (uint8) {
        uint8 nextNumberOfTiers = largestTierClaimed > MINIMUM_NUMBER_OF_TIERS ? largestTierClaimed + 1 : MINIMUM_NUMBER_OF_TIERS;
        if (nextNumberOfTiers >= _numTiers) { // check to see if we need to expand the number of tiers
            if (canaryClaimCount >= _canaryClaimExpansionThreshold(claimExpansionThreshold, _numTiers) &&
                claimCount >= _prizeClaimExpansionThreshold(claimExpansionThreshold, _numTiers)) {
                // increase the number of tiers to include a new tier
                nextNumberOfTiers = _numTiers + 1;
            }
        }
        return nextNumberOfTiers;
    }

    /// @notice Allows the Manager to complete the current prize period and starts the next one, updating the number of tiers, the winning random number, and the prize pool reserve
    /// @param winningRandomNumber_ The winning random number for the current draw
    /// @return The ID of the completed draw
    function completeAndStartNextDraw(uint256 winningRandomNumber_) external onlyManager returns (uint32) {
        // check winning random number
        require(winningRandomNumber_ != 0, "num invalid");
        uint64 nextDrawStartsAt_ = _nextDrawStartsAt();
        require(block.timestamp >= _nextDrawEndsAt(), "not elapsed");

        uint8 numTiers = numberOfTiers;
        uint32 completedDrawId = lastCompletedDrawId + 1;
        UD60x18 _prizeTokenPerShare = fromUD34x4toUD60x18(prizeTokenPerShare);
        uint8 nextNumberOfTiers = numTiers;
        if (lastCompletedDrawId != 0) {
            nextNumberOfTiers = _computeNextNumberOfTiers(numTiers);
        }

        // console2.log("nextNumberOfTiers", nextNumberOfTiers);
        uint256 totalShares = _getTotalShares(nextNumberOfTiers);
        // console2.log("totalShares", totalShares);
        (UD60x18 deltaPrizeTokensPerShare, UD60x18 remainder) = _computeDrawDeltaExchangeRate(toUD60x18(totalShares), toUD60x18(_contributionsForDraw(completedDrawId)));

        // console2.log("deltaPrizeTokensPerShare", deltaPrizeTokensPerShare.unwrap());
        // console2.log("remainder", remainder.unwrap());
        uint256 reclaimedLiquidity = _reclaimLiquidity(numTiers, nextNumberOfTiers, _prizeTokenPerShare);
        UD60x18 newPrizeTokenPerShare = _prizeTokenPerShare.add(deltaPrizeTokensPerShare);

        // Set canary tier
        _tierLiquidity[nextNumberOfTiers] = TierLiquidity({
            drawId: completedDrawId,
            prizeTokenPerShare: prizeTokenPerShare,
            prizeSize: uint96(_computePrizeSize(nextNumberOfTiers, nextNumberOfTiers, _prizeTokenPerShare, newPrizeTokenPerShare))
        });
        
        // console2.log("newPrizeTokenPerShare", newPrizeTokenPerShare.unwrap());

        uint256 reservePortion = fromUD60x18(deltaPrizeTokensPerShare.mul(toUD60x18(reserveShares)));

        prizeTokenPerShare = fromUD60x18toUD34x4(newPrizeTokenPerShare);
        _winningRandomNumber = winningRandomNumber_;
        numberOfTiers = nextNumberOfTiers;
        lastCompletedDrawId = completedDrawId;
        claimCount = 0;
        canaryClaimCount = 0;
        largestTierClaimed = 0;
        lastCompletedDrawStartedAt_ = nextDrawStartsAt_;
        // reserve += portion of contribution, reclaimed, plus any left over
        _reserve += reservePortion + reclaimedLiquidity + fromUD60x18(remainder);

        return lastCompletedDrawId;
    }

    /// @notice Reclaims liquidity from tiers, starting at the highest tier
    /// @param _numberOfTiers The existing number of tiers
    /// @param _nextNumberOfTiers The next number of tiers. Must be less than _numberOfTiers
    /// @return The total reclaimed liquidity
    function _reclaimLiquidity(uint8 _numberOfTiers, uint8 _nextNumberOfTiers, UD60x18 _prizeTokenPerShare) internal view returns (uint256) {
        UD60x18 reclaimedLiquidity;
        for (uint8 i = _nextNumberOfTiers; i < _numberOfTiers; i++) {
            TierLiquidity memory tierLiquidity = _tierLiquidity[i];
            reclaimedLiquidity = reclaimedLiquidity.add(_getRemainingTierLiquidity(i, tierShares, fromUD34x4toUD60x18(_tierLiquidity[i].prizeTokenPerShare), _prizeTokenPerShare));
        }
        reclaimedLiquidity = reclaimedLiquidity.add(_getRemainingTierLiquidity(_numberOfTiers, canaryShares, fromUD34x4toUD60x18(_tierLiquidity[_numberOfTiers].prizeTokenPerShare), _prizeTokenPerShare));
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

    function _contributionsForDraw(uint32 _drawId) internal view returns (uint256) {
        return DrawAccumulatorLib.getDisbursedBetween(totalAccumulator, _drawId, _drawId, smoothing.intoSD59x18());
    }

    /// @notice Computes the number of canary prizes that must be claimed to trigger the threshold
    /// @return The number of canary prizes
    function _canaryClaimExpansionThreshold(UD2x18 _claimExpansionThreshold, uint8 _numberOfTiers) internal view returns (uint256) {
        return fromUD60x18(intoUD60x18(_claimExpansionThreshold).mul(_canaryPrizeCountFractional(_numberOfTiers).floor()));
    }

    /// @notice Computes the number of prizes that must be claimed to trigger the threshold
    /// @return The number of prizes
    function _prizeClaimExpansionThreshold(UD2x18 _claimExpansionThreshold, uint8 _numberOfTiers) internal view returns (uint256) {
        return fromUD60x18(intoUD60x18(_claimExpansionThreshold).mul(toUD60x18(_estimatedPrizeCount(_numberOfTiers))));
    }

    /// @notice Calculates the total liquidity available for the current completed draw.
    function getTotalContributionsForCompletedDraw() external view returns (uint256) {
        return _contributionsForDraw(lastCompletedDrawId);
    }

    /**
        @dev Claims a prize for a given winner and tier.
        This function takes in an address _winner, a uint8 _tier, an address _to, a uint96 _fee, and an
        address _feeRecipient. It checks if _winner is actually the winner of the _tier for the calling vault.
        If so, it calculates the prize size and transfers it to _to. If not, it reverts with an error message.
        The function then checks the claim record of _winner to see if they have already claimed the prize for the
        current draw. If not, it updates the claim record with the claimed tier and emits a ClaimedPrize event with
        information about the claim.
        Note that this function can modify the state of the contract by updating the claim record, changing the largest
        tier claimed and the claim count, and transferring prize tokens. The function is marked as external which
        means that it can be called from outside the contract.
        @param _winner The address of the winner to claim the prize for.
        @param _tier The tier of the prize to be claimed.
        @param _to The address that the prize will be transferred to.
        @param _fee The fee associated with claiming the prize.
        @param _feeRecipient The address to receive the fee.
        @return The total prize size of the claimed prize. prize size = payout to winner + fee
    */
    function claimPrize(
        address _winner,
        uint8 _tier,
        address _to,
        uint96 _fee,
        address _feeRecipient
    ) external returns (uint256) {
        address _vault = msg.sender;
        if (!_isWinner(_vault, _winner, _tier)) {
            revert("did not win");
        }
        TierLiquidity memory tierLiquidity = _computeTierLiquidity(_tier, numberOfTiers, lastCompletedDrawId, fromUD34x4toUD60x18(prizeTokenPerShare));
        uint96 prizeSize = tierLiquidity.prizeSize;
        ClaimRecord memory claimRecord = claimRecords[_winner];
        if (claimRecord.drawId != lastCompletedDrawId) {
            claimRecord = ClaimRecord({drawId: lastCompletedDrawId, claimedTiers: uint8(0)});
        } else if (BitLib.getBit(claimRecord.claimedTiers, _tier)) {
            return 0;
        }
        require(_fee <= prizeSize, "fee too large");
        _totalClaimedPrizes += prizeSize;
        uint96 payout = prizeSize - _fee;
        if (largestTierClaimed < _tier) {
            largestTierClaimed = _tier;
        }
        uint96 shares;
        if (_tier == numberOfTiers) {
            canaryClaimCount++;
            shares = canaryShares;
        } else {
            claimCount++;
            shares = tierShares;
        }
        claimRecords[_winner] = ClaimRecord({drawId: lastCompletedDrawId, claimedTiers: uint8(BitLib.flipBit(claimRecord.claimedTiers, _tier))});
        tierLiquidity.prizeTokenPerShare = UD34x4.wrap(UD34x4.unwrap(tierLiquidity.prizeTokenPerShare) + UD34x4.unwrap(toUD34x4(prizeSize)) / shares);
        _tierLiquidity[_tier] = tierLiquidity;
        prizeToken.transfer(_to, payout);
        if (_fee > 0) {
            claimerRewards[_feeRecipient] += _fee;
        }
        emit ClaimedPrize(lastCompletedDrawId, _vault, _winner, _tier, uint152(payout), _to, _fee, _feeRecipient);
        return prizeSize;
    }

    function _computeTierLiquidity(uint8 _tier, uint8 _numberOfTiers, uint32 _lastCompletedDrawId, UD60x18 _prizeTokenPerShare) internal view returns (TierLiquidity memory) {
        TierLiquidity memory tierLiquidity = _tierLiquidity[_tier];
        if (tierLiquidity.drawId != _lastCompletedDrawId) {
            tierLiquidity.drawId = _lastCompletedDrawId;
            tierLiquidity.prizeSize = uint96(_computePrizeSize(_tier, _numberOfTiers, fromUD34x4toUD60x18(tierLiquidity.prizeTokenPerShare), _prizeTokenPerShare));
        }
        return tierLiquidity;
    }

    function _computePrizeSize(uint8 _tier, uint8 _numberOfTiers, UD60x18 _tierPrizeTokenPerShare, UD60x18 _prizeTokenPerShare) internal view returns (uint256) {
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

    /**
    * @notice Withdraws the claim fees for the caller.
    * @param _to The address to transfer the claim fees to.
    * @param _amount The amount of claim fees to withdraw
    */
    function withdrawClaimRewards(address _to, uint256 _amount) external {
        uint256 available = claimerRewards[msg.sender];
        if (_amount > available) {
            revert InsufficientRewardsError(_amount, available);
        }
        claimerRewards[msg.sender] -= _amount;
        prizeToken.transfer(_to, _amount);
    }

    /**
    * @notice Returns the balance of fees for a given claimer
    * @param _claimer The claimer to retrieve the fee balance for
    * @return The balance of fees for the given claimer
    */
    function balanceOfClaimRewards(address _claimer) external view returns (uint256) {
        return claimerRewards[_claimer];
    }

    /**
    * @notice Checks if the given user has won the prize for the specified tier in the given vault.
    * @param _vault The address of the vault to check.
    * @param _user The address of the user to check for the prize.
    * @param _tier The tier for which the prize is to be checked.
    * @return A boolean value indicating whether the user has won the prize or not.
    */
    function isWinner(
        address _vault,
        address _user,
        uint8 _tier
    ) external view returns (bool) {
        return _isWinner(_vault, _user, _tier);
    }

    /**
    * @notice Checks if the given user has won the prize for the specified tier in the given vault.
    * @param _vault The address of the vault to check.
    * @param _user The address of the user to check for the prize.
    * @param _tier The tier for which the prize is to be checked.
    * @return A boolean value indicating whether the user has won the prize or not.
    */
    function _isWinner(
        address _vault,
        address _user,
        uint8 _tier
    ) internal view returns (bool) {
        require(lastCompletedDrawId > 0, "no draw");
        require(_tier <= numberOfTiers, "invalid tier");
        SD59x18 tierOdds = TierCalculationLib.getTierOdds(_tier, numberOfTiers, grandPrizePeriodDraws);
        uint256 drawDuration = TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriodDraws);
        (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, drawDuration);
        SD59x18 vaultPortion = _getVaultPortion(_vault, lastCompletedDrawId, uint32(drawDuration), smoothing.intoSD59x18());
        SD59x18 tierPrizeCount;
        if (_tier == numberOfTiers) { // then canary tier
            UD60x18 cpc = _canaryPrizeCountFractional(_tier);
            tierPrizeCount = intoSD59x18(cpc);
        } else {
            tierPrizeCount = toSD59x18(int256(TierCalculationLib.prizeCount(_tier)));
        }
        return TierCalculationLib.isWinner(_user, _tier, _userTwab, _vaultTwabTotalSupply, vaultPortion, tierOdds, tierPrizeCount, _winningRandomNumber);
    }

    /***
    * @notice Calculates the start and end timestamps of the time-weighted average balance (TWAB) for the specified tier.
    * @param _tier The tier for which to calculate the TWAB timestamps.
    * @return The start and end timestamps of the TWAB.
    */
    function calculateTierTwabTimestamps(uint8 _tier) external view returns (uint64 startTimestamp, uint64 endTimestamp) {
        uint256 drawDuration = TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriodDraws);
        endTimestamp = lastCompletedDrawStartedAt_ + drawPeriodSeconds;
        startTimestamp = uint64(endTimestamp - drawDuration * drawPeriodSeconds);
    }

    /**
    * @notice Returns the time-weighted average balance (TWAB) and the TWAB total supply for the specified user in the given vault over a specified period.
    * @dev This function calculates the TWAB for a user by calling the getAverageBalanceBetween function of the TWAB controller for a specified period of time.
    * @param _vault The address of the vault for which to get the TWAB.
    * @param _user The address of the user for which to get the TWAB.
    * @param _drawDuration The duration of the period over which to calculate the TWAB, in number of draw periods.
    * @return twab The TWAB for the specified user in the given vault over the specified period.
    * @return twabTotalSupply The TWAB total supply over the specified period.
    */
    function _getVaultUserBalanceAndTotalSupplyTwab(address _vault, address _user, uint256 _drawDuration) internal view returns (uint256 twab, uint256 twabTotalSupply) {
        uint32 endTimestamp = uint32(lastCompletedDrawStartedAt_ + drawPeriodSeconds);
        uint32 startTimestamp = uint32(endTimestamp - _drawDuration * drawPeriodSeconds);

        twab = twabController.getAverageBalanceBetween(
            _vault,
            _user,
            startTimestamp,
            endTimestamp
        );

        twabTotalSupply = twabController.getAverageTotalSupplyBetween(
            _vault,
            startTimestamp,
            endTimestamp
        );
    }

    /**
    * @notice Returns the time-weighted average balance (TWAB) and the TWAB total supply for the specified user in the given vault over a specified period.
    * @param _vault The address of the vault for which to get the TWAB.
    * @param _user The address of the user for which to get the TWAB.
    * @param _drawDuration The duration of the period over which to calculate the TWAB, in number of draw periods.
    * @return The TWAB and the TWAB total supply for the specified user in the given vault over the specified period.
    */
    function getVaultUserBalanceAndTotalSupplyTwab(address _vault, address _user, uint256 _drawDuration) external view returns (uint256, uint256) {
        return _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, _drawDuration);
    }

    /**
    * @notice Calculates the portion of the vault's contribution to the prize pool over a specified duration in draws.
    * @param _vault The address of the vault for which to calculate the portion.
    * @param drawId_ The draw ID for which to calculate the portion.
    * @param _durationInDraws The duration of the period over which to calculate the portion, in number of draws.
    * @param _smoothing The smoothing value to use for calculating the portion.
    * @return The portion of the vault's contribution to the prize pool over the specified duration in draws.
    */
    function _getVaultPortion(address _vault, uint32 drawId_, uint32 _durationInDraws, SD59x18 _smoothing) internal view returns (SD59x18) {
        uint32 _startDrawIdIncluding = uint32(_durationInDraws > drawId_ ? 0 : drawId_-_durationInDraws+1);
        uint32 _endDrawIdExcluding = drawId_ + 1;
        uint256 vaultContributed = DrawAccumulatorLib.getDisbursedBetween(vaultAccumulator[_vault], _startDrawIdIncluding, _endDrawIdExcluding, _smoothing);
        uint256 totalContributed = DrawAccumulatorLib.getDisbursedBetween(totalAccumulator, _startDrawIdIncluding, _endDrawIdExcluding, _smoothing);
        if (totalContributed != 0) {
            return sd(int256(vaultContributed)).div(sd(int256(totalContributed)));
        } else {
            return sd(0);
        }
    }

    /**
        @notice Returns the portion of a vault's contributions in a given draw range.
        This function takes in an address _vault, a uint32 startDrawId, and a uint32 endDrawId.
        It calculates the portion of the _vault's contributions in the given draw range by calling the internal
        _getVaultPortion function with the _vault argument, startDrawId as the drawId_ argument,
        endDrawId - startDrawId as the _durationInDraws argument, and smoothing.intoSD59x18() as the _smoothing
        argument. The function then returns the resulting SD59x18 value representing the portion of the
        vault's contributions.
        @param _vault The address of the vault to calculate the contribution portion for.
        @param startDrawId The starting draw ID of the draw range to calculate the contribution portion for.
        @param endDrawId The ending draw ID of the draw range to calculate the contribution portion for.
        @return The portion of the _vault's contributions in the given draw range as an SD59x18 value.
    */
    function getVaultPortion(address _vault, uint32 startDrawId, uint32 endDrawId) external view returns (SD59x18) {
        return _getVaultPortion(_vault, startDrawId, endDrawId, smoothing.intoSD59x18());
    }

    /// @notice Calculates the prize size for the given tier
    /// @param _tier The tier to calculate the prize size for
    /// @return The prize size
    function calculatePrizeSize(uint8 _tier) external view returns (uint256) {
        uint8 numTiers = numberOfTiers;
        if (lastCompletedDrawId == 0 || _tier > numTiers) {
            return 0;
        }
        TierLiquidity memory tierLiquidity = _tierLiquidity[_tier];
        return _computePrizeSize(_tier, numTiers, fromUD34x4toUD60x18(tierLiquidity.prizeTokenPerShare), fromUD34x4toUD60x18(prizeTokenPerShare));
    }

    /// @notice Computes the total liquidity available to a tier
    /// @param _tier The tier to compute the liquidity for
    /// @return The total liquidity
    function getRemainingTierLiquidity(uint8 _tier) external view returns (uint256) {
        TierLiquidity memory tierLiquidity = _tierLiquidity[_tier];
        if (UD34x4.unwrap(tierLiquidity.prizeTokenPerShare) >= UD34x4.unwrap(prizeTokenPerShare)) {
            return 0;
        }
        UD60x18 delta = fromUD34x4toUD60x18(prizeTokenPerShare).sub(fromUD34x4toUD60x18(tierLiquidity.prizeTokenPerShare));
        return fromUD60x18(delta.mul(toUD60x18(_tier == numberOfTiers ? canaryShares : tierShares)));
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
        return uint256(_numberOfTiers) * uint256(tierShares) + uint256(canaryShares) + uint256(reserveShares);
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
