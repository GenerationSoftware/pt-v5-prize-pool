// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { sd, SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD1x18, sd1x18 } from "prb-math/SD1x18.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { TierCalculationLib } from "../src/libraries/TierCalculationLib.sol";
import { MAXIMUM_NUMBER_OF_TIERS, MINIMUM_NUMBER_OF_TIERS, NUMBER_OF_CANARY_TIERS } from "../src/abstract/TieredLiquidityDistributor.sol";
import {
  PrizePool,
  CreatorIsZeroAddress,
  OnlyCreator,
  DrawManagerAlreadySet,
  PrizeIsZero,
  ConstructorParams,
  InsufficientRewardsError,
  DrawTimeoutIsZero,
  DrawTimeoutGTGrandPrizePeriodDraws,
  PrizePoolNotShutdown,
  DidNotWin,
  AlreadyClaimed,
  RangeSizeZero,
  RewardTooLarge,
  ContributionGTDeltaBalance,
  InsufficientReserve,
  RandomNumberIsZero,
  AwardingDrawNotClosed,
  InvalidPrizeIndex,
  NoDrawsAwarded,
  InvalidTier,
  DrawManagerIsZeroAddress,
  CallerNotDrawManager,
  NotDeployer,
  RewardRecipientZeroAddress,
  FirstDrawOpensInPast,
  IncompatibleTwabPeriodLength,
  IncompatibleTwabPeriodOffset,
  ClaimPeriodExpired,
  PrizePoolShutdown,
  Observation,
  ShutdownPortion
} from "../src/PrizePool.sol";
import { ERC20Mintable } from "./mocks/ERC20Mintable.sol";

