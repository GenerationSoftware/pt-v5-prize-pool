// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { TieredLiquidityDistributorFuzzHarness } from "./helpers/TieredLiquidityDistributorFuzzHarness.sol";

contract TieredLiquidityDistributorInvariants is Test {
  TieredLiquidityDistributorFuzzHarness public distributor;

  function setUp() external {
    distributor = new TieredLiquidityDistributorFuzzHarness();
  }

  function testTiers_always_sum() external {
    uint256 expected = distributor.totalAdded() - distributor.totalConsumed();
    uint256 accounted = distributor.accountedLiquidity();

    // Uncomment to append delta data to local CSV file:
    // --------------------------------------------------------
    // uint256 delta = expected > accounted ? expected - accounted : accounted - expected;
    // vm.writeLine(string.concat(vm.projectRoot(), "/data/tiers_accounted_liquidity_delta.csv"), string.concat(vm.toString(distributor.numberOfTiers()), ",", vm.toString(delta)));
    // assertApproxEqAbs(accounted, expected, 50); // run with high ceiling to avoid failures while recording data
    // --------------------------------------------------------
    // Comment out to avoid failing test while recording data:
    assertEq(accounted, expected, "accounted equals expected");
    // --------------------------------------------------------
  }

  // Failure case regression test (2023-05-26)
  function testInvariantFailure_Case_2023_05_26() external {
    distributor.awardDraw(4, 253012247290373118207);
    distributor.awardDraw(4, 99152290762372054017);
    distributor.awardDraw(255, 792281625142643375935439);
    distributor.consumeLiquidity(1);
    distributor.consumeLiquidity(0);
    distributor.awardDraw(1, 2365);
    distributor.awardDraw(5, 36387);
    distributor.awardDraw(74, 486356342973499764);
    distributor.consumeLiquidity(174);
    distributor.consumeLiquidity(254);
    distributor.awardDraw(6, 2335051495798885129312);
    distributor.awardDraw(160, 543634559793817062402);
    distributor.awardDraw(187, 3765046993999626249);
    distributor.awardDraw(1, 196958881398058173458);
    uint256 expected = distributor.totalAdded() - distributor.totalConsumed();
    assertEq(distributor.accountedLiquidity(), expected);
  }
}
