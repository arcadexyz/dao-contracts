// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IArcadeStakingRewards {
    // ================================================= EVENTS ==================================================
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 depositId, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward, uint256 depositId);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);

    // ================================================= STRUCTS =================================================
    enum Lock {
        Short,
        Medium,
        Long
    }

    struct UserStake {
        Lock lock;
        uint32 unlockTimestamp;
        uint256 amount;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
    }

    // ============================================= VIEW FUNCTIONS ==============================================
    function getTotalUserDeposits(address account) external view returns (uint256);

    function getPendingRewards(address account, uint256 depositId) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewardsToken() external view returns (IERC20);

    function totalSupply() external view returns (uint256);

    function getAmountWithBonus(address account, uint256 depositId) external view returns (uint256);

    function getActiveStakes(address account) external view returns (uint256[] memory);

    function getLastDepositId(address account) external view returns (uint256);

    function getDepositIndicesWithRewards() external view returns (uint256[] memory, uint256[] memory);

    function getUserStake(address account, uint256 depositId) external view returns (uint8 lock, uint32 unlockTimestamp, uint256 amount, uint256 rewardPerTokenPaid, uint256 rewards);

    function getTotalUserDepositsWithBonus(address account) external view returns (uint256);

    function balanceOfDeposit(address account, uint256 depositId) external view returns (uint256);

    function getTotalUserPendingRewards(address account) external view returns (uint256);

    function convertLPToArcd(uint256 arcdWethPairAmount) external view returns (uint256);

    // =========================================== MUTATIVE FUNCTIONS ============================================
    function exitAll() external;

    function exit(uint256 depositId) external;

    function claimReward(uint256 depositId) external;

    function claimRewardAll() external;

    function deposit(uint256 amount, address firstDelegation, Lock lock) external;

    function withdraw(uint256 amount, uint256 depositId) external;

    function setRewardsDuration(uint256 _rewardsDuration) external;

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    function pause() external;

    function unpause() external;
}