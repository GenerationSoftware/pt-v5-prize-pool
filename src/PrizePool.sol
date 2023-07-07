// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud, toUD60x18, fromUD60x18, intoSD59x18 } from "prb-math/UD60x18.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { UD34x4, fromUD60x18 as fromUD60x18toUD34x4, intoUD60x18 as fromUD34x4toUD60x18, toUD34x4 } from "./libraries/UD34x4.sol";

import { TwabController } from "v5-twab-controller/TwabController.sol";
import { DrawAccumulatorLib, Observation } from "./libraries/DrawAccumulatorLib.sol";
import { TieredLiquidityDistributor, Tier } from "./abstract/TieredLiquidityDistributor.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";

/// @notice Emitted when someone tries to set the draw manager.
error DrawManagerAlreadySet();

/// @notice Emitted when someone tries to claim a prize that was already claimed.
/// @param winner The winner of the prize
/// @param tier The prize tier
error AlreadyClaimedPrize(
  address vault,
  address winner,
  uint8 tier,
  uint32 prizeIndex,
  address recipient
);

/// @notice Emitted when someone tries to withdraw too many rewards.
/// @param requested The requested reward amount to withdraw
/// @param available The total reward amount available for the caller to withdraw
error InsufficientRewardsError(uint256 requested, uint256 available);

/// @notice Emitted when an address did not win the specified prize on a vault when claiming.
/// @param winner The address checked for the prize
/// @param vault The vault address
/// @param tier The prize tier
/// @param prizeIndex The prize index
error DidNotWin(address vault, address winner, uint8 tier, uint32 prizeIndex);

/// @notice Emitted when the fee being claimed is larger than the max allowed fee.
/// @param fee The fee being claimed
/// @param maxFee The max fee that can be claimed
error FeeTooLarge(uint256 fee, uint256 maxFee);

/// @notice Emitted when the initialized smoothing number is not less than one.
/// @param smoothing The unwrapped smoothing value that exceeds the limit
error SmoothingGTEOne(int64 smoothing);

/// @notice Emitted when the contributed amount is more than the available, un-accounted balance.
/// @param amount The contribution amount that is being claimed
/// @param available The available un-accounted balance that can be claimed as a contribution
error ContributionGTDeltaBalance(uint256 amount, uint256 available);

/// @notice Emitted when the withdraw amount is greater than the available reserve.
/// @param amount The amount being withdrawn
/// @param reserve The total reserve available for withdrawal
error InsufficientReserve(uint104 amount, uint104 reserve);

/// @notice Emitted when the winning random number is zero.
error RandomNumberIsZero();

/// @notice Emitted when the draw cannot be closed since it has not finished.
/// @param drawEndsAt The timestamp in seconds at which the draw ends
/// @param errorTimestamp The timestamp in seconds at which the error occured
error DrawNotFinished(uint64 drawEndsAt, uint64 errorTimestamp);

/// @notice Emitted when prize index is greater or equal to the max prize count for the tier.
/// @param invalidPrizeIndex The invalid prize index
/// @param prizeCount The prize count for the tier
/// @param tier The tier number
error InvalidPrizeIndex(uint32 invalidPrizeIndex, uint32 prizeCount, uint8 tier);

/// @notice Emitted when there are no closed draws when a computation requires a closed draw.
error NoClosedDraw();

/// @notice Emitted when attempting to claim from a tier that does not exist.
/// @param tier The tier number that does not exist
/// @param numberOfTiers The current number of tiers
error InvalidTier(uint8 tier, uint8 numberOfTiers);

/// @notice Emitted when the caller is not the draw manager.
/// @param caller The caller address
/// @param drawManager The drawManager address
error CallerNotDrawManager(address caller, address drawManager);

/**
 * @notice Constructor Parameters
 * @param prizeToken The token to use for prizes
 * @param twabController The Twab Controller to retrieve time-weighted average balances from
 * @param drawManager The address of the draw manager for the prize pool
 * @param drawPeriodSeconds The number of seconds between draws. E.g. a Prize Pool with a daily draw should have a draw period of 86400 seconds.
 * @param firstDrawStartsAt The timestamp at which the first draw will start.
 * @param numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
 * @param tierShares The number of shares to allocate to each tier
 * @param canaryShares The number of shares to allocate to the canary tier.
 * @param reserveShares The number of shares to allocate to the reserve.
 * @param claimExpansionThreshold The percentage of prizes that must be claimed to bump the number of tiers. This threshold is used for both standard prizes and canary prizes.
 * @param smoothing The amount of smoothing to apply to vault contributions. Must be less than 1. A value of 0 is no smoothing, while greater values smooth until approaching infinity
 */
