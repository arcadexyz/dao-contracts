// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import { ASR_ZeroAddress } from "../src/errors/Staking.sol";

abstract contract ArcadeRewardsRecipient is Ownable {
    address public rewardsDistribution;

    constructor(address _rewardsDistribution) {
        if (address(_rewardsDistribution) == address(0)) revert ASR_ZeroAddress("rewardsDistribution");

        rewardsDistribution = _rewardsDistribution;
    }

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }

    function notifyRewardAmount(uint256 reward) external virtual;

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }
}