// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { sd } from "prb-math/SD59x18.sol";

import { PrizePool, ITWABController } from "../src/PrizePool.sol";
import { ERC20Mintable } from "./mocks/ERC20Mintable.sol";
import { TWABController } from "./mocks/TWABController.sol";

contract PrizePoolTest is Test {
    PrizePool public prizePool;

    ERC20Mintable public prizeToken;

    address public vault;

    TWABController public twabController;

    function setUp() public {
        prizeToken = new ERC20Mintable("PoolTogether POOL token", "POOL");
        twabController = new TWABController();

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
        // TODO: compute a random number
        PrizePool.Draw memory _nextDraw = PrizePool.Draw({
            winningRandomNumber: 123456,
            drawId: 1,
            timestamp: uint64(block.timestamp),
            beaconPeriodStartedAt: uint64(block.timestamp),
            beaconPeriodSeconds: 7 days
        });

        PrizePool.Draw memory _draw = prizePool.setDraw(_nextDraw);

        assertEq(_draw.winningRandomNumber, _nextDraw.winningRandomNumber);

        (uint256 winningRandomNumber,,,,) = prizePool.draw();

        assertEq(winningRandomNumber, _nextDraw.winningRandomNumber);
    }

    function testClaimPrize() public {
    }

    function testCheckIfWonPrizeSucceeds() public {
        uint256 _amountContributed = 100;

        prizeToken.mint(address(this), _amountContributed);
        prizeToken.approve(address(prizePool), _amountContributed);

        prizePool.contributePrizeTokens(_amountContributed);

        vm.mockCall(
            address(twabController),
            abi.encodeCall(
                TWABController.balanceOf,
                (
                    vault,
                    msg.sender,
                    uint64(block.timestamp),
                    uint64(block.timestamp + 7 days)
                )
            ),
            abi.encode(10)
        );

        assertEq(prizePool.checkIfWonPrize(vault, msg.sender, 1), true);
    }

    function testCheckIfWonPrizeFails() public {
        uint256 _amountContributed = 100;

        prizeToken.mint(address(this), _amountContributed);
        prizeToken.approve(address(prizePool), _amountContributed);

        prizePool.contributePrizeTokens(_amountContributed);

        vm.mockCall(
            address(twabController),
            abi.encodeCall(
                TWABController.balanceOf,
                (
                    vault,
                    msg.sender,
                    uint64(block.timestamp),
                    uint64(block.timestamp + 7 days)
                )
            ),
            abi.encode(10)
        );

        vm.mockCall(
            address(twabController),
            abi.encodeCall(
                TWABController.totalSupply,
                (
                    vault,
                    uint64(block.timestamp),
                    uint64(block.timestamp + 7 days)
                )
            ),
            abi.encode(_amountContributed)
        );

        assertEq(prizePool.checkIfWonPrize(vault, msg.sender, uint32(1)), false);
    }
}
