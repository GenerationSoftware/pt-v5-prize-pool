// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { DrawAccumulatorLib, Observation } from "src/libraries/DrawAccumulatorLib.sol";
import { E, SD59x18, sd, unwrap, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";

contract DrawAccumulatorFuzzHarness {
    using DrawAccumulatorLib for DrawAccumulatorLib.Accumulator;

    uint256 public totalAdded;

    DrawAccumulatorLib.Accumulator internal accumulator;

    function add(uint64 _amount, uint32 _drawId) public returns (bool) {
        SD59x18 alpha = sd(0.9e18);
        bool result = accumulator.add(_amount, _drawId, alpha);
        totalAdded += _amount;
        return result;
    }

    function newestObservation() external view returns (Observation memory) {
        return accumulator.newestObservation();
    }

    function newestDrawId() external view returns (uint256) {
        return accumulator.newestDrawId();
    }

}
