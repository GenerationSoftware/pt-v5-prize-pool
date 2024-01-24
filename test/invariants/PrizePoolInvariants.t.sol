// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { PrizePoolFuzzHarness } from "./helpers/PrizePoolFuzzHarness.sol";

contract PrizePoolInvariants is Test {
  PrizePoolFuzzHarness public prizePoolHarness;

  function setUp() external {
    prizePoolHarness = new PrizePoolFuzzHarness();

    targetContract(address(prizePoolHarness));
  }

  function invariant_balance_equals_accounted() external {
    uint balance = prizePoolHarness.token().balanceOf(address(prizePoolHarness.prizePool()));
    uint accounted = prizePoolHarness.prizePool().accountedBalance();

    assertEq(
      balance,
      accounted,
      "balance does not match accountedBalance"
    );
  }
}
