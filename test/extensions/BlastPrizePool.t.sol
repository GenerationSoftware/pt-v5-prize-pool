// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { BlastPrizePool, ConstructorParams, WETH, PrizeTokenNotExpectedToken, NoClaimableBalance } from "../../src/extensions/BlastPrizePool.sol";
import { IERC20 } from "../../src/PrizePool.sol";

contract BlastPrizePoolTest is Test {
  BlastPrizePool prizePool;

  address bob = makeAddr("bob");
  address alice = makeAddr("alice");

  address wethWhale = address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1);

  TwabController twabController;
  IERC20 prizeToken;
  address drawManager;

  uint256 TIER_SHARES = 100;
  uint256 CANARY_SHARES = 5;
  uint256 RESERVE_SHARES = 10;

  uint24 grandPrizePeriodDraws = 365;
  uint48 drawPeriodSeconds = 1 days;
  uint24 drawTimeout;
  uint48 firstDrawOpensAt;
  uint8 initialNumberOfTiers = 4;
  uint256 winningRandomNumber = 123456;
  uint256 tierLiquidityUtilizationRate = 1e18;

  uint256 blockNumber = 5213491;
  uint256 blockTimestamp = 1719236797;

  ConstructorParams params;

  function setUp() public {
    drawTimeout = 30;

    vm.createSelectFork("blast", blockNumber);
    vm.warp(blockTimestamp);

    prizeToken = IERC20(address(WETH));
    twabController = new TwabController(uint32(drawPeriodSeconds), uint32(blockTimestamp - 1 days));

    firstDrawOpensAt = uint48(blockTimestamp + 1 days); // set draw start 1 day into future

    drawManager = address(this);

    params = ConstructorParams(
      prizeToken,
      twabController,
      drawManager,
      tierLiquidityUtilizationRate,
      drawPeriodSeconds,
      firstDrawOpensAt,
      grandPrizePeriodDraws,
      initialNumberOfTiers,
      uint8(TIER_SHARES),
      uint8(CANARY_SHARES),
      uint8(RESERVE_SHARES),
      drawTimeout
    );

    prizePool = new BlastPrizePool(params);
    prizePool.setDrawManager(address(this));
  }

  function testWrongPrizeToken() public {
    params.prizeToken = IERC20(address(1));
    vm.expectRevert(abi.encodeWithSelector(PrizeTokenNotExpectedToken.selector, address(1), address(WETH)));
    prizePool = new BlastPrizePool(params);
  }

  function testClaimableYield() public {
    assertEq(IERC20(address(WETH)).balanceOf(address(prizePool)), 0);

    // check balance
    assertEq(prizePool.claimableYieldBalance(), 0);

    // donate some tokens to the prize pool
    vm.startPrank(wethWhale);
    IERC20(address(WETH)).approve(address(prizePool), 1e18);
    prizePool.donatePrizeTokens(1e18);
    vm.stopPrank();
    assertEq(prizePool.getDonatedBetween(1, 1), 1e18);

    // deal some ETH to the WETH contract and call addValue
    deal(address(WETH), 1e18 + address(WETH).balance);
    vm.startPrank(address(0x4300000000000000000000000000000000000000)); // REPORTER
    (bool success,) = address(WETH).call(abi.encodeWithSignature("addValue(uint256)", 0));
    vm.stopPrank();
    require(success, "addValue failed");

    // check balance non-zero
    uint256 claimable = prizePool.claimableYieldBalance();
    assertGt(claimable, 0);

    // trigger donation
    vm.startPrank(alice);
    uint256 donated = prizePool.donateClaimableYield();
    vm.stopPrank();

    assertEq(donated, claimable);
    assertEq(prizePool.getDonatedBetween(1, 1), 1e18 + donated);
    assertEq(prizePool.claimableYieldBalance(), 0);

    // reverts on donation of zero balance
    vm.expectRevert(abi.encodeWithSelector(NoClaimableBalance.selector));
    prizePool.donateClaimableYield();
  }

}