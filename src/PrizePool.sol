// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { SD59x18, sd } from "prb-math/SD59x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { UD34x4 } from "./libraries/UD34x4.sol";
import { DrawAccumulatorLib, Observation } from "./libraries/DrawAccumulatorLib.sol";
import { TieredLiquidityDistributor, Tier, MAXIMUM_NUMBER_OF_TIERS, MINIMUM_NUMBER_OF_TIERS } from "./abstract/TieredLiquidityDistributor.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";

/// @notice Emitted when the prize pool is constructed with a draw start that is in the past
error FirstDrawStartsInPast();

/// @notice Emitted when the Twab Controller has an incompatible period length
error IncompatibleTwabPeriodLength();

/// @notice Emitted when the Twab Controller has an incompatible period offset
error IncompatibleTwabPeriodOffset();

/// @notice Emitted when someone tries to set the draw manager with the zero address
error DrawManagerIsZeroAddress();

/// @notice Emitted when the caller is not the deployer.
error NotDeployer();

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

/// @notice Emitted when someone tries to claim a prize that is zero size
error PrizeIsZero();

/// @notice Emitted when someone tries to claim a prize, but sets the fee recipient address to the zero address.
error FeeRecipientZeroAddress();

/**
 * @notice Constructor Parameters
 * @param prizeToken The token to use for prizes
 * @param twabController The Twab Controller to retrieve time-weighted average balances from
 * @param drawPeriodSeconds The number of seconds between draws. E.g. a Prize Pool with a daily draw should have a draw period of 86400 seconds.
 * @param firstDrawStartsAt The timestamp at which the first draw will start.
 * @param numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
 * @param tierShares The number of shares to allocate to each tier
 * @param reserveShares The number of shares to allocate to the reserve.
 * @param smoothing The amount of smoothing to apply to vault contributions. Must be less than 1. A value of 0 is no smoothing, while greater values smooth until approaching infinity
 */
struct ConstructorParams {
  IERC20 prizeToken;
  TwabController twabController;
  uint32 drawPeriodSeconds;
  uint64 firstDrawStartsAt;
  SD1x18 smoothing;
  uint24 grandPrizePeriodDraws;
  uint8 numberOfTiers;
  uint8 tierShares;
  uint8 reserveShares;
}

/**
 * @title PoolTogether V5 Prize Pool
 * @author PoolTogether Inc Team
 * @notice The Prize Pool holds the prize liquidity and allows vaults to claim prizes.
 */
