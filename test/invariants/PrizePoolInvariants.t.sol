// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { PrizePoolFuzzHarness } from "./helpers/PrizePoolFuzzHarness.sol";
import { Test } from "forge-std/Test.sol";
import { CurrentTime, CurrentTimeConsumer } from "./helpers/CurrentTimeConsumer.sol";

contract PrizePoolInvariants is Test, CurrentTimeConsumer {
  PrizePoolFuzzHarness public prizePoolHarness;

  function setUp() external {
    currentTime = new CurrentTime(365 days);
    prizePoolHarness = new PrizePoolFuzzHarness(currentTime);
    targetContract(address(prizePoolHarness));
  }

  function invariant_balance_equals_accounted() external useCurrentTime {
    uint balance = prizePoolHarness.token().balanceOf(address(prizePoolHarness.prizePool()));
    uint accounted = prizePoolHarness.prizePool().accountedBalance();
    assertEq(balance, accounted, "balance does not match accountedBalance");
  }

  // function invariant_not_shutdown() external {
  //   assertEq(prizePoolHarness.prizePool().isShutdown(), false, "PrizePool is shutdown");
  // }

  // function test_the_thing() public {
  //   prizePoolHarness.contributeReserve(622, 14960);
	// 	prizePoolHarness.contributePrizeTokens(956, 23553);
	// 	prizePoolHarness.allocateRewardFromReserve(1);
	// 	prizePoolHarness.allocateRewardFromReserve(325742104);
	// 	prizePoolHarness.contributeReserve(10130, 21326);
	// 	prizePoolHarness.contributePrizeTokens(18446744073895616894, 18261);
	// 	prizePoolHarness.claimPrizes();
	// 	prizePoolHarness.withdrawClaimReward();
	// 	prizePoolHarness.withdrawClaimReward();
	// 	prizePoolHarness.contributeReserve(2281, 23443);
	// 	prizePoolHarness.claimPrizes();
	// 	prizePoolHarness.contributePrizeTokens(10648, 4583);
	// 	prizePoolHarness.allocateRewardFromReserve(311);
	// 	prizePoolHarness.contributeReserve(309485009821345068724781054, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
  // }
}
