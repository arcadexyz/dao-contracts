// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./interfaces/IArcadeStakingRewards.sol";
import "./ArcadeRewardsRecipient.sol";
import { Test } from "forge-std/Test.sol";
import {
    ASR_ZeroAddress,
    ASR_ZeroAmount,
    ASR_RewardsPeriod,
    ASR_StakingToken,
    ASR_RewardTooBig,
    ASR_BalanceAmount,
    ASR_InvalidLockValue,
    ASR_NoStake,
    ASR_Locked
} from "../src/errors/Staking.sol";

/**
 * TODO in next sprint:
 * support for locking multiple deposits
 * turn pool into voting vault
 * README
 */

/**
 * @title ArcadeStakingRewards
 * @author Non-Fungible Technologies, Inc.
 *
 * The ArcadeStakingRewards contract is a fork of the Synthetix StakingRewards
 * contract.
 * https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
 *
 * The contract manages a staking mechanism where users can stake the ERC20 stakingToken
 * and earn rewards over time, paid in the ERC20 rewardsToken.  Rewards are earned based
 * on the amount of stakingToken staked and the length of time staked.
 *
 * A user has the opportunity to enhance their reward earnings by opting for
 * a bonus multiplier that is contingent on the duration for which the user
 * locks their staking tokens. The available lock durations are categorized
 * as short, medium, and long. Each category is associated with a progressively
 * increasing multiplier, with the short duration offering the smallest and
 * the long duration offering the largest.
 * When a user decides to lock their staking tokens for one of these durations,
 * their total reward is calculated as:
 * (the user's staked amount * multiplier for the chosen duration) + original
 * staked amount.
 * This boosts the user's rewards in proportion to both the amount staked and
 * the duration of the stake.
 */

