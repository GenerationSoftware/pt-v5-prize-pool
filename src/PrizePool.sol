// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud, fromUD60x18, toUD60x18 } from "prb-math/UD60x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";

// import { TwabController } from "./interfaces/TwabController.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";

import { DrawAccumulatorLib, Observation } from "./libraries/DrawAccumulatorLib.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";
import { BitLib } from "./libraries/BitLib.sol";

contract PrizePool {

    struct ClaimRecord {
        uint32 drawId;
        uint8 claimedTiers;
    }

    event ClaimedPrize(
        uint32 indexed drawId,
        address indexed vault,
        address indexed winner,
        uint8 tier,
        uint152 payout,
        address to,
        uint96 fee,
        address feeRecipient
    );

    uint8 internal constant MINIMUM_NUMBER_OF_TIERS = 2;

    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS;

    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_2_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_3_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_4_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_5_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_6_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_7_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_8_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_9_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_10_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_11_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_12_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_13_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_14_TIERS;
    UD60x18 immutable internal CANARY_PRIZE_COUNT_FOR_15_TIERS;

    mapping(address => DrawAccumulatorLib.Accumulator) internal vaultAccumulators;

    DrawAccumulatorLib.Accumulator internal totalAccumulator;

    // tier number => tier exchange rate is prizeToken per share
    mapping(uint256 => UD60x18) internal _tierExchangeRates;

    mapping(address => ClaimRecord) internal claimRecords;

    // 160 bits
    IERC20 public immutable prizeToken;

    // 64 bits
    SD1x18 public immutable alpha;

    uint32 public immutable grandPrizePeriodDraws;

    TwabController public immutable twabController;

    uint96 public immutable tierShares;

    uint32 public immutable drawPeriodSeconds;

    // percentage of prizes that must be claimed to bump the number of tiers
    // 64 bits
    UD2x18 public immutable claimExpansionThreshold;

    uint96 public immutable canaryShares;

    uint96 public immutable reserveShares;

    uint256 internal _totalClaimedPrizes;

    UD60x18 public prizeTokenPerShare;

    uint256 public _reserve;

    uint256 public _winningRandomNumber;

    uint8 public numberOfTiers;

    uint32 public claimCount;

    uint32 public canaryClaimCount;

    uint8 public largestTierClaimed;

    uint32 public lastCompletedDrawId;

    uint64 internal lastCompletedlastCompletedDrawStartedAt_;

    // TODO: add requires
    constructor (
        IERC20 _prizeToken,
        TwabController _twabController,
        uint32 _grandPrizePeriodDraws,
        uint32 _drawPeriodSeconds,
        uint64 nextDrawStartsAt_,
        uint8 _numberOfTiers,
        uint96 _tierShares,
        uint96 _canaryShares,
        uint96 _reserveShares,
        UD2x18 _claimExpansionThreshold,
        SD1x18 _alpha
    ) {
        prizeToken = _prizeToken;
        twabController = _twabController;
        grandPrizePeriodDraws = _grandPrizePeriodDraws;
        numberOfTiers = _numberOfTiers;
        tierShares = _tierShares;
        canaryShares = _canaryShares;
        reserveShares = _reserveShares;
        alpha = _alpha;
        claimExpansionThreshold = _claimExpansionThreshold;
        drawPeriodSeconds = _drawPeriodSeconds;
        lastCompletedlastCompletedDrawStartedAt_ = nextDrawStartsAt_;

        require(numberOfTiers >= MINIMUM_NUMBER_OF_TIERS, "num-tiers-gt-1");

        ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS = TierCalculationLib.estimatedClaimCount(2, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS = TierCalculationLib.estimatedClaimCount(3, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS = TierCalculationLib.estimatedClaimCount(4, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS = TierCalculationLib.estimatedClaimCount(5, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS = TierCalculationLib.estimatedClaimCount(6, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS = TierCalculationLib.estimatedClaimCount(7, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS = TierCalculationLib.estimatedClaimCount(8, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS = TierCalculationLib.estimatedClaimCount(9, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS = TierCalculationLib.estimatedClaimCount(10, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS = TierCalculationLib.estimatedClaimCount(11, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS = TierCalculationLib.estimatedClaimCount(12, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS = TierCalculationLib.estimatedClaimCount(13, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS = TierCalculationLib.estimatedClaimCount(14, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS = TierCalculationLib.estimatedClaimCount(15, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS = TierCalculationLib.estimatedClaimCount(16, _grandPrizePeriodDraws);

        CANARY_PRIZE_COUNT_FOR_2_TIERS = TierCalculationLib.canaryPrizeCount(2, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_3_TIERS = TierCalculationLib.canaryPrizeCount(3, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_4_TIERS = TierCalculationLib.canaryPrizeCount(4, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_5_TIERS = TierCalculationLib.canaryPrizeCount(5, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_6_TIERS = TierCalculationLib.canaryPrizeCount(6, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_7_TIERS = TierCalculationLib.canaryPrizeCount(7, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_8_TIERS = TierCalculationLib.canaryPrizeCount(8, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_9_TIERS = TierCalculationLib.canaryPrizeCount(9, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_10_TIERS = TierCalculationLib.canaryPrizeCount(10, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_11_TIERS = TierCalculationLib.canaryPrizeCount(11, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_12_TIERS = TierCalculationLib.canaryPrizeCount(12, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_13_TIERS = TierCalculationLib.canaryPrizeCount(13, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_14_TIERS = TierCalculationLib.canaryPrizeCount(14, _canaryShares, _reserveShares, _tierShares);
        CANARY_PRIZE_COUNT_FOR_15_TIERS = TierCalculationLib.canaryPrizeCount(15, _canaryShares, _reserveShares, _tierShares);
    }

    function getWinningRandomNumber() external view returns (uint256) {
        return _winningRandomNumber;
    }

    function getLastCompletedDrawId() external view returns (uint256) {
        return lastCompletedDrawId;
    }

    function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns(uint256) {
        uint256 _deltaBalance = prizeToken.balanceOf(address(this)) - _accountedBalance();
        require(_deltaBalance >=  _amount, "PP/deltaBalance-gte-amount");
        DrawAccumulatorLib.add(vaultAccumulators[_prizeVault], _amount, lastCompletedDrawId + 1, alpha.intoSD59x18());
        DrawAccumulatorLib.add(totalAccumulator, _amount, lastCompletedDrawId + 1, alpha.intoSD59x18());
        console2.log("contributePrizeTokens lastCompletedDrawId + 1", lastCompletedDrawId + 1);
        return _deltaBalance;
    }

    function _accountedBalance() internal view returns (uint256) {
        Observation memory obs = DrawAccumulatorLib.newestObservation(totalAccumulator);
        return (obs.available + obs.disbursed) - _totalClaimedPrizes;
    }

    function getNextDrawId() external view returns (uint256) {
        return uint256(lastCompletedDrawId) + 1;
    }

    function lastCompletedDrawStartedAt() external view returns (uint64) {
        if (lastCompletedDrawId != 0) {
            return lastCompletedlastCompletedDrawStartedAt_;
        } else {
            return 0;
        }
    }

    function reserve() external view returns (uint256) {
        return _reserve;
    }

    function withdrawReserve(address _to, uint256 _amount) external {
        // NOTE: must make this function privileged
        require(_amount <= _reserve, "insuff");
        _reserve -= _amount;
        prizeToken.transfer(_to, _amount);
    }

    /**
     * Returns the start time of the draw for the next successful completeAndStartNextDraw
     */
    function nextDrawStartsAt() external view returns (uint256) {
        return _nextDrawStartsAt();
    }

    /**
     * Returns the start time of the draw for the next successful completeAndStartNextDraw
     */
    function _nextDrawStartsAt() internal view returns (uint64) {
        if (lastCompletedDrawId != 0) {
            return lastCompletedlastCompletedDrawStartedAt_ + drawPeriodSeconds;
        } else {
            return lastCompletedlastCompletedDrawStartedAt_;
        }
    }

    function completeAndStartNextDraw(uint256 winningRandomNumber_) external returns (uint32) {
        // check winning random number
        require(winningRandomNumber_ != 0, "num invalid");
        uint64 nextDrawStartsAt_ = _nextDrawStartsAt();
        require(block.timestamp >= nextDrawStartsAt_, "not elapsed");

        uint8 numTiers = numberOfTiers;
        uint8 nextNumberOfTiers = numberOfTiers;
        uint256 reclaimedLiquidity;
        // console2.log("completeAndStartNextDraw largestTierClaimed", largestTierClaimed);
        // console2.log("completeAndStartNextDraw numTiers", numTiers);
        // if the draw was eligible
        if (lastCompletedDrawId != 0) {
            if (largestTierClaimed < numTiers) {
                nextNumberOfTiers = largestTierClaimed > MINIMUM_NUMBER_OF_TIERS ? largestTierClaimed+1 : MINIMUM_NUMBER_OF_TIERS;
                reclaimedLiquidity = _reclaimTierLiquidity(numTiers, nextNumberOfTiers);
            } else {
                // check canary tier and standard tiers
                if (canaryClaimCount >= _canaryClaimExpansionThreshold(claimExpansionThreshold, numTiers) &&
                    claimCount >= _prizeClaimExpansionThreshold(claimExpansionThreshold, numTiers)) {
                    // expand the number of tiers
                    // first reset the next tier exchange rate to have accrued nothing (delta is zero)
                    _tierExchangeRates[numTiers] = prizeTokenPerShare;
                    // now increase the number of tiers to include te new tier
                    nextNumberOfTiers = numTiers + 1;
                }
            }
        }
        // add back canary liquidity
        reclaimedLiquidity += _getLiquidity(numTiers, canaryShares);

        _winningRandomNumber = winningRandomNumber_;
        numberOfTiers = nextNumberOfTiers;
        lastCompletedDrawId += 1;
        claimCount = 0;
        canaryClaimCount = 0;
        largestTierClaimed = 0;
        // reset canary tier
        _tierExchangeRates[nextNumberOfTiers] = prizeTokenPerShare;
        lastCompletedlastCompletedDrawStartedAt_ = nextDrawStartsAt_;
        
        (UD60x18 deltaExchangeRate, uint256 remainder) = _computeDrawDeltaExchangeRate(nextNumberOfTiers);
        prizeTokenPerShare = prizeTokenPerShare.add(deltaExchangeRate);

        uint256 _additionalReserve = fromUD60x18(deltaExchangeRate.mul(toUD60x18(reserveShares)));
        // console2.log("completeAndStartNextDraw _additionalReserve", _additionalReserve);
        // console2.log("completeAndStartNextDraw reclaimedLiquidity", reclaimedLiquidity);
        // console2.log("completeAndStartNextDraw remainder", remainder);
        _reserve += _additionalReserve + reclaimedLiquidity + remainder;

        return lastCompletedDrawId;
    }

    function _reclaimTierLiquidity(uint8 _numberOfTiers, uint8 _nextNumberOfTiers) internal view returns (uint256) {
        uint256 reclaimedLiquidity;
        // console2.log("_reclaimTierLiquidity _numberOfTiers", _numberOfTiers);
        // console2.log("_reclaimTierLiquidity _nextNumberOfTiers", _nextNumberOfTiers);
        for (uint8 i = _numberOfTiers - 1; i >= _nextNumberOfTiers; i--) {
            // reclaim the current unclaimed liquidity for that tier
            reclaimedLiquidity += _getLiquidity(i, tierShares);
            // console2.log("_reclaimTierLiquidity reclaimedLiquidity", reclaimedLiquidity);
        }
        return reclaimedLiquidity;
    }

    function _computeDrawDeltaExchangeRate(uint8 _numberOfTiers) internal view returns (UD60x18 deltaExchangeRate, uint256 remainder) {
        return TierCalculationLib.computeNextExchangeRateDelta(_getTotalShares(_numberOfTiers), DrawAccumulatorLib.getAvailableAt(totalAccumulator, lastCompletedDrawId, alpha.intoSD59x18()));
    }

    function _canaryClaimExpansionThreshold(UD2x18 _claimExpansionThreshold, uint8 _numberOfTiers) internal view returns (uint256) {
        return fromUD60x18(_claimExpansionThreshold.intoUD60x18().mul(_canaryPrizeCount(_numberOfTiers).floor()));
    }

    function _prizeClaimExpansionThreshold(UD2x18 _claimExpansionThreshold, uint8 _numberOfTiers) internal view returns (uint256) {
        return fromUD60x18(_claimExpansionThreshold.intoUD60x18().mul(toUD60x18(_estimatedPrizeCount(_numberOfTiers))));
    }

    function totalDrawLiquidity() external view returns (uint256) {
        return fromUD60x18(prizeTokenPerShare.mul(toUD60x18(_getTotalShares(numberOfTiers))));
    }

    function claimPrize(
        address _winner,
        uint8 _tier,
        address _to,
        uint96 _fee,
        address _feeRecipient
    ) external returns (uint256) {
        address _vault = msg.sender;
        uint256 prizeSize;
        if (_isWinner(_vault, _winner, _tier)) {
            // transfer prize to user
            prizeSize = _calculatePrizeSize(_tier);
        } else {
            revert("did not win");
        }
        ClaimRecord memory claimRecord = claimRecords[_winner];
        if (claimRecord.drawId != lastCompletedDrawId) {
            claimRecord = ClaimRecord({drawId: lastCompletedDrawId, claimedTiers: uint8(0)});
        } else if (BitLib.getBit(claimRecord.claimedTiers, _tier)) {
            return 0;
        }
        require(_fee <= prizeSize, "fee too large");
        _totalClaimedPrizes += prizeSize;
        uint256 payout = prizeSize - _fee;
        if (largestTierClaimed < _tier) {
            largestTierClaimed = _tier;
        }
        if (_tier == numberOfTiers) {
            canaryClaimCount++;
        } else {
            claimCount++;
        }
        claimRecords[_winner] = ClaimRecord({drawId: lastCompletedDrawId, claimedTiers: uint8(BitLib.flipBit(claimRecord.claimedTiers, _tier))});
        prizeToken.transfer(_to, payout);
        if (_fee > 0) {
            prizeToken.transfer(_feeRecipient, _fee);
        }
        emit ClaimedPrize(lastCompletedDrawId, _vault, _winner, _tier, uint152(payout), _to, _fee, _feeRecipient);
        return payout;
    }

    /**
    * TODO: check that beaconPeriodStartedAt is the timestamp at which the draw started
    * Add in memory start and end timestamp
    */
    function isWinner(
        address _vault,
        address _user,
        uint8 _tier
    ) external returns (bool) {
        return _isWinner(_vault, _user, _tier);
    }

    /**
    * TODO: check that beaconPeriodStartedAt is the timestamp at which the draw started
    * Add in memory start and end timestamp
    */
    function _isWinner(
        address _vault,
        address _user,
        uint8 _tier
    ) internal returns (bool) {
        require(lastCompletedDrawId > 0, "no draw");
        require(_tier <= numberOfTiers, "invalid tier");

        SD59x18 tierOdds = TierCalculationLib.getTierOdds(_tier, numberOfTiers, grandPrizePeriodDraws);
        uint256 drawDuration = TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriodDraws);
        (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, drawDuration);
        SD59x18 vaultPortion = _getVaultPortion(_vault, lastCompletedDrawId, uint32(drawDuration), alpha.intoSD59x18());
        SD59x18 tierPrizeCount;
        if (_tier == numberOfTiers) { // then canary tier
            tierPrizeCount = sd(int256(_canaryPrizeCount(_tier).unwrap()));
        } else {
            tierPrizeCount = toSD59x18(int256(TierCalculationLib.prizeCount(_tier)));
        }
        return TierCalculationLib.isWinner(_user, _tier, _userTwab, _vaultTwabTotalSupply, vaultPortion, tierOdds, tierPrizeCount, _winningRandomNumber);
    }

    function calculateTierTwabTimestamps(uint8 _tier) external view returns (uint64 startTimestamp, uint64 endTimestamp) {
        uint256 drawDuration = TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriodDraws);
        endTimestamp = lastCompletedlastCompletedDrawStartedAt_ + drawPeriodSeconds;
        startTimestamp = uint64(endTimestamp - drawDuration * drawPeriodSeconds);
    }

    function _getVaultUserBalanceAndTotalSupplyTwab(address _vault, address _user, uint256 _drawDuration) internal view returns (uint256 twab, uint256 twabTotalSupply) {
        {
            uint32 endTimestamp = uint32(lastCompletedlastCompletedDrawStartedAt_ + drawPeriodSeconds);
            uint32 startTimestamp = uint32(endTimestamp - _drawDuration * drawPeriodSeconds);

            twab = twabController.getAverageBalanceBetween(
                _vault,
                _user,
                startTimestamp,
                endTimestamp
            );

            twabTotalSupply = twabController.getAverageTotalSupplyBetween(
                _vault,
                startTimestamp,
                endTimestamp
            );
        }
    }

    function getVaultUserBalanceAndTotalSupplyTwab(address _vault, address _user, uint256 _drawDuration) external view returns (uint256, uint256) {
        return _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, _drawDuration);
    }

    function _getVaultPortion(address _vault, uint32 drawId_, uint32 _durationInDraws, SD59x18 _alpha) internal view returns (SD59x18) {
        uint32 _startDrawIdIncluding = uint32(_durationInDraws > drawId_ ? 0 : drawId_-_durationInDraws+1);
        uint32 _endDrawIdExcluding = drawId_ + 1;
        console2.log("_getVaultPortion _startDrawIdIncluding", _startDrawIdIncluding);
        console2.log("_getVaultPortion _endDrawIdExcluding", _endDrawIdExcluding);
        uint256 vaultContributed = 0;//DrawAccumulatorLib.getDisbursedBetween(vaultAccumulators[_vault], _startDrawIdIncluding, _endDrawIdExcluding, _alpha);
        uint256 totalContributed = 0;//DrawAccumulatorLib.getDisbursedBetween(totalAccumulator, _startDrawIdIncluding, _endDrawIdExcluding, _alpha);
        if (totalContributed != 0) {
            return sd(int256(vaultContributed)).div(sd(int256(totalContributed)));
        } else {
            return sd(0);
        }
    }

    function getVaultPortion(address _vault, uint32 startDrawId, uint32 endDrawId) external view returns (SD59x18) {
        return _getVaultPortion(_vault, startDrawId, endDrawId, alpha.intoSD59x18());
    }

    function calculatePrizeSize(uint8 _tier) external view returns (uint256) {
        return _calculatePrizeSize(_tier);
    }

    function _calculatePrizeSize(uint8 _tier) internal view returns (uint256) {
        if (lastCompletedDrawId == 0) {
            return 0;
        }
        if (_tier < numberOfTiers) {
            return _getLiquidity(_tier, tierShares) / TierCalculationLib.prizeCount(_tier);
        } else if (_tier == numberOfTiers) { // it's the canary tier
            // console2.log("canary liquidity", _getLiquidity(_tier, canaryShares));
            // console2.log("canary prize count", _canaryPrizeCount(_tier).unwrap());
            return fromUD60x18(toUD60x18(_getLiquidity(_tier, canaryShares)).div(_canaryPrizeCount(_tier)));
        } else {
            return 0;
        }
    }

    function getTierLiquidity(uint8 _tier) external view returns (uint256) {
        if (_tier > numberOfTiers) {
            return 0;
        } else if (_tier != numberOfTiers) {
            return _getLiquidity(_tier, tierShares);
        } else {
            return _getLiquidity(_tier, canaryShares);
        }
    }

    function _getLiquidity(uint8 _tier, uint256 _shares) internal view returns (uint256) {
        UD60x18 _numberOfPrizeTokenPerShareOutstanding = ud(UD60x18.unwrap(prizeTokenPerShare) - UD60x18.unwrap(_tierExchangeRates[_tier]));

        return fromUD60x18(_numberOfPrizeTokenPerShareOutstanding.mul(UD60x18.wrap(_shares*1e18)));
    }

    function getTotalShares() external view returns (uint256) {
        return _getTotalShares(numberOfTiers);
    }

    function _getTotalShares(uint8 _numberOfTiers) internal view returns (uint256) {
        return _numberOfTiers * tierShares + canaryShares + reserveShares;
    }

    function estimatedPrizeCount() external view returns (uint32) {
        return _estimatedPrizeCount(numberOfTiers);         
    }
    
    function estimatedPrizeCount(uint8 numTiers) external view returns (uint32) {
        return _estimatedPrizeCount(numTiers);
    }

    function canaryPrizeCountMultiplier(uint8 numTiers) external view returns (UD60x18) {
        return _canaryPrizeCount(numTiers);
    }

    // function canaryPrizeCount() external view returns (uint32) {
    //     return uint32(fromUD60x18(_canaryPrizeCount(numberOfTiers).floor()));
    // }

    // function canaryPrizeCount(uint8 numTiers) external view returns (uint32) {
    //     return uint32(fromUD60x18(_canaryPrizeCount(numTiers).floor()));
    // }

    function _estimatedPrizeCount(uint8 numTiers) internal view returns (uint32) {
        if (numTiers == 2) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS;
        } else if (numTiers == 3) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
        } else if (numTiers == 4) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
        } else if (numTiers == 5) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
        } else if (numTiers == 6) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
        } else if (numTiers == 7) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
        } else if (numTiers == 8) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
        } else if (numTiers == 9) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
        } else if (numTiers == 10) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
        } else if (numTiers == 11) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;
        } else if (numTiers == 12) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS;
        } else if (numTiers == 13) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS;
        } else if (numTiers == 14) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS;
        } else if (numTiers == 15) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS;
        } else if (numTiers == 16) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS;
        }
        return 0;
    }

    function _canaryPrizeCount(uint8 numTiers) internal view returns (UD60x18) {
        if (numTiers == 2) {
            return CANARY_PRIZE_COUNT_FOR_2_TIERS;
        } else if (numTiers == 3) {
            return CANARY_PRIZE_COUNT_FOR_3_TIERS;
        } else if (numTiers == 4) {
            return CANARY_PRIZE_COUNT_FOR_4_TIERS;
        } else if (numTiers == 5) {
            return CANARY_PRIZE_COUNT_FOR_5_TIERS;
        } else if (numTiers == 6) {
            return CANARY_PRIZE_COUNT_FOR_6_TIERS;
        } else if (numTiers == 7) {
            return CANARY_PRIZE_COUNT_FOR_7_TIERS;
        } else if (numTiers == 8) {
            return CANARY_PRIZE_COUNT_FOR_8_TIERS;
        } else if (numTiers == 9) {
            return CANARY_PRIZE_COUNT_FOR_9_TIERS;
        } else if (numTiers == 10) {
            return CANARY_PRIZE_COUNT_FOR_10_TIERS;
        } else if (numTiers == 11) {
            return CANARY_PRIZE_COUNT_FOR_11_TIERS;
        } else if (numTiers == 12) {
            return CANARY_PRIZE_COUNT_FOR_12_TIERS;
        } else if (numTiers == 13) {
            return CANARY_PRIZE_COUNT_FOR_13_TIERS;
        } else if (numTiers == 14) {
            return CANARY_PRIZE_COUNT_FOR_14_TIERS;
        } else if (numTiers == 15) {
            return CANARY_PRIZE_COUNT_FOR_15_TIERS;
        }
        return ud(0);
    }

}
