// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { RingBufferLib } from "ring-buffer-lib/RingBufferLib.sol";

// The maximum number of observations that can be recorded.
uint16 constant MAX_OBSERVATION_CARDINALITY = 366;

/// @notice Thrown when adding balance for draw zero.
error AddToDrawZero();

/// @notice Thrown when an action can't be done on a closed draw.
/// @param drawId The ID of the closed draw
/// @param newestDrawId The newest draw ID
error DrawAwarded(uint24 drawId, uint24 newestDrawId);

/// @notice Thrown when a draw range is not strictly increasing.
/// @param startDrawId The start draw ID of the range
/// @param endDrawId The end draw ID of the range
error InvalidDrawRange(uint24 startDrawId, uint24 endDrawId);

/// @notice The accumulator observation record
/// @param available The total amount available as of this Observation
/// @param disbursed The total amount disbursed in the past
struct Observation {
  uint96 available;
  uint160 disbursed;
}

/// @notice The metadata for using the ring buffer.
struct RingBufferInfo {
  uint16 nextIndex;
  uint16 cardinality;
}

/// @title Draw Accumulator Lib
/// @author G9 Software Inc.
/// @notice This contract distributes tokens over time according to an exponential weighted average.
/// Time is divided into discrete "draws", of which each is allocated tokens.
library DrawAccumulatorLib {

  /// @notice An accumulator for a draw.
  /// @param ringBufferInfo The metadata for the drawRingBuffer
  /// @param drawRingBuffer The ring buffer of draw ids
  /// @param observations The observations for each draw id
  struct Accumulator {
    RingBufferInfo ringBufferInfo; // 32 bits
    uint24[366] drawRingBuffer; // 8784 bits
    // 8784 + 32 = 8816 bits in total
    // 256 * 35 = 8960
    // 8960 - 8816 = 144 bits left over
    mapping(uint256 drawId => Observation observation) observations;
  }

  /// @notice Adds balance for the given draw id to the accumulator.
  /// @param accumulator The accumulator to add to
  /// @param _amount The amount of balance to add
  /// @param _drawId The draw id to which to add balance to. This must be greater than or equal to the previous
  /// addition's draw id.
  /// @return True if a new observation was created, false otherwise.
  function add(
    Accumulator storage accumulator,
    uint256 _amount,
    uint24 _drawId
  ) internal returns (bool) {
    if (_drawId == 0) {
      revert AddToDrawZero();
    }
    RingBufferInfo memory ringBufferInfo = accumulator.ringBufferInfo;

    uint24 newestDrawId_ = accumulator.drawRingBuffer[
      RingBufferLib.newestIndex(ringBufferInfo.nextIndex, MAX_OBSERVATION_CARDINALITY)
    ];

    if (_drawId < newestDrawId_) {
      revert DrawAwarded(_drawId, newestDrawId_);
    }

    mapping(uint256 drawId => Observation observation) storage accumulatorObservations = accumulator
      .observations;
    Observation memory newestObservation_ = accumulatorObservations[newestDrawId_];
    if (_drawId != newestDrawId_) {
      uint16 cardinality = ringBufferInfo.cardinality;
      if (ringBufferInfo.cardinality < MAX_OBSERVATION_CARDINALITY) {
        cardinality += 1;
      } else {
        // Delete the old observation to save gas (older than 1 year)
        delete accumulatorObservations[accumulator.drawRingBuffer[ringBufferInfo.nextIndex]];
      }

      accumulator.drawRingBuffer[ringBufferInfo.nextIndex] = _drawId;
      accumulatorObservations[_drawId] = Observation({
        available: SafeCast.toUint96(_amount),
        disbursed: SafeCast.toUint160(
          newestObservation_.disbursed +
            newestObservation_.available
        )
      });

      accumulator.ringBufferInfo = RingBufferInfo({
        nextIndex: uint16(RingBufferLib.nextIndex(ringBufferInfo.nextIndex, MAX_OBSERVATION_CARDINALITY)),
        cardinality: cardinality
      });

      return true;
    } else {
      accumulatorObservations[newestDrawId_] = Observation({
        available: SafeCast.toUint96(newestObservation_.available + _amount),
        disbursed: newestObservation_.disbursed
      });

      return false;
    }
  }

  /// @notice Returns the newest draw id from the accumulator.
  /// @param accumulator The accumulator to get the newest draw id from
  /// @return The newest draw id
  function newestDrawId(Accumulator storage accumulator) internal view returns (uint256) {
    return
      accumulator.drawRingBuffer[
        RingBufferLib.newestIndex(accumulator.ringBufferInfo.nextIndex, MAX_OBSERVATION_CARDINALITY)
      ];
  }

  /// @notice Returns the newest draw id from the accumulator.
  /// @param accumulator The accumulator to get the newest draw id from
  /// @return The newest draw id
  function newestObservation(Accumulator storage accumulator) internal view returns (Observation memory) {
    return accumulator.observations[
      newestDrawId(accumulator)
    ];
  }

  /// @notice Gets the balance that was disbursed between the given start and end draw ids, inclusive.
  /// @param _accumulator The accumulator to get the disbursed balance from
  /// @param _startDrawId The start draw id, inclusive
  /// @param _endDrawId The end draw id, inclusive
  /// @return The disbursed balance between the given start and end draw ids, inclusive
  function getDisbursedBetween(
    Accumulator storage _accumulator,
    uint24 _startDrawId,
    uint24 _endDrawId
  ) internal view returns (uint256) {
    if (_startDrawId > _endDrawId) {
      revert InvalidDrawRange(_startDrawId, _endDrawId);
    }

    RingBufferInfo memory ringBufferInfo = _accumulator.ringBufferInfo;

    if (ringBufferInfo.cardinality == 0) {
      return 0;
    }

    uint16 oldestIndex = uint16(
      RingBufferLib.oldestIndex(
        ringBufferInfo.nextIndex,
        ringBufferInfo.cardinality,
        MAX_OBSERVATION_CARDINALITY
      )
    );
    uint16 newestIndex = uint16(
      RingBufferLib.newestIndex(ringBufferInfo.nextIndex, ringBufferInfo.cardinality)
    );

    uint24 oldestDrawId = _accumulator.drawRingBuffer[oldestIndex];
    uint24 _newestDrawId = _accumulator.drawRingBuffer[newestIndex];

    if (_endDrawId < oldestDrawId || _startDrawId > _newestDrawId) {
      // if out of range, return 0
      return 0;
    }

    Observation memory atOrAfterStart;
    if (_startDrawId <= oldestDrawId || ringBufferInfo.cardinality == 1) {
      atOrAfterStart = _accumulator.observations[oldestDrawId];
    } else {
      // check if the start draw has an observation, otherwise search for the earliest observation after
      atOrAfterStart = _accumulator.observations[_startDrawId];
      if (atOrAfterStart.available == 0 && atOrAfterStart.disbursed == 0) {
        (, , , uint24 afterOrAtDrawId) = binarySearch(
          _accumulator.drawRingBuffer,
          oldestIndex,
          newestIndex,
          ringBufferInfo.cardinality,
          _startDrawId
        );
        atOrAfterStart = _accumulator.observations[afterOrAtDrawId];
      }
    }

    Observation memory atOrBeforeEnd;
    if (_endDrawId >= _newestDrawId || ringBufferInfo.cardinality == 1) {
      atOrBeforeEnd = _accumulator.observations[_newestDrawId];
    } else {
      // check if the end draw has an observation, otherwise search for the latest observation before
      atOrBeforeEnd = _accumulator.observations[_endDrawId];
      if (atOrBeforeEnd.available == 0 && atOrBeforeEnd.disbursed == 0) {
        (, uint24 beforeOrAtDrawId, , ) = binarySearch(
          _accumulator.drawRingBuffer,
          oldestIndex,
          newestIndex,
          ringBufferInfo.cardinality,
          _endDrawId
        );
        atOrBeforeEnd = _accumulator.observations[beforeOrAtDrawId];
      }
    }

    return atOrBeforeEnd.available + atOrBeforeEnd.disbursed - atOrAfterStart.disbursed;
  }

  /// @notice Binary searches an array of draw ids for the given target draw id.
  /// @dev The _targetDrawId MUST exist between the range of draws at _oldestIndex and _newestIndex (inclusive)
  /// @param _drawRingBuffer The array of draw ids to search
  /// @param _oldestIndex The oldest index in the ring buffer
  /// @param _newestIndex The newest index in the ring buffer
  /// @param _cardinality The number of items in the ring buffer
  /// @param _targetDrawId The target draw id to search for
  /// @return beforeOrAtIndex The index of the observation occurring at or before the target draw id
  /// @return beforeOrAtDrawId The draw id of the observation occurring at or before the target draw id
  /// @return afterOrAtIndex The index of the observation occurring at or after the target draw id
  /// @return afterOrAtDrawId The draw id of the observation occurring at or after the target draw id
  function binarySearch(
    uint24[366] storage _drawRingBuffer,
    uint16 _oldestIndex,
    uint16 _newestIndex,
    uint16 _cardinality,
    uint24 _targetDrawId
  )
    internal
    view
    returns (
      uint16 beforeOrAtIndex,
      uint24 beforeOrAtDrawId,
      uint16 afterOrAtIndex,
      uint24 afterOrAtDrawId
    )
  {
    uint16 leftSide = _oldestIndex;
    uint16 rightSide = _newestIndex < leftSide ? leftSide + _cardinality - 1 : _newestIndex;
    uint16 currentIndex;

    while (true) {
      // We start our search in the middle of the `leftSide` and `rightSide`.
      // After each iteration, we narrow down the search to the left or the right side while still starting our search in the middle.
      currentIndex = (leftSide + rightSide) / 2;

      beforeOrAtIndex = uint16(RingBufferLib.wrap(currentIndex, _cardinality));
      beforeOrAtDrawId = _drawRingBuffer[beforeOrAtIndex];

      afterOrAtIndex = uint16(RingBufferLib.nextIndex(currentIndex, _cardinality));
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
