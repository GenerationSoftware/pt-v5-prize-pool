// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { UD60x18, toUD60x18 } from "prb-math/UD60x18.sol";
import {
    UD34x4,
    toUD34x4,
    fromUD34x4,
    intoUD60x18,
    fromUD60x18,
    uUNIT,
    PRBMath_UD34x4_Convert_Overflow,
    PRBMath_UD34x4_fromUD60x18_Convert_Overflow,
    uMAX_UD34x4
} from "src/libraries/UD34x4.sol";

contract UD34x4Test is Test {

    function testToUD34x4_withUintMax() public {
        uint128 legalMax = type(uint128).max / uUNIT;
        UD34x4 result = toUD34x4(legalMax);
        assertEq(UD34x4.unwrap(result), legalMax * uUNIT);
    }

    function testToUD34x4_overflow() public {
        uint128 legalMax = uMAX_UD34x4 / uUNIT;
        vm.expectRevert(abi.encodeWithSelector(PRBMath_UD34x4_Convert_Overflow.selector, legalMax+1));
        toUD34x4(legalMax+1);
    }

    function testIntoUD60x18() public {
        UD34x4 x = UD34x4.wrap(100e4);
        UD60x18 result = intoUD60x18(x);
        assertEq(result.unwrap(), 100e18);
    }

    function testIntoUD60x18_large() public pure {
        UD34x4 x = UD34x4.wrap(6004291579826925202373984590);
        intoUD60x18(x);
    }

    function testFromUD60x18_normal() public {
        UD60x18 x = UD60x18.wrap(100.1234e18);
        UD34x4 result = fromUD60x18(x);
        assertEq(UD34x4.unwrap(result), 100.1234e4);
    }

    function testFromUD60x18_overflow() public {
        UD60x18 x = toUD60x18(uMAX_UD34x4);
        vm.expectRevert(abi.encodeWithSelector(PRBMath_UD34x4_fromUD60x18_Convert_Overflow.selector, x.unwrap()));
        fromUD60x18(x);
    }

}
