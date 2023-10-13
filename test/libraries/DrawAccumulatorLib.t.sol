// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { SD59x18, sd } from "prb-math/SD59x18.sol";

import { DrawAccumulatorLib, AddToDrawZero, DrawAwarded, InvalidDrawRange, Observation } from "../../src/libraries/DrawAccumulatorLib.sol";
import { DrawAccumulatorLibWrapper } from "../wrappers/DrawAccumulatorLibWrapper.sol";

contract DrawAccumulatorLibTest is Test {
  using DrawAccumulatorLib for DrawAccumulatorLib.Accumulator;

  DrawAccumulatorLib.Accumulator accumulator;
  DrawAccumulatorLibWrapper wrapper;
  SD59x18 alpha;
  uint contribution = 10000;

  function setUp() public {
    alpha = sd(0.9e18);
    /*
            Alpha of 0.9 and contribution of 10000 result in disbursal of:

            1	    1000
            2		900
            3		810
            4		729
            5       656
            6       590
            ...
        */
    wrapper = new DrawAccumulatorLibWrapper();
  }

  function testAdd_emitsAddToDrawZero() public {
    vm.expectRevert(abi.encodeWithSelector(AddToDrawZero.selector));
    add(0);
  }

  function testAdd_emitsDrawAwarded() public {
    add(4);
    vm.expectRevert(abi.encodeWithSelector(DrawAwarded.selector, 3, 4));
    add(3);
  }

  function testAddOne() public {
    DrawAccumulatorLib.add(accumulator, 100, 1, alpha);
    assertEq(accumulator.ringBufferInfo.cardinality, 1);
    assertEq(accumulator.ringBufferInfo.nextIndex, 1);
    assertEq(accumulator.drawRingBuffer[0], 1);
    assertEq(accumulator.observations[1].available, 100);
  }

  function testAddSame() public {
    DrawAccumulatorLib.add(accumulator, 100, 1, alpha);
    DrawAccumulatorLib.add(accumulator, 200, 1, alpha);

    assertEq(accumulator.ringBufferInfo.cardinality, 1);
    assertEq(accumulator.ringBufferInfo.nextIndex, 1);
    assertEq(accumulator.drawRingBuffer[0], 1);
    assertEq(accumulator.observations[1].available, 300);
  }

  function testAddSecond() public {
    DrawAccumulatorLib.add(accumulator, 100, 1, alpha);
    DrawAccumulatorLib.add(accumulator, 200, 3, alpha);

    assertEq(accumulator.ringBufferInfo.cardinality, 2);
    assertEq(accumulator.ringBufferInfo.nextIndex, 2);
    assertEq(accumulator.drawRingBuffer[0], 1);
    assertEq(accumulator.drawRingBuffer[1], 3);

    // 100 - 19 = 81

    assertEq(accumulator.observations[3].available, 281);
  }

  function testAddOne_deleteExpired() public {
    // set up accumulator as if we had just completed a buffer loop:
    for (uint16 i = 0; i < 366; i++) {
      wrapper.add(100, i + 1, alpha);
      assertEq(wrapper.getCardinality(), i + 1);
      assertEq(wrapper.getNextIndex(), i == 365 ? 0 : i + 1);
      assertEq(wrapper.getDrawRingBuffer(i), i + 1);
      assertGe(wrapper.getObservation(i + 1).available, wrapper.getObservation(i).available);
    }

    assertEq(wrapper.getCardinality(), 366);

    wrapper.add(200, 367, alpha);
    assertEq(wrapper.getCardinality(), 366);
    assertEq(wrapper.getNextIndex(), 1);
    assertEq(wrapper.getDrawRingBuffer(0), 367);
    assertGt(wrapper.getObservation(367).available, wrapper.getObservation(366).available);
    assertEq(wrapper.getObservation(1).available, 0); // deleted draw 1
  }

  function testGetTotalRemaining() public {
    add(1);

    assertEq(wrapper.getTotalRemaining(2, alpha), 9000);
  }

  function testGetTotalRemaining_empty() public {
    assertEq(wrapper.getTotalRemaining(1, alpha), 0);
  }

  function testGetTotalRemaining_invalidDraw() public {
    add(4);
    vm.expectRevert(abi.encodeWithSelector(DrawAwarded.selector, 2, 4));
    wrapper.getTotalRemaining(2, alpha);
  }

  function testGetDisbursedBetweenEmpty() public {
    assertEq(getDisbursedBetween(1, 4), 0);
  }

  function testGetDisbursedBetween_invalidRange() public {
    vm.expectRevert(abi.encodeWithSelector(InvalidDrawRange.selector, 2, 1));
    getDisbursedBetween(2, 1);
  }

  function testGetDisbursedBetween_endMoreThanOneBeforeLast() public {
    add(1);
    add(2);
    add(4);
    assertEq(getDisbursedBetween(1, 2), 2900); // end draw ID is more than 2 before last observation (4)
  }

  function testGetDisbursedBetween_endOneLessThanLast() public {
    add(1); // 1000
    add(2); // 1000 + 900
    // 900 + 810
    add(4); // 1000 + 810 + 729
    assertApproxEqAbs(getDisbursedBetween(1, 3), 4610, 1); // end draw ID is 1 before last observation (4)
  }

  function testGetDisbursedBetween_binarySearchBothStartAndEnd() public {
    // here we want to test a case where the algorithm must binary search both the start and end observations
    add(1); // 1000
    add(2); // 1000 + 900
    add(3); // 1000 + 900 + 810
    add(4); // 1000 + 900 + 810 + 729
    add(5);
    add(6);
    assertApproxEqAbs(getDisbursedBetween(3, 4), 6149, 1); // end draw ID is more than 2 before last observation (6) and start is not at earliest (1)
  }

  function testGetDisbursedBetween_binarySearchBothStartAndEnd_2ndScenario() public {
    // here we want to test a case where the algorithm must binary search both the start and end observations
    add(1); // 1000
    add(2); // 1000 + 900
    add(3); // 1000 + 900 + 810
    add(4); // 1000 + 900 + 810 + 729
    add(5);
    add(6);
    assertApproxEqAbs(getDisbursedBetween(2, 4), 8049, 1); // end draw ID is more than 2 before last observation (6) and start is not at earliest (1)
  }

  function testGetDisbursedBetween_binarySearchBothStartAndEnd_3rdScenario() public {
    // here we want to test a case where the algorithm must binary search both the start and end observations
    add(1); // 1000
    add(2); // 1000 + 900
    add(3); // 1000 + 900 + 810
    add(4); // 1000 + 900 + 810 + 729
    add(5); // 1000 + 900 + 810 + 729 + 656
    add(6);
    add(7);
    assertApproxEqAbs(getDisbursedBetween(2, 5), 12144, 2); // end draw ID is more than 2 before last observation (6) and start is not at earliest (1)
  }

  function testGetDisbursedBetween_binarySearchBothStartAndEnd_4thScenario() public {
    // here we want to test a case where the algorithm must binary search both the start and end observations
    add(1); // 1000
    add(2); // 1000 + 900
    // 900 + 810
    // 810 + 729
    add(5); // 1000 + 729 + 656
    add(6);
    add(7);
    assertApproxEqAbs(getDisbursedBetween(2, 5), 7534, 2); // end draw ID is more than 2 before last observation (6) and start is not at earliest (1)
  }

  function testGetDisbursedBetween_onOne() public {
    add(1);
    /*
            should include draw 1, 2, 3 and 4:
            1	    1000
            2		900
            3		810
            4		729
        */
    assertEq(getDisbursedBetween(1, 4), 3438);
  }

  function testGetDisbursedBetween_beforeOne() public {
    add(4);
    // should include draw 2, 3 and 4
    assertEq(getDisbursedBetween(2, 3), 0);
  }

  function testGetDisbursedBetween_endOnOne() public {
    add(4);
    // should include draw 2, 3 and 4
    assertEq(getDisbursedBetween(2, 4), 1000);
  }

  function testGetDisbursedBetween_startOnOne() public {
    add(4);
    // should include draw 2, 3 and 4
    assertEq(getDisbursedBetween(4, 4), 1000);
  }

  function testGetDisbursedBetween_afterOne() public {
    add(1);
    // should include draw 2, 3 and 4
    assertEq(getDisbursedBetween(2, 4), 2438);
  }

  function testGetDisbursedBetween_beforeOnTwo() public {
    add(4);
    add(5);
    /*
            should include draw 1, 2, 3 and 4:
            1	    1000
            2		900
            3		810 + 1000
            4		729 + 900
        */
    assertEq(getDisbursedBetween(1, 4), 1000);
  }

  function testGetDisbursedBetween_aroundFirstOfTwo() public {
    add(4);
    add(6);
    /*
            should include draw 1, 2, 3 and 4:
            1	    1000
            2		900
            3		810 + 1000
            4		729 + 900
        */
    assertEq(getDisbursedBetween(1, 5), 1899);
  }

  function testGetDisbursedBetween_acrossTwo() public {
    add(2);
    add(4);
    /*
            should include draw 2, 3 and 4:
            2	    1000
            3		900
            4		810 + 1000
            5		729 + 900
        */
    assertEq(getDisbursedBetween(1, 4), 3710);
  }

  function testGetDisbursedBetween_onOneBetweenTwo() public {
    add(2);
    add(4);
    /*
            should include draw 2, 3 and 4:
            2	    1000
            3		900
            4		810 + 1000
            5		729 + 900
        */
    assertEq(getDisbursedBetween(3, 3), 899);
  }

  function testGetDisbursedBetween_betweenTwo() public {
    add(1);
    add(4);
    /*
            should include draw 1, 2, 3 and 4:
            1	    1000
            2		900
            3		810
            4		729 + 1000
        */
    assertEq(getDisbursedBetween(2, 3), 1709);
  }

  function testGetDisbursedBetween_aroundLastOfTwo() public {
    add(1);
    add(4);
    /*
            should include draw 1, 2, 3 and 4:
            1	    1000
            2		900
            3		810
            4		729 + 1000
        */
    assertEq(getDisbursedBetween(3, 4), 2538);
  }

  function testGetDisbursedBetween_AfterLast() public {
    add(1);
    add(4);
    // 1  1000
    // 2  900
    // 3  810
    // 4  729 + 1000
    // 5  656 + 900
    // 6  590 + 810
    assertEq(getDisbursedBetween(6, 6), 1400);
  }

  function testIntegrateInf() public {
    assertEq(DrawAccumulatorLib.integrateInf(sd(0.9e18), 0, 100), 100);
    assertEq(DrawAccumulatorLib.integrateInf(sd(0.9e18), 1, 100), 90);
    assertEq(DrawAccumulatorLib.integrateInf(sd(0.9e18), 2, 100), 81);
    assertEq(DrawAccumulatorLib.integrateInf(sd(0.9e18), 3, 100), 72);
  }

  function testIntegrate() public {
    assertEq(DrawAccumulatorLib.integrate(sd(0.9e18), 0, 1, 10000), 1000);
    assertEq(DrawAccumulatorLib.integrate(sd(0.9e18), 1, 2, 10000), 899);
    assertEq(DrawAccumulatorLib.integrate(sd(0.9e18), 2, 3, 10000), 809);
    assertEq(DrawAccumulatorLib.integrate(sd(0.9e18), 3, 4, 10000), 728);
  }

  function testBinarySearchTwoWithFirstMatchingTarget() public {
    fillDrawRingBuffer([1, 3, 0, 0, 0]);
    (
      uint16 beforeOrAtIndex,
      uint24 beforeOrAtDrawId,
      uint16 afterOrAtIndex,
      uint24 afterOrAtDrawId
    ) = wrapper.binarySearch(0, 2, 2, 1);
    assertEq(beforeOrAtIndex, 0);
    assertEq(beforeOrAtDrawId, 1);
    assertEq(afterOrAtIndex, 1);
    assertEq(afterOrAtDrawId, 3);
  }

  function testBinarySearchMatchingTarget() public {
    fillDrawRingBuffer([1, 2, 3, 4, 5]);
    (
      uint16 beforeOrAtIndex,
      uint24 beforeOrAtDrawId,
      uint16 afterOrAtIndex,
      uint24 afterOrAtDrawId
    ) = wrapper.binarySearch(0, 4, 5, 3);
    assertEq(beforeOrAtIndex, 2);
    assertEq(beforeOrAtDrawId, 3);
    assertEq(afterOrAtIndex, 3);
    assertEq(afterOrAtDrawId, 4);
  }

  function testBinarySearchFirstMatchingTarget() public {
    fillDrawRingBuffer([1, 2, 3, 4, 5]);
    (
      uint16 beforeOrAtIndex,
      uint24 beforeOrAtDrawId,
      uint16 afterOrAtIndex,
      uint24 afterOrAtDrawId
    ) = wrapper.binarySearch(0, 4, 5, 1);
    assertEq(beforeOrAtIndex, 0);
    assertEq(beforeOrAtDrawId, 1);
    assertEq(afterOrAtIndex, 1);
    assertEq(afterOrAtDrawId, 2);
  }

  function testBinarySearchLastMatchingTarget() public {
    fillDrawRingBuffer([1, 2, 3, 4, 5]);
    (
      uint16 beforeOrAtIndex,
      uint24 beforeOrAtDrawId,
      uint16 afterOrAtIndex,
      uint24 afterOrAtDrawId
    ) = wrapper.binarySearch(0, 4, 5, 5);
    assertEq(beforeOrAtIndex, 3);
    assertEq(beforeOrAtDrawId, 4);
    assertEq(afterOrAtIndex, 4);
    assertEq(afterOrAtDrawId, 5);
  }

  function testBinarySearchTargetBetween() public {
    fillDrawRingBuffer([2, 4, 5, 6, 7]);
    (
      uint16 beforeOrAtIndex,
      uint24 beforeOrAtDrawId,
      uint16 afterOrAtIndex,
      uint24 afterOrAtDrawId
    ) = wrapper.binarySearch(0, 4, 5, 3);
    assertEq(beforeOrAtIndex, 0);
    assertEq(beforeOrAtDrawId, 2);
    assertEq(afterOrAtIndex, 1);
    assertEq(afterOrAtDrawId, 4);
  }

  function fillDrawRingBuffer(uint8[5] memory values) internal {
    for (uint16 i = 0; i < values.length; i++) {
      wrapper.setDrawRingBuffer(i, values[i]);
    }
    wrapper.setRingBufferInfo(uint16(values.length), uint16(values.length));
  }

  function add(uint16 drawId) internal {
    wrapper.add(10000, drawId, alpha);
  }

  function getDisbursedBetween(
    uint16 _startDrawId,
    uint16 _endDrawId
  ) internal view returns (uint256) {
    return wrapper.getDisbursedBetween(_startDrawId, _endDrawId, alpha);
  }
}
