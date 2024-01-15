// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IArcadeStakingRewards {
    // ================================================= EVENTS ==================================================
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 depositId, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);

    // ================================================= STRUCTS =================================================
    enum Lock {
        Short,
        Medium,
        Long,
        Invalid // added for testing purposes
    }

    struct UserStake {
        Lock lock;
        uint32 unlockTimestamp;
        uint256 amount;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
    }

    // ============================================= VIEW FUNCTIONS ==============================================
    function balanceOf(address account) external view returns (uint256);

    function earned(address account, uint256 depositId) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewardsToken() external view returns (IERC20);

    function totalSupply() external view returns (uint256);

    function getAmountWithBonus(address account, uint256 depositId) external view returns (uint256);

    function getActiveStakes(address account) external view returns (uint256[] memory);

    function getUserStakes(address account) external view returns (UserStake[] memory);

    function getDepositIndicesWithRewards() external view returns (uint256[] memory, uint256[] memory);

    // =========================================== MUTATIVE FUNCTIONS ============================================
    function exitAll() external;

    function exit(uint256 depositId) external;

    function claimReward(uint256 depositId) external;

    function claimRewardAll() external;

    function stake(uint256 amount, Lock lock) external;

    function withdraw(uint256 amount, uint256 depositId) external;

    function setRewardsDuration(uint256 _rewardsDuration) external;

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
}