contract ArcadeStakingRewards is IArcadeStakingRewards, ArcadeRewardsRecipient, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============================================ STATE ==============================================
    // ============== Constants ==============

    uint256 public constant ONE = 1e18;
    uint256 public constant ONE_CYCLE = 60 * 60 * 24 * 30; // 30 days
    uint256 public constant TWO_CYCLE = ONE_CYCLE * 2;
    uint256 public constant THREE_CYCLE = ONE_CYCLE * 3;

    uint256 public immutable SHORT_BONUS;
    uint256 public immutable MEDIUM_BONUS;
    uint256 public immutable LONG_BONUS;

    uint256 public immutable SHORT_LOCK_TIME;
    uint256 public immutable MEDIUM_LOCK_TIME;
    uint256 public immutable LONG_LOCK_TIME;

    // ============ Global State =============
    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => UserStake) public stakes;

    uint256 private totalDeposits;
    uint256 public totalDepositsWithBonus;

    // ========================================== CONSTRUCTOR ===========================================
    /**
     * @notice Sets up the contract by initializing the staking and rewards tokens,
     *         and setting the owner and rewards distribution addresses.
     *
     * @param _owner                       The address of the contract owner.
     * @param _rewardsDistribution         The address of the entity setting the rules
     *                                     of how rewards are distributed.
     * @param _rewardsToken                The address of the rewards ERC20 token.
     * @param _stakingToken                The address of the staking ERC20 token.
     * @param shortLockTime                The short lock time.
     * @param mediumLockTime               The medium lock time.
     * @param longLockTime                 The long lock time.
     * @param shortBonus                   The bonus multiplier for the short lock time.
     * @param mediumBonus                  The bonus multiplier for the medium lock time.
     * @param longBonus                    The bonus multiplier for the long lock time.
     */
    constructor(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        uint256 shortLockTime,
        uint256 mediumLockTime,
        uint256 longLockTime,
        uint256 shortBonus,
        uint256 mediumBonus,
        uint256 longBonus
    ) Ownable(_owner) {
        if (address(_rewardsDistribution) == address(0)) revert ASR_ZeroAddress();
        if (address(_rewardsToken) == address(0)) revert ASR_ZeroAddress();
        if (address(_stakingToken) == address(0)) revert ASR_ZeroAddress();
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;

        SHORT_BONUS = shortBonus;
        MEDIUM_BONUS = mediumBonus;
        LONG_BONUS = longBonus;

        SHORT_LOCK_TIME = shortLockTime;
        MEDIUM_LOCK_TIME = mediumLockTime;
        LONG_LOCK_TIME = longLockTime;
    }

    // ========================================== VIEW FUNCTIONS =========================================
    /**
     * @notice Returns the total amount of staking tokens held in the contract.
     *
     * @return uint256                     The amount of staked tokens.
     */
    function totalSupply() external view returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice Returns the amount of staking tokens staked by a user account.
     *
     * @param account                       The address of the account.
     *
     * @return uint256                      The amount that the user is staking.
     */
    function balanceOf(address account) external view returns (uint256) {
        UserStake storage userStake = stakes[account];

        return uint256(userStake.amount);
    }

    /**
     * @notice Returns the last timestamp at which rewards can be calculated and
     *         be accounted for.
     *
     * @return uint256                       The timestamp record after which rewards
     *                                       can no longer be calculated.
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Returns the amount of reward token earned per staked token.
     *
     * @return uint256                        The reward token amount per staked token.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalDepositsWithBonus == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored +
             ((((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate) * 1e18) / totalDepositsWithBonus);
    }

    /**
     * @notice Returns the amount of reward that an account has earned to date based on their
     *         staking.
     *
     * @param account                         The address of the user that is staking.
     *
     * @return uint256                        The amount of reward token earned.
     */
    function earned(address account) public view returns (uint256) {
        UserStake storage userStake = stakes[account];
        uint256 stakeAmountWithBonus = userStake.amountWithBonus;
        uint256 userRewardPerTokenPaid = userStake.rewardPerTokenPaid;
        uint256 userRewards = userStake.rewards;

        return (stakeAmountWithBonus * (rewardPerToken() - userRewardPerTokenPaid)) / 1e18 + userRewards;
    }

    /**
     * @notice Returns the amount of reward distributable over the current reward period.
     *
     * @return uint256                         The amount of reward token that is distributable.
     */
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /**
     * @notice Gets all of a user's stakes.
     * @dev This is provided because Solidity converts public arrays into index getters,
     *      but we need a way to allow external contracts and users to access the whole array.

     * @param account                           The user whose stakes to get.
     *
     * @return UserStake                        User's stake struct.
     */
    function getUserStakes(address account) public view returns (UserStake memory) {
        return stakes[account];
    }

    // ========================================= MUTATIVE FUNCTIONS ========================================
    /**
     * @notice Allows users to stake their tokens, which are then tracked in the contract. The total
     *         supply of staked tokens and individual user balances are updated accordingly.
     * @dev    Valid lock values are 0 (one 28 day cycle), 1 (two 28 day cycle), and 2 (three 28 day cycle).
     *
     * @param amount                           The amount of tokens the user stakes.
     * @param lock                             The amount of time to lock the stake for.
     */
    function stake(uint256 amount, Lock lock) external nonReentrant whenNotPaused updateReward(msg.sender) {
        if (amount == 0) revert ASR_ZeroAmount();

        // Accounting with bonus
        (uint256 bonus, uint256 lockDuration) = _getBonus(lock);
        uint256 amountWithBonus = amount + ((amount * bonus) / ONE);

         // populate user stake information
        stakes[msg.sender] = UserStake({
            amount: uint112(amount),
            amountWithBonus: uint112(amountWithBonus),
            unlockTimestamp: uint32(block.timestamp + lockDuration),
            rewardPerTokenPaid: uint112(rewardPerTokenStored),
            rewards: 0,
            lock: lock
        });

        totalDeposits += amount;
        totalDepositsWithBonus += amountWithBonus;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Allows users to withdraw their staked tokens. The total supply of staked tokens
     *         individual user balances are updated accordingly.
     *
     * @param amount                           The amount of tokens the user withdraws.
     */
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ASR_ZeroAmount();

        // Get user's stake
        UserStake storage userStake = stakes[msg.sender];
        uint256 depositAmount = userStake.amount;

        if (depositAmount == 0) revert ASR_NoStake();
        if (amount > depositAmount) revert ASR_BalanceAmount();
        if (userStake.unlockTimestamp == 0 || block.timestamp < userStake.unlockTimestamp) revert ASR_Locked();

        uint256 depositAmountCast = uint256(depositAmount) - amount;
        // Update user stake
        userStake.amount = uint112(depositAmountCast);

        (uint256 bonus,) = _getBonus(userStake.lock);
        uint256 amountToWithdrawWithBonus = amount + (amount * bonus) / ONE;
        userStake.amountWithBonus -= uint112(amountToWithdrawWithBonus);

        totalDeposits -= amount;
        totalDepositsWithBonus -= amountToWithdrawWithBonus;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Enables the claim of accumulated rewards.
     */
    function getReward() public nonReentrant updateReward(msg.sender) {
        // Get user's stake
        UserStake storage userStake = stakes[msg.sender];
        uint256 reward = userStake.rewards;

        if (reward > 0) {
            userStake.rewards = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @notice Allows users to withdraw their staked tokens and claim their reward tokens
     *         all in one transaction.
     */
    function exit() external {
        // Get user's stake
        UserStake storage userStake = stakes[msg.sender];
        uint256 depositAmount = userStake.amount;

        withdraw(depositAmount);
        getReward();
    }

    // ======================================== RESTRICTED FUNCTIONS =========================================
    /**
     * @notice Notifies the contract of new rewards available for distribution and adjusts the
     *         rewardRate rate at which rewards will be distributed to the users to over the remaining
     *         duration of the reward period.
     *         Can only be called by the rewardsDistribution address.
     *
     * @param reward                            The amount of new reward tokens.
     */
    function notifyRewardAmount(uint256 reward) external override onlyRewardsDistribution updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        if (rewardRate > (balance / rewardsDuration)) revert ASR_RewardTooBig();

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardAdded(reward);
    }

    /**
     * @notice Allows the contract owner to recover ERC20 tokens locked in the contract.
     *         Added to support recovering rewards from other systems such as BAL, to be
     *         distributed to holders.
     *
     * @param tokenAddress                       The address of the token to recover.
     * @param tokenAmount                        The amount of token to recover.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(stakingToken)) revert ASR_StakingToken();
        if (tokenAddress == address(0)) revert ASR_ZeroAddress();
        if (tokenAmount == 0) revert ASR_ZeroAmount();

        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);

        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice An only owner function to set the duration of the rewards period. The previous
     *         rewards period must be complete before a new duration can be set.
     *
     * @param _rewardsDuration                    The amount of time the rewards period will be.
     */
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        if (block.timestamp <= periodFinish) revert ASR_RewardsPeriod();

        rewardsDuration = _rewardsDuration;

        emit RewardsDurationUpdated(rewardsDuration);
    }

    // ============================================== HELPERS ===============================================
    /**
     * @notice Updates the reward calculation for a user before executing any transaction such as
     *         staking, withdrawing, or reward claiming, to ensure the correct calculation of
     *         rewards for the user.
     *
     * @param account                              The address of the user account to update the
     *                                             reward calculation for.
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            // Get user's stake
            UserStake storage userStake = stakes[msg.sender];
            userStake.rewards = uint112(earned(account));
            userStake.rewardPerTokenPaid = uint112(rewardPerTokenStored);
        }
        _;
    }

    /**
     * @dev Maps Lock enum values to corresponding lengths of time and reward bonuses.
     */
    function _getBonus(Lock _lock) internal view returns (uint256 bonus, uint256 lockDuration) {
        if (_lock == Lock.Short) {
            return (SHORT_BONUS, SHORT_LOCK_TIME);
        } else if (_lock == Lock.Medium) {
            return (MEDIUM_BONUS, MEDIUM_LOCK_TIME);
        } else if (_lock == Lock.Long) {
            return (LONG_BONUS, LONG_LOCK_TIME);
        } else {
            revert ASR_InvalidLockValue(uint256(_lock));
        }
    }
}