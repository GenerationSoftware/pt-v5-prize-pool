// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { sd } from "prb-math/SD59x18.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";

import { PrizePool } from "../src/PrizePool.sol";
import { ERC20Mintable } from "./mocks/ERC20Mintable.sol";
// import { TwabController } from "./mocks/TwabController.sol";

contract PrizePoolTest is Test {
    PrizePool public prizePool;

    ERC20Mintable public prizeToken;

    address public vault;

    TwabController public twabController;

    PrizePool.Draw draw;

    function setUp() public {
        prizeToken = new ERC20Mintable("PoolTogether POOL token", "POOL");
        twabController = new TwabController();

        prizePool = new PrizePool(
            prizeToken,
            twabController,
            uint64(52), // 52 weeks = 1 year
            uint32(2), // minimum number of tiers
            100e18,
            10e18,
            10e18,
            sd(0.9e18)
        );
        // prizeToken = prizePool.prizeToken;

        vault = address(this);

        draw = PrizePool.Draw({
            winningRandomNumber: 123456,
            drawId: 1,
            timestamp: uint64(block.timestamp),
            beaconPeriodStartedAt: uint64(block.timestamp),
            beaconPeriodSeconds: 7 days
        });
    }

    function testContributePrizeTokens() public {
        uint256 _amountContributed = 100;

        prizeToken.mint(address(this), _amountContributed);
        prizeToken.approve(address(prizePool), _amountContributed);

        uint256 _senderBalanceBefore = prizeToken.balanceOf(address(this));

        prizePool.contributePrizeTokens(_amountContributed);

        uint256 _senderBalanceAfter = prizeToken.balanceOf(address(this));

        assertEq(_senderBalanceBefore, _amountContributed);
        assertEq(_senderBalanceAfter, 0);
        assertEq(prizeToken.balanceOf(address(prizePool)), _amountContributed);
    }

    function testGetNextDrawId() public {
        uint256 nextDrawId = prizePool.getNextDrawId();
        assertEq(nextDrawId, 1);
    }

    // TODO: finish test
    function testSetDraw() public {
        PrizePool.Draw memory _draw = prizePool.setDraw(draw);
        assertEq(_draw.winningRandomNumber, draw.winningRandomNumber);
        (uint256 winningRandomNumber,,,,) = prizePool.draw();
        assertEq(winningRandomNumber, draw.winningRandomNumber);
    }

    function testIsWinnerSucceeds() public {
        uint256 amountContributed = 100;

        prizeToken.mint(address(this), amountContributed);
        prizeToken.approve(address(prizePool), amountContributed);
        prizePool.contributePrizeTokens(amountContributed);

        twabController.mint(address(this), msg.sender, 10);

        prizePool.setDraw(draw);

        assertEq(prizePool.isWinner(address(this), msg.sender, 1), true);
    }

    // function testIsWinnerFails() public {
    //     uint256 _amountContributed = 100;

    //     prizeToken.mint(address(this), _amountContributed);
    //     prizeToken.approve(address(prizePool), _amountContributed);
    //     prizePool.contributePrizeTokens(_amountContributed);

    //     twabController.mint(vault, msg.sender, 10);
    //     twabController.mint(vault, address(this), _amountContributed - 10);

    //     prizePool.setDraw(draw);

    //     assertEq(prizePool.isWinner(vault, msg.sender, uint32(1)), false);
    // }
}
