// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
  constructor (
    string memory _name,
    string memory _symbol
  ) ERC20(_name, _symbol) {}

  function mint(address _account, uint256 _amount) public {
    _mint(_account, _amount);
  }
}
