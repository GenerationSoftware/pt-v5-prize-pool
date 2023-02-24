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

    function testAddInvalidDraw() public {
        add(4);
        vm.expectRevert("invalid draw");
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

    function testGetTotalRemaining() public {
        add(1);

        assertEq(wrapper.getTotalRemaining(2, alpha), 9000);
    }

    function testGetTotalRemaining_empty() public {
        assertEq(wrapper.getTotalRemaining(1, alpha), 0);
    }

    function testGetTotalRemaining_invalidDraw() public {
        add(4);
        vm.expectRevert("invalid draw");
        wrapper.getTotalRemaining(2, alpha);
    }

    function testGetDisbursedBetweenEmpty() public {
        assertEq(getDisbursedBetween(1, 4), 0);
    }

    function testGetDisbursedBetween_invalidRange() public {
        vm.expectRevert("invalid draw range");
        getDisbursedBetween(2, 1);
    }

    function testGetDisbursedBetween_invalidEnd() public {
        add(3);
        vm.expectRevert("DAL/curr-invalid");
        getDisbursedBetween(1, 1);
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

    function testGetDisbursedBetween_beforeTwo() public {
        add(3);
        add(5);
        /*
            should include draw 1, 2, 3 and 4:
            3	    1000
            4		900
            5		810 + 1000
            6		729 + 900
        */
        assertEq(getDisbursedBetween(1, 4), 1899);
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
        assertEq(getDisbursedBetween(1, 4), 3709);
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

    function add(uint32 drawId) internal {
        wrapper.add(10000, drawId, alpha);
    }

    function getDisbursedBetween(uint32 _startDrawId, uint32 _endDrawId) internal view returns (uint256) {
        return wrapper.getDisbursedBetween(_startDrawId, _endDrawId, alpha);
    }

}
