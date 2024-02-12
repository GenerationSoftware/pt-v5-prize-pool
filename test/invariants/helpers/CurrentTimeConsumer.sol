// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { CurrentTime } from "./CurrentTime.sol";

contract CurrentTimeConsumer is CommonBase {

    CurrentTime public currentTime;

    modifier useCurrentTime() {
        warpCurrentTime();
        _;
    }

    modifier increaseCurrentTime(uint _amount) {
        currentTime.increase(_amount);
        warpCurrentTime();
        _;
    }

    function warpTo(uint _timestamp) internal {
        require(_timestamp > currentTime.timestamp(), "CurrentTimeConsumer/warpTo: cannot warp to the past");
        currentTime.set(_timestamp);
        warpCurrentTime();
    }

    function warpCurrentTime() internal {
        vm.warp(currentTime.timestamp());
    }
}