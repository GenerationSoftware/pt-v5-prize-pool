// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, IERC4626 } from "openzeppelin/token/ERC20/extensions/ERC4626.sol";

import { PrizePool, ConstructorParams } from "./PrizePool.sol";

/**
 * @title  PoolTogether V5 Prize PrizePool Factory
 * @author PoolTogether Inc. & G9 Software Inc.
 * @notice Factory contract for deploying new Prize Pool contracts
 */
contract PrizePoolFactory {
    /* ============ Events ============ */

    /**
     * @notice Emitted when a new PrizePool has been deployed by this factory.
     * @param prizePool The prizePool that was deployed
     */
    event NewPrizePool(
        PrizePool indexed prizePool
    );

    /* ============ Variables ============ */

    /// @notice List of all prizePools deployed by this factory.
    PrizePool[] public allPrizePools;

    /// @notice Mapping to verify if a PrizePool has been deployed via this factory.
    mapping(address prizePool => bool deployedByFactory) public deployedPrizePools;

    /// @notice Mapping to store deployer nonces for CREATE2
    mapping(address deployer => uint256 nonce) public deployerNonces;

    /* ============ External Functions ============ */

    /**
     * @notice Deploy a new prizePool
     * @dev `claimer` can be set to address zero if none is available yet.
     * @param _params Params struct for the Prize Pool configuration
     * @return PrizePool The newly deployed PrizePool
     */
    function deployPrizePool(
      ConstructorParams memory _params
    ) external returns (PrizePool) {
        PrizePool _prizePool = new PrizePool{
            salt: keccak256(abi.encode(msg.sender, deployerNonces[msg.sender]++))
        }(
            _params
        );

        allPrizePools.push(_prizePool);
        deployedPrizePools[address(_prizePool)] = true;

        emit NewPrizePool(
            _prizePool
        );

        return _prizePool;
    }

    function computePrizePoolAddress(
        ConstructorParams memory _params
    ) external view returns (address) {
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            keccak256(abi.encode(msg.sender, deployerNonces[msg.sender])),
            keccak256(abi.encodePacked(
                type(PrizePool).creationCode,
                abi.encode(_params)
            ))
        )))));
    }

    /**
     * @notice Total number of prizePools deployed by this factory.
     * @return uint256 Number of prizePools deployed by this factory.
     */
    function totalPrizePools() external view returns (uint256) {
        return allPrizePools.length;
    }
}
