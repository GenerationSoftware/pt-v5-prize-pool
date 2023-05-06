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
}
