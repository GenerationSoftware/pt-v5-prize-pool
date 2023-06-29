// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { sd, SD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD34x4, fromUD34x4 } from "src/libraries/UD34x4.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD1x18, sd1x18 } from "prb-math/SD1x18.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";

import { PrizePool, ConstructorParams, InsufficientRewardsError, AlreadyClaimedPrize, DidNotWin, FeeTooLarge, SmoothingGTEOne, ContributionGTDeltaBalance, InsufficientReserve, RandomNumberIsZero, DrawNotFinished, InvalidPrizeIndex, NoCompletedDraw, InvalidTier, DrawManagerAlreadySet, CallerNotDrawManager } from "../src/PrizePool.sol";
import { ERC20Mintable } from "./mocks/ERC20Mintable.sol";

contract PrizePoolTest is Test {
  PrizePool public prizePool;

  ERC20Mintable public prizeToken;

  address public vault;

  TwabController public twabController;

  address sender1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
  address sender2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
  address sender3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
  address sender4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
  address sender5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
  address sender6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

  uint64 lastCompletedDrawStartedAt;
  uint32 drawPeriodSeconds;
  uint256 winningRandomNumber = 123456;
  uint256 startTimestamp = 1000 days;

  /**********************************************************************************
   * Events copied from PrizePool.sol
   **********************************************************************************/
  /// @notice Emitted when a draw is completed.
  /// @param drawId The ID of the draw that was claimed
  /// @param winningRandomNumber The winning random number for the completed draw
  /// @param numTiers The number of prize tiers in the completed draw
  /// @param nextNumTiers The number of tiers for the next draw
  event DrawCompleted(
    uint16 indexed drawId,
    uint256 winningRandomNumber,
    uint8 numTiers,
    uint8 nextNumTiers
  );

  /// @notice Emitted when any amount of the reserve is withdrawn.
  /// @param to The address the assets are transferred to
  /// @param amount The amount of assets transferred
  event WithdrawReserve(address indexed to, uint256 amount);

  /// @notice Emitted when a vault contributes prize tokens to the pool.
  /// @param vault The address of the vault that is contributing tokens
  /// @param drawId The ID of the first draw that the tokens will be applied to
  /// @param amount The amount of tokens contributed
  event ContributePrizeTokens(address indexed vault, uint16 indexed drawId, uint256 amount);

  /// @notice Emitted when an address withdraws their claim rewards
  /// @param to The address the rewards are sent to
  /// @param amount The amount withdrawn
  /// @param available The total amount that was available to withdraw before the transfer
  event WithdrawClaimRewards(address indexed to, uint256 amount, uint256 available);

  /// @notice Emitted when the drawManager is set
  /// @param drawManager The draw manager
  event DrawManagerSet(address indexed drawManager);

  /**********************************************************************************/

  ConstructorParams params;

  function setUp() public {
    vm.warp(startTimestamp);

    prizeToken = new ERC20Mintable("PoolTogether POOL token", "POOL");
    twabController = new TwabController();

    lastCompletedDrawStartedAt = uint64(block.timestamp + 1 days); // set draw start 1 day into future
    drawPeriodSeconds = 1 days;

    address drawManager = address(this);

    params = ConstructorParams(
      prizeToken,
      twabController,
      drawManager,
      uint16(365),
      drawPeriodSeconds,
      lastCompletedDrawStartedAt,
      uint8(3), // minimum number of tiers
      100,
      10,
      10,
      ud2x18(0.9e18), // claim threshold of 90%
      sd1x18(0.9e18) // alpha
    );

    vm.expectEmit();
    emit DrawManagerSet(drawManager);
    prizePool = new PrizePool(params);

    vault = address(this);
  }

  function testConstructor_SmoothingGTEOne() public {
    params.smoothing = sd1x18(1.0e18); // smoothing
    vm.expectRevert(abi.encodeWithSelector(SmoothingGTEOne.selector, 1000000000000000000));
    new PrizePool(params);
  }

  function testTierOdds_Accuracy() public {
    SD59x18 odds = prizePool.getTierOdds(0, 3);
    assertEq(SD59x18.unwrap(odds), 2739726027397260);
    odds = prizePool.getTierOdds(3, 7);
    assertEq(SD59x18.unwrap(odds), 52342392259021369);
    odds = prizePool.getTierOdds(15, 16);
    assertEq(SD59x18.unwrap(odds), 1000000000000000000);
  }

  function testReserve_noRemainder() public {
    contribute(220e18);
    completeAndStartNextDraw(winningRandomNumber);

    // reserve + remainder
    assertEq(prizePool.reserve(), 1e18);
  }

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

  /**********************************************************************************/
  function testReserve_withRemainder() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    // reserve + remainder
    assertEq(prizePool.reserve(), 0.45454545454545466e18);
  }

  function testReserveForNextDraw_noDraw() public {
    contribute(100e18);
    assertEq(prizePool.reserveForNextDraw(), 0.45454545454545466e18);
  }

  function testReserveForNextDraw_existingDraw() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    contribute(100e18);

    /*
            prev canary: 0.454545454545454546e18
            prev reserve: 0.454545454545454546e18
            current reserve: 10/220e18 * 9e18 = 0.409090909090909091e18

            0.454545454545454546e18 + 0.454545454545454546e18 + 0.409090909090909091e18 = 1.318181818181818182e18
        */

    assertEq(prizePool.reserveForNextDraw(), 1.318181818181818310e18);
  }

  function testWithdrawReserve_notManager() public {
    vm.prank(address(0));
    vm.expectRevert(
      abi.encodeWithSelector(CallerNotDrawManager.selector, address(0), address(this))
    );
    prizePool.withdrawReserve(address(0), 1);
  }

  function testWithdrawReserve_insuff() public {
    vm.expectRevert(abi.encodeWithSelector(InsufficientReserve.selector, 1, 0));
    prizePool.withdrawReserve(address(this), 1);
  }

  function testWithdrawReserve() public {
    contribute(220e18);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizeToken.balanceOf(address(this)), 0);
    vm.expectEmit();
    emit WithdrawReserve(address(this), 1e18);
    prizePool.withdrawReserve(address(this), 1e18);
    assertEq(prizeToken.balanceOf(address(this)), 1e18);
  }

  function testCanaryPrizeCount_noParam() public {
    assertEq(prizePool.canaryPrizeCount(), 2);
  }

  function testCanaryPrizeCount_param() public {
    assertEq(prizePool.canaryPrizeCount(4), 8);
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

  function testGetTierPrizeCount() public {
    assertEq(prizePool.getTierPrizeCount(3), 4 ** 3);
  }

  function testContributePrizeTokens() public {
    contribute(100);
    assertEq(prizeToken.balanceOf(address(prizePool)), 100);
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
    completeAndStartNextDraw(1);
    assertEq(prizePool.reserve(), 0.45454545454545466e18);
    prizePool.withdrawReserve(address(this), uint104(prizePool.reserve()));
    assertEq(prizePool.accountedBalance(), prizeToken.balanceOf(address(prizePool)));
    assertEq(prizePool.reserve(), 0);
  }

  function testAccountedBalance_noClaims() public {
    contribute(100);
    assertEq(prizePool.accountedBalance(), 100);
  }

  function testAccountedBalance_oneClaim() public {
    contribute(100e18);
    completeAndStartNextDraw(1);
    mockTwab(msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
    assertEq(prizePool.accountedBalance(), 95.4545454545454546e18);
  }

  function testAccountedBalance_oneClaim_andMoreContrib() public {
    contribute(100e18);
    completeAndStartNextDraw(1);
    mockTwab(msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
    contribute(10e18);
    assertEq(prizePool.accountedBalance(), 105.4545454545454546e18);
  }

  function testAccountedBalance_twoClaims() public {
    contribute(100e18);
    completeAndStartNextDraw(1);
    mockTwab(msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
    // 10e18 - 4.5454545454545454e18 = 5.4545454545454546e18
    completeAndStartNextDraw(1);

    // 9e18*100/220 = 4.0909090909090909e18
    assertEq(prizePool.accountedBalance(), 95.4545454545454546e18, "accounted balance");

    mockTwab(msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
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
    completeAndStartNextDraw(winningRandomNumber); // draw 1
    completeAndStartNextDraw(winningRandomNumber); // draw 2
    assertEq(prizePool.getLastCompletedDrawId(), 2);
    contribute(100e18); // available on draw 3

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 2, 2)), 0);
  }

  function testGetVaultPortion_BeforeAndAtContribution() public {
    contribute(100e18); // available draw 1

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 1)), 1e18);
  }

  function testGetVaultPortion_BeforeAndAfterContribution() public {
    completeAndStartNextDraw(winningRandomNumber); // draw 1
    contribute(100e18); // available draw 2

    assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 2)), 1e18);
  }

  function testGetNextDrawId() public {
    uint256 nextDrawId = prizePool.getNextDrawId();
    assertEq(nextDrawId, 1);
  }

  function testCompleteAndStartNextDraw_notManager() public {
    vm.prank(address(0));
    vm.expectRevert(
      abi.encodeWithSelector(CallerNotDrawManager.selector, address(0), address(this))
    );
    prizePool.completeAndStartNextDraw(winningRandomNumber);
  }

  function testCompleteAndStartNextDraw_notElapsed_atStart() public {
    vm.warp(lastCompletedDrawStartedAt);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        lastCompletedDrawStartedAt + drawPeriodSeconds
      )
    );
    prizePool.completeAndStartNextDraw(winningRandomNumber);
  }

  function testCompleteAndStartNextDraw_notElapsed_subsequent() public {
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds);
    prizePool.completeAndStartNextDraw(winningRandomNumber);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        lastCompletedDrawStartedAt + drawPeriodSeconds * 2
      )
    );
    prizePool.completeAndStartNextDraw(winningRandomNumber);
  }

  function testCompleteAndStartNextDraw_notElapsed_nextDrawPartway() public {
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds);
    prizePool.completeAndStartNextDraw(winningRandomNumber);
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds + drawPeriodSeconds / 2);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        lastCompletedDrawStartedAt + drawPeriodSeconds * 2
      )
    );
    prizePool.completeAndStartNextDraw(winningRandomNumber);
  }

  function testCompleteAndStartNextDraw_notElapsed_partway() public {
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds / 2);
    vm.expectRevert(
      abi.encodeWithSelector(
        DrawNotFinished.selector,
        lastCompletedDrawStartedAt + drawPeriodSeconds
      )
    );
    prizePool.completeAndStartNextDraw(winningRandomNumber);
  }

  function testCompleteAndStartNextDraw_invalidNumber() public {
    vm.expectRevert(abi.encodeWithSelector(RandomNumberIsZero.selector));
    prizePool.completeAndStartNextDraw(0);
  }

  function testCompleteAndStartNextDraw_noLiquidity() public {
    completeAndStartNextDraw(winningRandomNumber);

    assertEq(prizePool.getWinningRandomNumber(), winningRandomNumber);
    assertEq(prizePool.getLastCompletedDrawId(), 1);
    assertEq(prizePool.getNextDrawId(), 2);
    assertEq(prizePool.lastCompletedDrawStartedAt(), lastCompletedDrawStartedAt);
    assertEq(prizePool.lastCompletedDrawEndedAt(), lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.lastCompletedDrawAwardedAt(), block.timestamp);
  }

  function testCompleteAndStartNextDraw_withLiquidity() public {
    contribute(100e18);
    // = 1e18 / 220e18 = 0.004545454...
    // but because of alpha only 10% is released on this draw
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(
      fromUD34x4(prizePool.prizeTokenPerShare()),
      0.045454545454545454e18,
      "prize token per share"
    );
    assertEq(prizePool.reserve(), 0.45454545454545466e18, "reserve"); // remainder of the complex fraction
    assertEq(prizePool.getTotalContributionsForCompletedDraw(), 10e18); // ensure not a single wei is lost!
  }

  function testTotalContributionsForCompletedDraw_noClaims() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getTotalContributionsForCompletedDraw(), 10e18, "first draw"); // 10e18
    completeAndStartNextDraw(winningRandomNumber);
    // liquidity should carry over!
    assertEq(
      prizePool.getTotalContributionsForCompletedDraw(),
      8.999999999999998700e18,
      "second draw"
    ); // 10e18 + 9e18
  }

  function testCompleteAndStartNextDraw_shrinkTiers() public {
    uint8 startingTiers = 5;

    // reset prize pool at higher tiers
    ConstructorParams memory prizePoolParams = ConstructorParams(
      prizeToken,
      twabController,
      address(this),
      uint16(365),
      drawPeriodSeconds,
      lastCompletedDrawStartedAt,
      startingTiers, // higher number of tiers
      100,
      10,
      10,
      ud2x18(0.9e18), // claim threshold of 90%
      sd1x18(0.9e18) // alpha
    );
    prizePool = new PrizePool(prizePoolParams);

    contribute(420e18);
    completeAndStartNextDraw(1234);

    // tier 0 liquidity: 10e18
    // tier 1 liquidity: 10e18
    // tier 2 liquidity: 10e18
    // tier 3 liquidity: 10e18
    // canary liquidity: 1e18
    // reserve liquidity: 1e18

    // tiers should not change upon first draw
    assertEq(prizePool.numberOfTiers(), startingTiers, "starting tiers");
    assertEq(prizePool.reserve(), 1e18, "reserve after first draw");

    // now claim only grand prize
    mockTwab(address(this), 0);
    claimPrize(address(this), 0, 0);

    vm.expectEmit();
    // shrink to minimum
    emit DrawCompleted(2, 4567, startingTiers, 3);

    completeAndStartNextDraw(4567);
    // reclaimed tier 2, 3, and canary.  22e18 in total.
    // draw 2 has 37.8.  Reserve is 10/220.0 * 37.8e18 = 1.718181818181818e18
    // 22e18 + 1.718181818181818e18 = 23.718181818181818e18
    // shrink by 2
    assertEq(prizePool.numberOfTiers(), 3, "number of tiers");
    assertEq(prizePool.reserve(), 23.71818181818181801e18, "size of reserve");
  }

  function testCompleteAndStartNextDraw_expandingTiers() public {
    contribute(1e18);
    completeAndStartNextDraw(1234);
    mockTwab(address(this), 0);
    claimPrize(address(this), 0, 0);
    mockTwab(sender1, 1);
    claimPrize(sender1, 1, 0);
    mockTwab(sender2, 1);
    claimPrize(sender2, 1, 0);
    mockTwab(sender3, 1);
    claimPrize(sender3, 1, 0);
    mockTwab(sender4, 1);
    claimPrize(sender4, 1, 0);

    // canary tiers
    mockTwab(sender5, 2);
    claimPrize(sender5, 2, 0);
    mockTwab(sender6, 2);
    claimPrize(sender6, 2, 0);

    vm.expectEmit();
    emit DrawCompleted(2, 245, 3, 4);

    completeAndStartNextDraw(245);
    assertEq(prizePool.numberOfTiers(), 4);
  }

  function testCompleteAndStartNextDraw_multipleDraws() public {
    contribute(1e18);
    completeAndStartNextDraw(1234);
    completeAndStartNextDraw(1234);
    completeAndStartNextDraw(554);

    mockTwab(sender5, 1);
    assertTrue(claimPrize(sender5, 1, 0) > 0, "has prize");
  }

  function testCompleteAndStartNextDraw_emitsEvent() public {
    vm.expectEmit();
    emit DrawCompleted(1, 12345, 3, 3);
    completeAndStartNextDraw(12345);
  }

  function testGetTotalShares() public {
    assertEq(prizePool.getTotalShares(), 220);
  }

  function testGetRemainingTierLiquidity_invalidTier() public {
    assertEq(prizePool.getTierRemainingLiquidity(10), 0);
  }

  function testGetRemainingTierLiquidity_grandPrize() public {
    contribute(1e18);
    completeAndStartNextDraw(winningRandomNumber);
    // 2 tiers at 100 shares each, and 10 for canary and 10 for reserve
    // = 100 / 220 = 10 / 22 = 0.45454545454545453
    // then take only 10% due to alpha = 0.9
    assertEq(prizePool.getTierRemainingLiquidity(0), 0.0454545454545454e18);
  }

  function testGetRemainingTierLiquidity_afterClaim() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    uint256 liquidity = 4.5454545454545454e18;
    assertEq(prizePool.getTierRemainingLiquidity(1), liquidity, "second tier");

    mockTwab(sender1, 1);
    uint256 prize = 1.13636363636363635e18;
    assertEq(claimPrize(sender1, 1, 0), prize, "second tier prize 1");

    // reduce by prize
    assertEq(
      prizePool.getTierRemainingLiquidity(1),
      liquidity - prize,
      "second tier liquidity post claim 1"
    );
  }

  function testGetRemainingTierLiquidity_canary() public {
    contribute(220e18);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getTierRemainingLiquidity(0), 10e18);
    assertEq(prizePool.getTierRemainingLiquidity(1), 10e18);
    // canary tier
    assertEq(prizePool.getTierRemainingLiquidity(2), 1e18);
  }

  function testSetDrawManager() public {
    params.drawManager = address(0);
    prizePool = new PrizePool(params);
    vm.expectEmit();
    emit DrawManagerSet(address(this));
    prizePool.setDrawManager(address(this));
    assertEq(prizePool.drawManager(), address(this));
  }

  function testSetDrawManager_alreadySet() public {
    vm.expectRevert(abi.encodeWithSelector(DrawManagerAlreadySet.selector));
    prizePool.setDrawManager(address(this));
  }

  function testIsWinner_noDraw() public {
    vm.expectRevert(abi.encodeWithSelector(NoCompletedDraw.selector));
    prizePool.isWinner(address(this), msg.sender, 10, 0);
  }

  function testIsWinner_invalidTier() public {
    completeAndStartNextDraw(winningRandomNumber);
    vm.expectRevert(abi.encodeWithSelector(InvalidTier.selector, 10, 3));
    prizePool.isWinner(address(this), msg.sender, 10, 0);
  }

  function testIsWinnerDailyPrize() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 1);
    assertEq(prizePool.isWinner(address(this), msg.sender, 1, 0), true);
  }

  function testIsWinnerGrandPrize() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    assertEq(prizePool.isWinner(address(this), msg.sender, 0, 0), true);
  }

  function testIsWinner_emitsInvalidPrizeIndex() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 1);
    vm.expectRevert(abi.encodeWithSelector(InvalidPrizeIndex.selector, 4, 4, 1));
    prizePool.isWinner(address(this), msg.sender, 1, 4);
  }

  function testWasClaimed_not() public {
    assertEq(prizePool.wasClaimed(msg.sender, 0, 0), false);
  }

  function testWasClaimed_single() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
    assertEq(prizePool.wasClaimed(msg.sender, 0, 0), true);
  }

  function testWasClaimed_old_draw() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    claimPrize(msg.sender, 0, 0);
    assertEq(prizePool.wasClaimed(msg.sender, 0, 0), true);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.wasClaimed(msg.sender, 0, 0), false);
  }

  function testClaimPrize_single() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    address winner = makeAddr("winner");
    address recipient = makeAddr("recipient");
    mockTwab(winner, 1);

    vm.expectEmit();
    emit ClaimedPrize(
      address(this),
      winner,
      recipient,
      1,
      1,
      0,
      1.13636363636363635e18,
      0,
      address(0)
    );
    prizePool.claimPrize(winner, 1, 0, recipient, 0, address(0));
    // grand prize is (100/220) * 0.1 * 100e18 = 4.5454...e18
    assertEq(prizeToken.balanceOf(recipient), 1.13636363636363635e18, "recipient balance is good");
    assertEq(prizePool.claimCount(), 1);
  }

  function testClaimPrize_withFee() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    // total prize size is returned
    claimPrize(msg.sender, 0, 0, 1e18, address(this));
    // grand prize is (100/220) * 0.1 * 100e18 = 4.5454...e18
    assertEq(prizeToken.balanceOf(msg.sender), 3.5454545454545454e18, "user balance after claim");
    assertEq(prizePool.claimCount(), 1);
    assertEq(prizePool.balanceOfClaimRewards(address(this)), 1e18);
  }

  function testClaimPrize_notWinner() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    vm.expectRevert(abi.encodeWithSelector(DidNotWin.selector, address(this), msg.sender, 0, 0));
    claimPrize(msg.sender, 0, 0);
  }

  function testClaimPrize_feeTooLarge() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    vm.expectRevert(abi.encodeWithSelector(FeeTooLarge.selector, 10e18, 4.5454545454545454e18));
    claimPrize(msg.sender, 0, 0, 10e18, address(0));
  }

  function testClaimPrize_grandPrize_claimTwice() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    assertEq(claimPrize(msg.sender, 0, 0), 4.5454545454545454e18, "prize size");
    // second claim is zero
    vm.expectRevert(
      abi.encodeWithSelector(
        AlreadyClaimedPrize.selector,
        address(this),
        msg.sender,
        0,
        0,
        msg.sender
      )
    );
    claimPrize(msg.sender, 0, 0);
  }

  function testClaimPrize_secondTier_claimTwice() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 1);
    assertEq(claimPrize(msg.sender, 1, 0), 1.13636363636363635e18, "first claim");
    // second claim is same
    mockTwab(sender2, 1);
    assertEq(claimPrize(sender2, 1, 0), 1.13636363636363635e18, "second claim");
  }

  function testClaimCanaryPrize() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(sender1, 2);
    claimPrize(sender1, 2, 0);
    assertEq(prizePool.claimCount(), 0);
    assertEq(prizePool.canaryClaimCount(), 1);
  }

  function testClaimPrizePartial() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(sender1, 2);
    claimPrize(sender1, 2, 0);
    assertEq(prizePool.claimCount(), 0);
    assertEq(prizePool.canaryClaimCount(), 1);
  }

  function testTotalClaimedPrizes() public {
    assertEq(prizePool.totalWithdrawn(), 0);
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    uint256 prize = 4.5454545454545454e18;
    assertEq(claimPrize(msg.sender, 0, 0), prize, "prize size");
    assertEq(prizePool.totalWithdrawn(), prize, "total claimed prize");
  }

  function testLastCompletedDrawStartedAt() public {
    assertEq(prizePool.lastCompletedDrawStartedAt(), 0);
    completeAndStartNextDraw(winningRandomNumber);

    assertEq(prizePool.lastCompletedDrawStartedAt(), lastCompletedDrawStartedAt);
    assertEq(prizePool.lastCompletedDrawEndedAt(), lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.lastCompletedDrawAwardedAt(), block.timestamp);
  }

  function testLastCompletedDrawEndedAt() public {
    assertEq(prizePool.lastCompletedDrawEndedAt(), 0);
    completeAndStartNextDraw(winningRandomNumber);

    assertEq(prizePool.lastCompletedDrawStartedAt(), lastCompletedDrawStartedAt);
    assertEq(prizePool.lastCompletedDrawEndedAt(), lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.lastCompletedDrawAwardedAt(), block.timestamp);
  }

  function testLastCompletedDrawAwardedAt() public {
    assertEq(prizePool.lastCompletedDrawAwardedAt(), 0);

    uint64 targetTimestamp = prizePool.nextDrawEndsAt() + 3 hours;

    vm.warp(targetTimestamp);
    prizePool.completeAndStartNextDraw(winningRandomNumber);

    assertEq(prizePool.lastCompletedDrawStartedAt(), lastCompletedDrawStartedAt);
    assertEq(prizePool.lastCompletedDrawEndedAt(), lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.lastCompletedDrawAwardedAt(), targetTimestamp);
  }

  function testHasNextDrawFinished() public {
    assertEq(prizePool.hasNextDrawFinished(), false);
    vm.warp(prizePool.nextDrawEndsAt() - 1);
    assertEq(prizePool.hasNextDrawFinished(), false);
    vm.warp(prizePool.nextDrawEndsAt());
    assertEq(prizePool.hasNextDrawFinished(), true);
  }

  function testWithdrawClaimRewards_sufficient() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);
    claimPrize(msg.sender, 0, 0, 1e18, address(this));
    prizePool.withdrawClaimRewards(address(this), 1e18);
    assertEq(prizeToken.balanceOf(address(this)), 1e18);
  }

  function testWithdrawClaimRewards_insufficient() public {
    vm.expectRevert(abi.encodeWithSelector(InsufficientRewardsError.selector, 1e18, 0));
    prizePool.withdrawClaimRewards(address(this), 1e18);
  }

  function testWithdrawClaimRewards_emitsEvent() public {
    contribute(100e18);
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(msg.sender, 0);

    prizePool.claimPrize(msg.sender, 0, 0, msg.sender, 1e18, address(this));

    vm.expectEmit();
    emit WithdrawClaimRewards(address(this), 5e17, 1e18);
    prizePool.withdrawClaimRewards(address(this), 5e17);
  }

  function testNextDrawStartsAt_zeroDraw() public {
    // current time *is* lastCompletedDrawStartedAt
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt);
  }

  function testNextDrawStartsAt_zeroDrawPartwayThrough() public {
    // current time is halfway through first draw
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds / 2);
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt);
  }

  function testNextDrawStartsAt_zeroDrawWithLongDelay() public {
    // current time is halfway through *second* draw
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds + drawPeriodSeconds / 2); // warp halfway through second draw
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt);
  }

  function testNextDrawStartsAt_nextDraw() public {
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt + drawPeriodSeconds);
  }

  function testNextDrawIncludesMissedDraws() public {
    assertEq(prizePool.getNextDrawId(), 1);
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds * 2);
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.nextDrawEndsAt(), lastCompletedDrawStartedAt + drawPeriodSeconds * 2);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getNextDrawId(), 2);
  }

  function testNextDrawIncludesMissedDraws_middleOfDraw() public {
    assertEq(prizePool.getNextDrawId(), 1);
    vm.warp(lastCompletedDrawStartedAt + (drawPeriodSeconds * 5) / 2);
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.nextDrawEndsAt(), lastCompletedDrawStartedAt + drawPeriodSeconds * 2);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getNextDrawId(), 2);
  }

  function testNextDrawIncludesMissedDraws_2Draws() public {
    assertEq(prizePool.getNextDrawId(), 1);
    vm.warp(lastCompletedDrawStartedAt + drawPeriodSeconds * 3);
    assertEq(prizePool.nextDrawStartsAt(), lastCompletedDrawStartedAt + drawPeriodSeconds * 2);
    assertEq(prizePool.nextDrawEndsAt(), lastCompletedDrawStartedAt + drawPeriodSeconds * 3);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getNextDrawId(), 2);
  }

  function testNextDrawIncludesMissedDraws_notFirstDraw() public {
    completeAndStartNextDraw(winningRandomNumber);
    uint64 _lastCompletedDrawStartedAt = prizePool.lastCompletedDrawStartedAt();
    assertEq(prizePool.getNextDrawId(), 2);
    vm.warp(_lastCompletedDrawStartedAt + drawPeriodSeconds * 2);
    assertEq(prizePool.nextDrawStartsAt(), _lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.nextDrawEndsAt(), _lastCompletedDrawStartedAt + drawPeriodSeconds * 2);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getNextDrawId(), 3);
  }

  function testNextDrawIncludesMissedDraws_manyDrawsIn_manyMissed() public {
    completeAndStartNextDraw(winningRandomNumber);
    completeAndStartNextDraw(winningRandomNumber);
    completeAndStartNextDraw(winningRandomNumber);
    completeAndStartNextDraw(winningRandomNumber);
    uint64 _lastCompletedDrawStartedAt = prizePool.lastCompletedDrawStartedAt();
    assertEq(prizePool.getNextDrawId(), 5);
    vm.warp(_lastCompletedDrawStartedAt + drawPeriodSeconds * 5);
    assertEq(prizePool.nextDrawStartsAt(), _lastCompletedDrawStartedAt + drawPeriodSeconds * 4);
    assertEq(prizePool.nextDrawEndsAt(), _lastCompletedDrawStartedAt + drawPeriodSeconds * 5);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getNextDrawId(), 6);
  }

  function testNextDrawIncludesMissedDraws_notFirstDraw_middleOfDraw() public {
    completeAndStartNextDraw(winningRandomNumber);
    uint64 _lastCompletedDrawStartedAt = prizePool.lastCompletedDrawStartedAt();
    assertEq(prizePool.getNextDrawId(), 2);
    vm.warp(_lastCompletedDrawStartedAt + (drawPeriodSeconds * 5) / 2);
    assertEq(prizePool.nextDrawStartsAt(), _lastCompletedDrawStartedAt + drawPeriodSeconds);
    assertEq(prizePool.nextDrawEndsAt(), _lastCompletedDrawStartedAt + drawPeriodSeconds * 2);
    completeAndStartNextDraw(winningRandomNumber);
    assertEq(prizePool.getNextDrawId(), 3);
  }

  function testGetVaultUserBalanceAndTotalSupplyTwab() public {
    completeAndStartNextDraw(winningRandomNumber);
    mockTwab(
      msg.sender,
      prizePool.lastCompletedDrawEndedAt() - 365 * drawPeriodSeconds,
      prizePool.lastCompletedDrawEndedAt()
    );
    (uint256 twab, uint256 twabTotalSupply) = prizePool.getVaultUserBalanceAndTotalSupplyTwab(
      address(this),
      msg.sender,
      365
    );
    assertEq(twab, 366e30);
    assertEq(twabTotalSupply, 1e30);
  }

  function mockGetAverageBalanceBetween(
    address _vault,
    address _user,
    uint64 _startTime,
    uint64 _endTime,
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

  function testEstimatedPrizeCount_current() public {
    assertEq(prizePool.estimatedPrizeCount(), 4);
  }

  function testEstimatedPrizeCount() public {
    // assumes grand prize is 365
    assertEq(prizePool.estimatedPrizeCount(0), 0);
    assertEq(prizePool.estimatedPrizeCount(1), 0);
    assertEq(prizePool.estimatedPrizeCount(2), 0);
    assertEq(prizePool.estimatedPrizeCount(3), 4);
    assertEq(prizePool.estimatedPrizeCount(4), 16);
    assertEq(prizePool.estimatedPrizeCount(5), 66);
    assertEq(prizePool.estimatedPrizeCount(6), 270);
    assertEq(prizePool.estimatedPrizeCount(7), 1108);
    assertEq(prizePool.estimatedPrizeCount(8), 4517);
    assertEq(prizePool.estimatedPrizeCount(9), 18358);
    assertEq(prizePool.estimatedPrizeCount(10), 74435);
    assertEq(prizePool.estimatedPrizeCount(11), 301239);
    assertEq(prizePool.estimatedPrizeCount(12), 1217266);
    assertEq(prizePool.estimatedPrizeCount(13), 4912619);
    assertEq(prizePool.estimatedPrizeCount(14), 19805536);
    assertEq(prizePool.estimatedPrizeCount(15), 79777187);
    assertEq(prizePool.estimatedPrizeCount(16), 0);
  }

  function testcanaryPrizeCountFractional() public {
    // assuming 10 reserve, 10 canary, and 100 per tier
    assertEq(prizePool.canaryPrizeCountFractional(0).unwrap(), 0);
    assertEq(prizePool.canaryPrizeCountFractional(1).unwrap(), 0);
    assertEq(prizePool.canaryPrizeCountFractional(2).unwrap(), 0);
    assertEq(prizePool.canaryPrizeCountFractional(3).unwrap(), 2327272727272727264);
    assertEq(prizePool.canaryPrizeCountFractional(4).unwrap(), 8400000000000000000);
    assertEq(prizePool.canaryPrizeCountFractional(5).unwrap(), 31695238095238095104);
    assertEq(prizePool.canaryPrizeCountFractional(6).unwrap(), 122092307692307691520);
    assertEq(prizePool.canaryPrizeCountFractional(7).unwrap(), 475664516129032257536);
    assertEq(prizePool.canaryPrizeCountFractional(8).unwrap(), 1865955555555555540992);
    assertEq(prizePool.canaryPrizeCountFractional(9).unwrap(), 7352819512195121938432);
    assertEq(prizePool.canaryPrizeCountFractional(10).unwrap(), 29063791304347825995776);
    assertEq(prizePool.canaryPrizeCountFractional(11).unwrap(), 115137756862745097011200);
    assertEq(prizePool.canaryPrizeCountFractional(12).unwrap(), 456879542857142854746112);
    assertEq(prizePool.canaryPrizeCountFractional(13).unwrap(), 1815239763934426215481344);
    assertEq(prizePool.canaryPrizeCountFractional(14).unwrap(), 7219286884848484797644800);
    assertEq(prizePool.canaryPrizeCountFractional(15).unwrap(), 28733936135211267454402560);
    assertEq(prizePool.canaryPrizeCountFractional(16).unwrap(), 0);
  }

  function contribute(uint256 amountContributed) public {
    contribute(amountContributed, address(this));
  }

  function contribute(uint256 amountContributed, address to) public {
    prizeToken.mint(address(prizePool), amountContributed);
    prizePool.contributePrizeTokens(to, amountContributed);
  }

  function completeAndStartNextDraw(uint256 _winningRandomNumber) public {
    vm.warp(prizePool.nextDrawEndsAt());
    prizePool.completeAndStartNextDraw(_winningRandomNumber);
  }

  function claimPrize(address sender, uint8 tier, uint32 prizeIndex) public returns (uint256) {
    return claimPrize(sender, tier, prizeIndex, 0, address(0));
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

  function mockTwab(address _account, uint256 startTime, uint256 endTime) public {
    mockGetAverageBalanceBetween(
      address(this),
      _account,
      uint32(startTime),
      uint32(endTime),
      366e30
    );
    mockGetAverageTotalSupplyBetween(address(this), uint32(startTime), uint32(endTime), 1e30);
  }

  function mockTwab(address _account, uint8 _tier) public {
    (uint64 startTime, uint64 endTime) = prizePool.calculateTierTwabTimestamps(_tier);
    mockTwab(_account, startTime, endTime);
  }
}
