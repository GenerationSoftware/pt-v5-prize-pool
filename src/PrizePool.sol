// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import { E, SD59x18, sd, unwrap } from "prb-math/SD59x18.sol";

import { ITWABController } from "./interfaces/ITWABController.sol";

contract PrizePool {
    IERC20 immutable public prizeToken;

    ITWABController immutable public twabController;

    uint256 public nextDrawLiquidity;

    /// @notice Draw struct created every draw
    /// @param winningRandomNumber The random number returned from the RNG service
    /// @param drawId The monotonically increasing drawId for each draw
    /// @param timestamp Unix timestamp of the draw. Recorded when the draw is created by the DrawBeacon.
    /// @param beaconPeriodStartedAt Unix timestamp of when the draw started
    /// @param beaconPeriodSeconds Unix timestamp of the beacon draw period for this draw.
    struct Draw {
        uint256 winningRandomNumber;
        uint32 drawId;
        uint64 timestamp;
        uint64 beaconPeriodStartedAt;
        uint32 beaconPeriodSeconds;
    }

    Draw public draw;

    // vault => drawId => amount contributed
    mapping(address => mapping(uint32 => uint256)) public vaultContribution;

    uint64 public immutable grandPrizePeriod;

    uint32 public numberOfTiers;

    // TODO: make internal
    uint256 public sharesPerTier;

    uint256 public canaryShares;

    uint256 public reserveShares;

    // tier number => tier exchange rate is prizeToken per share
    mapping(uint256 => uint256) internal _tierExchangeRates;

    uint256 internal _prizeTokenPerShare;

    // TODO: add requires
    constructor (
        IERC20 _prizeToken,
        ITWABController _twabController,
        uint64 _grandPrizePeriod,
        uint32 _numberOfTiers,
        uint256 _sharesPerTier,
        uint256 _canaryShares,
        uint256 _reserveShares

    ) {
        prizeToken = _prizeToken;
        twabController = _twabController;
        grandPrizePeriod = _grandPrizePeriod;
        numberOfTiers = _numberOfTiers;
        sharesPerTier = _sharesPerTier;
        canaryShares = _canaryShares;
        reserveShares = _reserveShares;
    }

    // TODO: see if we can transfer via a callback from the liquidator and add events
    function contributePrizeTokens(uint256 _amount) external {
        prizeToken.transferFrom(msg.sender, address(this), _amount);

        vaultContribution[msg.sender][uint32(draw.drawId + 1)] += _amount;
        nextDrawLiquidity += _amount;
    }

    function getNextDrawId() external view returns (uint256) {
        return uint256(draw.drawId) + 1;
    }

    // TODO: add event
    function setDraw(Draw calldata _nextDraw) external returns (Draw memory) {
        draw = _nextDraw;

        return _nextDraw;
    }

    function claimPrize() external returns (uint256) {

    }

    /**
    * TODO: check that beaconPeriodStartedAt is the timestamp at which the draw started
    * Add in memory start and end timestamp
    */
    function checkIfWonPrize(
        address _vault,
        address _user,
        uint32 _tier
    ) external returns (bool) {
        uint256 _vaultContribution = vaultContribution[_vault][draw.drawId];
        uint256 _userTWAB = twabController.balanceOf(
            _vault,
            _user,
            draw.beaconPeriodStartedAt,
            draw.beaconPeriodStartedAt + draw.beaconPeriodSeconds
        );

        uint256 _vaultTotalSupply = twabController.totalSupply(
            _vault,
            draw.beaconPeriodStartedAt,
            draw.beaconPeriodStartedAt + draw.beaconPeriodSeconds
        );

        // const divRand = (Math.random()*TOTAL_SUPPLY) / tierPrizeCount
        // const totalOdds = tierOdds*USER_BALANCE
        // const isWinner = divRand < totalOdds

        // TODO: salt totalOdds

        uint256 _tierPrizeCount = _prizeCount(_tier);

        uint256 _normalizedRandomNumber = (draw.winningRandomNumber % _vaultTotalSupply) / _tierPrizeCount;
        uint256 _userOdds = uint256(unwrap(_getTierOdds(_tier, numberOfTiers).mul(sd(int256(_userTWAB)))));
        // uint256 _userOdds = 1;

        return _normalizedRandomNumber < _userOdds;
        // return false;
    }

    /**
    const tierPrizeCount = prizeCount(t)
            const prizeSize = Math.trunc(getTierLiquidity(t)) / tierPrizeCount
            const K = Math.log(1/GRAND_PRIZE_FREQUENCY)/(-1*numTiers+1)
            const tierOdds = Math.E**(K*(t - (numTiers - 1)))

            let tierMatchingPrizeCount = 0
            let tierAwardedPrizeCount = 0
            let tierDroppedPrizes = 0
            for (let u = 0; u < options.users; u++) {
                const divRand = (Math.random()*TOTAL_SUPPLY) / tierPrizeCount
                const totalOdds = tierOdds*USER_BALANCE
                const isWinner = divRand < totalOdds
*/

    function _getTierOdds(uint256 _tier, uint256 _numberOfTiers) internal returns (SD59x18) {
        // Math.log(1/GRAND_PRIZE_FREQUENCY)/(-1*numTiers+1)
        SD59x18 _k = sd(1).div(
            sd(int256(uint256(grandPrizePeriod)))
        ).ln().div(
            sd(-1 * int256(_numberOfTiers) + 1)
        );

        // Math.E**(K*(t - (numTiers - 1)))
        return E.pow(_k.mul(sd(int256(_tier) - (int256(_numberOfTiers) - 1))));
    }

    function _getTierLiquidity(uint256 _tier) internal returns (uint256) {
        uint256 _numberOfPrizeTokenPerShareOutstanding = _prizeTokenPerShare - _tierExchangeRates[_tier];

        return _numberOfPrizeTokenPerShareOutstanding * sharesPerTier;
    }

    function _prizeCount(uint32 _tier) internal returns (uint256) {
        uint256 _numberOfPrizes = 4 ** _tier;

        return _numberOfPrizes;
    }
}
