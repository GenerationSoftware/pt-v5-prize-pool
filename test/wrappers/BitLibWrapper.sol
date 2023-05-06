// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { BitLib } from "src/libraries/BitLib.sol";

// Note: Need to store the results from the library in a variable to be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086
contract BitLibWrapper {


    /// @notice Flips one bit in a packed array of bits.
    /// @param packedBits The bit storage. There are 256 bits in a uint256.
    /// @param bit The bit to flip
    /// @return The passed bit storage that has the desired bit flipped.
    function flipBit(uint256 packedBits, uint8 bit) external pure returns (uint256) {
        uint256 result = BitLib.flipBit(packedBits, bit);
        return result;
    }

    /// @notice Retrieves the value of one bit from a packed array of bits.
    /// @param packedBits The bit storage. There are 256 bits in a uint256.
    /// @param bit The bit to retrieve
    /// @return The value of the desired bit
    function getBit(uint256 packedBits, uint8 bit) external pure returns (bool) {
        bool result = BitLib.getBit(packedBits, bit);
        return result;
    }

}
