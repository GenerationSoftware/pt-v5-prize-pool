// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev Because Foundry does not commit the state changes between invariant runs, we need to
/// save the current timestamp in a contract with persistent storage.
contract CurrentTime {
    uint256 public timestamp;

    constructor(uint256 _timestamp) {
        timestamp = _timestamp;
    }

    function set(uint _timestamp) external {
        timestamp = _timestamp;
    }

    function increase(uint256 _amount) external {
        timestamp += _amount;
    }
}