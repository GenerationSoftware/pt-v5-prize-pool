// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { SD59x18, convert, sd } from "prb-math/SD59x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { UD34x4, intoUD60x18 as fromUD34x4toUD60x18 } from "./libraries/UD34x4.sol";
import { DrawAccumulatorLib, Observation } from "./libraries/DrawAccumulatorLib.sol";
import { TieredLiquidityDistributor, Tier } from "./abstract/TieredLiquidityDistributor.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";

/// @notice Emitted when the prize pool is constructed with a first draw open timestamp that is in the past
error FirstDrawOpensInPast();

/// @notice Emitted when the Twab Controller has an incompatible period length
error IncompatibleTwabPeriodLength();

/// @notice Emitted when the Twab Controller has an incompatible period offset
error IncompatibleTwabPeriodOffset();

/// @notice Emitted when someone tries to set the draw manager with the zero address
error DrawManagerIsZeroAddress();

/// @notice Emitted when the caller is not the deployer.
error NotDeployer();

/// @notice Emitted when the range start draw id is computed with range of zero
error RangeSizeZero();

/// @notice Emitted if the prize pool has shutdown
error PrizePoolShutdown();

/// @notice Emitted if the prize pool is not shutdown
error PrizePoolNotShutdown();

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

/// @notice Emitted when the claim reward exceeds the maximum.
/// @param reward The reward being claimed
/// @param maxReward The max reward that can be claimed
error RewardTooLarge(uint256 reward, uint256 maxReward);

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

/// @notice Emitted when the draw cannot be awarded since it has not closed.
/// @param drawClosesAt The timestamp in seconds at which the draw closes
error AwardingDrawNotClosed(uint48 drawClosesAt);

/// @notice Emitted when prize index is greater or equal to the max prize count for the tier.
/// @param invalidPrizeIndex The invalid prize index
/// @param prizeCount The prize count for the tier
/// @param tier The tier number
error InvalidPrizeIndex(uint32 invalidPrizeIndex, uint32 prizeCount, uint8 tier);

/// @notice Emitted when there are no awarded draws when a computation requires an awarded draw.
error NoDrawsAwarded();

/// @notice Emitted when the Prize Pool is constructed with a draw timeout of zero
error DrawTimeoutIsZero();

/// @notice Emitted when the Prize Pool is constructed with a draw timeout greater than the grand prize period draws
error DrawTimeoutGTGrandPrizePeriodDraws();

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

/// @notice Emitted when someone tries to claim a prize, but sets the reward recipient address to the zero address.
error RewardRecipientZeroAddress();

/// @notice Emitted when a claim is attempted after the claiming period has expired.
error ClaimPeriodExpired();

/**
 * @notice Constructor Parameters
 * @param prizeToken The token to use for prizes
 * @param twabController The Twab Controller to retrieve time-weighted average balances from
 * @param drawManager The Draw Manager address that will award draws
 * @param tierLiquidityUtilizationRate The rate at which liquidity is utilized for prize tiers. This allows for deviations in prize claims; if 0.75e18 then it is 75% utilization so it can accommodate 25% deviation in more prize claims.
 * @param drawPeriodSeconds The number of seconds between draws. E.g. a Prize Pool with a daily draw should have a draw period of 86400 seconds.
 * @param firstDrawOpensAt The timestamp at which the first draw will open.
 * @param numberOfTiers The number of tiers to start with. Must be greater than or equal to the minimum number of tiers.
 * @param tierShares The number of shares to allocate to each tier
 * @param reserveShares The number of shares to allocate to the reserve.
 * @param drawTimeout The number of draws that need to be missed before the prize pool shuts down
 */
struct ConstructorParams {
  IERC20 prizeToken;
  TwabController twabController; // 160bits
  address drawManager;
  uint256 tierLiquidityUtilizationRate; // fixed point 18 number
  uint48 drawPeriodSeconds;
  uint48 firstDrawOpensAt; // 256bits WORD END
  uint24 grandPrizePeriodDraws;
  uint8 numberOfTiers;
  uint8 tierShares;
  uint8 reserveShares; // 112 bits since prev word, meaning 144 bits left
  uint24 drawTimeout; // if the timeout elapses without a new draw, then the prize pool shuts down. The timeout resets when a draw is awarded.
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
  /// @param claimReward The amount of prize tokens that were paid to the claimer
  /// @param claimRewardRecipient The address that the claimReward was sent to
  event ClaimedPrize(
    address indexed vault,
    address indexed winner,
    address indexed recipient,
    uint24 drawId,
    uint8 tier,
    uint32 prizeIndex,
    uint152 payout,
    uint96 claimReward,
    address claimRewardRecipient
  );

