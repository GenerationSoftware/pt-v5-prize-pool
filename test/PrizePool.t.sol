// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { sd, SD59x18 } from "prb-math/SD59x18.sol";
import { UD34x4, fromUD34x4 } from "../src/libraries/UD34x4.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD1x18, sd1x18 } from "prb-math/SD1x18.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { TierCalculationLib } from "../src/libraries/TierCalculationLib.sol";
import { MAXIMUM_NUMBER_OF_TIERS, MINIMUM_NUMBER_OF_TIERS } from "../src/abstract/TieredLiquidityDistributor.sol";
import { PrizePool, PrizeIsZero, ConstructorParams, InsufficientRewardsError, DidNotWin, FeeTooLarge, SmoothingGTEOne, ContributionGTDeltaBalance, InsufficientReserve, RandomNumberIsZero, DrawNotFinished, InvalidPrizeIndex, NoClosedDraw, InvalidTier, DrawManagerIsZeroAddress, CallerNotDrawManager, NotDeployer, FeeRecipientZeroAddress, FirstDrawStartsInPast, IncompatibleTwabPeriodLength, IncompatibleTwabPeriodOffset, ClaimPeriodExpired } from "../src/PrizePool.sol";
import { ERC20Mintable } from "./mocks/ERC20Mintable.sol";

