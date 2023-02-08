// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { E, SD59x18, sd, unwrap } from "prb-math/SD59x18.sol";

import { ITWABController } from "./interfaces/ITWABController.sol";

import { DrawAccumulatorLib } from "./libraries/DrawAccumulatorLib.sol";

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

    ITWABController immutable public twabController;

    uint64 public immutable grandPrizePeriod;

    // TODO: make internal
    uint256 public immutable sharesPerTier;

    uint256 public immutable canaryShares;

    uint256 public immutable reserveShares;

    mapping(address => DrawAccumulatorLib.Accumulator) internal vaultAccumulators;
    DrawAccumulatorLib.Accumulator internal totalSupplyAccumulator;

    // tier number => tier exchange rate is prizeToken per share
    mapping(uint256 => uint256) internal _tierExchangeRates;

    mapping(address => ClaimRecord) internal claimRecords;

    Draw public draw;

    uint32 public numberOfTiers;

    uint256 public reserve;

    uint256 internal _prizeTokenPerShare;

    uint128 claimCount;
    uint128 canaryClaimCount;

    // TODO: add requires
    constructor (
        IERC20 _prizeToken,
        ITWABController _twabController,
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
        totalSupplyAccumulator.add(_amount, draw.drawId + 1, alpha);
    }

    function getNextDrawId() external view returns (uint256) {
        return uint256(draw.drawId) + 1;
    }

    // TODO: add event
    function setDraw(Draw calldata _nextDraw) external returns (Draw memory) {
        // update _prizeTokenPerShare
        SD59x18 totalShares = sd(int256(_totalShares()));
        uint256 totalContributed = totalSupplyAccumulator.getAvailableAt(draw.drawId, alpha);
        SD59x18 delta = sd(int256(totalContributed)).div(totalShares);
        uint256 remainder = totalContributed - uint256(unwrap(delta.mul(totalShares)));
        _prizeTokenPerShare = _prizeTokenPerShare + uint256(unwrap(delta));
        reserve += remainder;
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
        if (checkIfWonPrize(_vault, _user, _tier)) {
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
    function checkIfWonPrize(
        address _vault,
        address _user,
        uint32 _tier
    ) public returns (bool) {

        uint256 drawDuration = uint256(unwrap(_estimatePrizeFrequencyInDraws(_tier, numberOfTiers).ceil()));

        uint64 endTimestamp = draw.beaconPeriodStartedAt + draw.beaconPeriodSeconds;
        uint64 startTimestamp = uint64(endTimestamp - drawDuration * draw.beaconPeriodSeconds);

        uint256 _userTwab = twabController.balanceOf(
            _vault,
            _user,
            startTimestamp,
            endTimestamp
        );

        uint256 _vaultTwabTotalSupply = twabController.totalSupply(
            _vault,
            startTimestamp,
            endTimestamp
        );

        uint256 vaultContributed = vaultAccumulators[_vault].getAvailableAt(draw.drawId, alpha);
        uint256 totalContributed = totalSupplyAccumulator.getAvailableAt(draw.drawId, alpha);

        // each user gets a different random number
        return _isWinner(_user, _tier, _userTwab, _vaultTwabTotalSupply, vaultContributed, totalContributed);
    }

    function _isWinner(
        address _user,
        uint32 _tier,
        uint256 _userTwab,
        uint256 _vaultTwabTotalSupply,
        uint256 _vaultContributed,
        uint256 _totalContributed
    ) internal view returns (bool) {
        uint256 chunkOffset = uint256(keccak256(abi.encode(_user, _tier, draw.winningRandomNumber))) % (_vaultTwabTotalSupply / _prizeCount(_tier));
        SD59x18 vaultPortion = sd(int256(_vaultContributed)).div(sd(int256(_totalContributed)));
        uint256 _userOdds = uint256(unwrap(_getTierOdds(_tier, numberOfTiers).mul(vaultPortion).mul(sd(int256(_userTwab)))));
        return chunkOffset < _userOdds;
    }

    function _estimatePrizeFrequencyInDraws(uint256 _tier, uint256 _numberOfTiers) internal view returns (SD59x18) {
        return sd(1).div(_getTierOdds(_tier, _numberOfTiers));
    }

    function _getTierOdds(uint256 _tier, uint256 _numberOfTiers) internal view returns (SD59x18) {
        SD59x18 _k = sd(1).div(
            sd(int256(uint256(grandPrizePeriod)))
        ).ln().div(
            sd(-1 * int256(_numberOfTiers) + 1)
        );

        return E.pow(_k.mul(sd(int256(_tier) - (int256(_numberOfTiers) - 1))));
    }

    function calculatePrizeSize(uint256 _tier) public view returns (uint256) {
        return _getTierLiquidity(_tier) / _prizeCount(_tier);
    }

    function _getTierLiquidity(uint256 _tier) internal view returns (uint256) {
        uint256 _numberOfPrizeTokenPerShareOutstanding = _prizeTokenPerShare - _tierExchangeRates[_tier];

        return _numberOfPrizeTokenPerShareOutstanding * sharesPerTier;
    }

    function _prizeCount(uint256 _tier) internal pure returns (uint256) {
        uint256 _numberOfPrizes = 4 ** _tier;

        return _numberOfPrizes;
    }

    function _totalShares() internal view returns (uint256) {
        return numberOfTiers * sharesPerTier + canaryShares + reserveShares;
    }

    function estimatedClaimCount() public view returns (uint256) {
        uint256 count = 0;
        uint256 _numberOfTiers = numberOfTiers;
        for (uint32 i = 0; i < _numberOfTiers; i++) {
            count += uint256(unwrap(sd(int256(_prizeCount(i))).mul(_getTierOdds(i, _numberOfTiers))));
        }
        return count;
    }
}
