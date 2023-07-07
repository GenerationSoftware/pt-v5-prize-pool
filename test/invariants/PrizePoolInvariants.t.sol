// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { PrizePoolFuzzHarness } from "./helpers/PrizePoolFuzzHarness.sol";

contract PrizePoolInvariants is Test {
  PrizePoolFuzzHarness public prizePoolHarness;

  function setUp() external {
    prizePoolHarness = new PrizePoolFuzzHarness();
  }

  function invariant_balance_equals_accountedBalance() external {
    uint balance = prizePoolHarness.token().balanceOf(address(prizePoolHarness.prizePool()));
    assertEq(
      balance,
      prizePoolHarness.prizePool().accountedBalance(),
      "balance does not match accountedBalance"
    );
  }
}