struct ConstructorParams {
  IERC20 prizeToken;
  TwabController twabController;
  address drawManager;
  uint32 drawPeriodSeconds;
  uint64 firstDrawStartsAt;
  uint8 numberOfTiers;
  uint8 tierShares;
  uint8 canaryShares;
  uint8 reserveShares;
  UD2x18 claimExpansionThreshold;
  SD1x18 smoothing;
}

/**
 * @title PoolTogether V5 Prize Pool
 * @author PoolTogether Inc Team
 * @notice The Prize Pool holds the prize liquidity and allows vaults to claim prizes.
 */
contract PrizePool is TieredLiquidityDistributor {
  using SafeERC20 for IERC20;

  /* ============ Events ============ */

  /// @notice Emitted when a prize is claimed.
  /// @param vault The address of the vault that claimed the prize.
  /// @param winner The address of the winner
  /// @param recipient The address of the prize recipient
  /// @param drawId The draw ID of the draw that was claimed.
  /// @param tier The prize tier that was claimed.
  /// @param payout The amount of prize tokens that were paid out to the winner
  /// @param fee The amount of prize tokens that were paid to the claimer
  /// @param feeRecipient The address that the claim fee was sent to
  event ClaimedPrize(
    address indexed vault,
    address indexed winner,
    address indexed recipient,
    uint16 drawId,
    uint8 tier,
    uint32 prizeIndex,
    uint152 payout,
    uint96 fee,
    address feeRecipient
  );

  /// @notice Emitted when a draw is closed.
  /// @param drawId The ID of the draw that was closed
  /// @param winningRandomNumber The winning random number for the closed draw
  /// @param numTiers The number of prize tiers in the closed draw
  /// @param nextNumTiers The number of tiers for the next draw
  /// @param reserve The resulting reserve available for the next draw
  /// @param prizeTokensPerShare The amount of prize tokens per share for the next draw
  /// @param drawStartedAt The start timestamp of the draw
  event DrawClosed(
    uint16 indexed drawId,
    uint256 winningRandomNumber,
    uint8 numTiers,
    uint8 nextNumTiers,
    uint104 reserve,
    UD34x4 prizeTokensPerShare,
    uint64 drawStartedAt
  );

  /// @notice Emitted when any amount of the reserve is withdrawn.
  /// @param to The address the assets are transferred to
  /// @param amount The amount of assets transferred
  event WithdrawReserve(address indexed to, uint256 amount);

  /// @notice Emitted when the reserve is manually increased.
  /// @param user The user who increased the reserve
  /// @param amount The amount of assets transferred
  event IncreaseReserve(address user, uint256 amount);

  /// @notice Emitted when a vault contributes prize tokens to the pool.
  /// @param vault The address of the vault that is contributing tokens
  /// @param drawId The ID of the first draw that the tokens will be applied to
  /// @param amount The amount of tokens contributed
  event ContributePrizeTokens(address indexed vault, uint16 indexed drawId, uint256 amount);

  /// @notice Emitted when an address withdraws their prize claim rewards.
  /// @param to The address the rewards are sent to
  /// @param amount The amount withdrawn
  /// @param available The total amount that was available to withdraw before the transfer
  event WithdrawClaimRewards(address indexed to, uint256 amount, uint256 available);

  /// @notice Emitted when an address receives new prize claim rewards.
  /// @param to The address the rewards are given to
  /// @param amount The amount increased
  event IncreaseClaimRewards(address indexed to, uint256 amount);

  /// @notice Emitted when the drawManager is set.
  /// @param drawManager The draw manager
  event DrawManagerSet(address indexed drawManager);

  /* ============ State ============ */

  /// @notice The DrawAccumulator that tracks the exponential moving average of the contributions by a vault.
  mapping(address => DrawAccumulatorLib.Accumulator) internal vaultAccumulator;

  /// @notice Records the claim record for a winner.
  /// @dev vault => account => drawId => tier => prizeIndex => claimed
  mapping(address => mapping(address => mapping(uint16 => mapping(uint8 => mapping(uint32 => bool)))))
    internal claimedPrizes;

  /// @notice Tracks the total fees accrued to each claimer.
  mapping(address => uint256) internal claimerRewards;

  /// @notice The degree of POOL contribution smoothing. 0 = no smoothing, ~1 = max smoothing. Smoothing spreads out vault contribution over multiple draws; the higher the smoothing the more draws.
  SD1x18 public immutable smoothing;

  /// @notice The token that is being contributed and awarded as prizes.
  IERC20 public immutable prizeToken;

  /// @notice The Twab Controller to use to retrieve historic balances.
  TwabController public immutable twabController;

  /// @notice The draw manager address.
  address public drawManager;

  /// @notice The number of seconds between draws.
  uint32 public immutable drawPeriodSeconds;

  /// @notice Percentage of prizes that must be claimed to bump the number of tiers.
  UD2x18 public immutable claimExpansionThreshold;

  /// @notice The exponential weighted average of all vault contributions.
  DrawAccumulatorLib.Accumulator internal totalAccumulator;

  /// @notice The total amount of prize tokens that have been claimed for all time.
  uint256 internal _totalWithdrawn;

  /// @notice The winner random number for the last closed draw.
  uint256 internal _winningRandomNumber;

  /// @notice The number of prize claims for the last closed draw.
  uint32 public claimCount;

  /// @notice The number of canary prize claims for the last closed draw.
  uint32 public canaryClaimCount;

  /// @notice The largest tier claimed so far for the last closed draw.
  uint8 public largestTierClaimed;

  /// @notice The timestamp at which the last closed draw started.
  uint64 internal _lastClosedDrawStartedAt;

  /// @notice The timestamp at which the last closed draw was awarded.
  uint64 internal _lastClosedDrawAwardedAt;

  /* ============ Constructor ============ */

  /// @notice Constructs a new Prize Pool.
  /// @param params A struct of constructor parameters
  constructor(
    ConstructorParams memory params
  )
    TieredLiquidityDistributor(
      params.numberOfTiers,
      params.tierShares,
      params.canaryShares,
      params.reserveShares
    )
  {
    if (unwrap(params.smoothing) >= unwrap(UNIT)) {
      revert SmoothingGTEOne(unwrap(params.smoothing));
    }
    prizeToken = params.prizeToken;
    twabController = params.twabController;
    smoothing = params.smoothing;
    claimExpansionThreshold = params.claimExpansionThreshold;
    drawPeriodSeconds = params.drawPeriodSeconds;
    _lastClosedDrawStartedAt = params.firstDrawStartsAt;

    drawManager = params.drawManager;
    if (params.drawManager != address(0)) {
      emit DrawManagerSet(params.drawManager);
    }
  }

  /* ============ Modifiers ============ */

  /// @notice Modifier that throws if sender is not the draw manager.
  modifier onlyDrawManager() {
    if (msg.sender != drawManager) {
      revert CallerNotDrawManager(msg.sender, drawManager);
    }
    _;
  }

  /* ============ External Write Functions ============ */

  /// @notice Allows a caller to set the DrawManager if not already set.
  /// @dev Notice that this can be front-run: make sure to verify the drawManager after construction
  /// @param _drawManager The draw manager
  function setDrawManager(address _drawManager) external {
    if (drawManager != address(0)) {
      revert DrawManagerAlreadySet();
    }
    drawManager = _drawManager;

    emit DrawManagerSet(_drawManager);
  }

  /// @notice Contributes prize tokens on behalf of the given vault. The tokens should have already been transferred to the prize pool.
  /// The prize pool balance will be checked to ensure there is at least the given amount to deposit.
  /// @return The amount of available prize tokens prior to the contribution.
  function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns (uint256) {
    uint256 _deltaBalance = prizeToken.balanceOf(address(this)) - _accountedBalance();
    if (_deltaBalance < _amount) {
      revert ContributionGTDeltaBalance(_amount, _deltaBalance);
    }
    DrawAccumulatorLib.add(
      vaultAccumulator[_prizeVault],
      _amount,
      lastClosedDrawId + 1,
      smoothing.intoSD59x18()
    );
    DrawAccumulatorLib.add(
      totalAccumulator,
      _amount,
      lastClosedDrawId + 1,
      smoothing.intoSD59x18()
    );
    emit ContributePrizeTokens(_prizeVault, lastClosedDrawId + 1, _amount);
    return _deltaBalance;
  }

  /// @notice Allows the Manager to withdraw tokens from the reserve.
  /// @param _to The address to send the tokens to
  /// @param _amount The amount of tokens to withdraw
  function withdrawReserve(address _to, uint104 _amount) external onlyDrawManager {
    if (_amount > _reserve) {
      revert InsufficientReserve(_amount, _reserve);
    }
    _reserve -= _amount;
    _transfer(_to, _amount);
    emit WithdrawReserve(_to, _amount);
  }

  /// @notice Allows the Manager to close the current open draw and open the next one.
  ///         Updates the number of tiers, the winning random number and the prize pool reserve.
  /// @param winningRandomNumber_ The winning random number for the current draw
  /// @return The ID of the closed draw
  function closeDraw(uint256 winningRandomNumber_) external onlyDrawManager returns (uint16) {
    // check winning random number
    if (winningRandomNumber_ == 0) {
      revert RandomNumberIsZero();
    }
    if (block.timestamp < _openDrawEndsAt()) {
      revert DrawNotFinished(_openDrawEndsAt(), uint64(block.timestamp));
    }

    uint8 _numTiers = numberOfTiers;
    uint8 _nextNumberOfTiers = _numTiers;

    if (lastClosedDrawId != 0) {
      _nextNumberOfTiers = _computeNextNumberOfTiers(_numTiers);
    }

    uint64 openDrawStartedAt_ = _openDrawStartedAt();

    _nextDraw(_nextNumberOfTiers, uint96(_contributionsForDraw(lastClosedDrawId + 1)));

    _winningRandomNumber = winningRandomNumber_;
    claimCount = 0;
    canaryClaimCount = 0;
    largestTierClaimed = 0;
    _lastClosedDrawStartedAt = openDrawStartedAt_;
    _lastClosedDrawAwardedAt = uint64(block.timestamp);

    emit DrawClosed(
      lastClosedDrawId,
      winningRandomNumber_,
      _numTiers,
      _nextNumberOfTiers,
      _reserve,
      prizeTokenPerShare,
      _lastClosedDrawStartedAt
    );

    return lastClosedDrawId;
  }

  /**
   * @dev Claims a prize for a given winner and tier.
   * This function takes in an address _winner, a uint8 _tier, a uint96 _fee, and an
   * address _feeRecipient. It checks if _winner is actually the winner of the _tier for the calling vault.
   * If so, it calculates the prize size and transfers it to the winner. If not, it reverts with an error message.
   * The function then checks the claim record of _winner to see if they have already claimed the prize for the
   * current draw. If not, it updates the claim record with the claimed tier and emits a ClaimedPrize event with
   * information about the claim.
   * Note that this function can modify the state of the contract by updating the claim record, changing the largest
   * tier claimed and the claim count, and transferring prize tokens. The function is marked as external which
   * means that it can be called from outside the contract.
   * @param _tier The tier of the prize to be claimed.
   * @param _winner The address of the eligible winner
   * @param _prizeIndex The prize to claim for the winner. Must be less than the prize count for the tier.
   * @param _prizeRecipient The recipient of the prize
   * @param _fee The fee associated with claiming the prize.
   * @param _feeRecipient The address to receive the fee.
   * @return Total prize amount claimed (payout and fees combined).
   */
  function claimPrize(
    address _winner,
    uint8 _tier,
    uint32 _prizeIndex,
    address _prizeRecipient,
    uint96 _fee,
    address _feeRecipient
  ) external returns (uint256) {
    Tier memory tierLiquidity = _getTier(_tier, numberOfTiers);

    if (_fee > tierLiquidity.prizeSize) {
      revert FeeTooLarge(_fee, tierLiquidity.prizeSize);
    }

    (SD59x18 _vaultPortion, SD59x18 _tierOdds, uint16 _drawDuration) = _computeVaultTierDetails(
      msg.sender,
      _tier,
      numberOfTiers,
      lastClosedDrawId
    );

    if (
      !_isWinner(msg.sender, _winner, _tier, _prizeIndex, _vaultPortion, _tierOdds, _drawDuration)
    ) {
      revert DidNotWin(msg.sender, _winner, _tier, _prizeIndex);
    }

    if (claimedPrizes[msg.sender][_winner][lastClosedDrawId][_tier][_prizeIndex]) {
      revert AlreadyClaimedPrize(msg.sender, _winner, _tier, _prizeIndex, _prizeRecipient);
    }

    claimedPrizes[msg.sender][_winner][lastClosedDrawId][_tier][_prizeIndex] = true;

    if (_isCanaryTier(_tier, numberOfTiers)) {
      canaryClaimCount++;
    } else {
      claimCount++;
    }

    if (largestTierClaimed < _tier) {
      largestTierClaimed = _tier;
    }

    // `amount` is a snapshot of the reserve before consuming liquidity
    _consumeLiquidity(tierLiquidity, _tier, tierLiquidity.prizeSize);

    if (_fee != 0) {
      emit IncreaseClaimRewards(_feeRecipient, _fee);
      claimerRewards[_feeRecipient] += _fee;
    }

    // `amount` is now the payout amount
    uint256 amount = tierLiquidity.prizeSize - _fee;

    emit ClaimedPrize(
      msg.sender,
      _winner,
      _prizeRecipient,
      lastClosedDrawId,
      _tier,
      _prizeIndex,
      uint152(amount),
      _fee,
      _feeRecipient
    );

    _transfer(_prizeRecipient, amount);

    return tierLiquidity.prizeSize;
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
    emit WithdrawClaimRewards(_to, _amount, _available);
  }

  /// @notice Allows anyone to deposit directly into the Prize Pool reserve.
  /// @dev Ensure caller has sufficient balance and has approved the Prize Pool to transfer the tokens
  /// @param _amount The amount of tokens to increase the reserve by
  function increaseReserve(uint104 _amount) external {
    _reserve += _amount;
    prizeToken.safeTransferFrom(msg.sender, address(this), _amount);
    emit IncreaseReserve(msg.sender, _amount);
  }

  /* ============ External Read Functions ============ */

  /// @notice Returns the winning random number for the last closed draw.
  /// @return The winning random number
  function getWinningRandomNumber() external view returns (uint256) {
    return _winningRandomNumber;
  }

  /// @notice Returns the last closed draw id.
  /// @return The last closed draw id
  function getLastClosedDrawId() external view returns (uint256) {
    return lastClosedDrawId;
  }

  /// @notice Returns the total prize tokens contributed between the given draw ids, inclusive. Note that this is after smoothing is applied.
  /// @return The total prize tokens contributed by all vaults
  function getTotalContributedBetween(
    uint16 _startDrawIdInclusive,
    uint16 _endDrawIdInclusive
  ) external view returns (uint256) {
    return
      DrawAccumulatorLib.getDisbursedBetween(
        totalAccumulator,
        _startDrawIdInclusive,
        _endDrawIdInclusive,
        smoothing.intoSD59x18()
      );
  }

  /// @notice Returns the total prize tokens contributed by a particular vault between the given draw ids, inclusive. Note that this is after smoothing is applied.
  /// @return The total prize tokens contributed by the given vault
  function getContributedBetween(
    address _vault,
    uint16 _startDrawIdInclusive,
    uint16 _endDrawIdInclusive
  ) external view returns (uint256) {
    return
      DrawAccumulatorLib.getDisbursedBetween(
        vaultAccumulator[_vault],
        _startDrawIdInclusive,
        _endDrawIdInclusive,
        smoothing.intoSD59x18()
      );
  }

  /// @notice Returns the
  /// @return The number of draws
  function getTierAccrualDurationInDraws(uint8 _tier) external view returns (uint16) {
    return
      uint16(TierCalculationLib.estimatePrizeFrequencyInDraws(_tierOdds(_tier, numberOfTiers)));
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

  /// @notice Returns the start time of the last closed draw. If there was no closed draw, then it will be zero.
  /// @return The start time of the last closed draw
  function lastClosedDrawStartedAt() external view returns (uint64) {
    return lastClosedDrawId != 0 ? _lastClosedDrawStartedAt : 0;
  }

  /// @notice Returns the end time of the last closed draw. If there was no closed draw, then it will be zero.
  /// @return The end time of the last closed draw
  function lastClosedDrawEndedAt() external view returns (uint64) {
    return lastClosedDrawId != 0 ? _lastClosedDrawStartedAt + drawPeriodSeconds : 0;
  }

  /// @notice Returns the time at which the last closed draw was awarded.
  /// @return The time at which the last closed draw was awarded
  function lastClosedDrawAwardedAt() external view returns (uint64) {
    return lastClosedDrawId != 0 ? _lastClosedDrawAwardedAt : 0;
  }

  /// @notice Returns whether the open draw has finished.
  /// @return Whether the open draw has finished
  function hasOpenDrawFinished() external view returns (bool) {
    return block.timestamp >= _openDrawEndsAt();
  }

  /// @notice Returns the start time of the open draw.
  /// @return The start time of the open draw
  function openDrawStartedAt() external view returns (uint64) {
    return _openDrawStartedAt();
  }

  /// @notice Returns the time at which the open draw ends
  /// @return The time at which the open draw ends
  function openDrawEndsAt() external view returns (uint64) {
    return _openDrawEndsAt();
  }

  /// @notice Returns the amount of tokens that will be added to the reserve when the open draw closes.
  /// @dev Intended for Draw manager to use after the draw has ended but not yet been closed.
  /// @return The amount of prize tokens that will be added to the reserve
  function reserveForOpenDraw() external view returns (uint256) {
    uint8 _numTiers = numberOfTiers;
    uint8 _nextNumberOfTiers = _numTiers;

    if (lastClosedDrawId != 0) {
      _nextNumberOfTiers = _computeNextNumberOfTiers(_numTiers);
    }

    (, uint104 newReserve, ) = _computeNewDistributions(
      _numTiers,
      _nextNumberOfTiers,
      uint96(_contributionsForDraw(lastClosedDrawId + 1))
    );

    return newReserve;
  }

  /// @notice Calculates the total liquidity available for the last closed draw.
  function getTotalContributionsForClosedDraw() external view returns (uint256) {
    return _contributionsForDraw(lastClosedDrawId);
  }

  /// @notice Returns whether the winner has claimed the tier for the last closed draw
  /// @param _vault The vault to check
  /// @param _winner The account to check
  /// @param _tier The tier to check
  /// @param _prizeIndex The prize index to check
  /// @return True if the winner claimed the tier for the current draw, false otherwise.
  function wasClaimed(
    address _vault,
    address _winner,
    uint8 _tier,
    uint32 _prizeIndex
  ) external view returns (bool) {
    return claimedPrizes[_vault][_winner][lastClosedDrawId][_tier][_prizeIndex];
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
    (SD59x18 vaultPortion, SD59x18 tierOdds, uint16 drawDuration) = _computeVaultTierDetails(
      _vault,
      _tier,
      numberOfTiers,
      lastClosedDrawId
    );
    return _isWinner(_vault, _user, _tier, _prizeIndex, vaultPortion, tierOdds, drawDuration);
  }

  /***
   * @notice Calculates the start and end timestamps of the time-weighted average balance (TWAB) for the specified tier.
   * @param _tier The tier for which to calculate the TWAB timestamps.
   * @return The start and end timestamps of the TWAB.
   */
  function calculateTierTwabTimestamps(
    uint8 _tier
  ) external view returns (uint64 startTimestamp, uint64 endTimestamp) {
    uint8 _numberOfTiers = numberOfTiers;
    _checkValidTier(_tier, _numberOfTiers);
    endTimestamp = _lastClosedDrawStartedAt + drawPeriodSeconds;
    SD59x18 tierOdds = _tierOdds(_tier, _numberOfTiers);
    uint256 durationInSeconds = TierCalculationLib.estimatePrizeFrequencyInDraws(tierOdds) * drawPeriodSeconds;

    startTimestamp = uint64(
      endTimestamp -
        durationInSeconds
    );
  }

  /**
   * @notice Returns the time-weighted average balance (TWAB) and the TWAB total supply for the specified user in the given vault over a specified period.
   * @param _vault The address of the vault for which to get the TWAB.
   * @param _user The address of the user for which to get the TWAB.
   * @param _drawDuration The duration of the period over which to calculate the TWAB, in number of draw periods.
   * @return The TWAB and the TWAB total supply for the specified user in the given vault over the specified period.
   */
  function getVaultUserBalanceAndTotalSupplyTwab(
    address _vault,
    address _user,
    uint256 _drawDuration
  ) external view returns (uint256, uint256) {
    return _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, _drawDuration);
  }

  /**
   * @notice Returns the portion of a vault's contributions in a given draw range.
   * This function takes in an address _vault, a uint16 startDrawId, and a uint16 endDrawId.
   * It calculates the portion of the _vault's contributions in the given draw range by calling the internal
   * _getVaultPortion function with the _vault argument, startDrawId as the drawId_ argument,
   * endDrawId - startDrawId as the _durationInDraws argument, and smoothing.intoSD59x18() as the _smoothing
   * argument. The function then returns the resulting SD59x18 value representing the portion of the
   * vault's contributions.
   * @param _vault The address of the vault to calculate the contribution portion for.
   * @param _startDrawId The starting draw ID of the draw range to calculate the contribution portion for.
   * @param _endDrawId The ending draw ID of the draw range to calculate the contribution portion for.
   * @return The portion of the _vault's contributions in the given draw range as an SD59x18 value.
   */
  function getVaultPortion(
    address _vault,
    uint16 _startDrawId,
    uint16 _endDrawId
  ) external view returns (SD59x18) {
    return _getVaultPortion(_vault, _startDrawId, _endDrawId, smoothing.intoSD59x18());
  }

  /**
   * @notice Computes and returns the next number of tiers based on the current prize claim counts. This number may change throughout the draw
   * @return The next number of tiers
   */
  function nextNumberOfTiers() external view returns (uint8) {
    return _computeNextNumberOfTiers(numberOfTiers);
  }

  /* ============ Internal Functions ============ */

  /// @notice Computes how many tokens have been accounted for
  /// @return The balance of tokens that have been accounted for
  function _accountedBalance() internal view returns (uint256) {
    Observation memory obs = DrawAccumulatorLib.newestObservation(totalAccumulator);
    return (obs.available + obs.disbursed) - _totalWithdrawn;
  }

  /// @notice Returns the start time of the draw for the next successful closeDraw
  function _openDrawStartedAt() internal view returns (uint64) {
    return _openDrawEndsAt() - drawPeriodSeconds;
  }

  function _checkValidTier(uint8 _tier, uint8 _numTiers) internal pure {
    if (_tier >= _numTiers) {
      revert InvalidTier(_tier, _numTiers);
    }
  }

  /// @notice Returns the time at which the open draw ends.
  function _openDrawEndsAt() internal view returns (uint64) {
    // If this is the first draw, we treat _lastClosedDrawStartedAt as the start of this draw
    uint64 _nextExpectedEndTime = _lastClosedDrawStartedAt +
      (lastClosedDrawId == 0 ? 1 : 2) *
      drawPeriodSeconds;

    if (block.timestamp > _nextExpectedEndTime) {
      // Use integer division to get the number of draw periods passed between the expected end time and now
      // Offset the end time by the total duration of the missed draws
      // drawPeriodSeconds * numMissedDraws
      _nextExpectedEndTime +=
        drawPeriodSeconds *
        (uint64((block.timestamp - _nextExpectedEndTime) / drawPeriodSeconds));
    }

    return _nextExpectedEndTime;
  }

  /// @notice Calculates the number of tiers for the next draw
  /// @param _numTiers The current number of tiers
  /// @return The number of tiers for the next draw
  function _computeNextNumberOfTiers(uint8 _numTiers) internal view returns (uint8) {
    UD2x18 _claimExpansionThreshold = claimExpansionThreshold;

    uint8 _nextNumberOfTiers = largestTierClaimed + 2; // canary tier, then length
    _nextNumberOfTiers = _nextNumberOfTiers > MINIMUM_NUMBER_OF_TIERS
      ? _nextNumberOfTiers
      : MINIMUM_NUMBER_OF_TIERS;

    if (_nextNumberOfTiers >= MAXIMUM_NUMBER_OF_TIERS) {
      return MAXIMUM_NUMBER_OF_TIERS;
    }

    // check to see if we need to expand the number of tiers
    if (
      _nextNumberOfTiers >= _numTiers &&
      canaryClaimCount >=
      fromUD60x18(
        intoUD60x18(_claimExpansionThreshold).mul(_canaryPrizeCountFractional(_numTiers).floor())
      ) &&
      claimCount >=
      fromUD60x18(
        intoUD60x18(_claimExpansionThreshold).mul(toUD60x18(_estimatedPrizeCount(_numTiers)))
      )
    ) {
      // increase the number of tiers to include a new tier
      _nextNumberOfTiers = _numTiers + 1;
    }

    return _nextNumberOfTiers;
  }

  /// @notice Computes the tokens to be disbursed from the accumulator for a given draw.
  /// @param _drawId The ID of the draw to compute the disbursement for.
  /// @return The amount of tokens contributed to the accumulator for the given draw.
  function _contributionsForDraw(uint16 _drawId) internal view returns (uint256) {
    return
      DrawAccumulatorLib.getDisbursedBetween(
        totalAccumulator,
        _drawId,
        _drawId,
        smoothing.intoSD59x18()
      );
  }

  /**
   * @notice Transfers the given amount of prize tokens to the given address.
   * @param _to The address to transfer to
   * @param _amount The amount to transfer
   */
  function _transfer(address _to, uint256 _amount) internal {
    _totalWithdrawn += _amount;
    prizeToken.safeTransfer(_to, _amount);
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
    uint16 _drawDuration
  ) internal view returns (bool) {
    uint8 _numberOfTiers = numberOfTiers;
    uint32 tierPrizeCount = _getTierPrizeCount(_tier, _numberOfTiers);

    if (_prizeIndex >= tierPrizeCount) {
      revert InvalidPrizeIndex(_prizeIndex, tierPrizeCount, _tier);
    }

    uint256 userSpecificRandomNumber = TierCalculationLib.calculatePseudoRandomNumber(
      _user,
      _tier,
      _prizeIndex,
      _winningRandomNumber
    );
    (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = _getVaultUserBalanceAndTotalSupplyTwab(
      _vault,
      _user,
      _drawDuration
    );

    return
      TierCalculationLib.isWinner(
        userSpecificRandomNumber,
        uint128(_userTwab),
        uint128(_vaultTwabTotalSupply),
        _vaultPortion,
        _tierOdds
      );
  }

  /**
   * @notice Computes the data needed for determining a winner of a prize from a specific vault for a specific draw.
   * @param _vault The address of the vault to check.
   * @param _tier The tier for which the prize is to be checked.
   * @param _numberOfTiers The number of tiers in the draw.
   * @param _lastClosedDrawId The ID of the last closed draw.
   * @return vaultPortion The portion of the prizes that are going to this vault.
   * @return tierOdds The odds of winning the prize for the given tier.
   * @return drawDuration The duration of the draw.
   */
  function _computeVaultTierDetails(
    address _vault,
    uint8 _tier,
    uint8 _numberOfTiers,
    uint16 _lastClosedDrawId
  ) internal view returns (SD59x18 vaultPortion, SD59x18 tierOdds, uint16 drawDuration) {
    if (_lastClosedDrawId == 0) {
      revert NoClosedDraw();
    }
    _checkValidTier(_tier, _numberOfTiers);

    tierOdds = _tierOdds(_tier, numberOfTiers);
    drawDuration = uint16(TierCalculationLib.estimatePrizeFrequencyInDraws(tierOdds));
    vaultPortion = _getVaultPortion(
      _vault,
      uint16(drawDuration > _lastClosedDrawId ? 0 : _lastClosedDrawId - drawDuration + 1),
      _lastClosedDrawId + 1,
      smoothing.intoSD59x18()
    );
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
  function _getVaultUserBalanceAndTotalSupplyTwab(
    address _vault,
    address _user,
    uint256 _drawDuration
  ) internal view returns (uint256 twab, uint256 twabTotalSupply) {
    uint32 _endTimestamp = uint32(_lastClosedDrawStartedAt + drawPeriodSeconds);
    uint32 _startTimestamp = uint32(_endTimestamp - _drawDuration * drawPeriodSeconds);

    twab = twabController.getTwabBetween(_vault, _user, _startTimestamp, _endTimestamp);

    twabTotalSupply = twabController.getTotalSupplyTwabBetween(
      _vault,
      _startTimestamp,
      _endTimestamp
    );
  }

  /**
   * @notice Calculates the portion of the vault's contribution to the prize pool over a specified duration in draws.
   * @param _vault The address of the vault for which to calculate the portion.
   * @param _startDrawId The starting draw ID (inclusive) of the draw range to calculate the contribution portion for.
   * @param _endDrawId The ending draw ID (inclusive) of the draw range to calculate the contribution portion for.
   * @param _smoothing The smoothing value to use for calculating the portion.
   * @return The portion of the vault's contribution to the prize pool over the specified duration in draws.
   */
  function _getVaultPortion(
    address _vault,
    uint16 _startDrawId,
    uint16 _endDrawId,
    SD59x18 _smoothing
  ) internal view returns (SD59x18) {
    uint256 totalContributed = DrawAccumulatorLib.getDisbursedBetween(
      totalAccumulator,
      _startDrawId,
      _endDrawId,
      _smoothing
    );

    if (totalContributed != 0) {
      // vaultContributed / totalContributed
      return
        sd(
          int256(
            DrawAccumulatorLib.getDisbursedBetween(
              vaultAccumulator[_vault],
              _startDrawId,
              _endDrawId,
              _smoothing
            )
          )
        ).div(sd(int256(totalContributed)));
    } else {
      return sd(0);
    }
  }
}
