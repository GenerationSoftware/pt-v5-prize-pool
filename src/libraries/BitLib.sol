// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

/// @title Helper functions to retrieve on bit from a word of bits.
library BitLib {
  /// @notice Flips one bit in a packed array of bits.
  /// @param packedBits The bit storage. There are 256 bits in a uint256.
  /// @param bit The bit to flip
  /// @return The passed bit storage that has the desired bit flipped.
  function flipBit(uint256 packedBits, uint8 bit) internal pure returns (uint256) {
    // create mask
    uint256 mask = 0x1 << bit;
    return packedBits ^ mask;
  }

  /// @notice Retrieves the value of one bit from a packed array of bits.
  /// @param packedBits The bit storage. There are 256 bits in a uint256.
  /// @param bit The bit to retrieve
  /// @return The value of the desired bit
  function getBit(uint256 packedBits, uint8 bit) internal pure returns (bool) {
    uint256 mask = (0x1 << bit); // ^ type(uint256).max;
    // 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    return (packedBits & mask) >> bit == 1;
  }
}
