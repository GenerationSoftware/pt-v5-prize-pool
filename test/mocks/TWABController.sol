// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ITWABController } from "../../src/interfaces/ITWABController.sol";

contract TWABController is ITWABController {
  function balanceOf(
    address vault,
    address user,
    uint64 drawStartTimestamp,
    uint64 drawEndTimestamp
  ) external pure returns (uint256) {
    return 10;
  }

  function totalSupply(
      address vault,
      uint64 drawStartTimestamp,
      uint64 drawEndTimestamp
  ) external pure returns(uint256) {
    return 100;
  }
}
