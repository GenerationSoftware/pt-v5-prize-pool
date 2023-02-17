// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { BitLib } from "src/libraries/BitLib.sol";

contract BitLibTest is Test {

    function testGetBit_zero() public {
        assertEq(BitLib.getBit(0x1, 0), true);
    }

    function testGetBit_three() public {
        assertEq(BitLib.getBit(0x4, 2), true);
    }

    function testGetBit_five() public {
        assertEq(BitLib.getBit(0x10, 4), true);
    }

    function testGetBit_last() public {
        assertEq(BitLib.getBit(0x8000000000000000000000000000000000000000000000000000000000000000, 255), true);
    }

    function testFlipBit_zero() public {
        assertEq(BitLib.flipBit(0x1, 0), 0x0);
    }

    function testFlipBit_five() public {
        assertEq(BitLib.flipBit(0x11, 4), 0x01);
    }

    function testFlipBit_last() public {
        assertEq(
            BitLib.flipBit(0x8f0000000000000000000000000000000000000000000000000000000000000f, 255),
            0x0f0000000000000000000000000000000000000000000000000000000000000f
        );
    }

    function testFlipBit_cast() public {
        assertEq(
            BitLib.flipBit(uint8(0x8f), 7),
            0x0f
        );
    }

}