contract PrizePoolTest is Test {
  PrizePool public prizePool;

  ERC20Mintable public prizeToken;

  address public vault;
  address public vault2;

  TwabController public twabController;

  address sender1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
  address sender2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
  address sender3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
  address sender4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
  address sender5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
  address sender6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

  uint TIER_SHARES = 100;
  uint RESERVE_SHARES = 10;

  uint24 grandPrizePeriodDraws = 365;
  uint48 firstDrawStartsAt;
  uint32 drawPeriodSeconds;
  uint8 initialNumberOfTiers;
  uint256 winningRandomNumber = 123456;
  uint256 startTimestamp = 1000 days;

  /**********************************************************************************
   * Events copied from PrizePool.sol
   **********************************************************************************/
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
    uint48 drawStartedAt
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
  /// @param drawId The ID of the first draw that the tokens will be applied to
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

  /// @notice Emitted when the drawManager is set.
  /// @param drawManager The draw manager
  event DrawManagerSet(address indexed drawManager);

  /**********************************************************************************/

  ConstructorParams params;

  function setUp() public {
    vm.warp(startTimestamp);

    prizeToken = new ERC20Mintable("PoolTogether POOL token", "POOL");
    drawPeriodSeconds = 1 days;
    twabController = new TwabController(drawPeriodSeconds, uint32(block.timestamp));

    firstDrawStartsAt = uint48(block.timestamp + 1 days); // set draw start 1 day into future
    initialNumberOfTiers = 3;

    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_OFFSET, ()),
      abi.encode(firstDrawStartsAt)
    );
    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_LENGTH, ()),
      abi.encode(drawPeriodSeconds)
    );

    address drawManager = address(this);
    vault = address(this);
    vault2 = address(0x1234);

    params = ConstructorParams(
      prizeToken,
      twabController,
      drawPeriodSeconds,
      firstDrawStartsAt,
      sd1x18(0.9e18), // alpha
      grandPrizePeriodDraws,
      initialNumberOfTiers, // minimum number of tiers
      uint8(TIER_SHARES),
      uint8(RESERVE_SHARES)
    );

    prizePool = new PrizePool(params);

    vm.expectEmit();
    emit DrawManagerSet(drawManager);
    prizePool.setDrawManager(drawManager);
  }

  function testConstructor() public {
    assertEq(prizePool.firstDrawStartsAt(), firstDrawStartsAt);
    assertEq(prizePool.drawPeriodSeconds(), drawPeriodSeconds);
  }

  function testConstructor_SmoothingGTEOne() public {
    params.smoothing = sd1x18(1.0e18); // smoothing
    vm.expectRevert(abi.encodeWithSelector(SmoothingGTEOne.selector, 1000000000000000000));
    new PrizePool(params);
  }

  function testConstructor_FirstDrawStartsInPast() public {
    vm.expectRevert(abi.encodeWithSelector(FirstDrawStartsInPast.selector));
    params.firstDrawStartsAt = 1 days;
    vm.warp(2 days);
    new PrizePool(params);
  }

  function testConstructor_IncompatibleTwabPeriodLength_longer() public {
    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_LENGTH, ()),
      abi.encode(drawPeriodSeconds * 2)
    );
    vm.expectRevert(abi.encodeWithSelector(IncompatibleTwabPeriodLength.selector));
    new PrizePool(params);
  }

  function testConstructor_IncompatibleTwabPeriodLength_not_modulo() public {
    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_LENGTH, ()),
      abi.encode(drawPeriodSeconds + 1)
    );
    vm.expectRevert(abi.encodeWithSelector(IncompatibleTwabPeriodLength.selector));
    new PrizePool(params);
  }

  function testConstructor_IncompatibleTwabPeriodOffset_notAligned() public {
    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_OFFSET, ()),
      abi.encode(params.firstDrawStartsAt - 1)
    );
    vm.expectRevert(abi.encodeWithSelector(IncompatibleTwabPeriodOffset.selector));
    new PrizePool(params);
  }

  function testReserve_noRemainder() public {
    contribute(310e18);
    closeDraw(winningRandomNumber);

    // reserve + remainder
    assertEq(prizePool.reserve(), 1e18);
  }

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

  /**********************************************************************************/
  function testContributedReserve() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);

    uint prizesPerShare = 10e18 / prizePool.getTotalShares();
    uint remainder = 10e18 - prizesPerShare * prizePool.getTotalShares();

    uint reserve = (prizesPerShare * RESERVE_SHARES) + remainder;

    assertEq(prizePool.reserve(), reserve);

    // increase reserve
    vm.startPrank(sender1);
    prizeToken.mint(sender1, 100e18);
    prizeToken.approve(address(prizePool), 100e18);

    vm.expectEmit();
    emit ContributedReserve(sender1, 100e18);
    prizePool.contributeReserve(100e18);

    assertEq(prizePool.reserve(), 100e18 + reserve);
    assertEq(prizePool.accountedBalance(), 200e18);
  }

  function testContributedReserve_Max() public {
    vm.startPrank(sender1);
    prizeToken.mint(sender1, type(uint104).max);
    prizeToken.approve(address(prizePool), type(uint104).max);
    assertEq(prizePool.reserve(), 0);
    // increase reserve by max amount
    prizePool.contributeReserve(type(uint96).max);
    assertEq(prizePool.reserve(), type(uint96).max);
  }

  function testReserve_withRemainder() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.reserve(), 0.322580645161290400e18);
  }

  function testReserveForOpenDraw_noDraw() public {
    contribute(100e18);
    uint reserve = 0.322580645161290400e18;
    assertEq(prizePool.reserveForOpenDraw(), reserve);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.reserve(), reserve);
  }

  function testReserveForOpenDraw_existingDraw() public {
    contribute(100e18);
    uint firstPrizesPerShare = 10e18 / prizePool.getTotalShares();
    // 0.322580645161290400 in reserve
    closeDraw(winningRandomNumber);

    // new liq + reclaimed canary
    uint draw2Liquidity = 8999999999999998700;
    uint reclaimedLiquidity = (TIER_SHARES * firstPrizesPerShare);
    uint newLiquidity = draw2Liquidity + reclaimedLiquidity;
    uint newPrizesPerShare = newLiquidity / prizePool.getTotalShares();
    uint remainder = newLiquidity - newPrizesPerShare * prizePool.getTotalShares();
    uint newReserve = (newPrizesPerShare * RESERVE_SHARES) + remainder;

    assertEq(prizePool.reserveForOpenDraw(), newReserve);
  }

  function testAllocateRewardFromReserve_notManager() public {
    vm.prank(address(0));
    vm.expectRevert(
      abi.encodeWithSelector(CallerNotDrawManager.selector, address(0), address(this))
    );
    prizePool.allocateRewardFromReserve(address(0), 1);
  }

  function testAllocateRewardFromReserve_insuff() public {
    vm.expectRevert(abi.encodeWithSelector(InsufficientReserve.selector, 1, 0));
    prizePool.allocateRewardFromReserve(address(this), 1);
  }

  function testAllocateRewardFromReserve() public {
    contribute(310e18);
    closeDraw(winningRandomNumber);
    assertEq(prizeToken.balanceOf(address(this)), 0);
    vm.expectEmit();
    emit AllocateRewardFromReserve(address(this), 1e18);
    prizePool.allocateRewardFromReserve(address(this), 1e18);
    assertEq(prizePool.rewardBalance(address(this)), 1e18);
    assertEq(prizeToken.balanceOf(address(this)), 0); // still 0 since there shouldn't be a transfer
    assertEq(prizePool.accountedBalance(), 310e18); // still 310e18 since there were no tokens transferred out yet

    // withdraw rewards:
    prizePool.withdrawRewards(address(this), 1e17);
    assertEq(prizePool.rewardBalance(address(this)), 9e17);
    assertEq(prizeToken.balanceOf(address(this)), 1e17);
    assertEq(prizePool.accountedBalance(), 3099e17);
  }

  function testGetTotalContributedBetween() public {
    contribute(10e18);
    assertEq(prizePool.getTotalContributedBetween(1, 1), 1e18);
  }

  function testGetContributedBetween() public {
    contribute(10e18);
    assertEq(prizePool.getContributedBetween(address(this), 1, 1), 1e18);
  }

  function testGetTierAccrualDurationInDraws() public {
    assertEq(prizePool.getTierAccrualDurationInDraws(0), 366);
  }

  function testContributePrizeTokens() public {
    contribute(100);
    assertEq(prizeToken.balanceOf(address(prizePool)), 100);
  }

  function testContributePrizeTokens_contributesToCurrentDrawNotOpenDraw() public {
    // warp 1 draw ahead so that the current draw is +1 from the open draw
    vm.warp(firstDrawStartsAt + drawPeriodSeconds);
    assertEq(prizePool.getOpenDrawId(), 1);

    // contribute and verify that contributions go to current draw (not open draw)
    contribute(1e18);
    assertEq(prizePool.getTotalContributedBetween(1, 1), 0);
    assertEq(prizePool.getTotalContributedBetween(2, 2), 1e17); // e17 since smoothing is in effect
    assertEq(prizePool.getTotalContributedBetween(1, 2), 1e17); // e17 since smoothing is in effect
  }

  function testContributePrizeTokens_notLostOnSkippedDraw() public {
    contribute(310e18);
    assertEq(prizeToken.balanceOf(address(prizePool)), 310e18);
    assertEq(prizePool.getOpenDrawId(), 1);

    // warp to skip a draw:
    vm.warp(firstDrawStartsAt + drawPeriodSeconds * 2);
    assertEq(prizePool.getOpenDrawId(), 2);

    // close draw:
    closeDraw(1234);

    // check if tier liquidity includes contribution from draws 1 + 2
    assertApproxEqAbs(prizePool.getTierRemainingLiquidity(0), 10e18 + 9e18, 10000);
  }

  function testContributePrizeTokens_emitsEvent() public {
    prizeToken.mint(address(prizePool), 100);
    vm.expectEmit();
    emit ContributePrizeTokens(address(this), 1, 100);
    prizePool.contributePrizeTokens(address(this), 100);
  }

  function testContributePrizeTokens_emitsContributionGTDeltaBalance() public {
    vm.expectRevert(abi.encodeWithSelector(ContributionGTDeltaBalance.selector, 100, 0));
    prizePool.contributePrizeTokens(address(this), 100);
  }

  function testAccountedBalance_withdrawnReserve() public {
    contribute(100e18);
    closeDraw(1);
    // reserve = 10e18 * (10 / 310) = 0.3225806451612903e18
    assertApproxEqAbs(
      prizePool.reserve(),
      (10e18 * RESERVE_SHARES) / prizePool.getTotalShares(),
      100
    );
    prizePool.allocateRewardFromReserve(address(this), prizePool.reserve());
    assertEq(prizePool.accountedBalance(), prizeToken.balanceOf(address(prizePool)));
    assertEq(prizePool.reserve(), 0);
  }

  function testAccountedBalance_noClaims() public {
    contribute(100);
    assertEq(prizePool.accountedBalance(), 100);
  }

  function testAccountedBalance_oneClaim() public {
    contribute(100e18);
    closeDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint prize = claimPrize(msg.sender, 0, 0);
    assertEq(prizePool.accountedBalance(), 100e18 - prize);
  }

  function testAccountedBalance_oneClaim_andMoreContrib() public {
    contribute(100e18);
    closeDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint prize = claimPrize(msg.sender, 0, 0);
    contribute(10e18);
    assertEq(prizePool.accountedBalance(), 110e18 - prize);
  }

  function testAccountedBalance_twoDraws_twoClaims() public {
    contribute(100e18);
    closeDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint prize = claimPrize(msg.sender, 0, 0);

    closeDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint prize2 = claimPrize(msg.sender, 0, 0);

    assertEq(prizePool.accountedBalance(), 100e18 - prize - prize2, "accounted balance");
  }

  function testGetVaultPortion_WhenEmpty() public {
    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 0)), 0);
  }

  function testGetVaultPortion_WhenOne() public {
    contribute(100e18); // available draw 1
    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 1, 1)), 1e18);
  }

  function testGetVaultPortion_WhenTwo() public {
    contribute(100e18); // available draw 1
    contribute(100e18, address(sender1)); // available draw 1

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 1, 1)), 0.5e18);
  }

  function testGetVaultPortion_WhenTwo_AccrossTwoDraws() public {
    contribute(100e18);
    contribute(100e18, address(sender1));

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 1, 2)), 0.5e18);
  }

  function testGetVaultPortion_BeforeContribution() public {
    contribute(100e18); // available on draw 1

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 0)), 0);
  }

  function testGetVaultPortion_BeforeContributionOnDraw3() public {
    closeDraw(winningRandomNumber); // draw 1
    closeDraw(winningRandomNumber); // draw 2
    assertEq(prizePool.getLastClosedDrawId(), 2);
    contribute(100e18); // available on draw 3

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 2, 2)), 0);
  }

  function testGetVaultPortion_BeforeAndAtContribution() public {
    contribute(100e18); // available draw 1

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 1)), 1e18);
  }

  function testGetVaultPortion_BeforeAndAfterContribution() public {
    closeDraw(winningRandomNumber); // draw 1
    contribute(100e18); // available draw 2

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 2)), 1e18);
  }

  function testGetOpenDrawId() public {
    uint256 openDrawId = prizePool.getOpenDrawId();
    assertEq(openDrawId, 1);
  }

  function testCloseAndOpenNextDraw_notManager() public {
    vm.prank(address(0));
    vm.expectRevert(
      abi.encodeWithSelector(CallerNotDrawManager.selector, address(0), address(this))
    );
    prizePool.closeDraw(winningRandomNumber);
  }

  function testCloseAndOpenNextDraw_notElapsed_atStart() public {
    vm.warp(firstDrawStartsAt);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        firstDrawStartsAt + drawPeriodSeconds,
        block.timestamp
      )
    );
    prizePool.closeDraw(winningRandomNumber);
  }

  function testCloseAndOpenNextDraw_notElapsed_subsequent() public {
    vm.warp(firstDrawStartsAt + drawPeriodSeconds);
    prizePool.closeDraw(winningRandomNumber);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        firstDrawStartsAt + drawPeriodSeconds * 2,
        block.timestamp
      )
    );
    prizePool.closeDraw(winningRandomNumber);
  }

  function testCloseAndOpenNextDraw_emittedDrawIdSameAsReturnedDrawId() public {
    contribute(510e18);
    uint24 expectedDrawId = 1;

    vm.expectEmit(true, true, true, false);
    emit DrawClosed(expectedDrawId, 12345, 3, 3, 0, UD34x4.wrap(0), firstDrawStartsAt);
    vm.warp(prizePool.openDrawEndsAt());
    uint24 closedDrawId = prizePool.closeDraw(12345);

    assertEq(closedDrawId, expectedDrawId, "closed draw ID matches expected");
  }

  function testCloseAndOpenNextDraw_notElapsed_openDrawPartway() public {
    vm.warp(firstDrawStartsAt + drawPeriodSeconds);
    prizePool.closeDraw(winningRandomNumber);
    vm.warp(firstDrawStartsAt + drawPeriodSeconds + drawPeriodSeconds / 2);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        firstDrawStartsAt + drawPeriodSeconds * 2,
        block.timestamp
      )
    );
    prizePool.closeDraw(winningRandomNumber);
  }

  function testCloseAndOpenNextDraw_notElapsed_partway() public {
    vm.warp(firstDrawStartsAt + drawPeriodSeconds / 2);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        firstDrawStartsAt + drawPeriodSeconds,
        block.timestamp
      )
    );
    prizePool.closeDraw(winningRandomNumber);
  }

  function testCloseAndOpenNextDraw_invalidNumber() public {
    vm.expectRevert(abi.encodeWithSelector(RandomNumberIsZero.selector));
    prizePool.closeDraw(0);
  }

  function testCloseAndOpenNextDraw_noLiquidity() public {
    closeDraw(winningRandomNumber);

    assertEq(prizePool.getWinningRandomNumber(), winningRandomNumber);
    assertEq(prizePool.getLastClosedDrawId(), 1);
    assertEq(prizePool.getOpenDrawId(), 2);
    assertEq(prizePool.lastClosedDrawStartedAt(), firstDrawStartsAt);
    assertEq(prizePool.lastClosedDrawEndedAt(), firstDrawStartsAt + drawPeriodSeconds);
    assertEq(prizePool.lastClosedDrawAwardedAt(), block.timestamp);
  }

  function testCloseAndOpenNextDraw_withLiquidity() public {
    contribute(100e18);
    // = 1e18 / 220e18 = 0.004545454...
    // but because of alpha only 10% is released on this draw
    closeDraw(winningRandomNumber);

    uint liquidityPerShare = 10e18 / prizePool.getTotalShares();
    uint remainder = 10e18 - liquidityPerShare * prizePool.getTotalShares();

    assertEq(
      fromUD34x4(prizePool.prizeTokenPerShare()),
      liquidityPerShare,
      "prize token per share"
    );

    uint reserve = remainder + RESERVE_SHARES * liquidityPerShare;

    assertEq(prizePool.reserve(), reserve, "reserve"); // remainder of the complex fraction
    assertEq(prizePool.getTotalContributedBetween(1, 1), 10e18); // ensure not a single wei is lost!
  }

  function testTotalContributionsForClosedDraw_noClaims() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getTotalContributedBetween(1, 1), 10e18, "first draw"); // 10e18
    closeDraw(winningRandomNumber);
    // liquidity should carry over!
    assertEq(prizePool.getTotalContributedBetween(2, 2), 8.999999999999998700e18, "second draw"); // 10e18 + 9e18
  }

  function testCloseAndOpenNextDraw_shouldNotShrinkOnFirst() public {
    uint8 startingTiers = 5;

    // reset prize pool at higher tiers
    ConstructorParams memory prizePoolParams = ConstructorParams(
      prizeToken,
      twabController,
      drawPeriodSeconds,
      firstDrawStartsAt,
      sd1x18(0.9e18), // alpha
      grandPrizePeriodDraws,
      startingTiers, // higher number of tiers
      100,
      10
    );
    prizePool = new PrizePool(prizePoolParams);
    prizePool.setDrawManager(address(this));

    contribute(510e18);
    closeDraw(1234);

    // tiers should not change upon first draw
    assertEq(prizePool.numberOfTiers(), startingTiers, "starting tiers");
  }

  function testCloseAndOpenNextDraw_shrinkTiers() public {
    uint8 startingTiers = 5;

    // reset prize pool at higher tiers
    ConstructorParams memory prizePoolParams = ConstructorParams(
      prizeToken,
      twabController,
      drawPeriodSeconds,
      firstDrawStartsAt,
      sd1x18(0.9e18), // alpha
      grandPrizePeriodDraws,
      startingTiers, // higher number of tiers
      100,
      10
    );
    prizePool = new PrizePool(prizePoolParams);
    prizePool.setDrawManager(address(this));

    contribute(510e18);

    assertEq(prizePool.estimateNextNumberOfTiers(), 3, "will reduce to 3");

    closeDraw(1234);

    assertEq(prizePool.reserve(), 1e18, "reserve after first draw");

    // close second draw
    closeDraw(4567);

    assertEq(prizePool.numberOfTiers(), 3, "number of tiers");

    // two tiers + canary tier = 30e18
    // total liquidity for second draw is 45.9e18
    // new liquidity for second draw = 75.9e18
    // reserve for second draw = (10/310)*75.9e18 = 2.445e18
    // total reserve = 3.445e18

    assertEq(prizePool.reserve(), 3.44838709677419347e18, "size of reserve");
  }

  function testCloseAndOpenNextDraw_expandingTiers() public {
    contribute(1e18);
    closeDraw(1234);

    // claim tier 0
    mockTwab(address(this), address(this), 0);
    claimPrize(address(this), 0, 0);

    // claim tier 1
    for (uint32 i = 0; i < 4; i++) {
      mockTwab(address(this), sender1, 1);
      claimPrize(sender1, 1, i);
    }

    // claim tier 2 (canary)
    for (uint32 i = 0; i < 16; i++) {
      mockTwab(address(this), sender2, 2);
      claimPrize(sender2, 2, i);
    }

    closeDraw(245);
    assertEq(prizePool.numberOfTiers(), 4);
  }

  function testCloseAndOpenNextDraw_multipleDraws() public {
    contribute(1e18);
    closeDraw(1234);
    closeDraw(1234);
    closeDraw(554);

    mockTwab(address(this), sender5, 1);
    assertTrue(claimPrize(sender5, 1, 0) > 0, "has prize");
  }

  function testCloseAndOpenNextDraw_emitsEvent() public {
    vm.expectEmit();
    emit DrawClosed(1, 12345, 3, 3, 0, UD34x4.wrap(0), firstDrawStartsAt);
    closeDraw(12345);
  }

  function testGetTotalShares() public {
    assertEq(prizePool.getTotalShares(), TIER_SHARES * 3 + RESERVE_SHARES);
  }

  function testGetRemainingTierLiquidity_invalidTier() public {
    assertEq(prizePool.getTierRemainingLiquidity(10), 0);
  }

  function testGetRemainingTierLiquidity_afterClaim() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);

    uint256 tierLiquidity = TIER_SHARES * (10e18 / prizePool.getTotalShares());

    assertEq(prizePool.getTierRemainingLiquidity(1), tierLiquidity, "second tier");

    mockTwab(address(this), sender1, 1);
    uint256 prize = prizePool.getTierPrizeSize(1);
    assertEq(claimPrize(sender1, 1, 0), prize, "second tier prize 1");

    // reduce by prize
    assertEq(
      prizePool.getTierRemainingLiquidity(1),
      tierLiquidity - prize,
      "second tier liquidity post claim 1"
    );
  }

  function testGetRemainingTierLiquidity_allTiers() public {
    contribute(310e18);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getTierRemainingLiquidity(0), 10e18);
    assertEq(prizePool.getTierRemainingLiquidity(1), 10e18);
    assertEq(prizePool.getTierRemainingLiquidity(2), 10e18);
  }

  function testSetDrawManager() public {
    address bob = makeAddr("bob");
    vm.expectEmit();
    emit DrawManagerSet(address(bob));
    prizePool.setDrawManager(address(bob));
    assertEq(prizePool.drawManager(), address(bob));
  }

  function testSetDrawManager_DrawManagerIsZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(DrawManagerIsZeroAddress.selector));
    prizePool.setDrawManager(address(0));
  }

  function testSetDrawManager_notOwner() public {
    vm.startPrank(address(1));
    vm.expectRevert("Ownable: caller is not the owner");
    prizePool.setDrawManager(address(this));
    vm.stopPrank();
  }

  function testIsWinner_noDraw() public {
    vm.expectRevert(abi.encodeWithSelector(NoClosedDraw.selector));
    prizePool.isWinner(address(this), msg.sender, 10, 0);
  }

  function testIsWinner_invalidTier() public {
    closeDraw(winningRandomNumber);

    // Less than number of tiers is valid.
    prizePool.isWinner(address(this), msg.sender, initialNumberOfTiers - 1, 0);

    // Number of tiers is invalid.
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTier.selector, initialNumberOfTiers, initialNumberOfTiers)
    );
    prizePool.isWinner(address(this), msg.sender, initialNumberOfTiers, 0);

    // More than number of tiers is invalid.
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTier.selector, initialNumberOfTiers + 1, initialNumberOfTiers)
    );
    prizePool.isWinner(address(this), msg.sender, initialNumberOfTiers + 1, 0);
  }

  function testIsWinnerDailyPrize() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    assertEq(prizePool.isWinner(address(this), msg.sender, 1, 0), true);
  }

  function testIsWinnerGrandPrize() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    assertEq(prizePool.isWinner(address(this), msg.sender, 0, 0), true);
  }

  function testIsWinner_emitsInvalidPrizeIndex() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    vm.expectRevert(abi.encodeWithSelector(InvalidPrizeIndex.selector, 4, 4, 1));
    prizePool.isWinner(address(this), msg.sender, 1, 4);
  }

  function testIsWinner_doesNotChange() public {
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    assertFalse(prizePool.isWinner(address(this), msg.sender, 1, 0), "not a winner");
    contribute(100e18);
    assertFalse(prizePool.isWinner(address(this), msg.sender, 1, 0), "still not a winner");
  }

  function testWasClaimed_not() public {
    assertEq(prizePool.wasClaimed(vault, msg.sender, 0, 0), false);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 0, 0), false);
  }

  function testWasClaimed_single() public {
    vm.prank(vault);
    contribute(100e18, vault);
    prizeToken.mint(address(prizePool), 100e18);

    closeDraw(winningRandomNumber);

    mockTwab(vault, msg.sender, 1);
    vm.prank(vault);
    claimPrize(msg.sender, 1, 0);

    assertEq(prizePool.wasClaimed(vault, msg.sender, 1, 0), true);
  }

  function testWasClaimed_single_twoVaults() public {
    vm.prank(vault);
    contribute(100e18, vault);
    prizeToken.mint(address(prizePool), 100e18);

    vm.prank(vault2);
    prizePool.contributePrizeTokens(vault2, 100e18);

    closeDraw(winningRandomNumber);

    mockTwab(vault, msg.sender, 1);
    vm.prank(vault);
    claimPrize(msg.sender, 1, 0);
    mockTwab(vault2, msg.sender, 1);
    vm.prank(vault2);
    claimPrize(msg.sender, 1, 0);

    assertEq(prizePool.wasClaimed(vault, msg.sender, 1, 0), true);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 1, 0), true);
  }

  function testWasClaimed_old_draw() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
    assertEq(prizePool.wasClaimed(vault, msg.sender, 0, 0), true);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 0, 0), false);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.wasClaimed(vault, msg.sender, 0, 0), false);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 0, 0), false);
  }

  function testAccountedBalance_remainder() public {
    contribute(1000);
    assertEq(prizePool.accountedBalance(), 1000, "accounted balance");
    closeDraw(winningRandomNumber);
    assertEq(prizePool.accountedBalance(), 1000, "accounted balance");
  }

  function testClaimPrize_zero() public {
    contribute(1000);
    closeDraw(winningRandomNumber);
    address winner = makeAddr("winner");
    mockTwab(address(this), winner, 1);
    assertEq(prizePool.getTierPrizeSize(2), 0, "prize size");
    vm.expectRevert(abi.encodeWithSelector(PrizeIsZero.selector));
    prizePool.claimPrize(winner, 1, 0, winner, 0, address(this));
  }

  function testClaimPrize_ClaimPeriodExpired() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    address winner = makeAddr("winner");
    mockTwab(address(this), winner, 1);
    uint periodStart = prizePool.openDrawStartedAt();

    // warp to end of open draw (end of claim period)
    vm.warp(periodStart + drawPeriodSeconds);
    vm.expectRevert(abi.encodeWithSelector(ClaimPeriodExpired.selector));
    prizePool.claimPrize(winner, 1, 0, winner, 0, address(this));

    // warp to end of open draw (end of claim period) + 1 sec
    vm.warp(periodStart + drawPeriodSeconds + 1);
    vm.expectRevert(abi.encodeWithSelector(ClaimPeriodExpired.selector));
    prizePool.claimPrize(winner, 1, 0, winner, 0, address(this));

    // warp to right before end of open draw (end of claim period)
    vm.warp(periodStart + drawPeriodSeconds - 1);
    vm.expectEmit();
    emit ClaimedPrize(
      address(this),
      winner,
      winner,
      1,
      1,
      0,
      uint152(prizePool.getTierPrizeSize(1)),
      0,
      address(this)
    );
    prizePool.claimPrize(winner, 1, 0, winner, 0, address(this));
  }

  function testClaimPrize_single() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    address winner = makeAddr("winner");
    address recipient = makeAddr("recipient");
    mockTwab(address(this), winner, 1);

    uint prize = 806451612903225800;
    assertApproxEqAbs(prize, (10e18 * TIER_SHARES) / (4 * prizePool.getTotalShares()), 100);

    vm.expectEmit();
    emit ClaimedPrize(address(this), winner, recipient, 1, 1, 0, uint152(prize), 0, address(this));
    assertEq(prizePool.claimPrize(winner, 1, 0, recipient, 0, address(this)), prize);
    assertEq(prizeToken.balanceOf(recipient), prize, "recipient balance is good");
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrize_withFee() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    // total prize size is returned
    vm.expectEmit();
    emit IncreaseClaimRewards(address(this), 1e18);

    uint prize = prizePool.getTierPrizeSize(0);

    claimPrize(msg.sender, 0, 0, 1e18, address(this));
    // grand prize is (100/220) * 0.1 * 100e18 = 4.5454...e18
    assertEq(prizeToken.balanceOf(msg.sender), prize - 1e18, "balance is prize less fee");
    assertEq(prizePool.claimCount(), 1);
    assertEq(prizePool.rewardBalance(address(this)), 1e18);
  }

  function testClaimPrize_notWinner() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    vm.expectRevert(abi.encodeWithSelector(DidNotWin.selector, address(this), msg.sender, 0, 0));
    claimPrize(msg.sender, 0, 0);
  }

  function testClaimPrize_feeTooLarge() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    uint prize = prizePool.getTierPrizeSize(0);
    vm.expectRevert(abi.encodeWithSelector(FeeTooLarge.selector, 10e18, prize));
    claimPrize(msg.sender, 0, 0, 10e18, address(this));
  }

  function testClaimPrize_grandPrize_cannotClaimTwice() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    uint prize = prizePool.getTierPrizeSize(0);
    assertEq(claimPrize(msg.sender, 0, 0), prize, "prize size");
    // second claim is zero
    assertEq(claimPrize(msg.sender, 0, 0), 0, "no more prize");
  }

  function testComputeNextNumberOfTiers_zero() public {
    assertEq(prizePool.computeNextNumberOfTiers(0), 3);
  }

  function testComputeNextNumberOfTiers_deviationLess() public {
    // no canary tiers taken
    assertEq(prizePool.computeNextNumberOfTiers(3), 3);
  }

  function testComputeNextNumberOfTiers_deviationMore() public {
    // deviation is ok
    assertEq(prizePool.computeNextNumberOfTiers(8), 3);
  }

  function testComputeNextNumberOfTiers_canaryPrizes() public {
    // canary prizes were taken!
    assertEq(prizePool.computeNextNumberOfTiers(16), 4);
    assertEq(prizePool.computeNextNumberOfTiers(20), 4);
    assertEq(prizePool.computeNextNumberOfTiers(24), 4);
  }

  function testComputeNextNumberOfTiers_beyondMinimum() public {
    // canary prizes were taken for tier 4!
    assertEq(prizePool.computeNextNumberOfTiers(80), 5);
  }

  function testComputeNextNumberOfTiers_beyondMinimum_bigDeviation() public {
    // half the canary prizes were taken
    assertEq(prizePool.computeNextNumberOfTiers(150), 5);
  }

  function testComputeNextNumberOfTiers_beyondMinimum_nextLevelUp() public {
    // half the canary prizes were taken
    assertEq(prizePool.computeNextNumberOfTiers(200), 6);
  }

  function testClaimPrize_secondTier_claimTwice() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    uint prize = prizePool.getTierPrizeSize(1);
    assertEq(claimPrize(msg.sender, 1, 0), prize, "first claim");
    // second claim is same
    mockTwab(address(this), sender2, 1);
    assertEq(claimPrize(sender2, 1, 0), prize, "second claim");
  }

  function testClaimCanaryPrize() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    claimPrize(sender1, 2, 0);
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrizePartial() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    claimPrize(sender1, 2, 0);
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrize_ZeroAddressFeeRecipient() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    vm.expectRevert(abi.encodeWithSelector(FeeRecipientZeroAddress.selector));
    prizePool.claimPrize(sender1, 2, 0, sender1, 1, address(0));
  }

  function testClaimPrize_ZeroAddressFeeRecipient_ZeroFee() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    prizePool.claimPrize(sender1, 2, 0, sender1, 0, address(0)); // zero fee, so no revert
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrize_claimFeesAccountedFor() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);

    address winner = makeAddr("winner");
    address recipient = makeAddr("recipient");
    mockTwab(address(this), winner, 1);

    uint96 fee = 0xfee;
    uint prizeAmount = 806451612903225800;
    uint prize = prizeAmount - fee;
    assertApproxEqAbs(prizeAmount, (10e18 * TIER_SHARES) / (4 * prizePool.getTotalShares()), 100);

    vm.expectEmit();
    emit ClaimedPrize(
      address(this),
      winner,
      recipient,
      1,
      1,
      0,
      uint152(prize),
      fee,
      address(this)
    );
    assertEq(prizePool.claimPrize(winner, 1, 0, recipient, fee, address(this)), prizeAmount);
    assertEq(prizeToken.balanceOf(recipient), prize, "recipient balance is good");
    assertEq(prizePool.claimCount(), 1);

    // Check if claim fees are accounted for
    // (if they aren't anyone can call contributePrizeTokens with the unaccounted fee amount and basically take it as their own)
    uint accountedBalance = prizePool.accountedBalance();
    uint actualBalance = prizeToken.balanceOf(address(prizePool));

    // show that the claimer can still withdraw their fees:
    assertEq(prizeToken.balanceOf(address(this)), 0);
    vm.expectEmit();
    emit WithdrawRewards(address(this), address(this), fee, fee);
    prizePool.withdrawRewards(address(this), fee);
    assertEq(prizeToken.balanceOf(address(this)), fee);

    accountedBalance = prizePool.accountedBalance();
    actualBalance = prizeToken.balanceOf(address(prizePool));
  }

  function testTotalWithdrawn() public {
    assertEq(prizePool.totalWithdrawn(), 0);
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    uint prize = prizePool.getTierPrizeSize(0);
    assertEq(claimPrize(msg.sender, 0, 0), prize, "prize size");
    assertEq(prizePool.totalWithdrawn(), prize, "total claimed prize");
  }

  function testLastClosedDrawStartedAt() public {
    assertEq(prizePool.lastClosedDrawStartedAt(), 0);
    closeDraw(winningRandomNumber);

    assertEq(prizePool.lastClosedDrawStartedAt(), firstDrawStartsAt);
    assertEq(prizePool.lastClosedDrawEndedAt(), firstDrawStartsAt + drawPeriodSeconds);
    assertEq(prizePool.lastClosedDrawAwardedAt(), block.timestamp);
  }

  function testLastClosedDrawEndedAt() public {
    assertEq(prizePool.lastClosedDrawEndedAt(), 0);
    closeDraw(winningRandomNumber);

    assertEq(prizePool.lastClosedDrawStartedAt(), firstDrawStartsAt);
    assertEq(prizePool.lastClosedDrawEndedAt(), firstDrawStartsAt + drawPeriodSeconds);
    assertEq(prizePool.lastClosedDrawAwardedAt(), block.timestamp);
  }

  function testOpenDrawStartedMatchesLastDrawClosed() public {
    vm.warp(prizePool.openDrawEndsAt() + 1 hours);
    prizePool.closeDraw(winningRandomNumber);
    assertEq(prizePool.openDrawStartedAt(), prizePool.lastClosedDrawEndedAt());
    vm.warp(prizePool.openDrawEndsAt() + 1 hours);
    prizePool.closeDraw(winningRandomNumber);
    assertEq(prizePool.openDrawStartedAt(), prizePool.lastClosedDrawEndedAt());
    vm.warp(prizePool.openDrawEndsAt() + 1 hours);
    prizePool.closeDraw(winningRandomNumber);
    assertEq(prizePool.openDrawStartedAt(), prizePool.lastClosedDrawEndedAt());
  }

  function testLastClosedDrawAwardedAt() public {
    assertEq(prizePool.lastClosedDrawAwardedAt(), 0);

    uint48 targetTimestamp = prizePool.openDrawEndsAt() + 3 hours;

    vm.warp(targetTimestamp);
    prizePool.closeDraw(winningRandomNumber);

    assertEq(prizePool.lastClosedDrawStartedAt(), firstDrawStartsAt);
    assertEq(prizePool.lastClosedDrawEndedAt(), firstDrawStartsAt + drawPeriodSeconds);
    assertEq(prizePool.lastClosedDrawAwardedAt(), targetTimestamp);
  }

  function testWithdrawRewards_sufficient() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    claimPrize(msg.sender, 0, 0, 1e18, address(this));
    prizePool.withdrawRewards(address(this), 1e18);
    assertEq(prizeToken.balanceOf(address(this)), 1e18);
  }

  function testWithdrawRewards_insufficient() public {
    vm.expectRevert(abi.encodeWithSelector(InsufficientRewardsError.selector, 1e18, 0));
    prizePool.withdrawRewards(address(this), 1e18);
  }

  function testWithdrawRewards_emitsEvent() public {
    contribute(100e18);
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);

    prizePool.claimPrize(msg.sender, 0, 0, msg.sender, 1e18, address(this));

    vm.expectEmit();
    emit WithdrawRewards(address(this), address(1), 5e17, 1e18);
    prizePool.withdrawRewards(address(1), 5e17);
  }

  function testOpenDrawStartsAt_zeroDraw() public {
    // current time *is* lastClosedDrawStartedAt
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt);
  }

  function testOpenDrawStartsAt_zeroDrawPartwayThrough() public {
    // current time is halfway through first draw
    vm.warp(firstDrawStartsAt + drawPeriodSeconds / 2);
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt);
  }

  function testOpenDrawStartsAt_zeroDrawWithLongDelay() public {
    // current time is halfway through *second* draw
    vm.warp(firstDrawStartsAt + drawPeriodSeconds + drawPeriodSeconds / 2); // warp halfway through second draw
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt);
  }

  function testOpenDrawStartsAt_openDraw() public {
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt + drawPeriodSeconds);
  }

  function testOpenDrawIncludesMissedDraws() public {
    assertEq(prizePool.getOpenDrawId(), 1);
    vm.warp(firstDrawStartsAt + drawPeriodSeconds * 2);
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt + drawPeriodSeconds);
    assertEq(prizePool.openDrawEndsAt(), firstDrawStartsAt + drawPeriodSeconds * 2);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getOpenDrawId(), 3);
  }

  function testOpenDrawIncludesMissedDraws_middleOfDraw() public {
    assertEq(prizePool.getOpenDrawId(), 1);
    vm.warp(firstDrawStartsAt + (drawPeriodSeconds * 5) / 2);
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt + drawPeriodSeconds);
    assertEq(prizePool.openDrawEndsAt(), firstDrawStartsAt + drawPeriodSeconds * 2);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getOpenDrawId(), 3);
  }

  function testNextDrawIncludesMissedDraws_2Draws() public {
    assertEq(prizePool.getOpenDrawId(), 1);
    vm.warp(firstDrawStartsAt + drawPeriodSeconds * 3);
    assertEq(prizePool.openDrawStartedAt(), firstDrawStartsAt + drawPeriodSeconds * 2);
    assertEq(prizePool.openDrawEndsAt(), firstDrawStartsAt + drawPeriodSeconds * 3);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getOpenDrawId(), 4);
  }

  function testOpenDrawIncludesMissedDraws_notFirstDraw() public {
    closeDraw(winningRandomNumber);
    uint48 _lastDrawClosedAt = prizePool.lastClosedDrawEndedAt();
    assertEq(prizePool.getOpenDrawId(), 2);
    vm.warp(_lastDrawClosedAt + drawPeriodSeconds * 2);
    assertEq(prizePool.openDrawStartedAt(), _lastDrawClosedAt + drawPeriodSeconds);
    assertEq(prizePool.openDrawEndsAt(), _lastDrawClosedAt + drawPeriodSeconds * 2);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getOpenDrawId(), 4);
  }

  function testOpenDrawIncludesMissedDraws_manyDrawsIn_manyMissed() public {
    closeDraw(winningRandomNumber);
    closeDraw(winningRandomNumber);
    closeDraw(winningRandomNumber);
    closeDraw(winningRandomNumber);
    uint48 _lastDrawClosedAt = prizePool.lastClosedDrawEndedAt();
    assertEq(prizePool.getOpenDrawId(), 5);
    vm.warp(_lastDrawClosedAt + drawPeriodSeconds * 5);
    assertEq(prizePool.openDrawStartedAt(), _lastDrawClosedAt + drawPeriodSeconds * 4);
    assertEq(prizePool.openDrawEndsAt(), _lastDrawClosedAt + drawPeriodSeconds * 5);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getOpenDrawId(), 10);
  }

  function testOpenDrawIncludesMissedDraws_notFirstDraw_middleOfDraw() public {
    closeDraw(winningRandomNumber);
    uint48 _lastDrawClosedAt = prizePool.lastClosedDrawEndedAt();
    assertEq(prizePool.getOpenDrawId(), 2);
    vm.warp(_lastDrawClosedAt + (drawPeriodSeconds * 5) / 2); // warp 2.5 draws in the future
    assertEq(prizePool.getOpenDrawId(), 3);
    assertEq(prizePool.openDrawStartedAt(), _lastDrawClosedAt + drawPeriodSeconds);
    assertEq(prizePool.openDrawEndsAt(), _lastDrawClosedAt + drawPeriodSeconds * 2);
    closeDraw(winningRandomNumber);
    assertEq(prizePool.getOpenDrawId(), 4);
  }

  function testGetVaultUserBalanceAndTotalSupplyTwab() public {
    closeDraw(winningRandomNumber);
    mockTwab(
      address(this),
      msg.sender,
      prizePool.lastClosedDrawEndedAt() - grandPrizePeriodDraws * drawPeriodSeconds,
      prizePool.lastClosedDrawEndedAt()
    );
    (uint256 twab, uint256 twabTotalSupply) = prizePool.getVaultUserBalanceAndTotalSupplyTwab(
      address(this),
      msg.sender,
      grandPrizePeriodDraws
    );
    assertEq(twab, 366e30);
    assertEq(twabTotalSupply, 1e30);
  }

  function testGetVaultUserBalanceAndTotalSupplyTwab_insufficientPast() public {
    vm.warp(1 days);
    params.firstDrawStartsAt = 2 days;
    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_OFFSET, ()),
      abi.encode(2 days)
    );
    prizePool = new PrizePool(params);
    prizePool.setDrawManager(address(this));
    closeDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0, prizePool.lastClosedDrawEndedAt());
    (uint256 twab, uint256 twabTotalSupply) = prizePool.getVaultUserBalanceAndTotalSupplyTwab(
      address(this),
      msg.sender,
      grandPrizePeriodDraws
    );
    assertEq(twab, 366e30);
    assertEq(twabTotalSupply, 1e30);
  }

  function mockGetAverageBalanceBetween(
    address _vault,
    address _user,
    uint48 _startTime,
    uint48 _endTime,
    uint256 _result
  ) internal {
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(
        TwabController.getTwabBetween.selector,
        _vault,
        _user,
        _startTime,
        _endTime
      ),
      abi.encode(_result)
    );
  }

  function mockGetAverageTotalSupplyBetween(
    address _vault,
    uint32 _startTime,
    uint32 _endTime,
    uint256 _result
  ) internal {
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(
        TwabController.getTotalSupplyTwabBetween.selector,
        _vault,
        _startTime,
        _endTime
      ),
      abi.encode(_result)
    );
  }

  function contribute(uint256 amountContributed) public {
    contribute(amountContributed, address(this));
  }

  function contribute(uint256 amountContributed, address to) public {
    prizeToken.mint(address(prizePool), amountContributed);
    prizePool.contributePrizeTokens(to, amountContributed);
  }

  function closeDraw(uint256 _winningRandomNumber) public {
    vm.warp(prizePool.openDrawEndsAt());
    prizePool.closeDraw(_winningRandomNumber);
  }

  function claimPrize(address sender, uint8 tier, uint32 prizeIndex) public returns (uint256) {
    return claimPrize(sender, tier, prizeIndex, 0, address(this));
  }

  function claimPrize(
    address sender,
    uint8 tier,
    uint32 prizeIndex,
    uint96 fee,
    address feeRecipient
  ) public returns (uint256) {
    return prizePool.claimPrize(sender, tier, prizeIndex, sender, fee, feeRecipient);
  }

  function mockTwab(address _vault, address _account, uint256 startTime, uint256 endTime) public {
    mockGetAverageBalanceBetween(_vault, _account, uint32(startTime), uint32(endTime), 366e30);
    mockGetAverageTotalSupplyBetween(_vault, uint32(startTime), uint32(endTime), 1e30);
  }

  function mockTwab(address _vault, address _account, uint8 _tier) public {
    (uint48 startTime, uint48 endTime) = prizePool.calculateTierTwabTimestamps(_tier);
    mockTwab(_vault, _account, startTime, endTime);
  }
}