  /// @notice Emitted when a draw is awarded.
  /// @param drawId The ID of the draw that was awarded
  /// @param winningRandomNumber The winning random number for the awarded draw
  /// @param lastNumTiers The previous number of prize tiers
  /// @param numTiers The number of prize tiers for the awarded draw
  /// @param reserve The resulting reserve available
  /// @param prizeTokensPerShare The amount of prize tokens per share for the awarded draw
  /// @param drawOpenedAt The start timestamp of the awarded draw
  event DrawAwarded(
    uint24 indexed drawId,
    uint256 winningRandomNumber,
    uint8 lastNumTiers,
    uint8 numTiers,
    uint104 reserve,
    UD34x4 prizeTokensPerShare,
    uint48 drawOpenedAt
  );

  /// @notice Emitted when any amount of the reserve is rewarded to a recipient.
  /// @param to The recipient of the reward
  /// @param amount The amount of assets rewarded
  event AllocateRewardFromReserve(address indexed to, uint256 amount);

  /// @notice Emitted when the reserve is manually increased.
  /// @param user The user who increased the reserve
  /// @param amount The amount of assets transferred
  event ContributedReserve(address indexed user, uint256 amount);

  /// @notice Emitted when a vault contributes prize tokens to the pool.
  /// @param vault The address of the vault that is contributing tokens
  /// @param drawId The ID of the first draw that the tokens will be contributed to
  /// @param amount The amount of tokens contributed
  event ContributePrizeTokens(address indexed vault, uint24 indexed drawId, uint256 amount);

  /// @notice Emitted when an address withdraws their prize claim rewards.
  /// @param account The account that is withdrawing rewards
  /// @param to The address the rewards are sent to
  /// @param amount The amount withdrawn
  /// @param available The total amount that was available to withdraw before the transfer
  event WithdrawRewards(
    address indexed account,
    address indexed to,
    uint256 amount,
    uint256 available
  );

  /// @notice Emitted when an address receives new prize claim rewards.
  /// @param to The address the rewards are given to
  /// @param amount The amount increased
  event IncreaseClaimRewards(address indexed to, uint256 amount);

  /* ============ State ============ */

  /// @notice The DrawAccumulator that tracks the exponential moving average of the contributions by a vault.
  mapping(address vault => DrawAccumulatorLib.Accumulator accumulator) internal _vaultAccumulator;

  /// @notice Records the claim record for a winner.
  mapping(address vault => mapping(address account => mapping(uint24 drawId => mapping(uint8 tier => mapping(uint32 prizeIndex => bool claimed)))))
    internal _claimedPrizes;

  /// @notice Tracks the total rewards accrued for a claimer or draw completer.
  mapping(address recipient => uint256 rewards) internal _rewards;

  /// @notice Records the last shutdown withdrawal for an account
  mapping(address vault => mapping(address user => uint24 drawId)) internal _lastShutdownWithdrawal;

  /// @notice The token that is being contributed and awarded as prizes.
  IERC20 public immutable prizeToken;

  /// @notice The Twab Controller to use to retrieve historic balances.
  TwabController public immutable twabController;

  /// @notice The number of seconds between draws.
  uint48 public immutable drawPeriodSeconds;

  /// @notice The timestamp at which the first draw will open.
  uint48 public immutable firstDrawOpensAt;

  /// @notice The maximum number of draws that can be missed before the prize pool is considered inactive.
  uint24 public immutable drawTimeout;

  /// @notice The exponential weighted average of all vault contributions.
  DrawAccumulatorLib.Accumulator internal _totalAccumulator;

  /// @notice The winner random number for the last awarded draw.
  uint256 internal _winningRandomNumber;

  /// @notice The draw manager address.
  address public drawManager;

  /// @notice Tracks reserve that was contributed directly to the reserve. Always increases.
  uint96 internal _directlyContributedReserve;

  /// @notice The number of prize claims for the last awarded draw.
  uint24 public claimCount;

  /// @notice The total amount of prize tokens that have been claimed for all time.
  uint128 internal _totalWithdrawn;

  /// @notice The total amount of rewards that have yet to be claimed
  uint104 internal _totalRewardsToBeClaimed;

