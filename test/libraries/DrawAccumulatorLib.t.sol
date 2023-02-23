// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { DrawAccumulatorLib } from "src/libraries/DrawAccumulatorLib.sol";
import { DrawAccumulatorLibWrapper } from "test/wrappers/DrawAccumulatorLibWrapper.sol";
import { SD59x18, sd } from "prb-math/SD59x18.sol";

contract DrawAccumulatorLibTest is Test {
    using DrawAccumulatorLib for DrawAccumulatorLib.Accumulator;

    DrawAccumulatorLib.Accumulator accumulator;
    DrawAccumulatorLibWrapper wrapper;
    SD59x18 alpha;

    function setUp() public {
        alpha = sd(0.9e18);
        wrapper = new DrawAccumulatorLibWrapper();
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

    function testGetAvailableAt() public {
        DrawAccumulatorLib.add(accumulator, 10000, 1, alpha);
        DrawAccumulatorLib.add(accumulator, 20000, 3, alpha);

        assertEq(DrawAccumulatorLib.getAvailableAt(accumulator, 1, alpha), 1000);
        assertEq(DrawAccumulatorLib.getAvailableAt(accumulator, 2, alpha), 899);
        assertEq(DrawAccumulatorLib.getAvailableAt(accumulator, 3, alpha), 2810);
    }


    function testGetTotalRemaining() public {
        DrawAccumulatorLib.add(accumulator, 10000, 1, alpha);

        assertEq(accumulator.getTotalRemaining(2, alpha), 9000);
    }

    function testGetDisbursedBetweenEmpty() public {
        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 1, 4, alpha), 0);
    }

    function testGetDisbursedBetweenWithOne() public {
        DrawAccumulatorLib.add(accumulator, 10000, 1, alpha);
        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 1, 4, alpha), 2709);
    }

    function testGetDisbursedBetween_withOne_searchAfter() public {
        DrawAccumulatorLib.add(accumulator, 10000, 1, alpha);
        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 2, 4, alpha), 2709);
    }

    function testGetDisbursedBetweenWithTwo() public {
        DrawAccumulatorLib.add(accumulator, 10000, 1, alpha);
        DrawAccumulatorLib.add(accumulator, 10000, 3, alpha);

        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 1, 4, alpha), 3709);
        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 2, 4, alpha), 2709);
        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 3, 4, alpha), 1810);
    }

    function testGetDisbursedPreviousDraw() public {
        DrawAccumulatorLib.add(accumulator, 10000, 1, alpha);
        DrawAccumulatorLib.add(accumulator, 10000, 4, alpha);

        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 1, 3, alpha), 1899);
    }

    function testGetDisbursedWithMatching() public {
        DrawAccumulatorLib.add(accumulator, 10000, 1, alpha);
        DrawAccumulatorLib.add(accumulator, 10000, 3, alpha);
        assertEq(DrawAccumulatorLib.getDisbursedBetween(accumulator, 4, 4, alpha), 0);
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
        (uint32 beforeOrAtIndex, uint32 beforeOrAtDrawId, uint32 afterOrAtIndex, uint32 afterOrAtDrawId) = wrapper.binarySearch(
            0, 2, 2, 1
        );
        assertEq(beforeOrAtIndex, 0);
        assertEq(beforeOrAtDrawId, 1);
        assertEq(afterOrAtIndex, 1);
        assertEq(afterOrAtDrawId, 3);
    }

    function testBinarySearchMatchingTarget() public {
        fillDrawRingBuffer([1, 2, 3, 4, 5]);
        (uint32 beforeOrAtIndex, uint32 beforeOrAtDrawId, uint32 afterOrAtIndex, uint32 afterOrAtDrawId) = wrapper.binarySearch(
            0, 4, 5, 3
        );
        assertEq(beforeOrAtIndex, 2);
        assertEq(beforeOrAtDrawId, 3);
        assertEq(afterOrAtIndex, 3);
        assertEq(afterOrAtDrawId, 4);
    }

    function testBinarySearchFirstMatchingTarget() public {
        fillDrawRingBuffer([1, 2, 3, 4, 5]);
        (uint32 beforeOrAtIndex, uint32 beforeOrAtDrawId, uint32 afterOrAtIndex, uint32 afterOrAtDrawId) = wrapper.binarySearch(
            0, 4, 5, 1
        );
        assertEq(beforeOrAtIndex, 0);
        assertEq(beforeOrAtDrawId, 1);
        assertEq(afterOrAtIndex, 1);
        assertEq(afterOrAtDrawId, 2);
    }

    function testBinarySearchLastMatchingTarget() public {
        fillDrawRingBuffer([1, 2, 3, 4, 5]);
        (uint32 beforeOrAtIndex, uint32 beforeOrAtDrawId, uint32 afterOrAtIndex, uint32 afterOrAtDrawId) = wrapper.binarySearch(
            0, 4, 5, 5
        );
        assertEq(beforeOrAtIndex, 3);
        assertEq(beforeOrAtDrawId, 4);
        assertEq(afterOrAtIndex, 4);
        assertEq(afterOrAtDrawId, 5);
    }

    function testBinarySearchTargetBetween() public {
        fillDrawRingBuffer([2, 4, 5, 6, 7]);
        (uint32 beforeOrAtIndex, uint32 beforeOrAtDrawId, uint32 afterOrAtIndex, uint32 afterOrAtDrawId) = wrapper.binarySearch(
            0, 4, 5, 3
        );
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

}
