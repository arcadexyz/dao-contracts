// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "openzeppelin-contracts-v5/contracts/access/Ownable.sol";

abstract contract ArcadeRewardsRecipient is Ownable {
    address public rewardsDistribution;

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }
}
