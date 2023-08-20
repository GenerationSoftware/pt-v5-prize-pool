// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

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

  uint public contributed;
  uint public withdrawn;
  uint public claimed;

  address claimer;

  uint currentTime;

  constructor() {
    vm.warp(365 days);

    claimer = makeAddr("claimer");
    address drawManager = address(this);
    uint32 drawPeriodSeconds = 1 hours;
    currentTime = block.timestamp;
    uint64 nextDrawStartsAt = uint64(currentTime);
    uint8 numberOfTiers = 3;
    uint8 tierShares = 100;
    uint8 reserveShares = 10;
    SD1x18 smoothing = SD1x18.wrap(0.9e18);

    token = new ERC20Mintable("name", "SYMBOL");
    TwabController twabController = new TwabController(drawPeriodSeconds, uint32(nextDrawStartsAt));
    // arbitrary mint
    twabController.mint(address(this), 100e18);

    ConstructorParams memory params = ConstructorParams(
      token,
      twabController,
      drawManager,
      drawPeriodSeconds,
      nextDrawStartsAt,
      smoothing,
      365,
      numberOfTiers,
      tierShares,
      reserveShares
    );
    prizePool = new PrizePool(params);
  }

  function contributePrizeTokens(uint64 _amount) warp public {
    contributed += _amount;
    token.mint(address(prizePool), _amount);
    prizePool.contributePrizeTokens(address(this), _amount);
  }

  function contributeReserve(uint64 _amount) warp public {
    contributed += _amount;
    token.mint(address(this), _amount);
    token.approve(address(prizePool), _amount);
    prizePool.contributeReserve(_amount);
  }

  function withdrawReserve() warp public {
    uint96 amount = prizePool.reserve();
    withdrawn += amount;
    prizePool.withdrawReserve(address(msg.sender), amount);
  }

  function withdrawClaimReward() warp public {
    vm.startPrank(claimer);
    prizePool.withdrawClaimRewards(address(claimer), prizePool.balanceOfClaimRewards(claimer));
    vm.stopPrank();
  }

  function claimPrizes() warp public {
    // console2.log("claimPrizes current time ", block.timestamp);
    if (prizePool.getLastClosedDrawId() == 0) {
      return;
    }
    for (uint8 i = 0; i < prizePool.numberOfTiers(); i++) {
      for (uint32 p = 0; p < prizePool.getTierPrizeCount(i); i++) {
        // console2.log("checking...", i, p);
        if (
          prizePool.isWinner(address(this), address(this), i, p) &&
          !prizePool.wasClaimed(address(this), address(this), i, p)
        ) {
          uint prizeSize = prizePool.getTierPrizeSize(i);
          if (prizeSize > 0) {
            // console2.log("claiming...");
            claimed += prizePool.claimPrize(address(this), i, p, address(this), 1, address(claimer));
          }
        }
      }
    }
  }

  function closeDraw() public {
    uint openDrawEndsAt = prizePool.openDrawEndsAt();
    currentTime = openDrawEndsAt;
    vm.warp(currentTime);
    prizePool.closeDraw(uint256(keccak256(abi.encode(block.timestamp))));
  }

  modifier warp() {
    vm.warp(currentTime);
    _;
  }
}
