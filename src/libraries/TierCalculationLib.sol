// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { E, SD59x18, sd, unwrap, convert, ceil } from "prb-math/SD59x18.sol";
import { UD60x18, convert as convertUD60x18 } from "prb-math/UD60x18.sol";

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
    uint16 _grandPrizePeriod
  ) internal pure returns (SD59x18) {
    SD59x18 _k = sd(1).div(sd(int16(_grandPrizePeriod))).ln().div(
      sd((-1 * int8(_numberOfTiers) + 1))
    );

    return E.pow(_k.mul(sd(int8(_tier) - (int8(_numberOfTiers) - 1))));
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
    uint256 _numberOfPrizes = 4 ** _tier;

    return _numberOfPrizes;
  }

  /// @notice Computes the number of canary prizes as a fraction, based on the share distribution. This is important because the canary prizes should be indicative of the smallest prizes if
  /// the number of prize tiers was to increase by 1.
  /// @param _numberOfTiers The number of tiers
  /// @param _canaryShares The number of shares allocated to canary prizes
  /// @param _reserveShares The number of shares allocated to the reserve
  /// @param _tierShares The number of shares allocated to prize tiers
  /// @return The number of canary prizes, including fractional prizes.
  function canaryPrizeCount(
    uint8 _numberOfTiers,
    uint8 _canaryShares,
    uint8 _reserveShares,
    uint8 _tierShares
  ) internal pure returns (UD60x18) {
    uint256 numerator = uint256(_canaryShares) *
      ((_numberOfTiers + 1) * uint256(_tierShares) + _canaryShares + _reserveShares);
    uint256 denominator = uint256(_tierShares) *
      ((_numberOfTiers) * uint256(_tierShares) + _canaryShares + _reserveShares);
    UD60x18 multiplier = convertUD60x18(numerator).div(convertUD60x18(denominator));
    return multiplier.mul(convertUD60x18(prizeCount(_numberOfTiers)));
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
    uint128 _userTwab,
    uint128 _vaultTwabTotalSupply,
    SD59x18 _vaultContributionFraction,
    SD59x18 _tierOdds
  ) internal pure returns (bool) {
    if (_vaultTwabTotalSupply == 0) {
      return false;
    }
    /*
            The user-held portion of the total supply is the "winning zone". If the above pseudo-random number falls within the winning zone, the user has won this tier

            However, we scale the size of the zone based on:
                - Odds of the tier occuring
                - Number of prizes
                - Portion of prize that was contributed by the vault
        */
    // first constrain the random number to be within the vault total supply
    uint256 constrainedRandomNumber = _userSpecificRandomNumber % (_vaultTwabTotalSupply);
    uint256 winningZone = calculateWinningZone(_userTwab, _vaultContributionFraction, _tierOdds);

    return constrainedRandomNumber < winningZone;
  }

  /// @notice Calculates a pseudo-random number that is unique to the user, tier, and winning random number.
  /// @param _user The user
  /// @param _tier The tier
  /// @param _prizeIndex The particular prize index they are checking
  /// @param _winningRandomNumber The winning random number
  /// @return A pseudo-random number
  function calculatePseudoRandomNumber(
    address _user,
    uint8 _tier,
    uint32 _prizeIndex,
    uint256 _winningRandomNumber
  ) internal pure returns (uint256) {
    return uint256(keccak256(abi.encode(_user, _tier, _prizeIndex, _winningRandomNumber)));
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
      uint256(
        convert(convert(int256(_userTwab)).mul(_tierOdds).mul(_vaultContributionFraction))
      );
  }

  /// @notice Computes the estimated number of prizes per draw given the number of tiers and the grand prize period.
  /// @param _numberOfTiers The number of tiers
  /// @param _grandPrizePeriod The grand prize period
  /// @return The estimated number of prizes per draw
  function estimatedClaimCount(
    uint8 _numberOfTiers,
    uint16 _grandPrizePeriod
  ) internal pure returns (uint32) {
    uint32 count = 0;
    for (uint8 i = 0; i < _numberOfTiers; i++) {
      count += uint32(
        uint256(
          unwrap(sd(int256(prizeCount(i))).mul(getTierOdds(i, _numberOfTiers, _grandPrizePeriod)))
        )
      );
    }
    return count;
  }
}
