// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { DrawAccumulatorFuzzHarness } from "./helpers/DrawAccumulatorFuzzHarness.sol";
import { Observation } from "../../src/libraries/DrawAccumulatorLib.sol";

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
