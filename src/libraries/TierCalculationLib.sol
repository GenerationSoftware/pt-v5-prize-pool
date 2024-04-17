// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { UniformRandomNumber } from "uniform-random-number/UniformRandomNumber.sol";
import { SD59x18, sd, unwrap, convert } from "prb-math/SD59x18.sol";

/// @title Tier Calculation Library
/// @author PoolTogether Inc. Team
/// @notice Provides helper functions to assist in calculating tier prize counts, frequency, and odds.
library TierCalculationLib {
  /// @notice Calculates the odds of a tier occurring.
  /// @param _tier The tier to calculate odds for
  /// @param _numberOfTiers The total number of tiers
  /// @param _grandPrizePeriod The number of draws between grand prizes
  /// @return The odds that a tier should occur for a single draw.
  function getTierOdds(
    uint8 _tier,
    uint8 _numberOfTiers,
    uint24 _grandPrizePeriod
  ) internal pure returns (SD59x18) {
    int8 oneMinusNumTiers = 1 - int8(_numberOfTiers);
    return
      sd(1).div(sd(int24(_grandPrizePeriod))).pow(
        sd(int8(_tier) + oneMinusNumTiers).div(sd(oneMinusNumTiers)).sqrt()
      );
  }

  /// @notice Estimates the number of draws between a tier occurring.
  /// @param _tierOdds The odds for the tier to calculate the frequency of
  /// @return The estimated number of draws between the tier occurring
  function estimatePrizeFrequencyInDraws(SD59x18 _tierOdds) internal pure returns (uint256) {
    return uint256(convert(sd(1e18).div(_tierOdds).ceil()));
  }

  /// @notice Computes the number of prizes for a given tier.
  /// @param _tier The tier to compute for
  /// @return The number of prizes
  function prizeCount(uint8 _tier) internal pure returns (uint256) {
    return 4 ** _tier;
  }

  /// @notice Determines if a user won a prize tier.
  /// @param _userSpecificRandomNumber The random number to use as entropy
  /// @param _userTwab The user's time weighted average balance
  /// @param _vaultTwabTotalSupply The vault's time weighted average total supply
  /// @param _vaultContributionFraction The portion of the prize that was contributed by the vault
  /// @param _tierOdds The odds of the tier occurring
  /// @return True if the user won the tier, false otherwise
  function isWinner(
    uint256 _userSpecificRandomNumber,
    uint256 _userTwab,
    uint256 _vaultTwabTotalSupply,
    SD59x18 _vaultContributionFraction,
    SD59x18 _tierOdds
  ) internal pure returns (bool) {
    if (_vaultTwabTotalSupply == 0) {
      return false;
    }

    /// The user-held portion of the total supply is the "winning zone".
    /// If the above pseudo-random number falls within the winning zone, the user has won this tier.
    /// However, we scale the size of the zone based on:
    ///   - Odds of the tier occurring
    ///   - Number of prizes
    ///   - Portion of prize that was contributed by the vault

    return
      UniformRandomNumber.uniform(_userSpecificRandomNumber, _vaultTwabTotalSupply) <
      calculateWinningZone(_userTwab, _vaultContributionFraction, _tierOdds);
  }

  /// @notice Calculates a pseudo-random number that is unique to the user, tier, and winning random number.
  /// @param _drawId The draw id the user is checking
  /// @param _vault The vault the user deposited into
  /// @param _user The user
  /// @param _tier The tier
  /// @param _prizeIndex The particular prize index they are checking
  /// @param _winningRandomNumber The winning random number
  /// @return A pseudo-random number
  function calculatePseudoRandomNumber(
    uint24 _drawId,
    address _vault,
    address _user,
    uint8 _tier,
    uint32 _prizeIndex,
    uint256 _winningRandomNumber
  ) internal pure returns (uint256) {
    return
      uint256(
        keccak256(abi.encode(_drawId, _vault, _user, _tier, _prizeIndex, _winningRandomNumber))
      );
  }

  /// @notice Calculates the winning zone for a user. If their pseudo-random number falls within this zone, they win the tier.
  /// @param _userTwab The user's time weighted average balance
  /// @param _vaultContributionFraction The portion of the prize that was contributed by the vault
  /// @param _tierOdds The odds of the tier occurring
  /// @return The winning zone for the user.
  function calculateWinningZone(
    uint256 _userTwab,
    SD59x18 _vaultContributionFraction,
    SD59x18 _tierOdds
  ) internal pure returns (uint256) {
    return
      uint256(convert(convert(int256(_userTwab)).mul(_tierOdds).mul(_vaultContributionFraction)));
  }

  /// @notice Computes the estimated number of prizes per draw for a given tier and tier odds.
  /// @param _tier The tier
  /// @param _odds The odds of the tier occurring for the draw
  /// @return The estimated number of prizes per draw for the given tier and tier odds
  function tierPrizeCountPerDraw(uint8 _tier, SD59x18 _odds) internal pure returns (uint32) {
    return uint32(uint256(unwrap(sd(int256(prizeCount(_tier))).mul(_odds))));
  }

  /// @notice Checks whether a tier is a valid tier
  /// @param _tier The tier to check
  /// @param _numberOfTiers The number of tiers
  /// @return True if the tier is valid, false otherwise
  function isValidTier(uint8 _tier, uint8 _numberOfTiers) internal pure returns (bool) {
    return _tier < _numberOfTiers;
  }
}
