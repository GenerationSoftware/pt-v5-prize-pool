// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

interface ITWABController {
    function balanceOf(
        address vault,
        address user,
        uint64 drawStartTimestamp,
        uint64 drawEndTimestamp
    ) external returns(uint256);

    function totalSupply(
        address vault,
        uint64 drawStartTimestamp,
        uint64 drawEndTimestamp
    ) external returns(uint256);
}
