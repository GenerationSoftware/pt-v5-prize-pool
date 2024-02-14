// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import "forge-std/Test.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { UD34x4, fromUD34x4 } from "../src/libraries/UD34x4.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { TierCalculationLib } from "../src/libraries/TierCalculationLib.sol";
import { MAXIMUM_NUMBER_OF_TIERS, MINIMUM_NUMBER_OF_TIERS } from "../src/abstract/TieredLiquidityDistributor.sol";
import {
  PrizePool,
  PrizePoolFactory,
  ConstructorParams
} from "../src/PrizePoolFactory.sol";
import { ERC20Mintable } from "./mocks/ERC20Mintable.sol";

contract PrizePoolFactoryTest is Test {

    event NewPrizePool(
        PrizePool indexed prizePool
    );

    PrizePoolFactory prizePoolFactory;

    ERC20Mintable prizeToken;
    TwabController twabController;
    uint48 drawPeriodSeconds = 1 days;
    uint48 firstDrawOpensAt = 100 days;
    uint24 grandPrizePeriodDraws = 10;
    uint8 numberOfTiers = 3;
    uint8 tierShares = 100;
    uint8 reserveShares = 70;
    uint24 drawTimeout = 10;

    function setUp() public {
        vm.warp(firstDrawOpensAt);
        prizePoolFactory = new PrizePoolFactory();
        prizeToken = new ERC20Mintable("PoolTogether POOL token", "POOL");
        twabController = new TwabController(uint32(drawPeriodSeconds), uint32(firstDrawOpensAt - 1 days));
    }

    function testDeployPrizePool() public {
        // Deploy a new prizePool
        // `claimer` can be set to address zero if none is available yet.
        // Params struct for the Prize Pool configuration
        // Returns the newly deployed PrizePool
        ConstructorParams memory params = ConstructorParams({
            prizeToken: prizeToken,
            twabController: twabController,
            drawPeriodSeconds: drawPeriodSeconds,
            firstDrawOpensAt: firstDrawOpensAt,
            grandPrizePeriodDraws: grandPrizePeriodDraws,
            numberOfTiers: numberOfTiers,
            tierShares: tierShares,
            reserveShares: reserveShares,
            drawTimeout: drawTimeout
        });
        address prizePoolAddress = prizePoolFactory.computePrizePoolAddress(params);
        vm.expectEmit();
        emit NewPrizePool(PrizePool(prizePoolAddress));
        PrizePool _prizePool = prizePoolFactory.deployPrizePool(params);
        assertEq(address(_prizePool), prizePoolAddress);
        assertEq(prizePoolFactory.totalPrizePools(), 1, "correct num of prize pools");
        assertEq(prizePoolFactory.deployedPrizePools(prizePoolAddress), true, "correct prize pool deployed");
        assertEq(prizePoolFactory.deployerNonces(address(this)), 1, "nonce was increased");
    }
}
