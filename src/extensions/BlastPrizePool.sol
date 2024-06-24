// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { PrizePool, ConstructorParams } from "../PrizePool.sol";

// The rebasing WETH token on Blast
IERC20Rebasing constant WETH = IERC20Rebasing(0x4300000000000000000000000000000000000004);

/// @notice The Blast yield modes for WETH
enum YieldMode {
  AUTOMATIC,
  VOID,
  CLAIMABLE
}

/// @notice The relevant interface for rebasing WETH on Blast
interface IERC20Rebasing {
  function configure(YieldMode) external returns (uint256);
  function claim(address recipient, uint256 amount) external returns (uint256);
  function getClaimableAmount(address account) external view returns (uint256);
}

/// @notice Thrown if the prize token is not the expected token on Blast.
/// @param prizeToken The prize token address
/// @param expectedToken The expected token address
error PrizeTokenNotExpectedToken(address prizeToken, address expectedToken);

/// @notice Thrown if a yield donation is triggered when there is no claimable balance.
error NoClaimableBalance();

/// @title PoolTogether V5 Blast Prize Pool
/// @author G9 Software Inc.
/// @notice A modified prize pool that opts in to claimable WETH yield on Blast and allows anyone to trigger
/// a donation of the accrued yield to the prize pool.
contract BlastPrizePool is PrizePool {

  /* ============ Constructor ============ */

  /// @notice Constructs a new Blast Prize Pool.
  /// @dev Reverts if the prize token is not the expected WETH token on Blast.
  /// @param params A struct of constructor parameters
  constructor(ConstructorParams memory params) PrizePool(params) {
    if (address(params.prizeToken) != address(WETH)) {
      revert PrizeTokenNotExpectedToken(address(params.prizeToken), address(WETH));
    }

    // Opt-in to claimable yield
    WETH.configure(YieldMode.CLAIMABLE);
  }

  /* ============ External Functions ============ */

  /// @notice Returns the claimable WETH yield balance for this contract
  function claimableYieldBalance() external view returns (uint256) {
    return WETH.getClaimableAmount(address(this));
  }

  /// @notice Claims the available WETH yield balance and donates it to the prize pool.
  /// @return The amount claimed and donated.
  function donateClaimableYield() external returns (uint256) {
    uint256 _claimableYieldBalance = WETH.getClaimableAmount(address(this));
    if (_claimableYieldBalance == 0) {
      revert NoClaimableBalance();
    }
    WETH.claim(address(this), _claimableYieldBalance);
    contributePrizeTokens(DONATOR, _claimableYieldBalance);
    return _claimableYieldBalance;
  }

}