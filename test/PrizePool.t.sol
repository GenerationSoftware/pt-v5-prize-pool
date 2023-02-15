// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { sd, SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD1x18, sd1x18 } from "prb-math/SD1x18.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";

import { PrizePool } from "../src/PrizePool.sol";
import { ERC20Mintable } from "./mocks/ERC20Mintable.sol";
// import { TwabController } from "./mocks/TwabController.sol";

contract PrizePoolTest is Test {
    PrizePool public prizePool;

    ERC20Mintable public prizeToken;

    address public vault;

    TwabController public twabController;

    address otherSender = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
    uint64 drawStartedAt;
    uint32 drawPeriodSeconds;
    uint256 winningRandomNumber = 123456;

    function setUp() public {
        vm.warp(1000 days);

        prizeToken = new ERC20Mintable("PoolTogether POOL token", "POOL");
        twabController = new TwabController();

        drawStartedAt = uint64(block.timestamp);
        drawPeriodSeconds = 1 days;

        prizePool = new PrizePool(
            prizeToken,
            twabController,
            uint32(365),
            drawPeriodSeconds,
            drawStartedAt,
            uint8(2), // minimum number of tiers
            100e18,
            10e18,
            10e18,
            ud2x18(0.9e18),
            sd1x18(0.9e18)
        );
        // prizeToken = prizePool.prizeToken;

        vault = address(this);
    }

    function testContributePrizeTokens() public {
        uint256 _amountContributed = 100;

        prizeToken.mint(address(prizePool), _amountContributed);
        prizePool.contributePrizeTokens(address(this), _amountContributed);

        assertEq(prizeToken.balanceOf(address(prizePool)), _amountContributed);
    }

    function testGetVaultPortionWhenEmpty() public {
        assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 1)), 0);
    }

    function testGetVaultPortionWhenOne() public {
        uint256 _amountContributed = 100e18;
        prizeToken.mint(address(prizePool), _amountContributed);
        prizePool.contributePrizeTokens(address(this), _amountContributed);
        assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 1, 2)), 1e18);
    }

    function testGetVaultPortionWhenTwo() public {
        uint256 _amountContributed = 100e18;

        prizeToken.mint(address(prizePool), _amountContributed);
        prizePool.contributePrizeTokens(address(this), _amountContributed);

        prizeToken.mint(address(prizePool), _amountContributed);
        vm.startPrank(otherSender);
        prizePool.contributePrizeTokens(address(otherSender), _amountContributed);
        vm.stopPrank();

        assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 1, 2)), 0.5e18);
    }

    function testGetNextDrawId() public {
        uint256 nextDrawId = prizePool.getNextDrawId();
        assertEq(nextDrawId, 1);
    }

    // TODO: finish test
    function testSetDrawNoLiquidity() public {
        prizePool.completeAndStartNextDraw(winningRandomNumber);
        assertEq(prizePool.getWinningRandomNumber(), winningRandomNumber);
    }

    function testSetDrawWithLiquidity() public {
        uint amountContributed = 1e18;
        prizeToken.mint(address(prizePool), amountContributed);
        prizePool.contributePrizeTokens(address(this), amountContributed);

        // = 1e18 / 220e18 = 0.004545454...
        // but because of alpha only 10% is released on this draw

        prizePool.completeAndStartNextDraw(winningRandomNumber);
        assertEq(prizePool.prizeTokenPerShare(), 0.000454545454545454e18);
    }

    function testGetTotalShares() public {
        assertEq(prizePool.getTotalShares(), 220e18);
    }

    function testGetTierLiquidity() public {
        uint amountContributed = 1e18;
        prizeToken.mint(address(prizePool), amountContributed);
        prizePool.contributePrizeTokens(address(this), amountContributed);

        // tick over liquidity
        prizePool.completeAndStartNextDraw(winningRandomNumber);

        // 2 tiers at 100 shares each, and 10 for canary and 10 for reserve
        // = 100 / 220 = 10 / 22 = 0.45454545454545453
        // then take only 10% due to alpha = 0.9
        assertEq(prizePool.getTierLiquidity(0), 0.045454545454545400e18);
    }

    function testIsWinnerDailyPrize() public {
        uint256 amountContributed = 100e18;

        prizeToken.mint(address(prizePool), amountContributed);
        prizePool.contributePrizeTokens(address(this), amountContributed);

        uint64 startTime = drawStartedAt;
        uint64 endTime = drawStartedAt + drawPeriodSeconds;

        // console2.log("testIsWinnerSucceeds startTime", startTime);
        // console2.log("testIsWinnerSucceeds endTime", endTime);

        mockGetAverageBalanceBetween(
            address(this),
            msg.sender,
            startTime,
            endTime,
            1e30
        );
        mockGetAverageTotalSupplyBetween(
            address(this),
            startTime,
            endTime,
            1e30
        );

        prizePool.completeAndStartNextDraw(winningRandomNumber);

        assertEq(prizePool.isWinner(address(this), msg.sender, 1), true);
    }

    function testIsWinnerGrandPrize() public {
        uint256 amountContributed = 100e18;

        prizeToken.mint(address(prizePool), amountContributed);
        prizePool.contributePrizeTokens(address(this), amountContributed);

        uint64 endTime = drawStartedAt + drawPeriodSeconds;
        uint64 startTime = endTime - 366 days;

        console2.log("testIsWinnerSucceeds startTime", startTime);
        console2.log("testIsWinnerSucceeds endTime", endTime);

        mockGetAverageBalanceBetween(
            address(this),
            msg.sender,
            startTime,
            endTime,
            365e30 // hack to ensure grand prize is won
        );

        mockGetAverageTotalSupplyBetween(
            address(this),
            startTime,
            endTime,
            1e30
        );

        prizePool.completeAndStartNextDraw(winningRandomNumber);

        assertEq(prizePool.isWinner(address(this), msg.sender, 0), true);
    }

    function testClaimPrize() public {

        uint256 amountContributed = 100e18;

        prizeToken.mint(address(prizePool), amountContributed);
        prizePool.contributePrizeTokens(address(this), amountContributed);

        uint64 endTime = drawStartedAt + drawPeriodSeconds;
        uint64 startTime = endTime - 366 days;

        mockGetAverageBalanceBetween(
            address(this),
            msg.sender,
            startTime,
            endTime,
            366e30
        );
        mockGetAverageTotalSupplyBetween(
            address(this),
            startTime,
            endTime,
            1e30
        );

        prizePool.completeAndStartNextDraw(winningRandomNumber);

        prizePool.claimPrize(address(this), msg.sender, 0);

        // grand prize is (100/220) * 0.1 * 100e18 = 4.5454...e18
        assertEq(prizeToken.balanceOf(msg.sender), 4.5454545454545454e18);
    }

    function testGetVaultUserBalanceAndTotalSupplyTwab() public {
        prizePool.completeAndStartNextDraw(winningRandomNumber);
        uint64 endTime = drawStartedAt + drawPeriodSeconds;
        uint64 startTime = endTime - 365 days;

        // console2.log("testGetVaultUserBalanceAndTotalSupplyTwab startTime", startTime);
        // console2.log("testGetVaultUserBalanceAndTotalSupplyTwab endTime", endTime);

        mockGetAverageBalanceBetween(
            address(this),
            msg.sender,
            startTime,
            endTime,
            100
        );
        mockGetAverageTotalSupplyBetween(
            address(this),
            startTime,
            endTime,
            100
        );
        (uint256 twab, uint256 twabTotalSupply) = prizePool.getVaultUserBalanceAndTotalSupplyTwab(address(this), msg.sender, 365);
        assertEq(twab, 100);
        assertEq(twabTotalSupply, 100);
    }

    function mockGetAverageBalanceBetween(address _vault, address _user, uint64 _startTime, uint64 _endTime, uint256 _result) internal {
        vm.mockCall(
            address(twabController),
            abi.encodeWithSelector(TwabController.getAverageBalanceBetween.selector, _vault, _user, _startTime, _endTime),
            abi.encode(_result)
        );
    }

    function mockGetAverageTotalSupplyBetween(address _vault, uint64 _startTime, uint64 _endTime, uint256 _result) internal {
        uint64[] memory startTimes = new uint64[](1);
        startTimes[0] = _startTime;
        uint64[] memory endTimes = new uint64[](1);
        endTimes[0] = _endTime;
        uint256[] memory result = new uint256[](1);
        result[0] = _result;
        vm.mockCall(
            address(twabController),
            abi.encodeWithSelector(TwabController.getAverageTotalSuppliesBetween.selector, _vault, startTimes, endTimes),
            abi.encode(result)
        );
    }

    function testEstimatedPrizeCount() public {
        // assumes grand prize is 365
        assertEq(prizePool.estimatedPrizeCount(2), 4);
        assertEq(prizePool.estimatedPrizeCount(3), 16);
        assertEq(prizePool.estimatedPrizeCount(4), 66);
        assertEq(prizePool.estimatedPrizeCount(5), 270);
        assertEq(prizePool.estimatedPrizeCount(6), 1108);
        assertEq(prizePool.estimatedPrizeCount(7), 4517);
        assertEq(prizePool.estimatedPrizeCount(8), 18358);
        assertEq(prizePool.estimatedPrizeCount(9), 74435);
        assertEq(prizePool.estimatedPrizeCount(10), 301239);
        assertEq(prizePool.estimatedPrizeCount(11), 1217266);
        assertEq(prizePool.estimatedPrizeCount(12), 4912619);
        assertEq(prizePool.estimatedPrizeCount(13), 19805536);
        assertEq(prizePool.estimatedPrizeCount(14), 79777187);
        assertEq(prizePool.estimatedPrizeCount(15), 321105952);
        assertEq(prizePool.estimatedPrizeCount(16), 1291645048);
    }
}
