// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { E, SD59x18, sd, unwrap, toSD59x18, fromSD59x18, ceil } from "prb-math/SD59x18.sol";
import { UD60x18, toUD60x18, fromUD60x18 } from "prb-math/UD60x18.sol";

library TierCalculationLib {

    function getTierOdds(uint256 _tier, uint256 _numberOfTiers, uint256 _grandPrizePeriod) internal pure returns (SD59x18) {
        SD59x18 _k = sd(1).div(
            sd(int256(uint256(_grandPrizePeriod)))
        ).ln().div(
            sd((-1 * int256(_numberOfTiers) + 1))
        );

        return E.pow(_k.mul(sd(int256(_tier) - (int256(_numberOfTiers) - 1))));
    }

    function estimatePrizeFrequencyInDraws(uint256 _tier, uint256 _numberOfTiers, uint256 _grandPrizePeriod) internal pure returns (uint256) {
        return uint256(fromSD59x18(
            sd(1e18).div(TierCalculationLib.getTierOdds(_tier, _numberOfTiers, _grandPrizePeriod)).ceil()
        ));
    }

    function prizeCount(uint256 _tier) internal pure returns (uint256) {
        uint256 _numberOfPrizes = 4 ** _tier;

        return _numberOfPrizes;
    }

    function computeNextExchangeRateDelta(
        uint256 _totalShares,
        uint256 _totalContributed
    ) internal pure returns (
        UD60x18 deltaExchangeRate,
        uint256 remainder
    ) {
        UD60x18 totalShares = toUD60x18(_totalShares);
        deltaExchangeRate = toUD60x18(_totalContributed).div(totalShares);
        remainder = _totalContributed - fromUD60x18(deltaExchangeRate.mul(totalShares));
    }

    function isWinner(
        address _user,
        uint32 _tier,
        uint256 _userTwab,
        uint256 _vaultTwabTotalSupply,
        SD59x18 _vaultPortion,
        SD59x18 _tierOdds,
        uint256 _winningRandomNumber
    ) internal pure returns (bool) {
        if (_vaultTwabTotalSupply == 0) {
            return false;
        }
        /*
            1. We generate a psuedo-random number that will be unique to the user and tier.
            2. Fit the PRN within the vault total supply.
        */
        uint256 prn = calculatePseudoRandomNumber(_user, _tier, _winningRandomNumber) % _vaultTwabTotalSupply;
        /*
            The user-held portion of the total supply is the "winning zone". If the above PRN falls within the winning zone, the user has won this tier

            However, we scale the size of the zone based on:
                - Odds of the tier occuring
                - Number of prizes
                - Portion of prize that was contributed by the vault
        */

        uint256 winningZone = calculateWinningZone(_userTwab, _tierOdds, _vaultPortion, prizeCount(_tier));

        return prn < winningZone;
    }

    function calculatePseudoRandomNumber(address _user, uint32 _tier, uint256 _winningRandomNumber) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(_user, _tier, _winningRandomNumber)));
    }

    function calculateWinningZone(
        uint256 _userTwab,
        SD59x18 _tierOdds,
        SD59x18 _vaultContributionFraction,
        uint256 _prizeCount
    ) internal pure returns (uint256) {
        return uint256(fromSD59x18(sd(int256(_userTwab*1e18)).mul(_tierOdds).mul(_vaultContributionFraction).mul(sd(int256(_prizeCount*1e18)))));
    }

    function estimatedClaimCount(uint256 _numberOfTiers, uint256 _grandPrizePeriod) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint32 i = 0; i < _numberOfTiers; i++) {
            count += uint256(unwrap(sd(int256(prizeCount(i))).mul(getTierOdds(i, _numberOfTiers, _grandPrizePeriod))));
        }
        return count;
    }
}