  /* ============ Constructor ============ */

  /// @notice Constructs a new Prize Pool.
  /// @param params A struct of constructor parameters
  constructor(
    ConstructorParams memory params
  )
    TieredLiquidityDistributor(
      params.tierLiquidityUtilizationRate,
      params.numberOfTiers,
      params.tierShares,
      params.reserveShares,
      params.grandPrizePeriodDraws
    )
  {
    if (params.drawTimeout == 0) {
      revert DrawTimeoutIsZero();
    }

    if (params.drawTimeout > params.grandPrizePeriodDraws) {
      revert DrawTimeoutGTGrandPrizePeriodDraws();
    }

    if (params.firstDrawOpensAt < block.timestamp) {
      revert FirstDrawOpensInPast();
    }

    uint48 twabPeriodOffset = params.twabController.PERIOD_OFFSET();
    uint48 twabPeriodLength = params.twabController.PERIOD_LENGTH();

    if (
      params.drawPeriodSeconds < twabPeriodLength ||
      params.drawPeriodSeconds % twabPeriodLength != 0
    ) {
      revert IncompatibleTwabPeriodLength();
    }

    if ((params.firstDrawOpensAt - twabPeriodOffset) % twabPeriodLength != 0) {
      revert IncompatibleTwabPeriodOffset();
    }

    if (params.drawManager == address(0)) {
      revert DrawManagerIsZeroAddress();
    }

    drawManager = params.drawManager;
    drawTimeout = params.drawTimeout;
    prizeToken = params.prizeToken;
    twabController = params.twabController;
    drawPeriodSeconds = params.drawPeriodSeconds;
    firstDrawOpensAt = params.firstDrawOpensAt;
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

  /// @notice Contributes prize tokens on behalf of the given vault.
  /// @dev The tokens should have already been transferred to the prize pool.
  /// @dev The prize pool balance will be checked to ensure there is at least the given amount to deposit.
  /// @param _prizeVault The address of the vault to contribute to
  /// @param _amount The amount of prize tokens to contribute
  /// @return The amount of available prize tokens prior to the contribution.
  function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns (uint256) {
    uint256 _deltaBalance = prizeToken.balanceOf(address(this)) - accountedBalance();
    if (_deltaBalance < _amount) {
      revert ContributionGTDeltaBalance(_amount, _deltaBalance);
    }
    uint24 openDrawId_ = getOpenDrawId();
    DrawAccumulatorLib.add(_vaultAccumulator[_prizeVault], _amount, openDrawId_);
    DrawAccumulatorLib.add(_totalAccumulator, _amount, openDrawId_);
    emit ContributePrizeTokens(_prizeVault, openDrawId_, _amount);
    return _deltaBalance;
  }

  /// @notice Allows the Manager to allocate a reward from the reserve to a recipient.
  /// @param _to The address to allocate the rewards to
  /// @param _amount The amount of tokens for the reward
  function allocateRewardFromReserve(address _to, uint96 _amount) external onlyDrawManager {
    if (_amount > _reserve) {
      revert InsufficientReserve(_amount, _reserve);
    }

    unchecked {
      _reserve -= _amount;
    }

    _rewards[_to] += _amount;
    _totalRewardsToBeClaimed = SafeCast.toUint104(_totalRewardsToBeClaimed + _amount);
    emit AllocateRewardFromReserve(_to, _amount);
  }

  /// @notice Allows the Manager to award a draw with the winning random number.
  /// @dev Updates the number of tiers, the winning random number and the prize pool reserve.
  /// @param winningRandomNumber_ The winning random number for the draw
  /// @return The ID of the awarded draw
  function awardDraw(uint256 winningRandomNumber_) external onlyDrawManager notShutdown returns (uint24) {
    // check winning random number
    if (winningRandomNumber_ == 0) {
      revert RandomNumberIsZero();
    }
    uint24 awardingDrawId = getDrawIdToAward();
    uint48 awardingDrawOpenedAt = drawOpensAt(awardingDrawId);
    uint48 awardingDrawClosedAt = awardingDrawOpenedAt + drawPeriodSeconds;
    if (block.timestamp < awardingDrawClosedAt) {
      revert AwardingDrawNotClosed(awardingDrawClosedAt);
    }

    uint24 lastAwardedDrawId_ = _lastAwardedDrawId;
    uint32 _claimCount = claimCount;
    uint8 _numTiers = numberOfTiers;
    uint8 _nextNumberOfTiers = _numTiers;

    if (lastAwardedDrawId_ != 0) {
      _nextNumberOfTiers = computeNextNumberOfTiers(_claimCount);
    }

    // If any draws were skipped from the last awarded draw to the one we are awarding, the contribution
    // from those skipped draws will be included in the new distributions.
    _awardDraw(
      awardingDrawId,
      _nextNumberOfTiers,
      getTotalContributedBetween(lastAwardedDrawId_ + 1, awardingDrawId)
    );

    _winningRandomNumber = winningRandomNumber_;
    if (_claimCount != 0) {
      claimCount = 0;
    }

    emit DrawAwarded(
      awardingDrawId,
      winningRandomNumber_,
      _numTiers,
      _nextNumberOfTiers,
      _reserve,
      prizeTokenPerShare,
      awardingDrawOpenedAt
    );

    return awardingDrawId;
  }

  /**
   * @notice Claims a prize for a given winner and tier.
   * @dev This function takes in an address _winner, a uint8 _tier, a uint96 _claimReward, and an
   * address _claimRewardRecipient. It checks if _winner is actually the winner of the _tier for the calling vault.
   * If so, it calculates the prize size and transfers it to the winner. If not, it reverts with an error message.
   * The function then checks the claim record of _winner to see if they have already claimed the prize for the
   * awarded draw. If not, it updates the claim record with the claimed tier and emits a ClaimedPrize event with
   * information about the claim.
   * Note that this function can modify the state of the contract by updating the claim record, changing the largest
   * tier claimed and the claim count, and transferring prize tokens. The function is marked as external which
   * means that it can be called from outside the contract.
   * @param _tier The tier of the prize to be claimed.
   * @param _winner The address of the eligible winner
   * @param _prizeIndex The prize to claim for the winner. Must be less than the prize count for the tier.
   * @param _prizeRecipient The recipient of the prize
   * @param _claimReward The claimReward associated with claiming the prize.
   * @param _claimRewardRecipient The address to receive the claimReward.
   * @return Total prize amount claimed (payout and claimRewards combined). If the prize was already claimed it returns zero.
   */
  function claimPrize(
    address _winner,
    uint8 _tier,
    uint32 _prizeIndex,
    address _prizeRecipient,
    uint96 _claimReward,
    address _claimRewardRecipient
  ) external returns (uint256) {
    /**
     * @dev Claims cannot occur after a draw has been finalized (1 period after a draw closes). This prevents
     * the reserve from changing while the following draw is being awarded.
     */
    uint24 lastAwardedDrawId_ = _lastAwardedDrawId;
    if (isDrawFinalized(lastAwardedDrawId_)) {
      revert ClaimPeriodExpired();
    }
    if (_claimRewardRecipient == address(0) && _claimReward > 0) {
      revert RewardRecipientZeroAddress();
    }

    uint8 _numTiers = numberOfTiers;

    Tier memory tierLiquidity = _getTier(_tier, _numTiers);

    if (_claimReward > tierLiquidity.prizeSize) {
      revert RewardTooLarge(_claimReward, tierLiquidity.prizeSize);
    }

    if (tierLiquidity.prizeSize == 0) {
      revert PrizeIsZero();
    }

    if (!isWinner(msg.sender, _winner, _tier, _prizeIndex)) {
      revert DidNotWin(msg.sender, _winner, _tier, _prizeIndex);
    }

    if (_claimedPrizes[msg.sender][_winner][lastAwardedDrawId_][_tier][_prizeIndex]) {
      return 0;
    }

    _claimedPrizes[msg.sender][_winner][lastAwardedDrawId_][_tier][_prizeIndex] = true;

    // `amount` is a snapshot of the reserve before consuming liquidity
    _consumeLiquidity(tierLiquidity, _tier, tierLiquidity.prizeSize);

    // `amount` is now the payout amount
    uint256 amount;
    if (_claimReward != 0) {
      emit IncreaseClaimRewards(_claimRewardRecipient, _claimReward);
      _rewards[_claimRewardRecipient] += _claimReward;

      unchecked {
        amount = tierLiquidity.prizeSize - _claimReward;
      }
    } else {
      amount = tierLiquidity.prizeSize;
    }

    // co-locate to save gas
    claimCount++;
    _totalWithdrawn = SafeCast.toUint128(_totalWithdrawn + amount);
    _totalRewardsToBeClaimed = SafeCast.toUint104(_totalRewardsToBeClaimed + _claimReward);

    emit ClaimedPrize(
      msg.sender,
      _winner,
      _prizeRecipient,
      lastAwardedDrawId_,
      _tier,
      _prizeIndex,
      uint152(amount),
      _claimReward,
      _claimRewardRecipient
    );

    prizeToken.safeTransfer(_prizeRecipient, amount);

    return tierLiquidity.prizeSize;
  }

  /**
   * @notice Withdraws earned rewards for the caller.
   * @param _to The address to transfer the rewards to
   * @param _amount The amount of rewards to withdraw
   */
  function withdrawRewards(address _to, uint256 _amount) external {
    uint256 _available = _rewards[msg.sender];

    if (_amount > _available) {
      revert InsufficientRewardsError(_amount, _available);
    }

    unchecked {
      _rewards[msg.sender] = _available - _amount;
    }

    _totalWithdrawn = SafeCast.toUint128(_totalWithdrawn + _amount);
    _totalRewardsToBeClaimed = SafeCast.toUint104(_totalRewardsToBeClaimed - _amount);

    prizeToken.safeTransfer(_to, _amount);

    emit WithdrawRewards(msg.sender, _to, _amount, _available);
  }

  /// @notice Allows anyone to deposit directly into the Prize Pool reserve.
  /// @dev Ensure caller has sufficient balance and has approved the Prize Pool to transfer the tokens
  /// @param _amount The amount of tokens to increase the reserve by
  function contributeReserve(uint96 _amount) external notShutdown {
    _reserve += _amount;
    _directlyContributedReserve += _amount;
    prizeToken.safeTransferFrom(msg.sender, address(this), _amount);
    emit ContributedReserve(msg.sender, _amount);
  }

  /* ============ External Read Functions ============ */

  /// @notice Returns the winning random number for the last awarded draw.
  /// @return The winning random number
  function getWinningRandomNumber() external view returns (uint256) {
    return _winningRandomNumber;
  }

  /// @notice Returns the last awarded draw id.
  /// @return The last awarded draw id
  function getLastAwardedDrawId() external view returns (uint24) {
    return _lastAwardedDrawId;
  }

  /// @notice Returns the total prize tokens contributed by a particular vault between the given draw ids, inclusive.
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
        _endDrawIdInclusive
      );
  }

  /// @notice Computes the expected duration prize accrual for a tier.
  /// @param _tier The tier to check
  /// @return The number of draws
  function getTierAccrualDurationInDraws(uint8 _tier) external view returns (uint24) {
    return
      uint24(TierCalculationLib.estimatePrizeFrequencyInDraws(getTierOdds(_tier, numberOfTiers)));
  }

  /// @notice The total amount of prize tokens that have been withdrawn as fees or prizes
  /// @return The total amount of prize tokens that have been withdrawn as fees or prizes
  function totalWithdrawn() external view returns (uint256) {
    return _totalWithdrawn;
  }

  /// @notice Returns the amount of tokens that will be added to the reserve when next draw to award is awarded.
  /// @dev Intended for Draw manager to use after a draw has closed but not yet been awarded.
  /// @return The amount of prize tokens that will be added to the reserve
  function pendingReserveContributions() external view returns (uint256) {
    uint8 _numTiers = numberOfTiers;
    uint24 lastAwardedDrawId_ = _lastAwardedDrawId;

    (uint104 newReserve, ) = _computeNewDistributions(
      _numTiers,
      lastAwardedDrawId_ == 0 ? _numTiers : computeNextNumberOfTiers(claimCount),
      fromUD34x4toUD60x18(prizeTokenPerShare),
      getTotalContributedBetween(lastAwardedDrawId_ + 1, getDrawIdToAward())
    );

    return newReserve;
  }

  /// @notice Returns whether the winner has claimed the tier for the last awarded draw
  /// @param _vault The vault to check
  /// @param _winner The account to check
  /// @param _tier The tier to check
  /// @param _prizeIndex The prize index to check
  /// @return True if the winner claimed the tier for the last awarded draw, false otherwise.
  function wasClaimed(
    address _vault,
    address _winner,
    uint8 _tier,
    uint32 _prizeIndex
  ) external view returns (bool) {
    return _claimedPrizes[_vault][_winner][_lastAwardedDrawId][_tier][_prizeIndex];
  }

  /**
   * @notice Returns the balance of rewards earned for the given address.
   * @param _recipient The recipient to retrieve the reward balance for
   * @return The balance of rewards for the given recipient
   */
  function rewardBalance(address _recipient) external view returns (uint256) {
    return _rewards[_recipient];
  }

  /**
   * @notice Computes and returns the next number of tiers based on the current prize claim counts. This number may change throughout the draw
   * @return The next number of tiers
   */
  function estimateNextNumberOfTiers() external view returns (uint8) {
    return computeNextNumberOfTiers(claimCount);
  }

  /* ============ Internal Functions ============ */

  /// @notice Computes how many tokens have been accounted for
  /// @return The balance of tokens that have been accounted for
  function accountedBalance() public view returns (uint256) {
    Observation memory obs = _totalAccumulator.observations[
      DrawAccumulatorLib.newestDrawId(_totalAccumulator)
    ];
    // totalRewards would be added to the below accounted balance.
    // obs.disbursed include the reserve, prizes, and prize liquidity

    /*
       obs.disbursed is the total amount of tokens all-time contributed by vaults and released. These tokens may:
       - still be held for future prizes
       - have been given as prizes
       - have been captured as fees
    */
    // obs.available is the total number of tokens that WILL be disbursed in the future.
    // _directlyContributedReserve are tokens that have been contributed directly to the reserve
    // totalWithdrawn represents all tokens that have been withdrawn

    return (obs.available + obs.disbursed) + uint256(_directlyContributedReserve) - uint256(_totalWithdrawn);
  }

  /// @notice Returns the open draw ID based on the current block timestamp.
  /// @dev Returns `1` if the first draw hasn't opened yet. This prevents any contributions from
  /// going to the inaccessible draw zero.
  /// @dev First draw has an ID of `1`. This means that if `_lastAwardedDrawId` is zero,
  /// we know that no draws have been awarded yet.
  /// @return The ID of the draw period that the current block is in
  function getOpenDrawId() public view returns (uint24) {
    uint48 _firstDrawOpensAt = firstDrawOpensAt;
    return
      (block.timestamp < _firstDrawOpensAt)
        ? 1
        : (uint24((block.timestamp - _firstDrawOpensAt) / drawPeriodSeconds) + 1);
  }

  /// @notice Returns the next draw ID that can be awarded.
  /// @dev It's possible for draws to be missed, so the next draw ID to award
  /// may be more than one draw ahead of the last awarded draw ID.
  /// @return The next draw ID that can be awarded
  function getDrawIdToAward() public view returns (uint24) {
    uint24 openDrawId_ = getOpenDrawId();
    return (openDrawId_ - _lastAwardedDrawId) > 1 ? openDrawId_ - 1 : openDrawId_;
  }

  /// @notice Returns the time at which a draw opens / opened at.
  /// @param drawId The draw to get the timestamp for
  /// @return The start time of the draw in seconds
  function drawOpensAt(uint24 drawId) public view returns (uint48) {
    return firstDrawOpensAt + (drawId - 1) * drawPeriodSeconds;
  }

  /// @notice Returns the time at which a draw closes / closed at.
  /// @param drawId The draw to get the timestamp for
  /// @return The end time of the draw in seconds
  function drawClosesAt(uint24 drawId) public view returns (uint48) {
    return firstDrawOpensAt + drawId * drawPeriodSeconds;
  }

  /// @notice Checks if the given draw is finalized.
  /// @param drawId The draw to check
  /// @return True if the draw is finalized, false otherwise
  function isDrawFinalized(uint24 drawId) public view returns (bool) {
    return block.timestamp >= drawClosesAt(drawId + 1);
  }

  /// @notice Calculates the number of tiers given the number of prize claims
  /// @dev This function will use the claim count to determine the number of tiers, then add one for the canary tier.
  /// @param _claimCount The number of prize claims
  /// @return The estimated number of tiers + the canary tier
  function computeNextNumberOfTiers(uint32 _claimCount) public view returns (uint8) {
    // claimCount is expected to be the estimated number of claims for the current prize tier.
    uint8 nextNumberOfTiers = _estimateNumberOfTiersUsingPrizeCountPerDraw(_claimCount) + 1;
    // limit change to 1 tier
    uint8 _numTiers = numberOfTiers;
    if (nextNumberOfTiers > _numTiers) {
      nextNumberOfTiers = _numTiers + 1;
    } else if (nextNumberOfTiers < _numTiers) {
      nextNumberOfTiers = _numTiers - 1;
    }
    return nextNumberOfTiers;
  }

  function shutdownBalanceOf(address _vault, address _account) public view returns (uint256) {
    if (!isShutdown()) {
      return 0;
    }

    // any liquidity prior to now
    uint24 shutdownDrawId = drawIdPriorToShutdown();
    uint24 startDrawIdInclusive = computeRangeStartDrawIdInclusive(shutdownDrawId, grandPrizePeriodDraws);

    SD59x18 vaultPortion = getVaultPortion(
      _vault,
      startDrawIdInclusive,
      shutdownDrawId
    );

    (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = getVaultUserBalanceAndTotalSupplyTwab(
      _vault,
      _account,
      startDrawIdInclusive,
      shutdownDrawId
    );

    uint24 drawIdToAward = getDrawIdToAward();
    uint24 lastWithdrawalDrawId = _lastShutdownWithdrawal[_vault][_account];

    uint256 liquidity;

    uint24 claimStartDrawId;

    // if there are previously disbursed funds, then we need to exclude prev claims.
    if (_lastAwardedDrawId != 0 && lastWithdrawalDrawId < shutdownDrawId) {
      // subtract whatever (if anything) was contributed after the shutdown draw id and the rewards to be claimed
      uint256 liquidityAfter;
      if (shutdownDrawId < drawIdToAward) {
        liquidityAfter += getTotalContributedBetween(shutdownDrawId + 1, drawIdToAward);
      }
      liquidity = accountedBalance() - liquidityAfter - _totalRewardsToBeClaimed;
      claimStartDrawId = shutdownDrawId;
    } else {
      claimStartDrawId = lastWithdrawalDrawId; 
    }
    
    if (claimStartDrawId < drawIdToAward) {
      liquidity += getTotalContributedBetween(claimStartDrawId + 1, drawIdToAward);
    }

    uint256 balance;
    if (liquidity != 0 && _vaultTwabTotalSupply != 0) {
      balance = uint256(convert(
        vaultPortion.mul(
          convert(int256(_userTwab)).div(convert(int256(_vaultTwabTotalSupply)))
        ).mul(convert(int256(liquidity)))
      ));
    }

    return balance;
  }

  function withdrawShutdownBalance(address _vault, address _recipient) external returns (uint256) {
    if (!isShutdown()) {
      revert PrizePoolNotShutdown();
    }
    uint256 balance = shutdownBalanceOf(_vault, msg.sender);
    if (balance > 0) {
      _lastShutdownWithdrawal[_vault][msg.sender] = getDrawIdToAward();
      prizeToken.safeTransfer(_recipient, balance);
      _totalWithdrawn += uint128(balance);
    }
    return balance;
  }

  function drawIdPriorToShutdown() public view returns (uint24) {
    return _lastAwardedDrawId + drawTimeout;
  }

  function shutdownAt() public view returns (uint256) {
    uint256 twabShutdownAt = twabController.lastObservationAt();
    uint256 drawTimeoutAt_ = drawTimeoutAt();
    return drawTimeoutAt_ < twabShutdownAt ? drawTimeoutAt_ : twabShutdownAt;
  }

  function isShutdown() public view returns (bool shutdown) {
    shutdown = block.timestamp >= shutdownAt();
  }

  /**
   * Returns the timestamp at which the prize pool will be considered inactive
   */
  function drawTimeoutAt() public view returns (uint256) { 
    return drawClosesAt(drawIdPriorToShutdown());
  }

  /// @notice Returns the total prize tokens contributed between the given draw ids, inclusive.
  /// @param _startDrawIdInclusive Start draw id inclusive
  /// @param _endDrawIdInclusive End draw id inclusive
  /// @return The total prize tokens contributed by all vaults
  function getTotalContributedBetween(
    uint24 _startDrawIdInclusive,
    uint24 _endDrawIdInclusive
  ) public view returns (uint256) {
    return
      DrawAccumulatorLib.getDisbursedBetween(
        _totalAccumulator,
        _startDrawIdInclusive,
        _endDrawIdInclusive
      );
  }

  /**
   * @notice Checks if the given user has won the prize for the specified tier in the given vault.
   * @param _vault The address of the vault to check
   * @param _user The address of the user to check for the prize
   * @param _tier The tier for which the prize is to be checked
   * @param _prizeIndex The prize index to check. Must be less than prize count for the tier
   * @return A boolean value indicating whether the user has won the prize or not
   */
  function isWinner(
    address _vault,
    address _user,
    uint8 _tier,
    uint32 _prizeIndex
  ) public view returns (bool) {
    uint24 lastAwardedDrawId_ = _lastAwardedDrawId;

    if (lastAwardedDrawId_ == 0) {
      revert NoDrawsAwarded();
    }
    if (_tier >= numberOfTiers) {
      revert InvalidTier(_tier, numberOfTiers);
    }

    SD59x18 tierOdds = getTierOdds(_tier, numberOfTiers);
    uint24 startDrawIdInclusive = computeRangeStartDrawIdInclusive(lastAwardedDrawId_, uint24(TierCalculationLib.estimatePrizeFrequencyInDraws(tierOdds)));

    uint32 tierPrizeCount = uint32(TierCalculationLib.prizeCount(_tier));

    if (_prizeIndex >= tierPrizeCount) {
      revert InvalidPrizeIndex(_prizeIndex, tierPrizeCount, _tier);
    }

    uint256 userSpecificRandomNumber = TierCalculationLib.calculatePseudoRandomNumber(
      lastAwardedDrawId_,
      _vault,
      _user,
      _tier,
      _prizeIndex,
      _winningRandomNumber
    );
    
    SD59x18 vaultPortion = getVaultPortion(
      _vault,
      startDrawIdInclusive,
      lastAwardedDrawId_
    );

    (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = getVaultUserBalanceAndTotalSupplyTwab(
      _vault,
      _user,
      startDrawIdInclusive,
      lastAwardedDrawId_
    );

    return
      TierCalculationLib.isWinner(
        userSpecificRandomNumber,
        _userTwab,
        _vaultTwabTotalSupply,
        vaultPortion,
        tierOdds
      );
  }

  function computeRangeStartDrawIdInclusive(uint24 _endDrawIdInclusive, uint24 _rangeSize) public pure returns (uint24) {
    if (_rangeSize != 0) {
      return _rangeSize > _endDrawIdInclusive ? 1 : _endDrawIdInclusive - _rangeSize + 1;
    } else {
      revert RangeSizeZero();
    }
  }

  /**
   * @notice Returns the time-weighted average balance (TWAB) and the TWAB total supply for the specified user in the given vault over a specified period.
   * @dev This function calculates the TWAB for a user by calling the getTwabBetween function of the TWAB controller for a specified period of time.
   * @param _vault The address of the vault for which to get the TWAB.
   * @param _user The address of the user for which to get the TWAB.
   * @param _startDrawIdInclusive The starting draw for the range (inclusive)
   * @param _endDrawIdInclusive The end draw for the range (inclusive)
   * @return twab The TWAB for the specified user in the given vault over the specified period.
   * @return twabTotalSupply The TWAB total supply over the specified period.
   */
  function getVaultUserBalanceAndTotalSupplyTwab(
    address _vault,
    address _user,
    uint24 _startDrawIdInclusive,
    uint24 _endDrawIdInclusive
  ) public view returns (uint256 twab, uint256 twabTotalSupply) {
    uint48 _startTimestamp = drawOpensAt(_startDrawIdInclusive);
    uint48 _endTimestamp = drawClosesAt(_endDrawIdInclusive);
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
   * @param _startDrawIdInclusive The starting draw ID (inclusive) of the draw range to calculate the contribution portion for.
   * @param _endDrawIdInclusive The ending draw ID (inclusive) of the draw range to calculate the contribution portion for.
   * @return The portion of the vault's contribution to the prize pool over the specified duration in draws.
   */
  function getVaultPortion(
    address _vault,
    uint24 _startDrawIdInclusive,
    uint24 _endDrawIdInclusive
  ) public view returns (SD59x18) {
    uint256 totalContributed = DrawAccumulatorLib.getDisbursedBetween(
      _totalAccumulator,
      _startDrawIdInclusive,
      _endDrawIdInclusive
    );

    // vaultContributed / totalContributed
    return
      totalContributed != 0
        ? sd(
          SafeCast.toInt256(
            DrawAccumulatorLib.getDisbursedBetween(
              _vaultAccumulator[_vault],
              _startDrawIdInclusive,
              _endDrawIdInclusive
            )
          )
        ).div(sd(SafeCast.toInt256(totalContributed)))
        : sd(0);
  }

  modifier notShutdown() {
    if (isShutdown()) {
      revert PrizePoolShutdown();
    }
    _;
  }
}
