// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { TieredLiquidityDistributorFuzzHarness } from "test/invariants/helpers/TieredLiquidityDistributorFuzzHarness.sol";

contract TieredLiquidityDistributorTest is Test {

    TieredLiquidityDistributorFuzzHarness public distributor;

    uint32 grandPrizePeriodDraws;
    uint8 numberOfTiers;
    uint8 tierShares;
    uint8 canaryShares;
    uint8 reserveShares;

    function setUp() external {
        grandPrizePeriodDraws = 10;
        numberOfTiers = 2;
        tierShares = 100;
        canaryShares = 10;
        reserveShares = 10;

        distributor = new TieredLiquidityDistributorFuzzHarness();

        // distributor = new TieredLiquidityDistributorWrapper(
        //     grandPrizePeriodDraws,
        //     numberOfTiers,
        //     tierShares,
        //     canaryShares,
        //     reserveShares
        // );
    }

    function testNewDraw() public {
        // distributor.nextDraw(254, 1);
        // console2.log("delta 1", distributor.net() - distributor.accountedLiquidity());
        // distributor.consumeLiquidity(252);
        // console2.log("delta 2", distributor.net() - distributor.accountedLiquidity());
        // distributor.nextDraw(3, 208847064800090702165);
        // distributor.nextDraw(153, 19);
        // distributor.nextDraw(254, 20282409603651670423947251286015);
        // console2.log("delta 3", distributor.net() - distributor.accountedLiquidity());
        // distributor.nextDraw(26, 20282409603651670423947251286014);
        // console2.log("delta 4", distributor.net() - distributor.accountedLiquidity());
        // distributor.consumeLiquidity(118);
        // console2.log("delta 5", distributor.net() - distributor.accountedLiquidity());
        // distributor.nextDraw(216, 10278);
        // console2.log("delta 6", distributor.net() - distributor.accountedLiquidity());
        // distributor.consumeLiquidity(10);
        // console2.log("delta 7", distributor.net() - distributor.accountedLiquidity());
        // distributor.consumeLiquidity(4);
        // console2.log("delta 8", distributor.net() - distributor.accountedLiquidity());
        // distributor.consumeLiquidity(71);
        // console2.log("delta 9", distributor.net() - distributor.accountedLiquidity());
        // distributor.consumeLiquidity(255);
        // console2.log("delta 0", distributor.net() - distributor.accountedLiquidity());
    }
}
