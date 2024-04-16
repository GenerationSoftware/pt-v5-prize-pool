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
}
