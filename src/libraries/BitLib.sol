// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

library BitLib {

    function flipBit(uint256 packedBits, uint256 bit) internal pure returns (uint256) {
        // create mask
        uint256 mask = 0x1 << bit;
        return packedBits ^ mask;
    }

    function getBit(uint256 packedBits, uint256 bit) internal pure returns (bool) {
        uint256 mask = (0x1 << bit);// ^ type(uint256).max;
        // 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        return (packedBits & mask) >> bit == 1;
    }
}