contract PrizePoolTest is Test {
  PrizePool public prizePool;

  ERC20Mintable public prizeToken;

  address public vault;
  address public vault2;

  address bob = makeAddr("bob");
  address alice = makeAddr("alice");

  TwabController public twabController;

  address drawManager;

  address sender1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
  address sender2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
  address sender3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
  address sender4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
  address sender5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
  address sender6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

  uint256 TIER_SHARES = 100;
  uint256 CANARY_SHARES = 5;
  uint256 RESERVE_SHARES = 10;

  uint24 grandPrizePeriodDraws = 365;
  uint48 drawPeriodSeconds = 1 days;
  uint24 drawTimeout; // = grandPrizePeriodDraws * drawPeriodSeconds; // 1000 days;
  uint48 firstDrawOpensAt;
  uint8 initialNumberOfTiers;
  uint256 winningRandomNumber = 123456;
  uint256 startTimestamp = 1000 days;
  uint256 tierLiquidityUtilizationRate = 1e18;

  /**********************************************************************************
   * Events copied from PrizePool.sol
   **********************************************************************************/
  event DrawAwarded(
    uint24 indexed drawId,
    uint256 winningRandomNumber,
    uint8 lastNumTiers,
    uint8 numTiers,
    uint104 reserve,
    uint128 prizeTokensPerShare,
    uint48 drawOpenedAt
  );
  event SetDrawManager(address indexed drawManager);
  event AllocateRewardFromReserve(address indexed to, uint256 amount);
  event ContributedReserve(address indexed user, uint256 amount);
  event ContributePrizeTokens(address indexed vault, uint24 indexed drawId, uint256 amount);
  event WithdrawRewards(
    address indexed account,
    address indexed to,
    uint256 amount,
    uint256 available
  );
  event IncreaseClaimRewards(address indexed to, uint256 amount);
  event DrawManagerSet(address indexed drawManager);

  /**********************************************************************************/

  ConstructorParams params;

  function setUp() public {
    drawTimeout = 30; //grandPrizePeriodDraws;
    vm.warp(startTimestamp);

    prizeToken = new ERC20Mintable("PoolTogether POOL token", "POOL");
    twabController = new TwabController(uint32(drawPeriodSeconds), uint32(startTimestamp - 1 days));

    firstDrawOpensAt = uint48(startTimestamp + 1 days); // set draw start 1 day into future
    initialNumberOfTiers = MINIMUM_NUMBER_OF_TIERS;

    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_OFFSET, ()),
      abi.encode(firstDrawOpensAt)
    );
    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.PERIOD_LENGTH, ()),
      abi.encode(drawPeriodSeconds)
    );

    drawManager = address(this);
    vault = address(this);
    vault2 = address(0x1234);

    params = ConstructorParams(
      prizeToken,
      twabController,
      drawManager,
      tierLiquidityUtilizationRate,
      drawPeriodSeconds,
      firstDrawOpensAt,
      grandPrizePeriodDraws,
      initialNumberOfTiers, // minimum number of tiers
      uint8(TIER_SHARES),
      uint8(CANARY_SHARES),
      uint8(RESERVE_SHARES),
      drawTimeout
    );

    prizePool = newPrizePool();
  }

  function testConstructor() public {
    assertEq(prizePool.firstDrawOpensAt(), firstDrawOpensAt);
    assertEq(prizePool.drawPeriodSeconds(), drawPeriodSeconds);
  }

  function testDrawTimeoutIsZero() public {
    params.drawTimeout = 0;
    vm.expectRevert(abi.encodeWithSelector(DrawTimeoutIsZero.selector));
    new PrizePool(params);
  }

  function testDrawTimeoutGTGrandPrizePeriodDraws() public {
    params.drawTimeout = grandPrizePeriodDraws + 1;
    vm.expectRevert(abi.encodeWithSelector(DrawTimeoutGTGrandPrizePeriodDraws.selector));
    new PrizePool(params);
  }

  function testConstructor_FirstDrawOpensInPast() public {
    vm.expectRevert(abi.encodeWithSelector(FirstDrawOpensInPast.selector));
    params.firstDrawOpensAt = 1 days;
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
      abi.encode(params.firstDrawOpensAt - 1)
    );
    vm.expectRevert(abi.encodeWithSelector(IncompatibleTwabPeriodOffset.selector));
    new PrizePool(params);
  }

  function testConstructor_CreatorIsZeroAddress() public {
    params.creator = address(0);
    vm.expectRevert(abi.encodeWithSelector(CreatorIsZeroAddress.selector));
    new PrizePool(params);
  }

  function testSetDrawManager() public {
    assertEq(prizePool.drawManager(), drawManager, "drawManager");
  }

  function testSetDrawManager_OnlyCreator() public {
    vm.prank(address(twabController));
    vm.expectRevert(abi.encodeWithSelector(OnlyCreator.selector));
    prizePool.setDrawManager(drawManager);
  }

  function testSetDrawManager_DrawManagerAlreadySet() public {
    vm.expectRevert(abi.encodeWithSelector(DrawManagerAlreadySet.selector));
    prizePool.setDrawManager(drawManager);
  }

  function testReserve_noRemainder() public {
    contribute(1e18 * prizePool.getTotalShares());
    awardDraw(winningRandomNumber);

    // reserve + remainder
    assertEq(prizePool.reserve(), 10e18);
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
    awardDraw(winningRandomNumber);

    uint256 prizesPerShare = 100e18 / prizePool.getTotalShares();
    uint256 remainder = 100e18 - prizesPerShare * prizePool.getTotalShares();

    uint256 reserve = (prizesPerShare * RESERVE_SHARES) + remainder;

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
    awardDraw(winningRandomNumber);
    assertEq(prizePool.reserve(), 4545454545454545550);
  }

  function testPendingReserveContributions_noDraw() public {
    contribute(100e18);
    uint256 firstPrizesPerShare = 100e18 / prizePool.getTotalShares();
    uint256 remainder = 100e18 - (firstPrizesPerShare * prizePool.getTotalShares());
    assertEq(prizePool.pendingReserveContributions(), remainder + (firstPrizesPerShare * RESERVE_SHARES));
  }

  function testPendingReserveContributions_existingDraw() public {
    awardDraw(winningRandomNumber);
    uint numShares = prizePool.computeTotalShares(prizePool.estimateNextNumberOfTiers());
    uint amount = 1e18 * numShares;
    contribute(amount);
    uint256 firstPrizesPerShare = amount / numShares;
    uint256 remainder = amount - (firstPrizesPerShare * numShares);
    assertEq(prizePool.pendingReserveContributions(), remainder + (firstPrizesPerShare * RESERVE_SHARES), "pending reserve contributions");
    awardDraw(winningRandomNumber);
    // reclaim daily and canary tiers
    uint reclaimedReserve = (1e18 * (2 * CANARY_SHARES)) * RESERVE_SHARES / prizePool.getTotalShares();
    assertApproxEqAbs(prizePool.pendingReserveContributions(), reclaimedReserve, 1000, "no pending reserve contributions");
  }

  function test_allocateRewardFromReserve_CallerNotDrawManager() public {
    vm.prank(address(0));
    vm.expectRevert(
      abi.encodeWithSelector(CallerNotDrawManager.selector, address(0), address(this))
    );
    prizePool.allocateRewardFromReserve(vault, 1);
  }

  function test_allocateRewardFromReserve_RewardRecipientZeroAddress() public {
    vm.expectRevert(
      abi.encodeWithSelector(RewardRecipientZeroAddress.selector)
    );
    prizePool.allocateRewardFromReserve(address(0), 1);
  }

  function test_allocateRewardFromReserve_PrizePoolShutdown() public {
    vm.warp(prizePool.shutdownAt());
    vm.expectRevert(
      abi.encodeWithSelector(PrizePoolShutdown.selector)
    );
    prizePool.allocateRewardFromReserve(address(0), 1);
  }

  function test_allocateRewardFromReserve_InsufficientReserve() public {
    vm.expectRevert(abi.encodeWithSelector(InsufficientReserve.selector, 1, 0));
    prizePool.allocateRewardFromReserve(address(this), 1);
  }

  function test_allocateRewardFromReserve() public {
    contribute(310e18);
    awardDraw(winningRandomNumber);
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
    assertEq(prizePool.getTotalContributedBetween(1, 1), 10e18);
  }

  function testGetTotalContributedBetween_oneBeforeLastContribution() public {
    contribute(10e18); // 1
    awardDraw(12345); // award 1
    awardDraw(123456); // award 2
    contribute(10e18); // 3
    assertEq(prizePool.getTotalContributedBetween(1, 2), 10e18);
  }

  function testGetContributedBetween() public {
    contribute(10e18);
    assertEq(prizePool.getContributedBetween(address(this), 1, 1), 10e18);
  }

  function testGetTierAccrualDurationInDraws() public {
    assertEq(prizePool.getTierAccrualDurationInDraws(0), 366);
  }

  function testContributePrizeTokens() public {
    contribute(100);
    assertEq(prizeToken.balanceOf(address(prizePool)), 100);
  }

  function testContributePrizeTokens_contributesToOpenDrawNotAwardingDraw() public {
    // warp 1 draw ahead so that the open draw is +1 from the awarding draw
    vm.warp(firstDrawOpensAt + drawPeriodSeconds);
    assertEq(prizePool.getDrawIdToAward(), 1);

    // contribute and verify that contributions go to open draw (not awarding draw)
    contribute(1e18);
    assertEq(prizePool.getTotalContributedBetween(1, 1), 0);
    assertEq(prizePool.getTotalContributedBetween(2, 2), 1e18); // e17 since smoothing is in effect
    assertEq(prizePool.getTotalContributedBetween(1, 2), 1e18); // e17 since smoothing is in effect
  }

  function testContributePrizeTokens_notLostOnSkippedDraw() public {
    uint amount = 1e18 * prizePool.getTotalShares();
    contribute(amount);
    assertEq(prizeToken.balanceOf(address(prizePool)), amount);
    assertEq(prizePool.getDrawIdToAward(), 1);

    // warp to skip a draw:
    vm.warp(firstDrawOpensAt + drawPeriodSeconds * 2);
    assertEq(prizePool.getDrawIdToAward(), 2);

    // award draw:
    awardDraw(1234);

    // check if tier liquidity includes contribution from draws 1 + 2
    assertEq(prizePool.getTotalContributedBetween(1, 1), amount);
    assertEq(prizePool.getTotalContributedBetween(2, 2), 0);
    assertEq(prizePool.getTierRemainingLiquidity(0), 100e18);
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

  function testDonatePrizeTokens() public {
    prizeToken.mint(address(this), 100);
    prizeToken.approve(address(prizePool), 100);
    prizePool.donatePrizeTokens(100);
    assertEq(prizeToken.balanceOf(address(prizePool)), 100);
    assertEq(prizePool.getTotalContributedBetween(1, 1), 100);
    assertEq(prizePool.getDonatedBetween(1,1), 100);
  }

  function testDonatePrizeTokens_twice() public {
    prizeToken.mint(address(this), 100);
    prizeToken.approve(address(prizePool), 100);
    prizePool.donatePrizeTokens(50);
    awardDraw(winningRandomNumber);
    prizePool.donatePrizeTokens(50);
    assertEq(prizeToken.balanceOf(address(prizePool)), 100);
    assertEq(prizePool.getTotalContributedBetween(1, 2), 100);
    assertEq(prizePool.getDonatedBetween(1, 2), 100);
  }

  function testAccountedBalance_withdrawnReserve() public {
    contribute(100e18);
    awardDraw(1);
    // reserve = 10e18 * (10 / 310) = 0.3225806451612903e18
    assertApproxEqAbs(
      prizePool.reserve(),
      (100e18 * RESERVE_SHARES) / prizePool.getTotalShares(),
      200
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
    awardDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint256 prize = claimPrize(msg.sender, 0, 0);
    assertEq(prizePool.accountedBalance(), 100e18 - prize);
  }

  function testAccountedBalance_oneClaim_andMoreContrib() public {
    contribute(100e18);
    awardDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint256 prize = claimPrize(msg.sender, 0, 0);
    contribute(10e18);
    assertEq(prizePool.accountedBalance(), 110e18 - prize);
  }

  function testAccountedBalance_twoDraws_twoClaims() public {
    contribute(100e18);
    awardDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint256 prize = claimPrize(msg.sender, 0, 0);

    awardDraw(1);
    mockTwab(address(this), msg.sender, 0);
    uint256 prize2 = claimPrize(msg.sender, 0, 0);

    assertEq(prizePool.accountedBalance(), 100e18 - prize - prize2, "accounted balance");
  }

  function testGetVaultPortion_fromDonator() public {
    contribute(100e18, prizePool.DONATOR()); // available draw 1
    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(prizePool.DONATOR(), 1, 1)), 0);
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
    awardDraw(winningRandomNumber); // draw 1
    awardDraw(winningRandomNumber); // draw 2
    assertEq(prizePool.getLastAwardedDrawId(), 2);
    contribute(100e18); // available on draw 3

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 2, 2)), 0);
  }

  function testGetVaultPortion_BeforeAndAtContribution() public {
    contribute(100e18); // available draw 1

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 1)), 1e18);
  }

  function testGetVaultPortion_BeforeAndAfterContribution() public {
    awardDraw(winningRandomNumber); // draw 1
    contribute(100e18); // available draw 2

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 2)), 1e18);
  }

  function testGetVaultPortion_ignoresDonations() public {
    // contribute to vault1
    prizeToken.mint(address(prizePool), 100);
    prizePool.contributePrizeTokens(address(vault), 100);

    // contribute to vault2
    prizeToken.mint(address(prizePool), 100);
    prizePool.contributePrizeTokens(address(vault2), 100);

    prizeToken.mint(address(this), 100);
    prizeToken.approve(address(prizePool), 100);
    prizePool.donatePrizeTokens(100);

    assertEq(prizePool.getVaultPortion(address(vault), 1, 1).unwrap(), 0.5e18);
    assertEq(prizePool.getVaultPortion(address(vault2), 1, 1).unwrap(), 0.5e18);
  }

  function testGetVaultPortion_handlesOnlyDonation() public {
    prizeToken.mint(address(this), 100);
    prizeToken.approve(address(prizePool), 100);
    prizePool.donatePrizeTokens(100);

    assertEq(prizePool.getVaultPortion(address(vault2), 1, 1).unwrap(), 0);
  }

  function test_getOpenDrawId_onStart() public {
    vm.warp(firstDrawOpensAt);
    assertEq(prizePool.getOpenDrawId(), 1);
  }

  function test_getOpenDrawId_halfway() public {
    vm.warp(firstDrawOpensAt + drawPeriodSeconds / 2);
    uint256 openDrawId = prizePool.getOpenDrawId();
    assertEq(openDrawId, 1);
  }

  function test_getOpenDrawId_onSecond() public {
    vm.warp(firstDrawOpensAt + drawPeriodSeconds);
    assertEq(prizePool.getOpenDrawId(), 2);
  }

  function testIsDrawFinalized() public {
    assertEq(prizePool.isDrawFinalized(1), false);
    awardDraw(12345);
    assertEq(prizePool.isDrawFinalized(1), false);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds);
    assertEq(prizePool.isDrawFinalized(1), false);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds * 2 - 1);
    assertEq(prizePool.isDrawFinalized(1), false);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds * 2);
    assertEq(prizePool.isDrawFinalized(1), true);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds * 2 + 1);
    assertEq(prizePool.isDrawFinalized(1), true);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds * 2 + 100 days);
    assertEq(prizePool.isDrawFinalized(1), true);
  }

  function testAwardDraw_notManager() public {
    vm.prank(address(0));
    vm.expectRevert(
      abi.encodeWithSelector(CallerNotDrawManager.selector, address(0), address(this))
    );
    prizePool.awardDraw(winningRandomNumber);
  }

  function testAwardDraw_notElapsed_atStart() public {
    vm.warp(firstDrawOpensAt);
    vm.expectRevert(
      abi.encodeWithSelector(AwardingDrawNotClosed.selector, firstDrawOpensAt + drawPeriodSeconds)
    );
    prizePool.awardDraw(winningRandomNumber);
  }

  function testAwardDraw_notElapsed_subsequent() public {
    vm.warp(firstDrawOpensAt + drawPeriodSeconds);
    prizePool.awardDraw(winningRandomNumber);
    vm.expectRevert(
      abi.encodeWithSelector(
        AwardingDrawNotClosed.selector,
        firstDrawOpensAt + drawPeriodSeconds * 2
      )
    );
    prizePool.awardDraw(winningRandomNumber);
  }

  function testAwardDraw_drawTimeout() public {
    vm.warp(prizePool.shutdownAt());
    vm.expectRevert(
      abi.encodeWithSelector(
        PrizePoolShutdown.selector
      )
    );
    prizePool.awardDraw(winningRandomNumber);
  }

  function testAwardDraw_twabShutdown() public {
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(twabController.lastObservationAt.selector),
      abi.encode(true)
    );
    vm.expectRevert(
      abi.encodeWithSelector(
        PrizePoolShutdown.selector
      )
    );
    prizePool.awardDraw(winningRandomNumber);
  }

  function testAwardDraw_emittedDrawIdSameAsReturnedDrawId() public {
    contribute(510e18);
    uint24 expectedDrawId = 1;

    vm.expectEmit(true, true, true, false);
    emit DrawAwarded(expectedDrawId, 12345, 3, 3, 0, 0, firstDrawOpensAt);
    vm.warp(prizePool.drawClosesAt(prizePool.getOpenDrawId()));
    uint24 closedDrawId = prizePool.awardDraw(12345);

    assertEq(closedDrawId, expectedDrawId, "awarded draw ID matches expected");
  }

  function testAwardDraw_notElapsed_openDrawPartway() public {
    vm.warp(firstDrawOpensAt + drawPeriodSeconds);
    prizePool.awardDraw(winningRandomNumber);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds + drawPeriodSeconds / 2);
    vm.expectRevert(
      abi.encodeWithSelector(
        AwardingDrawNotClosed.selector,
        firstDrawOpensAt + drawPeriodSeconds * 2
      )
    );
    prizePool.awardDraw(winningRandomNumber);
  }

  function testAwardDraw_notElapsed_partway() public {
    vm.warp(firstDrawOpensAt + drawPeriodSeconds / 2);
    vm.expectRevert(
      abi.encodeWithSelector(AwardingDrawNotClosed.selector, firstDrawOpensAt + drawPeriodSeconds)
    );
    prizePool.awardDraw(winningRandomNumber);
  }

  function testAwardDraw_invalidNumber() public {
    vm.expectRevert(abi.encodeWithSelector(RandomNumberIsZero.selector));
    prizePool.awardDraw(0);
  }

  function testAwardDraw_noLiquidity() public {
    awardDraw(winningRandomNumber);

    assertEq(prizePool.getWinningRandomNumber(), winningRandomNumber);
    assertEq(prizePool.getLastAwardedDrawId(), 1);
    assertEq(prizePool.getOpenDrawId(), 2);
    assertEq(prizePool.drawOpensAt(prizePool.getLastAwardedDrawId()), firstDrawOpensAt);
    assertEq(
      prizePool.drawClosesAt(prizePool.getLastAwardedDrawId()),
      firstDrawOpensAt + drawPeriodSeconds
    );
    assertEq(prizePool.lastAwardedDrawAwardedAt(), block.timestamp);
  }

  function testAwardDraw_withLiquidity() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);

    uint256 liquidityPerShare = 100e18 / prizePool.getTotalShares();
    uint256 remainder = 100e18 - liquidityPerShare * prizePool.getTotalShares();

    assertEq(
      prizePool.prizeTokenPerShare(),
      liquidityPerShare,
      "prize token per share"
    );

    uint256 reserve = remainder + RESERVE_SHARES * liquidityPerShare;

    assertEq(prizePool.reserve(), reserve, "reserve"); // remainder of the complex fraction
    assertEq(prizePool.getTotalContributedBetween(1, 1), 100e18); // ensure not a single wei is lost!
  }

  function test_getShutdownDrawId_init() public {
    params.drawTimeout = 40; // there are 40 draws within the timeframe: 1-40
    prizePool = newPrizePool();
    assertEq(prizePool.getShutdownDrawId(), 41, "draw id is the draw that ends before/on the timeout");
  }

  function test_getShutdownDrawId_shift() public {
    params.drawTimeout = 40;
    prizePool = newPrizePool();
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getShutdownDrawId(), 42, "draw id is the draw that ends before/on the timeout");
  }

  function test_getShutdownDrawId_twabShutdownAtLimit() public {
    params.drawPeriodSeconds = 1 days;
    params.drawTimeout = type(uint8).max;
    params.grandPrizePeriodDraws = 365;
    params.firstDrawOpensAt = uint48(twabController.lastObservationAt() - 1 days);
    prizePool = newPrizePool();
    assertEq(prizePool.getShutdownDrawId(), 2, "draw id is the draw that ends before the twab controller shutdown");
  }

  function testDrawTimeoutAt_init() public {
    assertEq(prizePool.drawTimeoutAt(), firstDrawOpensAt + drawTimeout*drawPeriodSeconds);
  }

  function testDrawTimeoutAt_oneDraw() public {
    params.drawTimeout = 2; // once two draws have passed the prize pool is timed out
    prizePool = newPrizePool();
    awardDraw(winningRandomNumber);
    assertEq(prizePool.drawTimeoutAt(), prizePool.lastAwardedDrawAwardedAt() + params.drawTimeout*drawPeriodSeconds);
  }

  function testShutdownAt_init() public {
    assertEq(prizePool.shutdownAt(), firstDrawOpensAt + drawTimeout*drawPeriodSeconds);
  }

  function testShutdownAt_nearTwabEnd() public {
    uint256 twabEnd = firstDrawOpensAt + (drawTimeout/2)*drawPeriodSeconds;
    vm.mockCall(
      address(twabController),
      abi.encodeCall(twabController.lastObservationAt, ()),
      abi.encode(twabEnd)
    );
    vm.warp(twabEnd - drawPeriodSeconds*3);
    awardDraw(winningRandomNumber);
    assertEq(prizePool.shutdownAt(), twabEnd);
  }

  function test_shutdownBalanceOf_notShutdown() public {
    assertEq(prizePool.shutdownBalanceOf(address(this), msg.sender), 0);
  }

  function test_shutdownBalanceOf_shutdown_noDraws_noBalance_noContributions() public {
    vm.warp(prizePool.shutdownAt());
    assertEq(prizePool.shutdownBalanceOf(address(this), msg.sender), 0);
  }

  function test_shutdownBalanceOf_shutdown_noDraws_withBalance_noContributions() public {
    vm.warp(prizePool.shutdownAt());
    mockShutdownTwab(1e18, 1e18);
    assertEq(prizePool.shutdownBalanceOf(address(this), msg.sender), 0);
  }

  function test_shutdownBalanceOf_shutdown_noDraws_withBalance_withContributions() public {
    contribute(100e18);
    vm.warp(prizePool.shutdownAt());
    mockShutdownTwab(1e18, 1e18);
    assertApproxEqAbs(prizePool.shutdownBalanceOf(address(this), msg.sender), 100e18, 10000);
    // should yield the same answer twice
    assertApproxEqAbs(prizePool.shutdownBalanceOf(address(this), msg.sender), 100e18, 10000);
  }
  
  function test_shutdownBalanceOf_shutdown_multiple_vault() public {
    contribute(50e18, vault);
    contribute(150e18, vault2);
    vm.warp(prizePool.shutdownAt());
    mockShutdownTwab(0.5e18, 1e18);
    assertApproxEqAbs(prizePool.shutdownBalanceOf(vault, msg.sender), 25e18, 10000);
  }

  function test_shutdownBalanceOf_shutdown_noDraws_withBalance_withContributions_partial() public {
    contribute(100e18);
    vm.warp(prizePool.shutdownAt());
    mockShutdownTwab(0.5e18, 1e18);
    assertApproxEqAbs(prizePool.shutdownBalanceOf(address(this), msg.sender), 50e18, 1000, "first claim");
  }

  function test_shutdownBalanceOf_shutdown_withDraws_withBalance_withContributions() public {
    params.drawTimeout = (grandPrizePeriodDraws/2);
    prizePool = newPrizePool();
    contribute(100e18);
    awardDraw(winningRandomNumber);
    contribute(100e18);
    awardDraw(winningRandomNumber);
    
    vm.warp(prizePool.shutdownAt());

    mockShutdownTwab(0.5e18, 1e18);
    assertApproxEqAbs(prizePool.shutdownBalanceOf(address(this), msg.sender), 100e18, 10000);
  }

  function test_shutdownBalanceOf_shutdown_withDrawsBeforeAndAfter_withBalance_withContributions() public {
    prizePool = newPrizePool();
    contribute(100e18);
    awardDraw(winningRandomNumber);
    contribute(100e18);
    awardDraw(winningRandomNumber);
    contribute(100e18);

    // we want shutdown draw id === draw id to award
    vm.warp(prizePool.lastAwardedDrawAwardedAt() + drawTimeout*drawPeriodSeconds);
    mockShutdownTwab(0.5e18, 1e18);
    assertEq(prizePool.shutdownBalanceOf(address(this), msg.sender), 150e18);
  }

  function test_shutdownBalanceOf_shutdown_noDraws_withBalance_withContributions_multiple_claims() public {
    contribute(100e18);
    vm.warp(prizePool.shutdownAt());
    mockShutdownTwab(0.5e18, 1e18);
    vm.startPrank(msg.sender);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 50e18, "first claim");
    vm.stopPrank();

    vm.warp(firstDrawOpensAt + drawPeriodSeconds + drawTimeout*drawPeriodSeconds + 49*drawPeriodSeconds);
    contribute(100e18); // contributed to last closed draw.  Means 10e18 is distributed to the next draw
    vm.warp(firstDrawOpensAt + drawPeriodSeconds + drawTimeout*drawPeriodSeconds + 50*drawPeriodSeconds); // move forward 1 draw

    // should be 50% of last contribution
    assertEq(prizePool.shutdownBalanceOf(address(this), msg.sender), 50e18, "second claim");
  }

  function test_shutdownBalanceOf_with_multiple_users_and_rewards() public {
    // reserve = 10/220 * 660 = 30
    // remaining = 630
    // bob = 120*630e18/440
    contribute(220e18, vault);
    contribute(440e18, vault2);
    awardDraw(1);
    prizePool.allocateRewardFromReserve(bob, 0.1e18);
    uint96 remainder = prizePool.reserve();    
    prizePool.allocateRewardFromReserve(alice, remainder);
    vm.warp(prizePool.shutdownAt());

    mockShutdownTwab(0.5e18, 1e18, bob, vault);
    mockShutdownTwab(500e18, 1000e18, alice, vault2);

    uint bobShutdownBalance = 630e18/6;
    uint aliceShutdownBalance = 630e18/3;
    assertEq(prizePool.shutdownBalanceOf(vault, bob), bobShutdownBalance, "bob balance");
    assertEq(prizePool.shutdownBalanceOf(vault2, alice), aliceShutdownBalance, "alice balance");
    assertEq(prizePool.rewardBalance(bob), 0.1e18, "bob rewards");
    assertEq(prizePool.rewardBalance(alice), remainder, "alice rewards");

    vm.prank(bob);
    prizePool.withdrawRewards(bob, 0.1e18);
    vm.prank(bob);
    prizePool.withdrawShutdownBalance(vault, bob);
    assertEq(prizeToken.balanceOf(bob), bobShutdownBalance + 0.1e18, "bob token balance");

    vm.prank(alice);
    prizePool.withdrawShutdownBalance(vault2, alice);
    vm.prank(alice);
    prizePool.withdrawRewards(alice, remainder);
    assertEq(prizeToken.balanceOf(alice), aliceShutdownBalance + remainder, "alice token balance");

    assertEq(prizePool.accountedBalance(), 660e18 - (630e18/6 + 630e18/3) - 0.1e18 - remainder, "final balance");
  }

  function test_computeShutdownPortion_empty() public {
    vm.warp(prizePool.shutdownAt());
    ShutdownPortion memory portion = prizePool.computeShutdownPortion(address(this), bob);
    assertEq(portion.numerator, 0);
    assertEq(portion.denominator, 0);
  }

  function test_computeShutdownPortion_nonZero() public {
    contribute(220e18, vault);
    uint newTime = prizePool.shutdownAt();
    vm.warp(newTime);
    mockShutdownTwab(0.5e18, 1e18, bob, vault);
    ShutdownPortion memory portion = prizePool.computeShutdownPortion(vault, bob);
    assertEq(portion.numerator, 220e18 * 0.5e18);
    assertEq(portion.denominator, 220e18 * 1e18);
  }

  function test_withdrawShutdownBalance_notShutdown() public {
    vm.expectRevert(abi.encodeWithSelector(PrizePoolNotShutdown.selector));
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 0);
  }

  function test_withdrawShutdownBalance_init() public {
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 0);
  }

  function test_withdrawShutdownBalance_contributeAfterShutdown() public {
    prizePool = newPrizePool();
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds);
    mockShutdownTwab(0.5e18, 1e18);
    vm.startPrank(msg.sender);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 0);
    contribute(100e18);
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds + drawPeriodSeconds);
    // they get nothing, since no one added before
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 0);
    vm.stopPrank();
  }

  function test_withdrawShutdownBalance_contributeBeforeAndAfterShutdown_oneClaim() public {
    prizePool = newPrizePool();
    contribute(100e18);
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds);
    mockShutdownTwab(0.5e18, 1e18);
    vm.startPrank(msg.sender);
    contribute(100e18);
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds + drawPeriodSeconds);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 100e18, "second claim");
    vm.stopPrank();
  }

  function test_withdrawShutdownBalance_contributeBeforeAndAfterShutdown_claimTwice() public {
    prizePool = newPrizePool();
    contribute(100e18);
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds);
    mockShutdownTwab(1e18, 1e18);
    vm.startPrank(msg.sender);
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds + drawPeriodSeconds);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 100e18, "first claim");
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 0e18, "second claim");
    vm.stopPrank();
  }

  function test_withdrawShutdownBalance_contributeBeforeAndAfterShutdown_twoClaim() public {
    prizePool = newPrizePool();
    contribute(100e18);
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds);
    mockShutdownTwab(0.5e18, 1e18);
    vm.startPrank(msg.sender);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 50e18, "first claim");
    contribute(100e18);
    vm.warp(firstDrawOpensAt + drawTimeout*drawPeriodSeconds + drawPeriodSeconds);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 50e18, "second claim");
    vm.stopPrank();
  }

  function test_withdrawShutdownBalance_onShutdown() public {
    prizePool = newPrizePool();
    contribute(100e18);
    awardDraw(winningRandomNumber);
    contribute(100e18);
    awardDraw(winningRandomNumber);
    contribute(100e18);

    // we want shutdown draw id === draw id to award
    vm.warp(prizePool.lastAwardedDrawAwardedAt() + drawTimeout*drawPeriodSeconds);
    mockShutdownTwab(0.5e18, 1e18);
    vm.startPrank(msg.sender);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 150e18);
    assertEq(prizePool.withdrawShutdownBalance(address(this), msg.sender), 0);
    vm.stopPrank();
  }

  function test_getDrawId() public {
    assertEq(prizePool.getDrawId(0), 1, "before start");
    assertEq(prizePool.getDrawId(firstDrawOpensAt), 1, "at start");
    assertEq(prizePool.getDrawId(firstDrawOpensAt + drawPeriodSeconds/2), 1, "after start");
    assertEq(prizePool.getDrawId(firstDrawOpensAt + drawPeriodSeconds), 2, "after first draw");
  }

  function test_getShutdownInfo_notShutdown() public {
    prizePool = newPrizePool();
    contribute(100e18);
    (uint256 balance, Observation memory obs) = prizePool.getShutdownInfo();
    assertEq(balance, 0);
  }

  function test_getShutdownInfo_shutdown() public {
    prizePool = newPrizePool();
    contribute(100e18);
    vm.warp(prizePool.drawClosesAt(drawTimeout));
    assertTrue(prizePool.isShutdown(), "is shutdown");
    (uint256 balance, Observation memory obs) = prizePool.getShutdownInfo();
    assertEq(balance, 100e18);
  }

  function test_getShutdownInfo_shutdown_lessRewards() public {
    prizePool = newPrizePool();
    contribute(100e18);
    awardDraw(1);
    prizePool.allocateRewardFromReserve(address(this), 1e18);
    vm.warp(prizePool.drawClosesAt(1 + drawTimeout));
    assertTrue(prizePool.isShutdown(), "is shutdown");
    (uint256 balance, Observation memory obs) = prizePool.getShutdownInfo();
    assertEq(balance, 99e18);
  }

  function test_getShutdownInfo_shutdown_frozenBalance() public {
    prizePool = newPrizePool();
    contribute(100e18);
    vm.warp(prizePool.drawClosesAt(drawTimeout));
    assertTrue(prizePool.isShutdown(), "is shutdown");
    uint256 balance; Observation memory obs;
    (balance, obs) = prizePool.getShutdownInfo(); // trigger to record
    assertEq(balance, 100e18);
    assertEq(obs.available, 100e18);
    assertEq(obs.disbursed, 0);
    
    contribute(100e18);
    
    (balance, obs) = prizePool.getShutdownInfo();
    assertEq(balance, 100e18);
    assertEq(obs.available, 100e18);
    assertEq(obs.disbursed, 0);
  }

  function testTotalContributionsForClosedDraw_noClaims() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getTotalContributedBetween(1, 1), 100e18, "first draw"); // 10e18
    awardDraw(winningRandomNumber);
    // liquidity should carry over!
    assertEq(prizePool.getTotalContributedBetween(2, 2), 0, "second draw");
  }

  function testAwardDraw_shouldNotShrinkOnFirst() public {
    uint8 startingTiers = 5;

    // reset prize pool at higher tiers
    params = ConstructorParams(
      prizeToken,
      twabController,
      drawManager,
      tierLiquidityUtilizationRate,
      drawPeriodSeconds,
      firstDrawOpensAt,
      grandPrizePeriodDraws,
      startingTiers, // higher number of tiers
      100,
      5,
      10,
      drawTimeout
    );
    prizePool = newPrizePool();

    contribute(510e18);
    awardDraw(1234);

    // tiers should not change upon first draw
    assertEq(prizePool.numberOfTiers(), startingTiers, "starting tiers");
  }

  function testAwardDraw_same() public {
    contribute(1e18);
    awardDraw(1234);
    // now tiers can change
    _claimAllPrizes(prizePool.numberOfTiers()-1);
    awardDraw(1234);
    assertEq(prizePool.numberOfTiers(), MINIMUM_NUMBER_OF_TIERS, "tiers has not changed");
  }

  function testAwardDraw_expandingTiers() public {
    contribute(1e18);
    awardDraw(1234);
    // claim all tiers
    _claimAllPrizes(prizePool.numberOfTiers());

    vm.expectEmit();
    emit DrawAwarded(
      2,
      245,
      MINIMUM_NUMBER_OF_TIERS,
      MINIMUM_NUMBER_OF_TIERS+1,
      45454545454545576 /*reserve from output*/,
      4545454545454545 /*prize tokens per share from output*/,
      firstDrawOpensAt + drawPeriodSeconds
    );
    awardDraw(245);
    assertEq(prizePool.numberOfTiers(), MINIMUM_NUMBER_OF_TIERS+1, "grow by 1");
  }

  function testAwardDraw_shrinkOne() public {
    contribute(1e18);
    awardDraw(1234);
    // claim all prizes no matter what
    _claimAllPrizes(prizePool.numberOfTiers());
    contribute(1e18); // ensure there is prize money
    awardDraw(245);

    // do not claim the canary prizes
    _claimAllPrizes(prizePool.numberOfTiers() - 2);

    vm.expectEmit();
    emit DrawAwarded(
      3,
      245,
      MINIMUM_NUMBER_OF_TIERS+1,
      MINIMUM_NUMBER_OF_TIERS,
      78125000000000236 /*reserve from output*/,
      7812499999999999 /*prize tokens per share from output*/,
      firstDrawOpensAt + drawPeriodSeconds*2
    );
    awardDraw(245);
    assertEq(prizePool.numberOfTiers(), MINIMUM_NUMBER_OF_TIERS, "grow by 1");
  }

  function testAwardDraw_shrinkMoreThan1() public {
    uint8 startingTiers = MINIMUM_NUMBER_OF_TIERS + 2;

    // reset prize pool at higher tiers
    params = ConstructorParams(
      prizeToken,
      twabController,
      address(this),
      tierLiquidityUtilizationRate,
      drawPeriodSeconds,
      firstDrawOpensAt,
      grandPrizePeriodDraws,
      startingTiers, // higher number of tiers
      100,
      5,
      10,
      drawTimeout
    );
    prizePool = newPrizePool();

    contribute(prizePool.getTotalShares() * 1e18);
    awardDraw(1234);
    // no claims
    awardDraw(4567);
    assertEq(prizePool.numberOfTiers(), startingTiers - 1, "number of tiers decreased by 1");
  }

  function testAwardDraw_multipleDraws() public {
    contribute(1e18);
    awardDraw(1234);
    awardDraw(1234);
    contribute(1e18);
    awardDraw(554);

    mockTwab(address(this), sender5, 1);
    assertTrue(claimPrize(sender5, 1, 0) > 0, "has prize");
  }

  function testAwardDraw_emitsEvent() public {
    vm.expectEmit();
    emit DrawAwarded(1, 12345, MINIMUM_NUMBER_OF_TIERS, MINIMUM_NUMBER_OF_TIERS, 0, 0, firstDrawOpensAt);
    awardDraw(12345);
  }

  function testEstimateNextNumberOfTiers_firstDrawNoChange() public {
    assertEq(prizePool.estimateNextNumberOfTiers(), MINIMUM_NUMBER_OF_TIERS, "no change");
  }

  function testEstimateNextNumberOfTiers_grow() public {
    contribute(100e18);
    awardDraw(1234);
    _claimAllPrizes(prizePool.numberOfTiers());
    assertEq(prizePool.estimateNextNumberOfTiers(), MINIMUM_NUMBER_OF_TIERS+1, "increase by 1");
  }

  function testEstimateNextNumberOfTiers_shrink() public {
    params.numberOfTiers = 7;
    prizePool = newPrizePool();
    contribute(100e18);
    awardDraw(1234);
    // no claims, now it'll decrease
    assertEq(prizePool.estimateNextNumberOfTiers(), 6, "decrease by 1");
  }

  function testGetTotalShares() public {
    assertEq(prizePool.getTotalShares(), (uint(MINIMUM_NUMBER_OF_TIERS) - uint(NUMBER_OF_CANARY_TIERS)) * uint(TIER_SHARES) + RESERVE_SHARES + NUMBER_OF_CANARY_TIERS * uint(CANARY_SHARES));
  }

  function testGetRemainingTierLiquidity_invalidTier() public {
    assertEq(prizePool.getTierRemainingLiquidity(10), 0);
  }

  function testGetRemainingTierLiquidity_afterClaim() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);

    uint256 tierLiquidity = TIER_SHARES * (100e18 / prizePool.getTotalShares());

    assertEq(prizePool.getTierRemainingLiquidity(1), tierLiquidity, "second tier");
    
    // Get the initial reserve to compare any additions after claim
    uint256 initialReserve = prizePool.reserve();

    mockTwab(address(this), sender1, 1);
    uint256 prize = prizePool.getTierPrizeSize(1);
    assertEq(claimPrize(sender1, 1, 0), prize, "second tier prize 1");

    // reduced by prize
    assertEq(
      prizePool.getTierRemainingLiquidity(1) + (prizePool.reserve() - initialReserve), // rounding errors are dumped in the reserve
      tierLiquidity - prize,
      "second tier liquidity post claim 1"
    );
  }

  function testGetRemainingTierLiquidity_allTiers() public {
    contribute(1e18 * prizePool.getTotalShares());
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getTierRemainingLiquidity(0), 100e18);
    assertEq(prizePool.getTierRemainingLiquidity(1), 100e18);
    assertEq(prizePool.getTierRemainingLiquidity(2), 5e18);
  }

  function testIsWinner_noDraw() public {
    vm.expectRevert(abi.encodeWithSelector(NoDrawsAwarded.selector));
    prizePool.isWinner(address(this), msg.sender, 10, 0);
  }

  function testIsWinner_invalidTier() public {
    awardDraw(winningRandomNumber);

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
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    assertEq(prizePool.isWinner(address(this), msg.sender, 1, 0), true);
  }

  function testIsWinnerGrandPrize() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    assertEq(prizePool.isWinner(address(this), msg.sender, 0, 0), true);
  }

  function testIsWinner_emitsInvalidPrizeIndex() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    vm.expectRevert(abi.encodeWithSelector(InvalidPrizeIndex.selector, 4, 4, 1));
    prizePool.isWinner(address(this), msg.sender, 1, 4);
  }

  function testIsWinner_doesNotChange() public {
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    assertFalse(prizePool.isWinner(address(this), msg.sender, 1, 0), "not a winner");
    contribute(100e18);
    assertFalse(prizePool.isWinner(address(this), msg.sender, 1, 0), "still not a winner");
  }

  function testIsWinner_normalPrizes() public {
    uint iterations = 20; //grandPrizePeriodDraws;
    uint users = 50;

    uint balance = 1e18;
    uint totalSupply = users * balance;

    uint256 random = uint256(keccak256(abi.encode(1234)));

    uint[] memory prizeCounts = new uint[](iterations);
    uint totalPrizeCount;

    for (uint i = 0; i < iterations; i++) {
      contribute(100e18);
      awardDraw(random);
      for (uint u = 0; u < users; u++) {
        address user = makeAddr(string(abi.encodePacked(u)));
        for (uint8 t = 0; t < prizePool.numberOfTiers() - 1; t++) {
          mockTwabForUser(address(this), user, t, balance);
          mockTwabTotalSupply(address(this), t, totalSupply);
          for (uint32 p = 0; p < prizePool.getTierPrizeCount(t); p++) {
            if (prizePool.isWinner(address(this), user, t, p)) {
              prizeCounts[i]++;
            }
          }
        }
      }
      // console2.log("Iteration %s prize count: %s", i, prizeCounts[i]);
      totalPrizeCount += prizeCounts[i];
      random = uint256(keccak256(abi.encode(random)));
    }

    console2.log("Average number of prizes: ", totalPrizeCount / iterations);
  }

  function testWasClaimed_not() public {
    assertEq(prizePool.wasClaimed(vault, msg.sender, 0, 0), false);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 0, 0), false);

    assertEq(prizePool.wasClaimed(vault, msg.sender, prizePool.getLastAwardedDrawId(), 0, 0), false);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, prizePool.getLastAwardedDrawId(), 0, 0), false);
  }

  function testWasClaimed_single() public {
    vm.prank(vault);
    contribute(100e18, vault);
    prizeToken.mint(address(prizePool), 100e18);

    awardDraw(winningRandomNumber);

    mockTwab(vault, msg.sender, 1);
    vm.prank(vault);
    claimPrize(msg.sender, 1, 0);

    assertEq(prizePool.wasClaimed(vault, msg.sender, 1, 0), true);
    assertEq(prizePool.wasClaimed(vault, msg.sender, prizePool.getLastAwardedDrawId(), 1, 0), true);
  }

  function testWasClaimed_single_twoVaults() public {
    vm.prank(vault);
    contribute(100e18, vault);
    prizeToken.mint(address(prizePool), 100e18);

    vm.prank(vault2);
    prizePool.contributePrizeTokens(vault2, 100e18);

    awardDraw(winningRandomNumber);

    mockTwab(vault, msg.sender, 1);
    vm.prank(vault);
    claimPrize(msg.sender, 1, 0);
    mockTwab(vault2, msg.sender, 1);
    vm.prank(vault2);
    claimPrize(msg.sender, 1, 0);

    assertEq(prizePool.wasClaimed(vault, msg.sender, 1, 0), true);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 1, 0), true);

    assertEq(prizePool.wasClaimed(vault, msg.sender, prizePool.getLastAwardedDrawId(), 1, 0), true);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, prizePool.getLastAwardedDrawId(), 1, 0), true);
  }

  function testWasClaimed_old_draw() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
    assertEq(prizePool.wasClaimed(vault, msg.sender, 0, 0), true);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 0, 0), false);
    assertEq(prizePool.wasClaimed(vault, msg.sender, prizePool.getLastAwardedDrawId(), 0, 0), true);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, prizePool.getLastAwardedDrawId(), 0, 0), false);
    awardDraw(winningRandomNumber);
    assertEq(prizePool.wasClaimed(vault, msg.sender, 0, 0), false);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, 0, 0), false);
    assertEq(prizePool.wasClaimed(vault, msg.sender, prizePool.getLastAwardedDrawId(), 0, 0), false);
    assertEq(prizePool.wasClaimed(vault2, msg.sender, prizePool.getLastAwardedDrawId(), 0, 0), false);
  }

  function testAccountedBalance_remainder() public {
    contribute(1000);
    assertEq(prizePool.accountedBalance(), 1000, "accounted balance");
    awardDraw(winningRandomNumber);
    assertEq(prizePool.accountedBalance(), 1000, "accounted balance");
  }

  function testClaimPrize_zero() public {
    awardDraw(winningRandomNumber);
    address winner = makeAddr("winner");
    mockTwab(address(this), winner, 1);
    assertEq(prizePool.getTierPrizeSize(2), 0, "prize size");
    vm.expectRevert(abi.encodeWithSelector(PrizeIsZero.selector));
    prizePool.claimPrize(winner, 1, 0, winner, 0, address(this));
  }

  function testClaimPrize_ClaimPeriodExpired() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    uint24 awardedDrawId = prizePool.getLastAwardedDrawId();
    address winner = makeAddr("winner");
    mockTwab(address(this), winner, 1);
    uint256 awardedDrawOpened = prizePool.drawOpensAt(awardedDrawId);

    // warp to end of awarded draw (end of claim period)
    vm.warp(awardedDrawOpened + drawPeriodSeconds * 2);
    vm.expectRevert(abi.encodeWithSelector(ClaimPeriodExpired.selector));
    prizePool.claimPrize(winner, 1, 0, winner, 0, address(this));

    // warp to end of awarded draw (end of claim period) + 1 sec
    vm.warp(awardedDrawOpened + drawPeriodSeconds * 2 + 1);
    vm.expectRevert(abi.encodeWithSelector(ClaimPeriodExpired.selector));
    prizePool.claimPrize(winner, 1, 0, winner, 0, address(this));

    // warp to right before end of awarded draw (end of claim period)
    vm.warp(awardedDrawOpened + drawPeriodSeconds * 2 - 1);
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
    awardDraw(winningRandomNumber);
    address winner = makeAddr("winner");
    address recipient = makeAddr("recipient");
    mockTwab(address(this), winner, 1);

    uint256 prize = prizePool.getTierPrizeSize(1);

    vm.expectEmit();
    emit ClaimedPrize(address(this), winner, recipient, 1, 1, 0, uint152(prize), 0, address(this));
    assertEq(prizePool.claimPrize(winner, 1, 0, recipient, 0, address(this)), prize);
    assertEq(prizeToken.balanceOf(recipient), prize, "recipient balance is good");
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrize_withFee() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    // total prize size is returned
    vm.expectEmit();
    emit IncreaseClaimRewards(address(this), 1e18);

    uint256 prize = prizePool.getTierPrizeSize(0);

    claimPrize(msg.sender, 0, 0, 1e18, address(this));
    // grand prize is (100/220) * 0.1 * 100e18 = 4.5454...e18
    assertEq(prizeToken.balanceOf(msg.sender), prize - 1e18, "balance is prize less fee");
    assertEq(prizePool.claimCount(), 1);
    assertEq(prizePool.rewardBalance(address(this)), 1e18);
  }

  function testClaimPrize_notWinner() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    vm.expectRevert(abi.encodeWithSelector(DidNotWin.selector, address(this), msg.sender, 0, 0));
    claimPrize(msg.sender, 0, 0);
  }

  function testClaimPrize_feeTooLarge() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    uint256 prize = prizePool.getTierPrizeSize(0);
    vm.expectRevert(abi.encodeWithSelector(RewardTooLarge.selector, 100e18, prize));
    claimPrize(msg.sender, 0, 0, 100e18, address(this));
  }

  function testClaimPrize_grandPrize_cannotClaimTwice() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    uint256 prize = prizePool.getTierPrizeSize(0);
    assertEq(claimPrize(msg.sender, 0, 0), prize, "prize size");
    // second claim reverts
    vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector, address(this), msg.sender, 0, 0));
    claimPrize(msg.sender, 0, 0);
  }

  function testComputeNextNumberOfTiers_zero() public {
    assertEq(prizePool.computeNextNumberOfTiers(0), MINIMUM_NUMBER_OF_TIERS);
  }

  function testComputeNextNumberOfTiers_deviationLess() public {
    // no canary tiers taken
    assertEq(prizePool.computeNextNumberOfTiers(3), MINIMUM_NUMBER_OF_TIERS);
  }

  function testComputeNextNumberOfTiers_deviationMore() public {
    // deviation is ok
    assertEq(prizePool.computeNextNumberOfTiers(8), MINIMUM_NUMBER_OF_TIERS);
  }

  function testComputeNextNumberOfTiers_canaryPrizes() public {
    // canary prizes were taken!
    assertEq(prizePool.computeNextNumberOfTiers(16), 4);
    assertEq(prizePool.computeNextNumberOfTiers(20), 4);
    assertEq(prizePool.computeNextNumberOfTiers(24), 4);
  }

  function testComputeNextNumberOfTiers_beyondMinimum_maxIncreaseBy1() public {
    // canary prizes were taken for tier 4!
    // should crank up to 5, but limit increasee to 1
    assertEq(prizePool.computeNextNumberOfTiers(80), 4);
  }

  function testComputeNextNumberOfTiers_beyondMinimum_bigDeviation_maxIncreaseBy1() public {
    // half the canary prizes were taken
    assertEq(prizePool.computeNextNumberOfTiers(150), 4);
  }

  function testComputeNextNumberOfTiers_beyondMinimum_nextLevelUp_maxIncreaseBy1() public {
    // half the canary prizes were taken
    assertEq(prizePool.computeNextNumberOfTiers(200), 4);
  }

  function testComputeNextNumberOfTiers_drop_maxDecreaseBy1() public {
    params.numberOfTiers = 7;
    prizePool = newPrizePool();
    awardDraw(1234);
    assertEq(prizePool.computeNextNumberOfTiers(0), 6);
  }

  function testClaimPrize_secondTier_claimTwice() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 1);
    uint256 prize = prizePool.getTierPrizeSize(1);
    assertEq(claimPrize(msg.sender, 1, 0), prize, "first claim");
    // second claim is same
    mockTwab(address(this), sender2, 1);
    assertEq(claimPrize(sender2, 1, 0), prize, "second claim");
  }

  function testClaimCanaryPrize() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    claimPrize(sender1, 2, 0);
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrizePartial() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    claimPrize(sender1, 2, 0);
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrize_ZeroAddressFeeRecipient() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    vm.expectRevert(abi.encodeWithSelector(RewardRecipientZeroAddress.selector));
    prizePool.claimPrize(sender1, 2, 0, sender1, 1, address(0));
  }

  function testClaimPrize_ZeroAddressFeeRecipient_ZeroFee() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), sender1, 2);
    prizePool.claimPrize(sender1, 2, 0, sender1, 0, address(0)); // zero fee, so no revert
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrize_claimFeesAccountedFor() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);

    address winner = makeAddr("winner");
    address recipient = makeAddr("recipient");
    mockTwab(address(this), winner, 1);

    uint96 fee = 0xfee;
    uint256 prize = prizePool.getTierPrizeSize(1);

    vm.expectEmit();
    emit ClaimedPrize(
      address(this),
      winner,
      recipient,
      1,
      1,
      0,
      uint152(prize-fee),
      fee,
      address(this)
    );
    prizePool.claimPrize(winner, 1, 0, recipient, fee, address(this));
    assertEq(prizeToken.balanceOf(recipient), prize - fee, "recipient balance is good");
    assertEq(prizePool.claimCount(), 1);

    // Check if claim fees are accounted for
    // (if they aren't anyone can call contributePrizeTokens with the unaccounted fee amount and basically take it as their own)
    uint256 accountedBalance = prizePool.accountedBalance();
    uint256 actualBalance = prizeToken.balanceOf(address(prizePool));

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
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    uint256 prize = prizePool.getTierPrizeSize(0);
    assertEq(claimPrize(msg.sender, 0, 0), prize, "prize size");
    assertEq(prizePool.totalWithdrawn(), prize, "total claimed prize");
  }

  function testLastAwardedDrawOpensAt() public {
    uint24 lastAwardedDrawId = prizePool.getLastAwardedDrawId();
    assertEq(lastAwardedDrawId, 0);
    vm.expectRevert(); // draw zero does not have an open time (you can never contribute to it)
    prizePool.drawOpensAt(lastAwardedDrawId);
    awardDraw(winningRandomNumber);

    assertEq(prizePool.drawOpensAt(prizePool.getLastAwardedDrawId()), firstDrawOpensAt);
    assertEq(
      prizePool.drawClosesAt(prizePool.getLastAwardedDrawId()),
      firstDrawOpensAt + drawPeriodSeconds
    );
    assertEq(prizePool.lastAwardedDrawAwardedAt(), block.timestamp);
  }

  function testLastAwardedDrawClosesAt() public {
    assertEq(prizePool.drawClosesAt(prizePool.getLastAwardedDrawId()), firstDrawOpensAt);
    awardDraw(winningRandomNumber);

    assertEq(prizePool.drawOpensAt(prizePool.getLastAwardedDrawId()), firstDrawOpensAt);
    assertEq(
      prizePool.drawClosesAt(prizePool.getLastAwardedDrawId()),
      firstDrawOpensAt + drawPeriodSeconds
    );
    assertEq(prizePool.lastAwardedDrawAwardedAt(), block.timestamp);
  }

  function testOpenDrawStartMatchesLastDrawAwarded() public {
    vm.warp(prizePool.drawClosesAt(prizePool.getOpenDrawId()) + 1 hours);
    prizePool.awardDraw(winningRandomNumber);
    assertEq(
      prizePool.drawOpensAt(prizePool.getOpenDrawId()),
      prizePool.drawClosesAt(prizePool.getLastAwardedDrawId())
    );
    vm.warp(prizePool.drawClosesAt(prizePool.getOpenDrawId()) + 1 hours);
    prizePool.awardDraw(winningRandomNumber);
    assertEq(
      prizePool.drawOpensAt(prizePool.getOpenDrawId()),
      prizePool.drawClosesAt(prizePool.getLastAwardedDrawId())
    );
    vm.warp(prizePool.drawClosesAt(prizePool.getOpenDrawId()) + 1 hours);
    prizePool.awardDraw(winningRandomNumber);
    assertEq(
      prizePool.drawOpensAt(prizePool.getOpenDrawId()),
      prizePool.drawClosesAt(prizePool.getLastAwardedDrawId())
    );
  }

  function testLastAwardedDrawAwardedAt() public {
    assertEq(prizePool.lastAwardedDrawAwardedAt(), 0);

    uint48 targetTimestamp = prizePool.drawClosesAt(prizePool.getOpenDrawId()) + 3 hours;

    vm.warp(targetTimestamp);
    prizePool.awardDraw(winningRandomNumber);

    assertEq(prizePool.drawOpensAt(prizePool.getLastAwardedDrawId()), firstDrawOpensAt);
    assertEq(
      prizePool.drawClosesAt(prizePool.getLastAwardedDrawId()),
      firstDrawOpensAt + drawPeriodSeconds
    );
    assertEq(prizePool.lastAwardedDrawAwardedAt(), targetTimestamp);
  }

  function testDrawOpensAtShouldNotOverflow() public {
    assertEq(
      prizePool.drawOpensAt(65700), // DrawID after 180 years for a daily draw
      prizePool.firstDrawOpensAt() + (65700 - 1) * drawPeriodSeconds
    );
  }

  function testDrawClosesAtShouldNotOverflow() public {
    assertEq(
      prizePool.drawClosesAt(65700), // DrawID after 180 years for a daily draw
      prizePool.firstDrawOpensAt() + 65700 * drawPeriodSeconds
    );
  }

  function testWithdrawRewards_sufficient() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
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
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);

    prizePool.claimPrize(msg.sender, 0, 0, msg.sender, 1e18, address(this));

    vm.expectEmit();
    emit WithdrawRewards(address(this), address(1), 5e17, 1e18);
    prizePool.withdrawRewards(address(1), 5e17);
  }

  function testWithdrawRewards_transferToPrizePool() public {
    contribute(100e18);
    awardDraw(winningRandomNumber);
    mockTwab(address(this), msg.sender, 0);
    claimPrize(msg.sender, 0, 0, 1e18, address(this));
    prizePool.withdrawRewards(address(prizePool), 1e18); // leave the tokens in the prize pool
    assertEq(prizeToken.balanceOf(address(this)), 0);
    assertEq(prizeToken.balanceOf(address(prizePool)) - prizePool.accountedBalance(), 1e18); // tokens are in prize pool
  }

  function testDrawToAward_zeroDraw() public {
    // current time *is* lastAwardedDrawAwardedAt
    assertEq(prizePool.getDrawIdToAward(), 1);
  }

  function testDrawToAward_zeroDrawPartwayThrough() public {
    // current time is halfway through first draw
    vm.warp(firstDrawOpensAt + drawPeriodSeconds / 2);
    assertEq(prizePool.getDrawIdToAward(), 1);
  }

  function testDrawToAward_zeroDrawWithLongDelay() public {
    // current time is halfway through *second* draw
    vm.warp(firstDrawOpensAt + drawPeriodSeconds + drawPeriodSeconds / 2); // warp halfway through second draw
    assertEq(prizePool.getDrawIdToAward(), 1);
  }

  function testDrawToAward_openDraw() public {
    assertEq(prizePool.getDrawIdToAward(), 1);
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getDrawIdToAward(), 2);
  }

  function testDrawToAwardSkipsMissedDraws() public {
    assertEq(prizePool.getDrawIdToAward(), 1);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds * 2);
    assertEq(
      prizePool.drawOpensAt(prizePool.getDrawIdToAward()),
      firstDrawOpensAt + drawPeriodSeconds
    );
    assertEq(
      prizePool.drawClosesAt(prizePool.getDrawIdToAward()),
      firstDrawOpensAt + drawPeriodSeconds * 2
    );
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getDrawIdToAward(), 3);
  }

  function testDrawToAwardSkipsMissedDraws_middleOfDraw() public {
    assertEq(prizePool.getDrawIdToAward(), 1);
    vm.warp(firstDrawOpensAt + (drawPeriodSeconds * 5) / 2);
    assertEq(
      prizePool.drawOpensAt(prizePool.getDrawIdToAward()),
      firstDrawOpensAt + drawPeriodSeconds
    );
    assertEq(
      prizePool.drawClosesAt(prizePool.getDrawIdToAward()),
      firstDrawOpensAt + drawPeriodSeconds * 2
    );
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getDrawIdToAward(), 3);
  }

  function testDrawToAwardSkipsMissedDraws_2Draws() public {
    assertEq(prizePool.getDrawIdToAward(), 1);
    vm.warp(firstDrawOpensAt + drawPeriodSeconds * 3);
    assertEq(
      prizePool.drawOpensAt(prizePool.getDrawIdToAward()),
      firstDrawOpensAt + drawPeriodSeconds * 2
    );
    assertEq(
      prizePool.drawClosesAt(prizePool.getDrawIdToAward()),
      firstDrawOpensAt + drawPeriodSeconds * 3
    );
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getDrawIdToAward(), 4);
  }

  function testDrawToAwardSkipsMissedDraws_notFirstDraw() public {
    awardDraw(winningRandomNumber);
    uint48 _lastDrawClosedAt = prizePool.drawClosesAt(prizePool.getLastAwardedDrawId());
    assertEq(prizePool.getDrawIdToAward(), 2);
    vm.warp(_lastDrawClosedAt + drawPeriodSeconds * 2);
    assertEq(
      prizePool.drawOpensAt(prizePool.getDrawIdToAward()),
      _lastDrawClosedAt + drawPeriodSeconds
    );
    assertEq(
      prizePool.drawClosesAt(prizePool.getDrawIdToAward()),
      _lastDrawClosedAt + drawPeriodSeconds * 2
    );
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getDrawIdToAward(), 4);
  }

  function testDrawToAwardSkipsMissedDraws_manyDrawsIn_manyMissed() public {
    awardDraw(winningRandomNumber);
    awardDraw(winningRandomNumber);
    awardDraw(winningRandomNumber);
    awardDraw(winningRandomNumber);
    uint48 _lastDrawClosedAt = prizePool.drawClosesAt(prizePool.getLastAwardedDrawId());
    assertEq(prizePool.getDrawIdToAward(), 5);
    vm.warp(_lastDrawClosedAt + drawPeriodSeconds * 5);
    assertEq(
      prizePool.drawOpensAt(prizePool.getDrawIdToAward()),
      _lastDrawClosedAt + drawPeriodSeconds * 4
    );
    assertEq(
      prizePool.drawClosesAt(prizePool.getDrawIdToAward()),
      _lastDrawClosedAt + drawPeriodSeconds * 5
    );
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getDrawIdToAward(), 10);
  }

  function testDrawToAwardSkipsMissedDraws_notFirstDraw_middleOfDraw() public {
    awardDraw(winningRandomNumber);
    uint48 _lastDrawClosedAt = prizePool.drawClosesAt(prizePool.getLastAwardedDrawId());
    assertEq(prizePool.getDrawIdToAward(), 2);
    vm.warp(_lastDrawClosedAt + (drawPeriodSeconds * 5) / 2); // warp 2.5 draws in the future
    assertEq(prizePool.getDrawIdToAward(), 3);
    assertEq(
      prizePool.drawOpensAt(prizePool.getDrawIdToAward()),
      _lastDrawClosedAt + drawPeriodSeconds
    );
    assertEq(
      prizePool.drawClosesAt(prizePool.getDrawIdToAward()),
      _lastDrawClosedAt + drawPeriodSeconds * 2
    );
    awardDraw(winningRandomNumber);
    assertEq(prizePool.getDrawIdToAward(), 4);
  }

  function testGetVaultUserBalanceAndTotalSupplyTwab() public {
    awardDraw(winningRandomNumber);
    uint24 lastAwardedDrawId = prizePool.getLastAwardedDrawId();
    mockGetAverageBalanceBetween(address(this), msg.sender, 1, lastAwardedDrawId, 366e30);
    mockTwabTotalSupplyDrawRange(address(this), 1, lastAwardedDrawId, 1e30);
    (uint256 twab, uint256 twabTotalSupply) = prizePool.getVaultUserBalanceAndTotalSupplyTwab(
      address(this),
      msg.sender,
      lastAwardedDrawId,
      lastAwardedDrawId
    );
    assertEq(twab, 366e30);
    assertEq(twabTotalSupply, 1e30);
  }

  function testComputeRangeStartDrawIdInclusive() public {
    vm.expectRevert(abi.encodeWithSelector(RangeSizeZero.selector));
    prizePool.computeRangeStartDrawIdInclusive(1, 0);
  }

  function testGetTotalAccumulatorNewestObservation() public {
    Observation memory initialObs = prizePool.getTotalAccumulatorNewestObservation();
    assertEq(initialObs.available, 0);
    assertEq(initialObs.disbursed, 0);

    contribute(100e18);
    Observation memory afterContributionObs = prizePool.getTotalAccumulatorNewestObservation();
    assertEq(afterContributionObs.available, 100e18);
    assertEq(afterContributionObs.disbursed, 0);

    awardDraw(winningRandomNumber);
    Observation memory afterAwardObs = prizePool.getTotalAccumulatorNewestObservation();
    assertEq(afterContributionObs.available, 100e18);
    assertEq(afterContributionObs.disbursed, 0);

    contribute(100e18);
    Observation memory after2ndContributionObs = prizePool.getTotalAccumulatorNewestObservation();
    assertEq(after2ndContributionObs.available, 100e18);
    assertEq(after2ndContributionObs.disbursed, 100e18); // new obs, so old available is moved to new disbursed
  }

  function testGetVaultAccumulatorNewestObservation() public {
    Observation memory initialObs = prizePool.getVaultAccumulatorNewestObservation(address(this));
    assertEq(initialObs.available, 0);
    assertEq(initialObs.disbursed, 0);

    contribute(100e18);
    Observation memory afterContributionObs = prizePool.getVaultAccumulatorNewestObservation(address(this));
    assertEq(afterContributionObs.available, 100e18);
    assertEq(afterContributionObs.disbursed, 0);

    awardDraw(winningRandomNumber);
    Observation memory afterAwardObs = prizePool.getVaultAccumulatorNewestObservation(address(this));
    assertEq(afterContributionObs.available, 100e18);
    assertEq(afterContributionObs.disbursed, 0);

    contribute(100e18);
    Observation memory after2ndContributionObs = prizePool.getVaultAccumulatorNewestObservation(address(this));
    assertEq(after2ndContributionObs.available, 100e18);
    assertEq(after2ndContributionObs.disbursed, 100e18); // new obs, so old available is moved to new disbursed
  }

  // function mockGetAverageBalanceBetween(
  //   address _vault,
  //   address _user,
  //   uint48 _startTime,
  //   uint48 _endTime,
  //   uint256 _result
  // ) internal {
  //   vm.mockCall(
  //     address(twabController),
  //     abi.encodeWithSelector(
  //       TwabController.getTwabBetween.selector,
  //       _vault,
  //       _user,
  //       _startTime,
  //       _endTime
  //     ),
  //     abi.encode(_result)
  //   );
  // }

  // function mockGetAverageTotalSupplyBetween(
  //   address _vault,
  //   uint32 _startTime,
  //   uint32 _endTime,
  //   uint256 _result
  // ) internal {
  //   vm.mockCall(
  //     address(twabController),
  //     abi.encodeWithSelector(
  //       TwabController.getTotalSupplyTwabBetween.selector,
  //       _vault,
  //       _startTime,
  //       _endTime
  //     ),
  //     abi.encode(_result)
  //   );
  // }

  function contribute(uint256 amountContributed) public {
    contribute(amountContributed, address(this));
  }

  function contribute(uint256 amountContributed, address to) public {
    prizeToken.mint(address(prizePool), amountContributed);
    prizePool.contributePrizeTokens(to, amountContributed);
  }

  function awardDraw(uint256 _winningRandomNumber) public {
    vm.warp(prizePool.drawClosesAt(prizePool.getDrawIdToAward()));
    prizePool.awardDraw(_winningRandomNumber);
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

  function mockTwab(address _vault, address _account, uint8 _tier) public {
    mockTwabForUser(_vault, _account, _tier, 366e30);
    mockTwabTotalSupply(_vault, _tier, 1e30);
  }

  function mockTwabForUser(address _vault, address _account, uint8 _tier, uint256 _balance) public {
    uint24 endDraw = prizePool.getLastAwardedDrawId();
    uint24 durationDraws = prizePool.getTierAccrualDurationInDraws(_tier);
    uint24 startDraw = prizePool.computeRangeStartDrawIdInclusive(endDraw, durationDraws);
    mockGetAverageBalanceBetween(_vault, _account, startDraw, endDraw, _balance);
  }

  function mockTwabTotalSupply(address _vault, uint8 _tier, uint256 _totalSupply) public {
    uint24 endDraw = prizePool.getLastAwardedDrawId();
    uint24 durationDraws = prizePool.getTierAccrualDurationInDraws(_tier);
    uint24 startDraw = prizePool.computeRangeStartDrawIdInclusive(endDraw, durationDraws);
    mockTwabTotalSupplyDrawRange(_vault, startDraw, endDraw, _totalSupply);
  }

  function mockGetAverageBalanceBetween(address _vault, address _account, uint24 startDrawIdInclusive, uint24 endDrawIdInclusive, uint256 amount) public {
    uint48 startTime = prizePool.drawOpensAt(startDrawIdInclusive);
    uint48 endTime = prizePool.drawClosesAt(endDrawIdInclusive);
    // mockGetAverageBalanceBetween(_vault, _account, uint32(startTime), uint32(endTime), amount);
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(
        TwabController.getTwabBetween.selector,
        _vault,
        _account,
        startTime,
        endTime
      ),
      abi.encode(amount)
    );
  }

  function mockTwabTotalSupplyDrawRange(address _vault, uint24 startDrawIdInclusive, uint24 endDrawIdInclusive, uint256 amount) public {
    uint48 startTime = prizePool.drawOpensAt(startDrawIdInclusive);
    uint48 endTime = prizePool.drawClosesAt(endDrawIdInclusive);
    // mockGetAverageTotalSupplyBetween(_vault, uint32(startTime), uint32(endTime), amount);
    vm.mockCall(
      address(twabController),
      abi.encodeWithSelector(
        TwabController.getTotalSupplyTwabBetween.selector,
        _vault,
        startTime,
        endTime
      ),
      abi.encode(amount)
    );
  }

  function grandPrizeRangeStart(uint24 endDrawIdInclusive) public view returns (uint24) {
    return prizePool.computeRangeStartDrawIdInclusive(endDrawIdInclusive, grandPrizePeriodDraws);
  }

  function shutdownRangeDrawIds() public view returns (uint24, uint24) {
    uint24 drawIdPriorToShutdown = prizePool.getShutdownDrawId() - 1;
    uint24 rangeStart = grandPrizeRangeStart(drawIdPriorToShutdown);
    return (rangeStart, drawIdPriorToShutdown);
  }

  function mockShutdownTwab(uint256 userTwab, uint256 totalSupplyTwab) public {
    mockShutdownTwab(userTwab, totalSupplyTwab, msg.sender);
  }

  function mockShutdownTwab(uint256 userTwab, uint256 totalSupplyTwab, address account) public {
    mockShutdownTwab(userTwab, totalSupplyTwab, account, address(this));
  }

  function mockShutdownTwab(uint256 userTwab, uint256 totalSupplyTwab, address account, address _vault) public {
    (uint24 startDrawId, uint24 shutdownDrawId) = shutdownRangeDrawIds();
    console2.log("mockShutdownTwab ", startDrawId, shutdownDrawId);
    console2.log("shutdown close time", prizePool.drawClosesAt(shutdownDrawId));
    console2.log("account: ", account);
    console2.log("vault: ", vault);
    mockGetAverageBalanceBetween(_vault, account, startDrawId, shutdownDrawId, userTwab);
    mockTwabTotalSupplyDrawRange(_vault, startDrawId, shutdownDrawId, totalSupplyTwab);
  }

  function newPrizePool() public returns (PrizePool) {
    PrizePool _prizePool = new PrizePool(params);
    vm.expectEmit();
    emit SetDrawManager(drawManager);
    _prizePool.setDrawManager(drawManager);
    return _prizePool;
  }

  function _claimAllPrizes(uint8 _tiersToClaim) internal {
    for (uint8 tier = 0; tier < _tiersToClaim; tier++) {
      uint prizes = 4**tier;
      for (uint32 prize = 0; prize < prizes; prize++) {
        mockTwab(address(this), address(this), tier);
        claimPrize(address(this), tier, prize);
      }
    }
  }
}
