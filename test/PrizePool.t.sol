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

    address sender1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
    address sender2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
    address sender3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
    address sender4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
    address sender5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
    address sender6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

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
            ud2x18(0.9e18), // claim threshold of 90%
            sd1x18(0.9e18) // alpha
        );

        vault = address(this);
    }

    function testContributePrizeTokens() public {
        contribute(100);
        assertEq(prizeToken.balanceOf(address(prizePool)), 100);
    }

    function testGetVaultPortionWhenEmpty() public {
        assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 0, 1)), 0);
    }

    function testGetVaultPortionWhenOne() public {
        contribute(100e18);
        assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 1, 2)), 1e18);
    }

    function testGetVaultPortionWhenTwo() public {
        contribute(100e18);
        contribute(100e18, address(sender1));

        assertEq(SD59x18.unwrap(prizePool.getVaultPortion(address(this), 1, 2)), 0.5e18);
    }

    function testGetNextDrawId() public {
        uint256 nextDrawId = prizePool.getNextDrawId();
        assertEq(nextDrawId, 1);
    }

    function testCompleteAndStartNextDrawNoLiquidity() public {
        completeAndStartNextDraw(winningRandomNumber);
        assertEq(prizePool.getWinningRandomNumber(), winningRandomNumber);
        assertEq(prizePool.getDrawId(), 1);
        assertEq(prizePool.getNextDrawId(), 2);
        assertEq(prizePool.drawStartedAt(), drawStartedAt + drawPeriodSeconds);
    }

    function testCompleteAndStartNextDrawWithLiquidity() public {
        contribute(1e18);
        // = 1e18 / 220e18 = 0.004545454...
        // but because of alpha only 10% is released on this draw
        completeAndStartNextDraw(winningRandomNumber);
        assertEq(prizePool.prizeTokenPerShare().unwrap(), 0.000454545454545454e18);
        assertEq(prizePool.reserve(), 120); // remainder of the complex fraction
        assertEq(prizePool.totalDrawLiquidity(), 0.1e18 - 120); // ensure not a single wei is lost!
    }

    function testCompleteAndStartNextDraw_expandingTiers() public {
        contribute(1e18);
        completeAndStartNextDraw(1234);
        mockTwab(address(this), 0);
        claimPrize(address(this), 0);
        mockTwab(sender1, 1);
        claimPrize(sender1, 1);
        mockTwab(sender2, 1);
        claimPrize(sender2, 1);
        mockTwab(sender3, 1);
        claimPrize(sender3, 1);
        mockTwab(sender4, 1);
        claimPrize(sender4, 1);

        // canary tiers
        mockTwab(sender5, 2);
        claimPrize(sender5, 2);
        mockTwab(sender6, 2);
        claimPrize(sender6, 2);

        completeAndStartNextDraw(245);
        assertEq(prizePool.numberOfTiers(), 3);
    }

    function testGetTotalShares() public {
        assertEq(prizePool.getTotalShares(), 220e18);
    }

    function testGetTierLiquidity() public {
        contribute(1e18);
        // tick over liquidity
        completeAndStartNextDraw(winningRandomNumber);
        // 2 tiers at 100 shares each, and 10 for canary and 10 for reserve
        // = 100 / 220 = 10 / 22 = 0.45454545454545453
        // then take only 10% due to alpha = 0.9
        assertEq(prizePool.getTierLiquidity(0), 0.045454545454545400e18);
    }

    function testIsWinnerDailyPrize() public {
        contribute(100e18);
        completeAndStartNextDraw(winningRandomNumber);
        mockTwab(msg.sender, 1);
        assertEq(prizePool.isWinner(address(this), msg.sender, 1), true);
    }

    function testIsWinnerGrandPrize() public {
        contribute(100e18);
        completeAndStartNextDraw(winningRandomNumber);
        mockTwab(msg.sender, 0);
        assertEq(prizePool.isWinner(address(this), msg.sender, 0), true);
    }

    function testClaimPrize() public {
        contribute(100e18);
        completeAndStartNextDraw(winningRandomNumber);
        mockTwab(msg.sender, 0);
        claimPrize(msg.sender, 0);
        // grand prize is (100/220) * 0.1 * 100e18 = 4.5454...e18
        assertEq(prizeToken.balanceOf(msg.sender), 4.5454545454545454e18);
        assertEq(prizePool.claimCount(), 1);
    }

    function testClaimCanaryPrize() public {
        contribute(100e18);
        completeAndStartNextDraw(winningRandomNumber);
        mockTwab(sender1, 2);
        claimPrize(sender1, 2);
        assertEq(prizePool.claimCount(), 0);
        assertEq(prizePool.canaryClaimCount(), 1);
    }

    function testClaimPrizePartial() public {
        contribute(100e18);
        completeAndStartNextDraw(winningRandomNumber);
        mockTwab(sender1, 2);
        claimPrize(sender1, 2);
        assertEq(prizePool.claimCount(), 0);
        assertEq(prizePool.canaryClaimCount(), 1);
    }

    // function testCalculatePrizeSize() public {
    //     contribute(100e18);
    //     prizePool.calculatePrizeSize();
    // }

    function testGetVaultUserBalanceAndTotalSupplyTwab() public {
        completeAndStartNextDraw(winningRandomNumber);
        mockTwab(msg.sender, prizePool.drawStartedAt() + drawPeriodSeconds - 365 * drawPeriodSeconds, prizePool.drawStartedAt() + drawPeriodSeconds);
        (uint256 twab, uint256 twabTotalSupply) = prizePool.getVaultUserBalanceAndTotalSupplyTwab(address(this), msg.sender, 365);
        assertEq(twab, 366e30);
        assertEq(twabTotalSupply, 1e30);
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

    function contribute(uint256 amountContributed) public {
        contribute(amountContributed, address(this));
    }

    function contribute(uint256 amountContributed, address to) public {
        prizeToken.mint(address(prizePool), amountContributed);
        prizePool.contributePrizeTokens(to, amountContributed);
    }

    function completeAndStartNextDraw(uint256 _winnerRandomNumber) public {
        vm.warp(prizePool.drawStartedAt() + drawPeriodSeconds);
        prizePool.completeAndStartNextDraw(_winnerRandomNumber);
    }

    function claimPrize(address sender, uint8 tier) public returns (uint256) {
        uint256 result = prizePool.claimPrize(sender, tier, sender, 0, address(0));
        return result;
    }

    function mockTwab(address _account, uint64 startTime, uint64 endTime) public {
        console2.log("mockTwab startTime", startTime);
        console2.log("mockTwab endTime", endTime);
        mockGetAverageBalanceBetween(
            address(this),
            _account,
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
    }

    function mockTwab(address _account, uint8 _tier) public {
        (uint64 startTime, uint64 endTime) = prizePool.calculateTierTwabTimestamps(_tier);
        mockTwab(_account, startTime, endTime);
    }
}
