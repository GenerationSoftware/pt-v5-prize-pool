// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { RingBufferLib } from "./RingBufferLib.sol";
import { E, SD59x18, sd, unwrap, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";

library DrawAccumulatorLib {

    uint24 internal constant MAX_CARDINALITY = 366;

    struct Observation {
        // track the total amount available as of this Observation
        uint96 available;
        // track the total accumulated previously
        uint168 disbursed;
    }

    struct RingBufferInfo {
        uint16 nextIndex;
        uint16 cardinality;
    }

    struct Accumulator {
        RingBufferInfo ringBufferInfo;
        uint32[MAX_CARDINALITY] drawRingBuffer;
        mapping(uint256 => Observation) observations;
    }

    struct Pair32 {
        uint32 first;
        uint32 second;
    }

    function add(Accumulator storage accumulator, uint256 _amount, uint32 _drawId, SD59x18 _alpha) internal {
        RingBufferInfo memory ringBufferInfo = accumulator.ringBufferInfo;

        uint256 newestIndex = RingBufferLib.newestIndex(ringBufferInfo.nextIndex, MAX_CARDINALITY);
        uint32 newestDrawId = accumulator.drawRingBuffer[newestIndex];

        require(_drawId >= newestDrawId, "invalid draw");

        Observation memory newestObservation = accumulator.observations[newestDrawId];
        if (_drawId != newestDrawId) {

            uint256 relativeDraw = _drawId - newestDrawId;

            uint256 remainingAmount = integrateInf(_alpha, relativeDraw, newestObservation.available);
            uint256 disbursedAmount = integrate(_alpha, 0, relativeDraw, newestObservation.available);

            accumulator.drawRingBuffer[ringBufferInfo.nextIndex] = _drawId;
            accumulator.observations[_drawId] = Observation({
                available: uint96(_amount + remainingAmount),
                disbursed: uint168(newestObservation.disbursed + disbursedAmount)
            });
            uint16 nextIndex = uint16(RingBufferLib.nextIndex(ringBufferInfo.nextIndex, MAX_CARDINALITY));
            uint16 cardinality = ringBufferInfo.cardinality;
            if (ringBufferInfo.cardinality < MAX_CARDINALITY) {
                cardinality += 1;
            }
            accumulator.ringBufferInfo = RingBufferInfo({
                nextIndex: nextIndex,
                cardinality: cardinality
            });
        } else {
            accumulator.observations[newestDrawId] = Observation({
                available: uint96(newestObservation.available + _amount),
                disbursed: newestObservation.disbursed
            });
        }
    }

    function getTotalRemaining(Accumulator storage accumulator, uint32 _endDrawId, SD59x18 _alpha) internal view returns (uint256) {
        RingBufferInfo memory ringBufferInfo = accumulator.ringBufferInfo;
        uint256 newestIndex = RingBufferLib.newestIndex(ringBufferInfo.nextIndex, MAX_CARDINALITY);
        uint32 newestDrawId = accumulator.drawRingBuffer[newestIndex];
        require(_endDrawId >= newestDrawId, "invalid draw");
        Observation memory newestObservation = accumulator.observations[newestDrawId];
        return integrateInf(_alpha, _endDrawId - newestDrawId, newestObservation.available);
    }

    function getAvailableAt(Accumulator storage accumulator, uint32 _drawId, SD59x18 _alpha) internal view returns (uint256) {
        RingBufferInfo memory ringBufferInfo = accumulator.ringBufferInfo;
        Pair32 memory indexes = computeIndices(ringBufferInfo);
        uint32 beforeOrAtDrawId = accumulator.drawRingBuffer[indexes.second];
        Observation memory beforeOrAtObservation;
        if (_drawId >= beforeOrAtDrawId) {
            beforeOrAtObservation = accumulator.observations[beforeOrAtDrawId];
        } else {
            uint32 oldestDrawId = accumulator.drawRingBuffer[indexes.first];
            // console2.log("oldestDrawId ", oldestDrawId);
            require(_drawId >= oldestDrawId, "too old");
            (,beforeOrAtDrawId,,) = binarySearch(
                accumulator.drawRingBuffer, indexes.first, indexes.second, ringBufferInfo.cardinality, _drawId
            );
            beforeOrAtObservation = accumulator.observations[beforeOrAtDrawId];
        }
        uint drawIdDiff = _drawId - beforeOrAtDrawId;
        return integrate(_alpha, drawIdDiff, drawIdDiff+1, beforeOrAtObservation.available);
    }

    /**
     * Requires endDrawId to be greater than (the newest draw id - 1)
     */
    function getDisbursedBetween(
        Accumulator storage accumulator,
        uint32 _startDrawId,
        uint32 _endDrawId,
        SD59x18 _alpha
    ) internal view returns (uint256) {
        RingBufferInfo memory ringBufferInfo = accumulator.ringBufferInfo;

        if (ringBufferInfo.cardinality == 0) {
            return 0;
        }

        Pair32 memory indexes = computeIndices(ringBufferInfo);
        Pair32 memory drawIds = readDrawIds(accumulator, indexes);
        require(_endDrawId >= drawIds.second-1, "DAL/curr-invalid");

        if (_endDrawId == _startDrawId) {
            return 0;
        }

        /*

        head: residual accrual from observation before start. (if any)
        body: if there is more than one observations between start and current, then take the past accumulator diff
        tail: accrual between the newest observation and current.  if card > 1 there is a tail (almost always)
        
           |        |
        o       o       o

        |           |
          o     o       o

         */

        // find the tail
        if (_endDrawId == drawIds.second-1) { // if looking for one older
            // look at the previous observation
            drawIds.second = accumulator.drawRingBuffer[RingBufferLib.offset(indexes.second, 1, ringBufferInfo.cardinality)];
        }

        Observation memory newestObservation = accumulator.observations[drawIds.second];
        // Add the tail
        uint256 sum = integrate(_alpha, 0, _endDrawId - drawIds.second, newestObservation.available);

        // Calculate the head (if any)
        uint32 afterOrAtDrawId;
        if (drawIds.first < _startDrawId) {
            uint32 beforeOrAtDrawId;
            // calculate body
            (, beforeOrAtDrawId, , afterOrAtDrawId) = binarySearch(
                accumulator.drawRingBuffer, indexes.first, indexes.second, ringBufferInfo.cardinality, _startDrawId
            );
            Observation memory beforeOrAt = accumulator.observations[beforeOrAtDrawId];

            sum += integrate(_alpha, _startDrawId - beforeOrAtDrawId, afterOrAtDrawId - beforeOrAtDrawId, beforeOrAt.available); // head
        } else {
            afterOrAtDrawId = drawIds.first;
        }

        // Calculate the body
        if (afterOrAtDrawId != drawIds.second) {
            Observation memory afterOrAt = accumulator.observations[afterOrAtDrawId];
            sum += newestObservation.disbursed - afterOrAt.disbursed; // body
        }

        return sum;
    }

    function computeIndices(RingBufferInfo memory ringBufferInfo) internal pure returns (Pair32 memory) {
        return Pair32({
            first: uint32(RingBufferLib.oldestIndex(ringBufferInfo.nextIndex, ringBufferInfo.cardinality, MAX_CARDINALITY)),
            second: uint32(RingBufferLib.newestIndex(ringBufferInfo.nextIndex, ringBufferInfo.cardinality))
        });
    }

    function readDrawIds(Accumulator storage accumulator, Pair32 memory indices) internal view returns (Pair32 memory) {
        return Pair32({
            first: uint32(accumulator.drawRingBuffer[indices.first]),
            second: uint32(accumulator.drawRingBuffer[indices.second])
        });
    }

    /**
     * @notice Returns the remaining prize tokens available from relative draw _x
     */
    function integrateInf(SD59x18 _alpha, uint _x, uint _k) internal pure returns (uint256) {
        return uint256(fromSD59x18(computeC(_alpha, _x, _k)));
    }

    /**
     * @notice returns the number of tokens that were given out between draw _start and draw _end
     */
    function integrate(SD59x18 _alpha, uint _start, uint _end, uint _k) internal pure returns (uint256) {
        int start = unwrap(
            computeC(_alpha, _start, _k)
        );
        // console2.log("integrate start" , start);
        int end = unwrap(
            computeC(_alpha, _end, _k)
        );
        // console2.log("integrate end" , end);
        return uint256(
            fromSD59x18(
                sd(
                    start
                    -
                    end
                )
            )
        );
    }

    function computeC(SD59x18 _alpha, uint _x, uint _k) internal pure returns (SD59x18) {
        return toSD59x18(int(_k)).mul(_alpha.pow(toSD59x18(int256(_x))));
    }

    /**
     */
    function binarySearch(
        uint32[MAX_CARDINALITY] storage _drawRingBuffer,
        uint32 _oldestIndex,
        uint32 _newestIndex,
        uint32 _cardinality,
        uint32 _targetDrawId
    ) internal view returns (
        uint32 beforeOrAtIndex,
        uint32 beforeOrAtDrawId,
        uint32 afterOrAtIndex,
        uint32 afterOrAtDrawId
    ) {
        uint32 leftSide = _oldestIndex;
        uint32 rightSide = _newestIndex < leftSide
            ? leftSide + _cardinality - 1
            : _newestIndex;
        uint32 currentIndex;

        while (true) {
            // We start our search in the middle of the `leftSide` and `rightSide`.
            // After each iteration, we narrow down the search to the left or the right side while still starting our search in the middle.
            currentIndex = (leftSide + rightSide) / 2;

            beforeOrAtIndex = uint32(RingBufferLib.wrap(currentIndex, _cardinality));
            beforeOrAtDrawId = _drawRingBuffer[beforeOrAtIndex];

            afterOrAtIndex = uint32(RingBufferLib.nextIndex(currentIndex, _cardinality));
            afterOrAtDrawId = _drawRingBuffer[afterOrAtIndex];

            bool targetAtOrAfter = beforeOrAtDrawId <= _targetDrawId;

            // Check if we've found the corresponding Observation.
            if (targetAtOrAfter && _targetDrawId <= afterOrAtDrawId) {
                break;
            }

            // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower. To the left of the current index.
            if (!targetAtOrAfter) {
                rightSide = currentIndex - 1;
            } else {
                // Otherwise, we keep searching higher. To the left of the current index.
                leftSide = currentIndex + 1;
            }
        }
    }
}
