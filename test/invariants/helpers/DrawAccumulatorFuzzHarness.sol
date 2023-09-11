// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { DrawAccumulatorLib, Observation } from "../../../src/libraries/DrawAccumulatorLib.sol";
import { E, SD59x18, sd, unwrap } from "prb-math/SD59x18.sol";

contract DrawAccumulatorFuzzHarness {
  using DrawAccumulatorLib for DrawAccumulatorLib.Accumulator;

  uint256 public totalAdded;

  DrawAccumulatorLib.Accumulator internal accumulator;

  uint16 currentDrawId = 1;

  function add(uint64 _amount, uint8 _drawInc) public returns (bool) {
    currentDrawId += (_drawInc / 16);
    SD59x18 alpha = sd(0.9e18);
    bool result = accumulator.add(_amount, currentDrawId, alpha);
    totalAdded += _amount;
    return result;
  }

  function newestObservation() external view returns (Observation memory) {
    return accumulator.observations[accumulator.newestDrawId()];
  }

  function newestDrawId() external view returns (uint256) {
    return accumulator.newestDrawId();
  }
}