contract PrizePool is TieredLiquidityDistributor, Ownable {
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
    uint24 drawId,
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
    uint24 indexed drawId,
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
  event ContributedReserve(address indexed user, uint256 amount);

  /// @notice Emitted when a vault contributes prize tokens to the pool.
  /// @param vault The address of the vault that is contributing tokens
  /// @param drawId The ID of the first draw that the tokens will be applied to
  /// @param amount The amount of tokens contributed
  event ContributePrizeTokens(address indexed vault, uint24 indexed drawId, uint256 amount);

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
  mapping(address vault => DrawAccumulatorLib.Accumulator accumulator) internal _vaultAccumulator;

  /// @notice Records the claim record for a winner.
  mapping(address vault => mapping(address account => mapping(uint24 drawId => mapping(uint8 tier => mapping(uint32 prizeIndex => bool claimed)))))
    internal _claimedPrizes;

  /// @notice Tracks the total fees accrued to each claimer.
  mapping(address claimer => uint256 rewards) internal _claimerRewards;

  /// @notice The degree of POOL contribution smoothing. 0 = no smoothing, ~1 = max smoothing.
  /// @dev Smoothing spreads out vault contribution over multiple draws; the higher the smoothing the more draws.
  SD1x18 public immutable smoothing;

  /// @notice The token that is being contributed and awarded as prizes.
  IERC20 public immutable prizeToken;

  /// @notice The Twab Controller to use to retrieve historic balances.
  TwabController public immutable twabController;

  /// @notice The draw manager address.
  address public drawManager;

  /// @notice The number of seconds between draws.
  uint32 public immutable drawPeriodSeconds;

  /// @notice The timestamp at which the first draw will open.
  uint64 public immutable firstDrawStartsAt;

  /// @notice The exponential weighted average of all vault contributions.
  DrawAccumulatorLib.Accumulator internal _totalAccumulator;

  /// @notice The winner random number for the last closed draw.
  uint256 internal _winningRandomNumber;

  /// @notice The number of prize claims for the last closed draw.
  uint32 public claimCount;

  /// @notice The total amount of prize tokens that have been claimed for all time.
  uint160 internal _totalWithdrawn;

  /// @notice The timestamp at which the last closed draw started.
  uint64 internal _lastClosedDrawStartedAt;

  /// @notice The timestamp at which the last closed draw was awarded.
  uint64 internal _lastClosedDrawAwardedAt;

  /// @notice Tracks reserve that was contributed directly to the reserve. Always increases.
  uint192 internal _directlyContributedReserve;

  /* ============ Constructor ============ */

  /// @notice Constructs a new Prize Pool.
  /// @param params A struct of constructor parameters
  constructor(
    ConstructorParams memory params
  )
    TieredLiquidityDistributor(
      params.numberOfTiers,
      params.tierShares,
      params.reserveShares,
      params.grandPrizePeriodDraws
    )
    Ownable()
  {
    if (unwrap(params.smoothing) >= unwrap(UNIT)) {
      revert SmoothingGTEOne(unwrap(params.smoothing));
    }

    if (params.firstDrawStartsAt < block.timestamp) {
      revert FirstDrawStartsInPast();
    }

    uint48 twabPeriodOffset = params.twabController.PERIOD_OFFSET();
    uint48 twabPeriodLength = params.twabController.PERIOD_LENGTH();

    if (
      params.drawPeriodSeconds < twabPeriodLength ||
      params.drawPeriodSeconds % twabPeriodLength != 0
    ) {
      revert IncompatibleTwabPeriodLength();
    }

    if ((params.firstDrawStartsAt - twabPeriodOffset) % twabPeriodLength != 0) {
      revert IncompatibleTwabPeriodOffset();
    }

    prizeToken = params.prizeToken;
    twabController = params.twabController;
    smoothing = params.smoothing;
    drawPeriodSeconds = params.drawPeriodSeconds;
    _lastClosedDrawStartedAt = params.firstDrawStartsAt;
    firstDrawStartsAt = params.firstDrawStartsAt;
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
  /// @param _drawManager The draw manager
  function setDrawManager(address _drawManager) external onlyOwner {
    if (_drawManager == address(0)) {
      revert DrawManagerIsZeroAddress();
    }
    drawManager = _drawManager;

    emit DrawManagerSet(_drawManager);
  }

  /// @notice Contributes prize tokens on behalf of the given vault.
  /// @dev The tokens should have already been transferred to the prize pool.
  /// @dev The prize pool balance will be checked to ensure there is at least the given amount to deposit.
  /// @param _prizeVault The address of the vault to contribute to
  /// @param _amount The amount of prize tokens to contribute
  /// @return The amount of available prize tokens prior to the contribution.
  function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns (uint256) {
    uint256 _deltaBalance = prizeToken.balanceOf(address(this)) - _accountedBalance();
    if (_deltaBalance < _amount) {
      revert ContributionGTDeltaBalance(_amount, _deltaBalance);
    }
    uint24 openDrawId = _lastClosedDrawId + 1;
    SD59x18 _smoothing = smoothing.intoSD59x18();
    DrawAccumulatorLib.add(_vaultAccumulator[_prizeVault], _amount, openDrawId, _smoothing);
    DrawAccumulatorLib.add(_totalAccumulator, _amount, openDrawId, _smoothing);
    emit ContributePrizeTokens(_prizeVault, openDrawId, _amount);
    return _deltaBalance;
  }

  /// @notice Allows the Manager to withdraw tokens from the reserve.
  /// @param _to The address to send the tokens to
  /// @param _amount The amount of tokens to withdraw
  function withdrawReserve(address _to, uint96 _amount) external onlyDrawManager {
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
  function closeDraw(uint256 winningRandomNumber_) external onlyDrawManager returns (uint24) {
    // check winning random number
    if (winningRandomNumber_ == 0) {
      revert RandomNumberIsZero();
    }
    if (block.timestamp < _openDrawEndsAt()) {
      revert DrawNotFinished(_openDrawEndsAt(), uint64(block.timestamp));
    }

    uint24 lastClosedDrawId_ = _lastClosedDrawId;
    uint24 nextDrawId = lastClosedDrawId_ + 1;
    uint32 _claimCount = claimCount;
    uint8 _numTiers = numberOfTiers;
    uint8 _nextNumberOfTiers = _numTiers;

    if (lastClosedDrawId_ != 0) {
      _nextNumberOfTiers = _computeNextNumberOfTiers(_claimCount);
    }

    uint64 openDrawStartedAt_ = _openDrawStartedAt();

    _nextDraw(_nextNumberOfTiers, _contributionsForDraw(nextDrawId));

    _winningRandomNumber = winningRandomNumber_;
    if (_claimCount != 0) {
      claimCount = 0;
    }
    _lastClosedDrawStartedAt = openDrawStartedAt_;
    _lastClosedDrawAwardedAt = uint64(block.timestamp);

    emit DrawClosed(
      nextDrawId,
      winningRandomNumber_,
      _numTiers,
      _nextNumberOfTiers,
      _reserve,
      prizeTokenPerShare,
      _lastClosedDrawStartedAt
    );

    return lastClosedDrawId_;
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
   * @return Total prize amount claimed (payout and fees combined). If the prize was already claimed it returns zero.
   */
  function claimPrize(
    address _winner,
    uint8 _tier,
    uint32 _prizeIndex,
    address _prizeRecipient,
    uint96 _fee,
    address _feeRecipient
  ) external returns (uint256) {
    if (_feeRecipient == address(0) && _fee > 0) {
      revert FeeRecipientZeroAddress();
    }

    uint8 _numTiers = numberOfTiers;

    Tier memory tierLiquidity = _getTier(_tier, _numTiers);

    if (_fee > tierLiquidity.prizeSize) {
      revert FeeTooLarge(_fee, tierLiquidity.prizeSize);
    }

    if (tierLiquidity.prizeSize == 0) {
      revert PrizeIsZero();
    }

    {
      // hide the variables!
      (
        SD59x18 _vaultPortion,
        SD59x18 _computedTierOdds,
        uint24 _drawDuration
      ) = _computeVaultTierDetails(msg.sender, _tier, numberOfTiers, _lastClosedDrawId);

      if (
        !_isWinner(
          _lastClosedDrawId,
          msg.sender,
          _winner,
          _tier,
          _prizeIndex,
          _vaultPortion,
          _computedTierOdds,
          _drawDuration
        )
      ) {
        revert DidNotWin(msg.sender, _winner, _tier, _prizeIndex);
      }
    }

    if (_claimedPrizes[msg.sender][_winner][_lastClosedDrawId][_tier][_prizeIndex]) {
      return 0;
    }

    _claimedPrizes[msg.sender][_winner][_lastClosedDrawId][_tier][_prizeIndex] = true;

    // `amount` is a snapshot of the reserve before consuming liquidity
    _consumeLiquidity(tierLiquidity, _tier, tierLiquidity.prizeSize);

    // `amount` is now the payout amount
    uint256 amount;
    if (_fee != 0) {
      emit IncreaseClaimRewards(_feeRecipient, _fee);
      _claimerRewards[_feeRecipient] += _fee;
      amount = tierLiquidity.prizeSize - _fee;
    } else {
      amount = tierLiquidity.prizeSize;
    }

    // co-locate to save gas
    claimCount++;
    _totalWithdrawn = SafeCast.toUint160(_totalWithdrawn + amount);

    emit ClaimedPrize(
      msg.sender,
      _winner,
      _prizeRecipient,
      _lastClosedDrawId,
      _tier,
      _prizeIndex,
      uint152(amount),
      _fee,
      _feeRecipient
    );

    prizeToken.safeTransfer(_prizeRecipient, amount);

    return tierLiquidity.prizeSize;
  }

  /**
   * @notice Withdraws the claim fees for the caller.
   * @param _to The address to transfer the claim fees to.
   * @param _amount The amount of claim fees to withdraw
   */
  function withdrawClaimRewards(address _to, uint256 _amount) external {
    uint256 _available = _claimerRewards[msg.sender];

    if (_amount > _available) {
      revert InsufficientRewardsError(_amount, _available);
    }

    _claimerRewards[msg.sender] = _available - _amount;
    _transfer(_to, _amount);
    emit WithdrawClaimRewards(_to, _amount, _available);
  }

  /// @notice Allows anyone to deposit directly into the Prize Pool reserve.
  /// @dev Ensure caller has sufficient balance and has approved the Prize Pool to transfer the tokens
  /// @param _amount The amount of tokens to increase the reserve by
  function contributeReserve(uint96 _amount) external {
    _reserve += _amount;
    _directlyContributedReserve += _amount;
    prizeToken.safeTransferFrom(msg.sender, address(this), _amount);
    emit ContributedReserve(msg.sender, _amount);
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
    return _lastClosedDrawId;
  }

  /// @notice Returns the total prize tokens contributed between the given draw ids, inclusive.
  /// @dev Note that this is after smoothing is applied.
  /// @param _startDrawIdInclusive Start draw id inclusive
  /// @param _endDrawIdInclusive End draw id inclusive
  /// @return The total prize tokens contributed by all vaults
  function getTotalContributedBetween(
    uint24 _startDrawIdInclusive,
    uint24 _endDrawIdInclusive
  ) external view returns (uint256) {
    return
      DrawAccumulatorLib.getDisbursedBetween(
        _totalAccumulator,
        _startDrawIdInclusive,
        _endDrawIdInclusive,
        smoothing.intoSD59x18()
      );
  }

  /// @notice Returns the total prize tokens contributed by a particular vault between the given draw ids, inclusive.
  /// @dev Note that this is after smoothing is applied.
  /// @param _vault The address of the vault
  /// @param _startDrawIdInclusive Start draw id inclusive
  /// @param _endDrawIdInclusive End draw id inclusive
  /// @return The total prize tokens contributed by the given vault
  function getContributedBetween(
    address _vault,
    uint24 _startDrawIdInclusive,
    uint24 _endDrawIdInclusive
  ) external view returns (uint256) {
    return
      DrawAccumulatorLib.getDisbursedBetween(
        _vaultAccumulator[_vault],
        _startDrawIdInclusive,
        _endDrawIdInclusive,
        smoothing.intoSD59x18()
      );
  }

  /// @notice Computes the expected duration prize accrual for a tier.
  /// @param _tier The tier to check
  /// @return The number of draws
  function getTierAccrualDurationInDraws(uint8 _tier) external view returns (uint24) {
    return
      uint24(TierCalculationLib.estimatePrizeFrequencyInDraws(_tierOdds(_tier, numberOfTiers)));
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
    return _lastClosedDrawId != 0 ? _lastClosedDrawStartedAt : 0;
  }

  /// @notice Returns the end time of the last closed draw. If there was no closed draw, then it will be zero.
  /// @return The end time of the last closed draw
  function lastClosedDrawEndedAt() external view returns (uint64) {
    return _lastClosedDrawId != 0 ? _lastClosedDrawStartedAt + drawPeriodSeconds : 0;
  }

  /// @notice Returns the time at which the last closed draw was awarded.
  /// @return The time at which the last closed draw was awarded
  function lastClosedDrawAwardedAt() external view returns (uint64) {
    return _lastClosedDrawId != 0 ? _lastClosedDrawAwardedAt : 0;
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

    if (_lastClosedDrawId != 0) {
      _nextNumberOfTiers = _computeNextNumberOfTiers(claimCount);
    }

    (, uint104 newReserve, ) = _computeNewDistributions(
      _numTiers,
      _nextNumberOfTiers,
      _contributionsForDraw(_lastClosedDrawId + 1)
    );

    return newReserve;
  }

  /// @notice Calculates the total liquidity available for the last closed draw.
  function getTotalContributionsForClosedDraw() external view returns (uint256) {
    return _contributionsForDraw(_lastClosedDrawId);
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
    return _claimedPrizes[_vault][_winner][_lastClosedDrawId][_tier][_prizeIndex];
  }

  /**
   * @notice Returns the balance of fees for a given claimer
   * @param _claimer The claimer to retrieve the fee balance for
   * @return The balance of fees for the given claimer
   */
  function balanceOfClaimRewards(address _claimer) external view returns (uint256) {
    return _claimerRewards[_claimer];
  }

  /**
   * @notice Checks if the given user has won the prize for the specified tier in the given vault.
   * @param _vault The address of the vault to check.
   * @param _user The address of the user to check for the prize.
   * @param _tier The tier for which the prize is to be checked.
   * @param _prizeIndex The index of the prize to check (less than prize count for tier)
   * @return A boolean value indicating whether the user has won the prize or not.
   */
  function isWinner(
    address _vault,
    address _user,
    uint8 _tier,
    uint32 _prizeIndex
  ) external view returns (bool) {
    (SD59x18 vaultPortion, SD59x18 tierOdds, uint24 drawDuration) = _computeVaultTierDetails(
      _vault,
      _tier,
      numberOfTiers,
      _lastClosedDrawId
    );
    return
      _isWinner(
        _lastClosedDrawId,
        _vault,
        _user,
        _tier,
        _prizeIndex,
        vaultPortion,
        tierOdds,
        drawDuration
      );
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
    uint256 durationInSeconds = TierCalculationLib.estimatePrizeFrequencyInDraws(tierOdds) *
      drawPeriodSeconds;

    startTimestamp = uint64(endTimestamp - durationInSeconds);
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
   * @notice Returns the portion of a vault's contributions in a given draw range as a fraction.
   * @param _vault The address of the vault to calculate the contribution portion for.
   * @param _startDrawId The starting draw ID of the draw range to calculate the contribution portion for.
   * @param _endDrawId The ending draw ID of the draw range to calculate the contribution portion for.
   * @return The portion of the _vault's contributions in the given draw range as an SD59x18 value.
   */
  function getVaultPortion(
    address _vault,
    uint24 _startDrawId,
    uint24 _endDrawId
  ) external view returns (SD59x18) {
    return _getVaultPortion(_vault, _startDrawId, _endDrawId, smoothing.intoSD59x18());
  }

  /**
   * @notice Computes and returns the next number of tiers based on the current prize claim counts. This number may change throughout the draw
   * @return The next number of tiers
   */
  function estimateNextNumberOfTiers() external view returns (uint8) {
    return _computeNextNumberOfTiers(claimCount);
  }

  /* ============ Internal Functions ============ */

  /// @notice Computes how many tokens have been accounted for
  /// @return The balance of tokens that have been accounted for
  function _accountedBalance() internal view returns (uint256) {
    Observation memory obs = DrawAccumulatorLib.newestObservation(_totalAccumulator);
    return (obs.available + obs.disbursed) + _directlyContributedReserve - _totalWithdrawn;
  }

  /// @notice Returns the start time of the draw for the next successful closeDraw
  /// @return The timestamp at which the open draw started
  function _openDrawStartedAt() internal view returns (uint64) {
    return _openDrawEndsAt() - drawPeriodSeconds;
  }

  /// @notice Reverts if the given _tier is >= _numTiers
  /// @param _tier The tier to check
  /// @param _numTiers The current number of tiers
  function _checkValidTier(uint8 _tier, uint8 _numTiers) internal pure {
    if (_tier >= _numTiers) {
      revert InvalidTier(_tier, _numTiers);
    }
  }

  /// @notice Returns the time at which the open draw ends.
  /// @return The timestamp at which the open draw ends
  function _openDrawEndsAt() internal view returns (uint64) {
    uint32 _drawPeriodSeconds = drawPeriodSeconds;

    // If this is the first draw, we treat _lastClosedDrawStartedAt as the start of this draw
    uint64 _nextExpectedEndTime = _lastClosedDrawStartedAt +
      (_lastClosedDrawId == 0 ? 1 : 2) *
      drawPeriodSeconds;

    if (block.timestamp > _nextExpectedEndTime) {
      // Use integer division to get the number of draw periods passed between the expected end time and now
      // Offset the end time by the total duration of the missed draws
      // drawPeriodSeconds * numMissedDraws
      _nextExpectedEndTime +=
        _drawPeriodSeconds *
        (uint64((block.timestamp - _nextExpectedEndTime) / _drawPeriodSeconds));
    }

    return _nextExpectedEndTime;
  }

  /// @notice Calculates the number of tiers given the number of prize claims
  /// @dev This function will use the claim count to determine the number of tiers, then add one for the canary tier.
  /// @param _claimCount The number of prize claims
  /// @return The estimated number of tiers + the canary tier
  function _computeNextNumberOfTiers(uint32 _claimCount) internal view returns (uint8) {
    // claimCount is expected to be the estimated number of claims for the current prize tier.
    return _estimateNumberOfTiersUsingPrizeCountPerDraw(_claimCount) + 1;
  }

  /// @notice Calculates the number of tiers given the number of prize claims
  /// @dev This function will use the claim count to determine the number of tiers, then add one for the canary tier.
  /// @param _claimCount The number of prize claims
  /// @return The estimated number of tiers + the canary tier
  function computeNextNumberOfTiers(uint32 _claimCount) external view returns (uint8) {
    return _computeNextNumberOfTiers(_claimCount);
  }

  /// @notice Computes the tokens to be disbursed from the accumulator for a given draw.
  /// @param _drawId The ID of the draw to compute the disbursement for.
  /// @return The amount of tokens contributed to the accumulator for the given draw.
  function _contributionsForDraw(uint24 _drawId) internal view returns (uint256) {
    return
      DrawAccumulatorLib.getDisbursedBetween(
        _totalAccumulator,
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
    _totalWithdrawn = SafeCast.toUint160(_totalWithdrawn + _amount);
    prizeToken.safeTransfer(_to, _amount);
  }

  /**
   * @notice Checks if the given user has won the prize for the specified tier in the given vault.
   * @param _drawId The draw ID for which to check the winner
   * @param _vault The address of the vault to check
   * @param _user The address of the user to check for the prize
   * @param _tier The tier for which the prize is to be checked
   * @param _prizeIndex The prize index to check. Must be less than prize count for the tier
   * @param _vaultPortion The portion of the prizes that were contributed by the given vault
   * @param _tierOdds The tier odds to apply to make prizes less frequent
   * @param _drawDuration The duration of prize accrual for the given tier
   * @return A boolean value indicating whether the user has won the prize or not
   */
  function _isWinner(
    uint32 _drawId,
    address _vault,
    address _user,
    uint8 _tier,
    uint32 _prizeIndex,
    SD59x18 _vaultPortion,
    SD59x18 _tierOdds,
    uint24 _drawDuration
  ) internal view returns (bool) {
    uint32 tierPrizeCount = uint32(TierCalculationLib.prizeCount(_tier));

    if (_prizeIndex >= tierPrizeCount) {
      revert InvalidPrizeIndex(_prizeIndex, tierPrizeCount, _tier);
    }

    uint256 userSpecificRandomNumber = TierCalculationLib.calculatePseudoRandomNumber(
      _drawId,
      _vault,
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
        _userTwab,
        _vaultTwabTotalSupply,
        _vaultPortion,
        _tierOdds
      );
  }

  /**
   * @notice Computes the data needed for determining a winner of a prize from a specific vault for a specific draw.
   * @param _vault The address of the vault to check.
   * @param _tier The tier for which the prize is to be checked.
   * @param _numberOfTiers The number of tiers in the draw.
   * @param lastClosedDrawId_ The ID of the last closed draw.
   * @return vaultPortion The portion of the prizes that are going to this vault.
   * @return tierOdds The odds of winning the prize for the given tier.
   * @return drawDuration The duration of the draw.
   */
  function _computeVaultTierDetails(
    address _vault,
    uint8 _tier,
    uint8 _numberOfTiers,
    uint24 lastClosedDrawId_
  ) internal view returns (SD59x18 vaultPortion, SD59x18 tierOdds, uint24 drawDuration) {
    if (lastClosedDrawId_ == 0) {
      revert NoClosedDraw();
    }
    _checkValidTier(_tier, _numberOfTiers);

    tierOdds = _tierOdds(_tier, _numberOfTiers);
    drawDuration = uint24(TierCalculationLib.estimatePrizeFrequencyInDraws(tierOdds));
    vaultPortion = _getVaultPortion(
      _vault,
      SafeCast.toUint24(
        drawDuration > lastClosedDrawId_ ? 1 : lastClosedDrawId_ - drawDuration + 1
      ),
      lastClosedDrawId_,
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
    uint48 _endTimestamp = uint48(_lastClosedDrawStartedAt + drawPeriodSeconds);
    uint48 durationSeconds = uint48(_drawDuration * drawPeriodSeconds);
    uint48 _startTimestamp = _endTimestamp > durationSeconds ? _endTimestamp - durationSeconds : 0;

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
    uint24 _startDrawId,
    uint24 _endDrawId,
    SD59x18 _smoothing
  ) internal view returns (SD59x18) {
    uint256 totalContributed = DrawAccumulatorLib.getDisbursedBetween(
      _totalAccumulator,
      _startDrawId,
      _endDrawId,
      _smoothing
    );

    // vaultContributed / totalContributed
    return
      totalContributed != 0
        ? sd(
          SafeCast.toInt256(
            DrawAccumulatorLib.getDisbursedBetween(
              _vaultAccumulator[_vault],
              _startDrawId,
              _endDrawId,
              _smoothing
            )
          )
        ).div(sd(SafeCast.toInt256(totalContributed)))
        : sd(0);
  }
}
