// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { DrawAccumulatorLib, Observation } from "../../../src/libraries/DrawAccumulatorLib.sol";
import { E, SD59x18, sd, unwrap } from "prb-math/SD59x18.sol";

contract DrawAccumulatorFuzzHarness {
  using DrawAccumulatorLib for DrawAccumulatorLib.Accumulator;

  uint256 public totalAdded;

  DrawAccumulatorLib.Accumulator internal accumulator;

  uint16 currentDrawId = uint8(uint256(blockhash(block.number - 1))) + 1;

  function add(uint88 _amount, uint8 _drawInc) public returns (bool) {
    currentDrawId += (_drawInc / 16);
    bool result = accumulator.add(_amount, currentDrawId);
    totalAdded += _amount;
    return result;
  }

  function getDisbursedBetween(uint16 _start, uint16 _end) external view returns (uint256 result) {
    uint24 start = _start % (currentDrawId*2);
    uint24 end = start + _end % (currentDrawId*2);
    result = accumulator.getDisbursedBetween(start, end);
  }

  function newestObservation() external view returns (Observation memory) {
    return accumulator.observations[accumulator.newestDrawId()];
  }

  function newestDrawId() external view returns (uint256) {
    return accumulator.newestDrawId();
  }
}
