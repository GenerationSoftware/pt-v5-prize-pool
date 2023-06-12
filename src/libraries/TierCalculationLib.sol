// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { E, SD59x18, sd, unwrap, toSD59x18, fromSD59x18, ceil } from "prb-math/SD59x18.sol";
import { UD60x18, toUD60x18, fromUD60x18 } from "prb-math/UD60x18.sol";

/// @title Tier Calculation Library
/// @author PoolTogether Inc. Team
/// @notice Provides helper functions to assist in calculating tier prize counts, frequency, and odds.
library TierCalculationLib {

    /// @notice Calculates the odds of a tier occurring
    /// @param _tier The tier to calculate odds for
    /// @param _numberOfTiers The total number of tiers
    /// @param _grandPrizePeriod The number of draws between grand prizes
    /// @return The odds that a tier should occur for a single draw.
    function getTierOdds(uint256 _tier, uint256 _numberOfTiers, uint256 _grandPrizePeriod) internal pure returns (SD59x18) {
        SD59x18 _k = sd(1).div(
            sd(int256(uint256(_grandPrizePeriod)))
        ).ln().div(
            sd((-1 * int256(_numberOfTiers) + 1))
        );

        return E.pow(_k.mul(sd(int256(_tier) - (int256(_numberOfTiers) - 1))));
    }

    /// @notice Estimates the number of draws between a tier occurring
    /// @param _tier The tier to calculate the frequency of
    /// @param _numberOfTiers The total number of tiers
    /// @param _grandPrizePeriod The number of draws between grand prizes
    /// @return The estimated number of draws between the tier occurring
    function estimatePrizeFrequencyInDraws(uint256 _tier, uint256 _numberOfTiers, uint256 _grandPrizePeriod) internal pure returns (uint256) {
        return uint256(fromSD59x18(
            sd(1e18).div(TierCalculationLib.getTierOdds(_tier, _numberOfTiers, _grandPrizePeriod)).ceil()
        ));
    }

    /// @notice Computes the number of prizes for a given tier
    /// @param _tier The tier to compute for
    /// @return The number of prizes
    function prizeCount(uint256 _tier) internal pure returns (uint256) {
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
        uint256 _numberOfTiers,
        uint256 _canaryShares,
        uint256 _reserveShares,
        uint256 _tierShares
    ) internal pure returns (UD60x18) {
        uint256 numerator = _canaryShares * ((_numberOfTiers+1) * _tierShares + _canaryShares + _reserveShares);
        uint256 denominator = _tierShares * ((_numberOfTiers) * _tierShares + _canaryShares + _reserveShares);
        UD60x18 multiplier = toUD60x18(numerator).div(toUD60x18(denominator));
        return multiplier.mul(toUD60x18(prizeCount(_numberOfTiers)));
    }

    /// @notice Determines if a user won a prize tier
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
        SD59x18 _tierOdds,
        uint32 _tierPrizeCount
    ) internal view returns (bool) {
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
        uint256 constrainedRandomNumber = _userSpecificRandomNumber % (_vaultTwabTotalSupply*_tierPrizeCount);
        uint256 winningZone = calculateWinningZone(_userTwab*uint256(_tierPrizeCount), _vaultContributionFraction, _tierOdds);

        return constrainedRandomNumber < winningZone;
    }

    /// @notice Calculates a pseudo-random number that is unique to the user, tier, and winning random number
    /// @param _user The user
    /// @param _tier The tier
    /// @param _prizeIndex The particular prize index they are checking
    /// @param _winningRandomNumber The winning random number
    /// @return A pseudo-random number
    function calculatePseudoRandomNumber(
        address _user,
        uint32 _tier,
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
        return uint256(fromSD59x18(
            toSD59x18(int256(_userTwab)).mul(_tierOdds).mul(_vaultContributionFraction)
        ));
    }

    /// @notice Computes the estimated number of prizes per draw given the number of tiers and the grand prize period.
    /// @param _numberOfTiers The number of tiers
    /// @param _grandPrizePeriod The grand prize period
    /// @return The estimated number of prizes per draw
    function estimatedClaimCount(uint256 _numberOfTiers, uint256 _grandPrizePeriod) internal pure returns (uint32) {
        uint32 count = 0;
        for (uint32 i = 0; i < _numberOfTiers; i++) {
            count += uint32(uint256(unwrap(sd(int256(prizeCount(i))).mul(getTierOdds(i, _numberOfTiers, _grandPrizePeriod)))));
        }
        return count;
    }
}
