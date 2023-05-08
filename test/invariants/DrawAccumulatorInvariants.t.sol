// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { DrawAccumulatorFuzzHarness } from "./helpers/DrawAccumulatorFuzzHarness.sol";
import { Observation } from "src/libraries/DrawAccumulatorLib.sol";
import { SD59x18, unwrap, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";

contract DrawAccumulatorInvariants is Test {

    DrawAccumulatorFuzzHarness public accumulator;

    function setUp() external {
        accumulator = new DrawAccumulatorFuzzHarness();
    }

    function invariant_future_plus_past_equals_total() external {
        Observation memory obs = accumulator.newestObservation();
        assertEq(obs.available + obs.disbursed, accumulator.totalAdded());
    }
}
