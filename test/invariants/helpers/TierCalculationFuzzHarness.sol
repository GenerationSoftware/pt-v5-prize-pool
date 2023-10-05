// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { TierCalculationLib } from "../../../src/libraries/TierCalculationLib.sol";
import { SD59x18, unwrap, convert } from "prb-math/SD59x18.sol";
import { CommonBase } from "forge-std/Base.sol";

contract TierCalculationFuzzHarness is CommonBase {
  uint8 public immutable grandPrizePeriod = 10;
  uint128 immutable eachUserBalance = 100e18;
  SD59x18 immutable vaultPortion = convert(1);
  uint8 immutable _userCount = 20;
  uint8 public immutable numberOfTiers = 5;

  uint public winnerCount;
  uint32 public draws;

  function awardDraw(uint256 winningRandomNumber) public returns (uint) {
    uint drawPrizeCount;
    for (uint8 t = 0; t < numberOfTiers; t++) {
      uint32 prizeCount = uint32(TierCalculationLib.prizeCount(t));
      SD59x18 tierOdds = TierCalculationLib.getTierOdds(t, numberOfTiers, grandPrizePeriod);
      for (uint u = 1; u < _userCount + 1; u++) {
        address userAddress = vm.addr(u);
        for (uint32 p = 0; p < prizeCount; p++) {
          uint256 prn = TierCalculationLib.calculatePseudoRandomNumber(
            1,
            address(this),
            userAddress,
            t,
            p,
            winningRandomNumber
          );
          if (
            TierCalculationLib.isWinner(
              prn,
              eachUserBalance,
              _userCount * eachUserBalance,
              vaultPortion,
              tierOdds
            )
          ) {
            drawPrizeCount++;
          }
        }
      }
    }
    winnerCount += drawPrizeCount;
    draws++;
    return drawPrizeCount;
  }

  function averagePrizesPerDraw() public view returns (uint256) {
    return winnerCount / draws;
  }
}
