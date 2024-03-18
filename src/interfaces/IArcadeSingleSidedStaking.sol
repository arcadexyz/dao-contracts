// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IArcadeSingleSidedStaking {
    // ================================================= EVENTS ==================================================
    event RewardAdded(uint256 reward);
    event Deposited(address indexed user, uint256 depositId, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward, uint256 depositId);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event VoteChange(address indexed from, address indexed to, int256 amount);
    event RewardEmissionActivated(uint256 rewardAmount, uint256 rewardEnd);

    // ================================================= STRUCTS =================================================
    enum Lock {
        Short,
        Medium,
        Long
    }

    struct UserDeposit {
        Lock lock;
        uint32 unlockTimestamp;
        uint256 amount;
    }

    // ============================================= VIEW FUNCTIONS ==============================================
    function getTotalUserDeposits(address account) external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getDepositBonus(address account, uint256 depositId) external view returns (uint256);

    function getActiveDeposits(address account) external view returns (uint256[] memory);

    function getLastDepositId(address account) external view returns (uint256);

    function getUserDeposit(address account, uint256 depositId) external view returns (uint8 lock, uint32 unlockTimestamp, uint256 amount);

    function balanceOfDeposit(address account, uint256 depositId) external view returns (uint256);

    // =========================================== MUTATIVE FUNCTIONS ============================================
    function exitAll() external;

    function exit(uint256 depositId) external;

    function deposit(uint256 amount, address firstDelegation, Lock lock) external;

    function withdraw(uint256 amount, uint256 depositId) external;

    function setRewardsDuration(uint256 _rewardsDuration) external;

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    function pause() external;

    function unpause() external;
}