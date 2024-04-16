// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { CurrentTime, CurrentTimeConsumer } from "./CurrentTimeConsumer.sol";
import { PrizePool, ConstructorParams } from "../../../src/PrizePool.sol";
import { MINIMUM_NUMBER_OF_TIERS } from "../../../src/abstract/TieredLiquidityDistributor.sol";
import { ERC20Mintable } from "../../mocks/ERC20Mintable.sol";

contract PrizePoolFuzzHarness is CommonBase, StdCheats, StdUtils, CurrentTimeConsumer {
  PrizePool public prizePool;
  ERC20Mintable public token;
  TwabController twabController;

  uint256 public contributed;
  uint256 public withdrawn;
  uint256 public claimed;

  address claimer;

  address[4] public actors;
  address internal currentActor;

  uint256 tierLiquidityUtilizationRate = 1e18;
  address drawManager = address(this);
  uint48 drawPeriodSeconds = 1 hours;
  uint48 awardDrawStartsAt;
  uint24 grandPrizePeriod = 365;
  uint8 numberOfTiers = MINIMUM_NUMBER_OF_TIERS;
  uint8 tierShares = 100;
  uint8 canaryShares = 5;
  uint8 reserveShares = 10;
  uint24 drawTimeout = 5;

  constructor(CurrentTime _currentTime) {
    currentTime = _currentTime;
    warpCurrentTime();
    // console2.log("constructor 1");
    claimer = makeAddr("claimer");
    // console2.log("constructor 2");
    for (uint i = 0; i != actors.length; i++) {
      actors[i] = makeAddr(string(abi.encodePacked("actor", i)));
    }
    // console2.log("constructor 3");

    // console2.log("constructor 4");

    awardDrawStartsAt = uint48(currentTime.timestamp());

    // console2.log("constructor 4.1");

    token = new ERC20Mintable("name", "SYMBOL");
    twabController = new TwabController(
      uint32(drawPeriodSeconds),
      uint32(awardDrawStartsAt)
    );
    // console2.log("constructor 5");
    // arbitrary mint
    twabController.mint(address(this), 100e18);

    // console2.log("constructor 6");
    ConstructorParams memory params = ConstructorParams(
      token,
      twabController,
      drawManager,
      tierLiquidityUtilizationRate,
      drawPeriodSeconds,
      awardDrawStartsAt,
      grandPrizePeriod,
      numberOfTiers,
      tierShares,
      canaryShares,
      reserveShares,
      drawTimeout
    );

    // console2.log("constructor 7");

    prizePool = new PrizePool(params);
  }

  function deposit(uint88 _amount, uint256 actorSeed) public useCurrentTime prankActor(actorSeed) {
    twabController.mint(_actor(actorSeed), _amount);
  }

  function contributePrizeTokens(uint88 _amount, uint256 actorSeed) public increaseCurrentTime(_timeIncrease()) prankActor(actorSeed) {
    // console2.log("contributePrizeTokens");
    contributed += _amount;
    token.mint(address(prizePool), _amount);
    prizePool.contributePrizeTokens(_actor(actorSeed), _amount);
  }

  function donatePrizeTokens(uint88 _amount, uint256 actorSeed) public increaseCurrentTime(_timeIncrease()) prankActor(actorSeed) {
    // console2.log("contributePrizeTokens");
    address actor = _actor(actorSeed);
    token.mint(address(actor), _amount);
    vm.startPrank(actor);
    token.approve(address(prizePool), _amount);
    contributed += _amount;
    prizePool.donatePrizeTokens(_amount);
    vm.stopPrank();
  }

  function contributeReserve(uint88 _amount, uint256 actorSeed) public increaseCurrentTime(_timeIncrease()) prankActor(actorSeed) {
    if (prizePool.isShutdown()) {
      return;
    }
    contributed += _amount;
    token.mint(_actor(actorSeed), _amount);
    token.approve(address(prizePool), _amount);
    prizePool.contributeReserve(_amount);
  }

  function shutdown() public increaseCurrentTime(_timeIncrease()) {
    vm.warp(prizePool.shutdownAt());
  }

  function allocateRewardFromReserve(uint256 actorSeed) public increaseCurrentTime(_timeIncrease()) prankDrawManager {
    // console2.log("allocateRewardFromReserve");
    uint96 amount = prizePool.reserve();
    withdrawn += amount;
    prizePool.allocateRewardFromReserve(_actor(actorSeed), amount);
  }

  function withdrawClaimReward() public increaseCurrentTime(_timeIncrease()) {
    // console2.log("withdrawClaimReward");
    vm.startPrank(claimer);
    prizePool.withdrawRewards(address(claimer), prizePool.rewardBalance(claimer));
    vm.stopPrank();
  }

  function claimPrizes() public useCurrentTime {
    // console2.log("claimPrizes");
    // console2.log("prizePool.numberOfTiers()", prizePool.numberOfTiers());
    if (prizePool.getLastAwardedDrawId() == 0) {
      // console2.log("skiipping");
      return;
    }
    for (uint i = 0; i < actors.length; i++) {
      _claimFor(actors[i]);
    }
  }

  function withdrawShutdownBalance(uint256 _actorSeed) public increaseCurrentTime(_timeIncrease()) prankActor(_actorSeed) {
    // console2.log("withdrawShutdownBalance withdrawShutdownBalance withdrawShutdownBalance withdrawShutdownBalance");
    address actor = _actor(_actorSeed);
    if (prizePool.shutdownBalanceOf(address(this), actor) > 0) {
      // console2.log("HAS A SHUTDOWN BALANCE");
    }
    prizePool.withdrawShutdownBalance(address(this), actor);
  }

  function awardDraw() public useCurrentTime prankDrawManager {
    // console2.log("AWARDING");
    uint24 drawId = prizePool.getDrawIdToAward();
    uint256 drawToAwardClosesAt = prizePool.drawClosesAt(drawId);
    if (drawToAwardClosesAt > currentTime.timestamp()) {
      warpTo(drawToAwardClosesAt);
    }
    prizePool.awardDraw(uint256(keccak256(abi.encode(block.timestamp))));
    // console2.log("SUCCESSSSS AWARDED DRAW");
  }

  function _actor(uint256 actorIndexSeed) internal view returns (address) {
    return actors[_bound(actorIndexSeed, 0, actors.length - 1)];
  }

  function _timeIncrease() internal view returns (uint256) {
    uint amount = _bound(uint256(keccak256(abi.encode(block.timestamp))), 0, drawPeriodSeconds/2);
    // console2.log("amount", amount);
    return amount;
  }

  function _claimFor(address actor_) internal {
    uint8 numTiers = prizePool.numberOfTiers();
    for (uint8 i = 0; i < numTiers; i++) {
      for (uint32 p = 0; p < prizePool.getTierPrizeCount(i); p++) {
        if (
          prizePool.isWinner(address(this), actor_, i, p) &&
          !prizePool.wasClaimed(address(this), actor_, i, p) &&
          prizePool.claimCount() < 4**2 // prevent claiming all prizes
        ) {
          // console2.log("CLAIMING");
          uint256 prizeSize = prizePool.getTierPrizeSize(i);
          if (prizeSize > 0) {
            claimed += prizePool.claimPrize(
              actor_,
              i,
              p,
              address(this),
              uint96(prizeSize/10),
              address(claimer)
            );
          }
        }
      }
    }
  }

  modifier prankActor(uint256 actorIndexSeed) {
    currentActor = _actor(actorIndexSeed);
    vm.startPrank(currentActor);
    _;
    vm.stopPrank();
  }

  modifier prankDrawManager() {
    vm.startPrank(drawManager);
    _;
    vm.stopPrank();
  }
}
