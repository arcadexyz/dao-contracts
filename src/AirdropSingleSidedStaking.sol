// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./interfaces/IAirdropSingleSidedStaking.sol";
import "./ArcadeSingleSidedStaking.sol";

import { ASS_CallerNotAirdropDistribution } from "../src/errors/SingleSidedStaking.sol";

contract AirdropSingleSidedStaking is IAirdropSingleSidedStaking, ArcadeSingleSidedStaking {
    address public airdropDistribution;

    /**
     * @notice Sets up the contract by initializing the deposit token and the owner.
     *
     * @param _owner                       The address of the contract owner.
     * @param _arcd                        The address of the deposit ERC20 token.
     * @param _airdropDistribution         The address of the airdrop distributor contract.
     */
    constructor(
        address _owner,
        address _arcd,
        address _airdropDistribution
    ) ArcadeSingleSidedStaking(_owner, _arcd) {
        if (address(_airdropDistribution) == address(0)) revert ASS_ZeroAddress("airdropDistribution");

        airdropDistribution = _airdropDistribution;
    }

    modifier onlyAirdropDistribution() {
        if(msg.sender != airdropDistribution) revert ASS_CallerNotAirdropDistribution();
        _;
    }

    /** @notice Receives an airdrop for a specific recipient with a specified amount, delegation,
     *          and lock period. This function is restricted to be called by the airdrop distribution
     *          account only and will call the internal `_deposit` function to handle the token
     *          transfer and voting power allocation.
     *
     * @param recipient                     The address of the user who will receive the airdropped tokens.
     * @param amount                        The amount of tokens that will be airdropped to the user.
     * @param delegation                    The address of the user's delegatee.
     * @param lock                          The lock period for the airdropped tokens.
     */
    function airdropReceive(
        address recipient,
        uint256 amount,
        address delegation,
        Lock lock
    ) external onlyAirdropDistribution {
        _deposit(recipient, amount, delegation, lock);
    }

    /** @notice Sets the airdrop distribution account that is allowed to call `airdropReceive`.
     *
     * @param _airdropDistribution            The address allowed caller.
     */
    function setAirdropDistribution(address _airdropDistribution) external onlyOwner {
        airdropDistribution = _airdropDistribution;

        emit AirdropDistributionSet(_airdropDistribution);
    }
}