// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { PrizePool, ConstructorParams } from "../../../src/PrizePool.sol";
import { ERC20Mintable } from "../../mocks/ERC20Mintable.sol";

contract PrizePoolFuzzHarness is CommonBase, StdCheats {
  PrizePool public prizePool;
  ERC20Mintable public token;

  uint256 public contributed;
  uint256 public withdrawn;
  uint256 public claimed;

  address claimer;

  uint256 currentTime;

  constructor() {
    vm.warp(365 days);

    claimer = makeAddr("claimer");
    address drawManager = address(this);
    uint48 drawPeriodSeconds = 1 hours;
    currentTime = block.timestamp;
    uint48 awardDrawStartsAt = uint48(currentTime);
    uint8 numberOfTiers = 3;
    uint8 tierShares = 100;
    uint8 reserveShares = 10;
    SD1x18 smoothing = SD1x18.wrap(0.9e18);

    token = new ERC20Mintable("name", "SYMBOL");
    TwabController twabController = new TwabController(
      uint32(drawPeriodSeconds),
      uint32(awardDrawStartsAt)
    );
    // arbitrary mint
    twabController.mint(address(this), 100e18);

    ConstructorParams memory params = ConstructorParams(
      token,
      twabController,
      drawPeriodSeconds,
      awardDrawStartsAt,
      smoothing,
      365,
      numberOfTiers,
      tierShares,
      reserveShares
    );
    prizePool = new PrizePool(params);
    prizePool.setDrawManager(drawManager);
  }

  function contributePrizeTokens(uint88 _amount) public warp {
    contributed += _amount;
    token.mint(address(prizePool), _amount);
    prizePool.contributePrizeTokens(address(this), _amount);
  }

  function contributeReserve(uint88 _amount) public warp {
    contributed += _amount;
    token.mint(address(this), _amount);
    token.approve(address(prizePool), _amount);
    prizePool.contributeReserve(_amount);
  }

  function allocateRewardFromReserve() public warp {
    uint96 amount = prizePool.reserve();
    withdrawn += amount;
    prizePool.allocateRewardFromReserve(address(msg.sender), amount);
  }

  function withdrawClaimReward() public warp {
    vm.startPrank(claimer);
    prizePool.withdrawRewards(address(claimer), prizePool.rewardBalance(claimer));
    vm.stopPrank();
  }

  function claimPrizes() public warp {
    if (prizePool.getLastAwardedDrawId() == 0) {
      return;
    }
    for (uint8 i = 0; i < prizePool.numberOfTiers(); i++) {
      for (uint32 p = 0; p < prizePool.getTierPrizeCount(i); i++) {
        if (
          prizePool.isWinner(address(this), address(this), i, p) &&
          !prizePool.wasClaimed(address(this), address(this), i, p)
        ) {
          uint256 prizeSize = prizePool.getTierPrizeSize(i);
          if (prizeSize > 0) {
            claimed += prizePool.claimPrize(
              address(this),
              i,
              p,
              address(this),
              1,
              address(claimer)
            );
          }
        }
      }
    }
  }

  function awardDraw() public {
    uint256 drawToAwardClosesAt = prizePool.drawClosesAt(prizePool.getDrawIdToAward());
    currentTime = drawToAwardClosesAt;
    vm.warp(currentTime);
    prizePool.awardDraw(uint256(keccak256(abi.encode(block.timestamp))));
  }

  modifier warp() {
    vm.warp(currentTime);
    _;
  }
}
