// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { TieredLiquidityDistributorFuzzHarness } from "./helpers/TieredLiquidityDistributorFuzzHarness.sol";

contract TieredLiquidityDistributorInvariants is Test {

    TieredLiquidityDistributorFuzzHarness public distributor;

    function setUp() external {
        distributor = new TieredLiquidityDistributorFuzzHarness();
    }

    function invariant_tiers_always_sum() external {
        uint256 expected = distributor.totalAdded() - distributor.totalConsumed();
        assertApproxEqAbs(distributor.accountedLiquidity(), expected, 7);
    }

    function testInvariantFailure_Case_26_05_2023() external {
        distributor.nextDraw(3, 253012247290373118207);
        distributor.nextDraw(2, 99152290762372054017);
        distributor.nextDraw(255, 79228162514264337593543950333);
        distributor.consumeLiquidity(1);
        distributor.consumeLiquidity(0);
        distributor.nextDraw(0, 2365);
        distributor.nextDraw(4, 36387);
        distributor.nextDraw(73, 486356342973499764);
        distributor.consumeLiquidity(174);
        distributor.consumeLiquidity(254);
        distributor.nextDraw(5, 2335051495798885129312);
        distributor.nextDraw(159, 543634559793817062402422965);
        distributor.nextDraw(186, 3765046993999626249);
        distributor.nextDraw(0, 196958881398058173458);
        uint256 expected = distributor.totalAdded() - distributor.totalConsumed();
        assertApproxEqAbs(distributor.accountedLiquidity(), expected, 7);
    }
}
