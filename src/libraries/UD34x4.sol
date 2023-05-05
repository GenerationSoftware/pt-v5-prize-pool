// SPDX-License-Identifier: GPL-3.0

import { UD60x18, uMAX_UD60x18 } from "prb-math/UD60x18.sol";

type UD34x4 is uint128;

/// @notice Emitted when converting a basic integer to the fixed-point format overflows UD34x4.
error PRBMath_UD34x4_Convert_Overflow(uint128 x);
error PRBMath_UD34x4_fromUD60x18_Convert_Overflow(uint256 x);

/// @dev The maximum value an UD34x4 number can have.
uint128 constant uMAX_UD34x4 = 340282366920938463463374607431768211455;

uint128 constant uUNIT = 1e4;

/// @notice Casts an UD34x4 number into UD60x18.
/// @dev Requirements:
/// - x must be less than or equal to `uMAX_UD2x18`.
function intoUD60x18(UD34x4 x) pure returns (UD60x18 result) {
    uint256 xUint = UD34x4.unwrap(x) * 1e14;
    result = UD60x18.wrap(xUint);
}

/// @notice Casts an UD34x4 number into UD60x18.
/// @dev Requirements:
/// - x must be less than or equal to `uMAX_UD2x18`.
function fromUD60x18(UD60x18 x) pure returns (UD34x4 result) {
    uint256 xUint = UD60x18.unwrap(x) / 1e14;
    if (xUint > uMAX_UD34x4) {
        revert PRBMath_UD34x4_fromUD60x18_Convert_Overflow(x.unwrap());
    }
    result = UD34x4.wrap(uint128(xUint));
}

/// @notice Converts an UD34x4 number to a simple integer by dividing it by `UNIT`. Rounds towards zero in the process.
/// @dev Rounds down in the process.
/// @param x The UD34x4 number to convert.
/// @return result The same number in basic integer form.
function convert(UD34x4 x) pure returns (uint128 result) {
    result = UD34x4.unwrap(x) / uUNIT;
}

/// @notice Converts a simple integer to UD34x4 by multiplying it by `UNIT`.
///
/// @dev Requirements:
/// - x must be less than or equal to `MAX_UD34x4` divided by `UNIT`.
///
/// @param x The basic integer to convert.
/// @param result The same number converted to UD34x4.
function convert(uint128 x) pure returns (UD34x4 result) {
    if (x > uMAX_UD34x4 / uUNIT) {
        revert PRBMath_UD34x4_Convert_Overflow(x);
    }
    unchecked {
        result = UD34x4.wrap(x * uUNIT);
    }
}

/// @notice Alias for the `convert` function defined above.
/// @dev Here for backward compatibility. Will be removed in V4.
function fromUD34x4(UD34x4 x) pure returns (uint128 result) {
    result = convert(x);
}

/// @notice Alias for the `convert` function defined above.
/// @dev Here for backward compatibility. Will be removed in V4.
function toUD34x4(uint128 x) pure returns (UD34x4 result) {
    result = convert(x);
}
