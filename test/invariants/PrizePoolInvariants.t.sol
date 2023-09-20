// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { PrizePoolFuzzHarness } from "./helpers/PrizePoolFuzzHarness.sol";

contract PrizePoolInvariants is Test {
  PrizePoolFuzzHarness public prizePoolHarness;

  function setUp() external {
    prizePoolHarness = new PrizePoolFuzzHarness();

    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = prizePoolHarness.contributePrizeTokens.selector;
    selectors[1] = prizePoolHarness.contributeReserve.selector;
    selectors[2] = prizePoolHarness.allocateRewardFromReserve.selector;
    selectors[3] = prizePoolHarness.withdrawClaimReward.selector;
    selectors[4] = prizePoolHarness.claimPrizes.selector;
    selectors[5] = prizePoolHarness.closeDraw.selector;
    targetSelector(FuzzSelector({ addr: address(prizePoolHarness), selectors: selectors }));
    targetContract(address(prizePoolHarness));
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
