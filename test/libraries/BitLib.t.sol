// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { BitLibWrapper } from "test/wrappers/BitLibWrapper.sol";

contract BitLibTest is Test {

    BitLibWrapper bitLib;

    function setUp() public {
        bitLib = new BitLibWrapper();
    }

    function testGetBit_zero() public {
        assertEq(bitLib.getBit(0x1, 0), true);
    }

    function testGetBit_three() public {
        assertEq(bitLib.getBit(0x4, 2), true);
    }

    function testGetBit_five() public {
        assertEq(bitLib.getBit(0x10, 4), true);
    }

    function testGetBit_last() public {
        assertEq(bitLib.getBit(0x8000000000000000000000000000000000000000000000000000000000000000, 255), true);
    }

    function testFlipBit_zero() public {
        assertEq(bitLib.flipBit(0x1, 0), 0x0);
    }

    function testFlipBit_five() public {
        assertEq(bitLib.flipBit(0x11, 4), 0x01);
    }

    function testFlipBit_last() public {
        assertEq(
            bitLib.flipBit(0x8f0000000000000000000000000000000000000000000000000000000000000f, 255),
            0x0f0000000000000000000000000000000000000000000000000000000000000f
        );
    }

    function testFlipBit_cast() public {
        assertEq(
            bitLib.flipBit(uint8(0x8f), 7),
            0x0f
        );
    }

}
