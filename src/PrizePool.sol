// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud, fromUD60x18 } from "prb-math/UD60x18.sol";

// import { TwabController } from "./interfaces/TwabController.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";

import { DrawAccumulatorLib } from "./libraries/DrawAccumulatorLib.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";

contract PrizePool {
    using DrawAccumulatorLib for DrawAccumulatorLib.Accumulator;

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

    struct ClaimRecord {
        uint32 drawId;
        uint224 amount;
    }

    SD59x18 immutable public alpha;
    
    IERC20 immutable public prizeToken;

    TwabController immutable public twabController;

    uint64 public immutable grandPrizePeriod;

    // TODO: make internal
    uint256 public immutable sharesPerTier;

    uint256 public immutable canaryShares;

    uint256 public immutable reserveShares;

    
    mapping(address => DrawAccumulatorLib.Accumulator) internal vaultAccumulators;
    DrawAccumulatorLib.Accumulator internal totalAccumulator;

    // tier number => tier exchange rate is prizeToken per share
    mapping(uint256 => UD60x18) internal _tierExchangeRates;

    mapping(address => ClaimRecord) internal claimRecords;

    Draw public draw;

    uint32 public numberOfTiers;

    uint256 public reserve;

    UD60x18 internal _prizeTokenPerShare;

    uint128 claimCount;
    uint128 canaryClaimCount;

    // TODO: add requires
    constructor (
        IERC20 _prizeToken,
        TwabController _twabController,
        uint64 _grandPrizePeriod,
        uint32 _numberOfTiers,
        uint256 _sharesPerTier,
        uint256 _canaryShares,
        uint256 _reserveShares,
        SD59x18 _alpha
    ) {
        prizeToken = _prizeToken;
        twabController = _twabController;
        grandPrizePeriod = _grandPrizePeriod;
        numberOfTiers = _numberOfTiers;
        sharesPerTier = _sharesPerTier;
        canaryShares = _canaryShares;
        reserveShares = _reserveShares;
        alpha = _alpha;
    }

    // TODO: see if we can transfer via a callback from the liquidator and add events
    function contributePrizeTokens(uint256 _amount) external {
        prizeToken.transferFrom(msg.sender, address(this), _amount);

        vaultAccumulators[msg.sender].add(_amount, draw.drawId + 1, alpha);
        totalAccumulator.add(_amount, draw.drawId + 1, alpha);
    }

    function getNextDrawId() external view returns (uint256) {
        return uint256(draw.drawId) + 1;
    }

    // TODO: add event
    function setDraw(Draw calldata _nextDraw) external returns (Draw memory) {
        (UD60x18 deltaExchangeRate, uint256 remainder) = TierCalculationLib.computeNextExchangeRateDelta(_totalShares(), totalAccumulator.getAvailableAt(draw.drawId + 1, alpha));
        _prizeTokenPerShare = ud(UD60x18.unwrap(_prizeTokenPerShare) + UD60x18.unwrap(deltaExchangeRate));
        // reserve += remainder;
        require(_nextDraw.drawId == draw.drawId + 1, "not next draw");
        draw = _nextDraw;
        claimCount = 0;
        canaryClaimCount = 0;
        return _nextDraw;
    }

    function claimPrize(
        address _vault,
        address _user,
        uint32 _tier
    ) external returns (uint256) {
        uint256 prizeSize;
        if (isWinner(_vault, _user, _tier)) {
            // transfer prize to user
            prizeSize = calculatePrizeSize(_tier);
        }
        ClaimRecord memory claimRecord = claimRecords[_user];
        uint32 drawId = draw.drawId;
        uint256 payout = prizeSize;
        if (payout > 0 && claimRecord.drawId == drawId) {
            if (claimRecord.amount >= payout) {
                revert("already claimed");
            } else {
                payout -= claimRecord.amount;
            }
        }
        if (payout > 0) {
            claimRecords[_user] = ClaimRecord({drawId: drawId, amount: uint224(payout + claimRecord.amount)});
            prizeToken.transfer(_user, prizeSize);
        }
        return payout;
    }

    /**
    * TODO: check that beaconPeriodStartedAt is the timestamp at which the draw started
    * Add in memory start and end timestamp
    */
    function isWinner(
        address _vault,
        address _user,
        uint32 _tier
    ) public returns (bool) {
        require(draw.drawId > 0, "no draw");

        uint256 drawDuration = TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriod);

        uint256 _userTwab;
        uint256[] memory _vaultTwabTotalSupplies;
        SD59x18 vaultPortion;

        {
            uint64 endTimestamp = draw.beaconPeriodStartedAt + draw.beaconPeriodSeconds;
            uint64 startTimestamp = uint64(endTimestamp - drawDuration * draw.beaconPeriodSeconds);

            console2.log("endTimestamp", endTimestamp);
            console2.log("startTimestamp", startTimestamp);

            _userTwab = twabController.getAverageBalanceBetween(
                _vault,
                _user,
                startTimestamp,
                endTimestamp
            );
            
            uint64[] memory startTimestamps = new uint64[](1);
            startTimestamps[0] = startTimestamp;
            uint64[] memory endTimestamps;
            endTimestamps[0] = endTimestamp;

            _vaultTwabTotalSupplies = twabController.getAverageTotalSuppliesBetween(
                _vault,
                startTimestamps,
                endTimestamps
            );
        }

        {
            uint256 vaultContributed = vaultAccumulators[_vault].getDisbursedBetween(uint32(draw.drawId-drawDuration), draw.drawId, alpha);
            uint256 totalContributed = totalAccumulator.getDisbursedBetween(uint32(draw.drawId-drawDuration), draw.drawId, alpha);
            vaultPortion = sd(int256(vaultContributed)).div(sd(int256(totalContributed)));
        }

        SD59x18 tierOdds = TierCalculationLib.getTierOdds(_tier, numberOfTiers, grandPrizePeriod);
        // each user gets a different random number
        return TierCalculationLib.isWinner(_user, _tier, _userTwab, _vaultTwabTotalSupplies[0], vaultPortion, tierOdds, draw.winningRandomNumber);
    }

    function calculatePrizeSize(uint256 _tier) public view returns (uint256) {
        return _getTierLiquidity(_tier) / TierCalculationLib.prizeCount(_tier);
    }

    function getTierLiquidity(uint256 _tier) internal view returns (uint256) {
        return _getTierLiquidity(_tier);
    }

    function _getTierLiquidity(uint256 _tier) internal view returns (uint256) {
        UD60x18 _numberOfPrizeTokenPerShareOutstanding = ud(UD60x18.unwrap(_prizeTokenPerShare) - UD60x18.unwrap(_tierExchangeRates[_tier]));

        return fromUD60x18(_numberOfPrizeTokenPerShareOutstanding.mul(UD60x18.wrap(sharesPerTier*1e18)));
    }

    function _totalShares() internal view returns (uint256) {
        return numberOfTiers * sharesPerTier + canaryShares + reserveShares;
    }

}
