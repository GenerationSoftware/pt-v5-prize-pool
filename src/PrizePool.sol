// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
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
import { TieredLiquidityDistributor, Tier } from "./abstract/TieredLiquidityDistributor.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";
import { BitLib } from "./libraries/BitLib.sol";

/// @notice Emitted when someone tries to claim a prize that was already claimed
error AlreadyClaimedPrize(address winner, uint8 tier);

/// @notice Emitted when someone tries to withdraw too many rewards
error InsufficientRewardsError(uint256 requested, uint256 available);

error DidNotWin(address winner, address vault, uint8 tier, uint32 prize);

error FeeTooLarge(uint256 fee, uint256 maxFee);

/**
 * @title PoolTogether V5 Prize Pool
 * @author PoolTogether Inc Team
 * @notice The Prize Pool holds the prize liquidity and allows vaults to claim prizes.
 */
contract PrizePool is Manageable, Multicall, TieredLiquidityDistributor {
    using SafeERC20 for IERC20;

    /// @notice Emitted when a prize is claimed.
    /// @param drawId The draw ID of the draw that was claimed.
    /// @param vault The address of the vault that claimed the prize.
    /// @param winner The address of the winner
    /// @param tier The prize tier that was claimed.
    /// @param payout The amount of prize tokens that were paid out to the winner
    /// @param fee The amount of prize tokens that were paid to the claimer
    /// @param feeRecipient The address that the claim fee was sent to
    event ClaimedPrize(
        uint32 indexed drawId,
        address indexed vault,
        address indexed winner,
        uint8 tier,
        uint152 payout,
        uint96 fee,
        address feeRecipient
    );

    /// @notice The DrawAccumulator that tracks the exponential moving average of the contributions by a vault
    mapping(address => DrawAccumulatorLib.Accumulator) internal vaultAccumulator;

    /// @notice Records the claim record for a winner
    /// @dev account => drawId => tier => prizeIndex => claimed
    mapping(address => mapping(uint32 => mapping(uint8 => mapping(uint32 => bool)))) internal claimedPrizes;

    /// @notice Tracks the total fees accrued to each claimer
    mapping(address => uint256) internal claimerRewards;

    /// @notice The degree of POOL contribution smoothing. 0 = no smoothing, ~1 = max smoothing. Smoothing spreads out vault contribution over multiple draws; the higher the smoothing the more draws.
    SD1x18 public immutable smoothing;

    /// @notice The token that is being contributed and awarded as prizes
    IERC20 public immutable prizeToken;

    /// @notice The Twab Controller to use to retrieve historic balances.
    TwabController public immutable twabController;

    /// @notice The number of seconds between draws
    uint32 public immutable drawPeriodSeconds;

    // percentage of prizes that must be claimed to bump the number of tiers
    // 64 bits
    UD2x18 public immutable claimExpansionThreshold;

    /// @notice The exponential weighted average of all vault contributions
    DrawAccumulatorLib.Accumulator internal totalAccumulator;

    uint256 internal _totalWithdrawn;

    /// @notice The winner random number for the last completed draw
    uint256 internal _winningRandomNumber;

    /// @notice The number of prize claims for the last completed draw
    uint32 public claimCount;

    /// @notice The number of canary prize claims for the last completed draw
    uint32 public canaryClaimCount;

    /// @notice The largest tier claimed so far for the last completed draw
    uint8 public largestTierClaimed;

    /// @notice The timestamp at which the last completed draw started
    uint64 internal _lastCompletedDrawStartedAt;

    /// @notice The timestamp at which the last completed draw was awarded
    uint64 internal _lastCompletedDrawAwardedAt;

    /**
     * @notice Constructs a new Prize Pool
     * @param _prizeToken The token to use for prizes
     * @param _twabController The Twab Controller retrieve time-weighted average balances from
     * @param _grandPrizePeriodDraws The average number of draws between grand prizes. This determines the statistical frequency of grand prizes.
     * @param _drawPeriodSeconds The number of seconds between draws. E.g. a Prize Pool with a daily draw should have a draw period of 86400 seconds.
     * @param _firstDrawStartsAt The timestamp at which the first draw will start.
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
        uint64 _firstDrawStartsAt,
        uint8 _numberOfTiers,
        uint8 _tierShares,
        uint8 _canaryShares,
        uint8 _reserveShares,
        UD2x18 _claimExpansionThreshold,
        SD1x18 _smoothing
    ) Ownable(msg.sender) TieredLiquidityDistributor(_grandPrizePeriodDraws, _numberOfTiers, _tierShares, _canaryShares, _reserveShares) {
        prizeToken = _prizeToken;
        twabController = _twabController;
        smoothing = _smoothing;
        claimExpansionThreshold = _claimExpansionThreshold;
        drawPeriodSeconds = _drawPeriodSeconds;
        _lastCompletedDrawStartedAt = _firstDrawStartsAt;

        require(unwrap(_smoothing) < unwrap(UNIT), "smoothing-lt-1");
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
        return (obs.available + obs.disbursed) - _totalWithdrawn;
    }

    /// @notice The total amount of prize tokens that have been claimed for all time
    /// @return The total amount of prize tokens that have been claimed for all time
    function totalWithdrawn() external view returns (uint256) {
        return _totalWithdrawn;
    }

    /// @notice Computes how many tokens have been accounted for
    /// @return The balance of tokens that have been accounted for
    function accountedBalance() external view returns (uint256) {
        return _accountedBalance();
    }

    /// @notice Returns the start time of the last completed draw. If there was no completed draw, then it will be zero.
    /// @return The start time of the last completed draw
    function lastCompletedDrawStartedAt() external view returns (uint64) {
        return lastCompletedDrawId != 0 ? _lastCompletedDrawStartedAt : 0;
    }

    /// @notice Returns the end time of the last completed draw. If there was no completed draw, then it will be zero.
    /// @return The end time of the last completed draw
    function lastCompletedDrawEndedAt() external view returns (uint64) {
        return lastCompletedDrawId != 0 ? _lastCompletedDrawStartedAt + drawPeriodSeconds : 0;
    }

    /// @notice Returns the time at which the last completed draw was awarded.
    /// @return The time at which the last completed draw was awarded
    function lastCompletedDrawAwardedAt() external view returns (uint64) {
        return lastCompletedDrawId != 0 ? _lastCompletedDrawAwardedAt : 0;
    }

    // @notice Allows the Manager to withdraw tokens from the reserve
    /// @param _to The address to send the tokens to
    /// @param _amount The amount of tokens to withdraw
    function withdrawReserve(address _to, uint104 _amount) external onlyManager {
        require(_amount <= _reserve, "insuff");
        _reserve -= _amount;
        _transfer(_to, _amount);
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
        // If this is the first draw, we treat _lastCompletedDrawStartedAt as the start of this draw
        uint64 _nextExpectedStartTime = _lastCompletedDrawStartedAt + (lastCompletedDrawId == 0 ? 0 : 1) * drawPeriodSeconds;
        uint64 _nextExpectedEndTime = _nextExpectedStartTime + drawPeriodSeconds;

        if (block.timestamp > _nextExpectedEndTime) {
            // Use integer division to get the number of draw periods passed between the expected end time and now
            // Offset the start time by the total duration of the missed draws
            // drawPeriodSeconds * numMissedDraws
            _nextExpectedStartTime += drawPeriodSeconds * (uint32((block.timestamp - _nextExpectedEndTime) / drawPeriodSeconds));
        }

        return _nextExpectedStartTime;
    }

    /// @notice Returns the time at which the next draw end.
    function _nextDrawEndsAt() internal view returns (uint64) {
        // If this is the first draw, we treat _lastCompletedDrawStartedAt as the start of this draw
        uint64 _nextExpectedEndTime = _lastCompletedDrawStartedAt + (lastCompletedDrawId == 0 ? 1 : 2) * drawPeriodSeconds;

        if (block.timestamp > _nextExpectedEndTime) {
            // Use integer division to get the number of draw periods passed between the expected end time and now
            // Offset the end time by the total duration of the missed draws
            // drawPeriodSeconds * numMissedDraws
            _nextExpectedEndTime += drawPeriodSeconds * (uint32((block.timestamp - _nextExpectedEndTime) / drawPeriodSeconds));
        }

        return _nextExpectedEndTime;
    }

    function _computeNextNumberOfTiers(uint8 _numTiers) internal view returns (uint8) {
        UD2x18 _claimExpansionThreshold = claimExpansionThreshold;
        uint8 _nextNumberOfTiers = largestTierClaimed > MINIMUM_NUMBER_OF_TIERS ? largestTierClaimed + 1 : MINIMUM_NUMBER_OF_TIERS;

        // check to see if we need to expand the number of tiers
        if (_nextNumberOfTiers >= _numTiers) {
            if (
                canaryClaimCount >= fromUD60x18(intoUD60x18(_claimExpansionThreshold).mul(_canaryPrizeCountFractional(_numTiers).floor()))&&
                claimCount >= fromUD60x18(intoUD60x18(_claimExpansionThreshold).mul(toUD60x18(_estimatedPrizeCount(_numTiers))))
            ) {
                // increase the number of tiers to include a new tier
                _nextNumberOfTiers = _numTiers + 1;
            }
        }

        return _nextNumberOfTiers;
    }

    /// @notice Allows the Manager to complete the current prize period and starts the next one, updating the number of tiers, the winning random number, and the prize pool reserve
    /// @param winningRandomNumber_ The winning random number for the current draw
    /// @return The ID of the completed draw
    function completeAndStartNextDraw(uint256 winningRandomNumber_) external onlyManager returns (uint32) {
        // check winning random number
        require(winningRandomNumber_ != 0, "num invalid");
        require(block.timestamp >= _nextDrawEndsAt(), "not elapsed");

        uint8 _numTiers = numberOfTiers;
        uint8 _nextNumberOfTiers = _numTiers;

        if (lastCompletedDrawId != 0) {
            _nextNumberOfTiers = _computeNextNumberOfTiers(_numTiers);
        }

        uint64 nextDrawStartsAt_ = _nextDrawStartsAt();

        _nextDraw(_nextNumberOfTiers, uint96(_contributionsForDraw(lastCompletedDrawId + 1)));

        _winningRandomNumber = winningRandomNumber_;
        claimCount = 0;
        canaryClaimCount = 0;
        largestTierClaimed = 0;
        _lastCompletedDrawStartedAt = nextDrawStartsAt_;
        _lastCompletedDrawAwardedAt = uint64(block.timestamp);

        return lastCompletedDrawId;
    }

    /// @notice Returns the amount of tokens that will be added to the reserve on the next draw.
    /// @dev Intended for Draw manager to use after the draw has ended but not yet been completed.
    /// @return The amount of prize tokens that will be added to the reserve
    function reserveForNextDraw() external view returns (uint256) {
        uint8 _numTiers = numberOfTiers;
        uint8 _nextNumberOfTiers = _numTiers;

        if (lastCompletedDrawId != 0) {
            _nextNumberOfTiers = _computeNextNumberOfTiers(_numTiers);
        }

        (, uint104 newReserve, ) = _computeNewDistributions(_numTiers, _nextNumberOfTiers, uint96(_contributionsForDraw(lastCompletedDrawId+1)));

        return newReserve;
    }

    /// @notice Computes the tokens to be disbursed from the accumulator for a given draw.
    function _contributionsForDraw(uint32 _drawId) internal view returns (uint256) {
        return DrawAccumulatorLib.getDisbursedBetween(totalAccumulator, _drawId, _drawId, smoothing.intoSD59x18());
    }

    /// @notice Calculates the total liquidity available for the current completed draw.
    function getTotalContributionsForCompletedDraw() external view returns (uint256) {
        return _contributionsForDraw(lastCompletedDrawId);
    }

    /// @notice Returns whether the winner has claimed the tier for the last completed draw
    /// @param _winner The account to check
    /// @param _tier The tier to check
    /// @return True if the winner claimed the tier for the current draw, false otherwise.
    function wasClaimed(address _winner, uint8 _tier, uint32 _prizeIndex) external view returns (bool) {
        return claimedPrizes[_winner][lastCompletedDrawId][_tier][_prizeIndex];
    }

    /**
        @dev Claims a prize for a given winner and tier.
        This function takes in an address _winner, a uint8 _tier, a uint96 _fee, and an
        address _feeRecipient. It checks if _winner is actually the winner of the _tier for the calling vault.
        If so, it calculates the prize size and transfers it to the winner. If not, it reverts with an error message.
        The function then checks the claim record of _winner to see if they have already claimed the prize for the
        current draw. If not, it updates the claim record with the claimed tier and emits a ClaimedPrize event with
        information about the claim.
        Note that this function can modify the state of the contract by updating the claim record, changing the largest
        tier claimed and the claim count, and transferring prize tokens. The function is marked as external which
        means that it can be called from outside the contract.
        @param _tier The tier of the prize to be claimed.
        @param _winners The address of the winners to claim the prize for.
        @param _prizeIndices The array of prizes to claim for each winner.
        @param _feePerPrizeClaim The fee associated with claiming the prize.
        @param _feeRecipient The address to receive the fee.
        @return Total prize amount claimed (payout and fees combined).
    */
    function claimPrizes(
        uint8 _tier,
        address[] calldata _winners,
        uint32[][] calldata _prizeIndices,
        uint96 _feePerPrizeClaim,
        address _feeRecipient
    ) external returns (uint256) {
        require(_winners.length == _prizeIndices.length, "length mismatch");

        Tier memory tierLiquidity = _getTier(_tier, numberOfTiers);
        if (_feePerPrizeClaim > tierLiquidity.prizeSize) {
            revert FeeTooLarge(_feePerPrizeClaim, tierLiquidity.prizeSize);
        }

        uint32 prizeClaimCount = _claimPrizes(msg.sender, _tier, _winners, _prizeIndices, tierLiquidity.prizeSize - _feePerPrizeClaim, _feePerPrizeClaim, _feeRecipient);

        if (_tier == numberOfTiers) {
            canaryClaimCount += prizeClaimCount;
        } else {
            claimCount += prizeClaimCount;
        }

        if (largestTierClaimed < _tier) {
            largestTierClaimed = _tier;
        }

        _consumeLiquidity(tierLiquidity, _tier, tierLiquidity.prizeSize * prizeClaimCount);

        if (_feePerPrizeClaim != 0 && prizeClaimCount != 0) {
            claimerRewards[_feeRecipient] += _feePerPrizeClaim * prizeClaimCount;
        }

        return tierLiquidity.prizeSize * prizeClaimCount;
    }

    function _claimPrizes(
        address _vault,
        uint8 _tier,
        address[] calldata _winners,
        uint32[][] calldata _prizeIndices,
        uint96 _payout,
        uint96 _feePerPrizeClaim,
        address _feeRecipient
    ) internal returns (uint32) {
        uint32 _prizeClaimCount = 0;
        (SD59x18 _vaultPortion, SD59x18 _tierOdds, uint32 _drawDuration) = _computeVaultTierDetails(_vault, _tier, numberOfTiers, lastCompletedDrawId);

        for (uint winnerIndex = 0; winnerIndex < _winners.length; winnerIndex++) {
            _prizeClaimCount += _claimWinnerPrizes(_vault, _tier, _winners[winnerIndex], _prizeIndices[winnerIndex], _payout, _feePerPrizeClaim, _feeRecipient, _vaultPortion, _tierOdds, _drawDuration);
        }

        return _prizeClaimCount;
    }

    function _claimWinnerPrizes(
        address _vault,
        uint8 _tier,
        address _winner,
        uint32[] calldata _prizeIndices,
        uint96 _payout,
        uint96 _feePerPrizeClaim,
        address _feeRecipient,
        SD59x18 _vaultPortion,
        SD59x18 _tierOdds,
        uint32 _drawDuration
    ) internal returns (uint32) {
        for (uint256 _prizeArrayIndex = 0; _prizeArrayIndex < _prizeIndices.length; _prizeArrayIndex++) {
            if (!_isWinner(_vault, _winner, _tier, _prizeIndices[_prizeArrayIndex], _vaultPortion, _tierOdds, _drawDuration)) {
                revert DidNotWin(_winner, _vault, _tier, _prizeIndices[_prizeArrayIndex]);
            }

            if (claimedPrizes[_winner][lastCompletedDrawId][_tier][_prizeIndices[_prizeArrayIndex]]) {
                revert AlreadyClaimedPrize(_winner, _tier);
            }

            claimedPrizes[_winner][lastCompletedDrawId][_tier][_prizeIndices[_prizeArrayIndex]] = true;
            _transfer(_winner, _payout);

            emit ClaimedPrize(lastCompletedDrawId, _vault, _winner, _tier, uint152(_payout), _feePerPrizeClaim, _feeRecipient);
        }

        return uint32(_prizeIndices.length);
    }

    function _transfer(address _to, uint256 _amount) internal {
        _totalWithdrawn += _amount;
        prizeToken.safeTransfer(_to, _amount);
    }

    /**
    * @notice Withdraws the claim fees for the caller.
    * @param _to The address to transfer the claim fees to.
    * @param _amount The amount of claim fees to withdraw
    */
    function withdrawClaimRewards(address _to, uint256 _amount) external {
        uint256 _available = claimerRewards[msg.sender];

        if (_amount > _available) {
            revert InsufficientRewardsError(_amount, _available);
        }

        claimerRewards[msg.sender] -= _amount;
        _transfer(_to, _amount);
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
        uint8 _tier,
        uint32 _prizeIndex
    ) external view returns (bool) {
        (SD59x18 vaultPortion, SD59x18 tierOdds, uint32 drawDuration) = _computeVaultTierDetails(_vault, _tier, numberOfTiers, lastCompletedDrawId);
        return _isWinner(_vault, _user, _tier, _prizeIndex, vaultPortion, tierOdds, drawDuration);
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
        uint8 _tier,
        uint32 _prizeIndex,
        SD59x18 _vaultPortion,
        SD59x18 _tierOdds,
        uint32 _drawDuration
    ) internal view returns (bool) {
        uint8 _numberOfTiers = numberOfTiers;
        uint32 tierPrizeCount = _tier != _numberOfTiers ? uint32(TierCalculationLib.prizeCount(_tier)) : _canaryPrizeCount(_numberOfTiers);

        require(_prizeIndex < tierPrizeCount, "invalid prize index");

        uint256 userSpecificRandomNumber = TierCalculationLib.calculatePseudoRandomNumber(_user, _tier, _prizeIndex, _winningRandomNumber);
        (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, _drawDuration);

        return TierCalculationLib.isWinner(userSpecificRandomNumber, uint128(_userTwab), uint128(_vaultTwabTotalSupply), _vaultPortion, _tierOdds, tierPrizeCount);
    }

    function _computeVaultTierDetails(address _vault, uint8 _tier, uint8 _numberOfTiers, uint32 _lastCompletedDrawId) internal view returns (SD59x18 vaultPortion, SD59x18 tierOdds, uint32 drawDuration) {
        require(_lastCompletedDrawId > 0, "no draw");
        require(_tier <= _numberOfTiers, "invalid tier");

        tierOdds = TierCalculationLib.getTierOdds(_tier, _numberOfTiers, grandPrizePeriodDraws);
        drawDuration = uint32(TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, _numberOfTiers, grandPrizePeriodDraws));
        vaultPortion = _getVaultPortion(
            _vault,
            uint32(drawDuration > _lastCompletedDrawId ? 0 : _lastCompletedDrawId - drawDuration + 1),
            _lastCompletedDrawId + 1,
            smoothing.intoSD59x18()
        );
    }

    /***
    * @notice Calculates the start and end timestamps of the time-weighted average balance (TWAB) for the specified tier.
    * @param _tier The tier for which to calculate the TWAB timestamps.
    * @return The start and end timestamps of the TWAB.
    */
    function calculateTierTwabTimestamps(uint8 _tier) external view returns (uint64 startTimestamp, uint64 endTimestamp) {
        endTimestamp = _lastCompletedDrawStartedAt + drawPeriodSeconds;

        // endTimestamp - (drawDuration * drawPeriodSeconds)
        startTimestamp = uint64(endTimestamp - TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriodDraws) * drawPeriodSeconds);
    }

    /**
    * @notice Returns the time-weighted average balance (TWAB) and the TWAB total supply for the specified user in the given vault over a specified period.
    * @dev This function calculates the TWAB for a user by calling the getTwabBetween function of the TWAB controller for a specified period of time.
    * @param _vault The address of the vault for which to get the TWAB.
    * @param _user The address of the user for which to get the TWAB.
    * @param _drawDuration The duration of the period over which to calculate the TWAB, in number of draw periods.
    * @return twab The TWAB for the specified user in the given vault over the specified period.
    * @return twabTotalSupply The TWAB total supply over the specified period.
    */
    function _getVaultUserBalanceAndTotalSupplyTwab(address _vault, address _user, uint256 _drawDuration) internal view returns (uint256 twab, uint256 twabTotalSupply) {
        uint32 _endTimestamp = uint32(_lastCompletedDrawStartedAt + drawPeriodSeconds);
        uint32 _startTimestamp = uint32(_endTimestamp - _drawDuration * drawPeriodSeconds);

        twab = twabController.getTwabBetween(
            _vault,
            _user,
            _startTimestamp,
            _endTimestamp
        );

        twabTotalSupply = twabController.getTotalSupplyTwabBetween(
            _vault,
            _startTimestamp,
            _endTimestamp
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
    * @param _startDrawId The starting draw ID (inclusive) of the draw range to calculate the contribution portion for.
    * @param _endDrawId The ending draw ID (inclusive) of the draw range to calculate the contribution portion for.
    * @param _smoothing The smoothing value to use for calculating the portion.
    * @return The portion of the vault's contribution to the prize pool over the specified duration in draws.
    */
    function _getVaultPortion(address _vault, uint32 _startDrawId, uint32 _endDrawId, SD59x18 _smoothing) internal view returns (SD59x18) {
        uint256 totalContributed = DrawAccumulatorLib.getDisbursedBetween(totalAccumulator, _startDrawId, _endDrawId, _smoothing);

        if (totalContributed != 0) {
            // vaultContributed / totalContributed
            return sd(int256(
                DrawAccumulatorLib.getDisbursedBetween(vaultAccumulator[_vault], _startDrawId, _endDrawId, _smoothing)
            )).div(sd(int256(totalContributed)));
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
        @param _startDrawId The starting draw ID of the draw range to calculate the contribution portion for.
        @param _endDrawId The ending draw ID of the draw range to calculate the contribution portion for.
        @return The portion of the _vault's contributions in the given draw range as an SD59x18 value.
    */
    function getVaultPortion(address _vault, uint32 _startDrawId, uint32 _endDrawId) external view returns (SD59x18) {
        return _getVaultPortion(_vault, _startDrawId, _endDrawId, smoothing.intoSD59x18());
    }

    /// @notice Calculates the prize size for the given tier
    /// @param _tier The tier to calculate the prize size for
    /// @return The prize size
    function calculatePrizeSize(uint8 _tier) external view returns (uint256) {
        uint8 _numTiers = numberOfTiers;

        if (lastCompletedDrawId == 0 || _tier > _numTiers) {
            return 0;
        }

        return _computePrizeSize(_tier, _numTiers, fromUD34x4toUD60x18(_getTier(_tier, _numTiers).prizeTokenPerShare), fromUD34x4toUD60x18(prizeTokenPerShare));
    }
}
