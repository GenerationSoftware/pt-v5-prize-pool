// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { UD60x18, toUD60x18, fromUD60x18 } from "prb-math/UD60x18.sol";

import { TieredLiquidityDistributorFuzzHarness } from "./helpers/TieredLiquidityDistributorFuzzHarness.sol";

contract TieredLiquidityDistributorInvariants is Test {

    TieredLiquidityDistributorFuzzHarness public distributor;

    function setUp() external {
        distributor = new TieredLiquidityDistributorFuzzHarness();
    }

    function invariant_tiers_always_sum() external {
        uint256 expected = distributor.totalAdded() - distributor.totalConsumed();
        uint256 accounted = distributor.accountedLiquidity();

        // Uncomment to append delta data to local CSV file:
        // --------------------------------------------------------
        // uint256 delta = expected > accounted ? expected - accounted : accounted - expected;
        // vm.writeLine(string.concat(vm.projectRoot(), "/data/tiers_accounted_liquidity_delta.csv"), string.concat(vm.toString(distributor.numberOfTiers()), ",", vm.toString(delta)));
        // assertApproxEqAbs(accounted, expected, 50); // run with high ceiling to avoid failures while recording data
        // --------------------------------------------------------
        // Comment out to avoid failing test while recording data:
        assertApproxEqAbs(accounted, expected, expectedLiquidityDeltaRange(distributor.numberOfTiers()));
        // --------------------------------------------------------
    }

    // Failure case regression test (2023-05-26)
    function testInvariantFailure_Case_2023_05_26() external {
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
        assertApproxEqAbs(distributor.accountedLiquidity(), expected, expectedLiquidityDeltaRange(distributor.numberOfTiers()));
    }

    /**
        Helper function using a custom fit expected ceiling for liquidity delta as a function of the number of tiers currently used.
        NOTE: Line fit is from (2, 8) to (15, 18).
     */ 
    function expectedLiquidityDeltaRange(uint8 numberOfTiers) internal pure returns(uint256) {
        require(numberOfTiers >= 2, "DeltaRange/number of tiers too low");
        UD60x18 slope = toUD60x18(10).div(toUD60x18(13));
        return 8 + fromUD60x18(slope.mul(toUD60x18(numberOfTiers - 2)).ceil());
    }

    // Tests for the helper function
    function testDeltaRange_At2() external {
        assertEq(expectedLiquidityDeltaRange(2), 8);
    }

    function testDeltaRange_At15() external {
        assertEq(expectedLiquidityDeltaRange(15), 18);
    }
}
