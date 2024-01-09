// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./interfaces/IArcadeStakingRewards.sol";
import "./ArcadeRewardsRecipient.sol";

import {
    ASR_ZeroAddress,
    ASR_ZeroAmount,
    ASR_RewardsPeriod,
    ASR_StakingToken,
    ASR_RewardTooHigh,
    ASR_BalanceAmount,
    ASR_InvalidLockValue,
    ASR_NoStake,
    ASR_Locked,
    ASR_RewardsToken,
    ASR_InvalidDepositId
} from "../src/errors/Staking.sol";
import { console } from "forge-std/Test.sol";
/**
 * TODO next:
 * turn pool into voting vault
 * Add README
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
 * Users have the flexibility to make multiple deposits, each accruing
 * rewards separately until the staking period concludes. Upon depositing
 * their tokens for staking, users are required to commit to a lock period
 * where funds are immovable (even if the staking cycle concludes), until
 * the chosen lock period expires. Early withdrawal is not permitted before
 * the locking period is over.
 * Should users choose not to withdraw their funds post the lock period, these
 * funds will seamlessly transition into a subsequent staking cycle. Unlike the
 * initial deposit, these automatically re-staked funds are not bound by a lock
 * period and can be freely withdrawn at any point, even before the current
 * staking cycle concludes.
 *
 * The lock period gives users the opportunity to enhance their reward earnings
 * with a bonus multiplier that is contingent on the duration for which the user
 * chooses to lock their staking tokens. The available lock durations are categorized
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
    IERC20 public immutable rewardsToken;
    IERC20 public immutable stakingToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => UserStake[]) public stakes;

    uint256 public totalDeposits;
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
     * @return userBalance                  The total amount that the user is staking.
     */
    function balanceOf(address account) external view returns (uint256 userBalance) {
        UserStake[] storage userStakes = stakes[account];
        userBalance = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            UserStake storage userStake = userStakes[i];
            userBalance += userStake.amount;
        }
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
             ((((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate) * ONE) / totalDepositsWithBonus);
    }

    /**
     * @notice Returns the amount of reward that an account has earned to date based on their
     *         staking.
     *
     * @param account                         The address of the user that is staking.
     *
     * @return totalEarned                    The total amount of reward token earned.
     * @return rewards                        Array of rewards amounts earned for each deposit.
     */
    function earned(address account) public view returns (uint256 totalEarned, uint256[] memory rewards) {
        rewards = new uint256[](stakes[account].length);

        UserStake[] storage userStakes = stakes[account];
        totalEarned = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            uint256 stakeAmountWithBonus = getAmountWithBonus(account, i);

            UserStake storage userStake = userStakes[i];
            uint256 userRewardPerTokenPaid = userStake.rewardPerTokenPaid;
            uint256 userRewards = userStake.rewards;

            rewards[i] = ((stakeAmountWithBonus * (rewardPerToken() - userRewardPerTokenPaid)) / ONE + userRewards);
            totalEarned += ((stakeAmountWithBonus * (rewardPerToken() - userRewardPerTokenPaid)) / ONE + userRewards);
        }
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
     * @return UserStake                        Array of user's stake structs.
     */
    function getUserStakes(address account) public view returns (UserStake[] memory) {
        return stakes[account];
    }

    /**
     * @notice Gets all of a user's active stakes.
     * @dev This is provided because Solidity converts public arrays into index getters,
     *      but we need a way to allow external contracts and users to access the whole array.

     * @param account                           The user whose stakes to get.
     *
     * @return activeStakes                     Array of id's of user's active stakes.
     */
    function getActiveStakes(address account) public view returns (uint256[] memory) {
        UserStake[] storage userStakes = stakes[account];
        uint256 activeCount = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            UserStake storage userStake = userStakes[i];
            if (userStake.amount > 0) {
                activeCount++;
            }
        }

        uint256[] memory activeStakes = new uint256[](activeCount);
        uint256 activeIndex;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            if (userStakes[i].amount > 0) {
                activeStakes[activeIndex] = i;
                activeIndex++;
            }
        }

        return activeStakes;
    }

    /**
     * @notice Gets all of a user's deposit ids for stakes that are holding a reward.
     *         If the stake is inactive, i.e., userStake.amount == 0, the function
     *         automatically sends the rewards for that deposit to the user.
     *
     * @return rewardedDeposits                 Array of id's of user's stakes holding rewards.
     */
    function getRewardDeposit() public returns (uint256[] memory) {
       uint256[] memory rewards = new uint256[](stakes[msg.sender].length);

        UserStake[] storage userStakes = stakes[msg.sender];
        uint256 rewarded = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            uint256 stakeAmountWithBonus = getAmountWithBonus(msg.sender, i);

            UserStake storage userStake = userStakes[i];
            uint256 userRewardPerTokenPaid = userStake.rewardPerTokenPaid;
            uint256 userRewards = userStake.rewards;

            rewards[i] = ((stakeAmountWithBonus * (rewardPerToken() - userRewardPerTokenPaid)) / ONE + userRewards);

            if (rewards[i] > 0) {
                rewarded++;
            }
        }

        uint256[] memory rewardedDeposits = new uint256[](rewarded);
        uint256 rewardedIndex;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            if (userStakes[i].rewards > 0) {
                rewardedDeposits[rewardedIndex] = i;
                rewardedIndex++;

                if (userStakes[i].amount == 0) {
                    getReward(i);
                }
            }
        }
        return rewardedDeposits;
    }

    /**
     * @notice Gets a user's staked amount reflecting their locking bonus multiplier.
     *
     * @param account                           The user's account.
     *
     * @return amountWithBonus                  Value of user stake with bonus.
     */
    function getAmountWithBonus(address account, uint256 depositId) public view returns (uint256 amountWithBonus) {
        UserStake[] storage userStakes = stakes[account];

        UserStake storage userStake = userStakes[depositId];
        uint256 amount = userStake.amount;
        Lock lock = userStake.lock;

        // Accounting with bonus
        (uint256 bonus,) = _getBonus(lock);
        amountWithBonus = (amount + ((amount * bonus) / ONE));
    }

    // ========================================= MUTATIVE FUNCTIONS ========================================
    /**
     * @notice Allows users to stake their tokens, which are then tracked in the contract. The total
     *         supply of staked tokens and individual user balances are updated accordingly.
     * @dev    Valid lock values are 0 (one 28 day cycle), 1 (two 28 day cycle), and 2 (three 28 day cycle).
     *
     * @param amount                            The amount of tokens the user stakes.
     * @param lock                              The amount of time to lock the stake for.
     */
    function stake(uint256 amount, Lock lock) external nonReentrant whenNotPaused updateReward(msg.sender) {
        if (amount == 0) revert ASR_ZeroAmount();

        // Accounting with bonus
        (uint256 bonus, uint256 lockDuration) = _getBonus(lock);
        uint256 amountWithBonus = amount + ((amount * bonus) / ONE);

        // populate user stake information
        stakes[msg.sender].push(
            UserStake({
                amount: amount,
                unlockTimestamp: uint32(block.timestamp + lockDuration),
                rewardPerTokenPaid: rewardPerTokenStored,
                rewards: 0,
                lock: lock
            })
        );

        totalDeposits += amount;
        totalDepositsWithBonus += amountWithBonus;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, stakes[msg.sender].length - 1, amount);
    }

    /**
     * @notice Allows users to withdraw their staked tokens. The total supply of staked tokens
     *         individual user balances are updated accordingly.
     *
     * @param amount                           The amount of tokens the user withdraws.
     * @param depositId                        The specified deposit to withdraw.
     */
    function withdraw(uint256 amount, uint256 depositId) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ASR_ZeroAmount();
        if (depositId >= stakes[msg.sender].length) revert ASR_InvalidDepositId();

        // Get user's stake
        UserStake storage userStake = stakes[msg.sender][depositId];
        uint256 depositAmount = userStake.amount;

        if (depositAmount == 0) revert ASR_NoStake();
        if (amount > depositAmount) revert ASR_BalanceAmount();
        if (userStake.unlockTimestamp == 0 || block.timestamp < userStake.unlockTimestamp) revert ASR_Locked();

        // Update user stake
        userStake.amount -= amount;

        (uint256 bonus,) = _getBonus(userStake.lock);
        uint256 amountToWithdrawWithBonus = amount + (amount * bonus) / ONE;

        totalDeposits -= amount;
        totalDepositsWithBonus -= amountToWithdrawWithBonus;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Enables the claim of accumulated rewards.
     *
     * @param depositId                        The specified deposit to get the reward for.
     */
    function getReward(uint256 depositId) public nonReentrant updateReward(msg.sender) {
        // Get user's stake
        UserStake storage userStake = stakes[msg.sender][depositId];
        uint256 reward = userStake.rewards;

        if (reward > 0) {
            userStake.rewards = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @notice Allows users to withdraw their staked tokens and claim their rewards
     *         for a specific deposit id, all in one transaction.
     *         Lock period needs to have ended.
     *
     * @param depositId                        The specified deposit to exit.
     */
    function exit(uint256 depositId) external {
        UserStake[] storage userStakes = stakes[msg.sender];
        UserStake storage userStake = userStakes[depositId];

        withdraw(userStake.amount, depositId);
        getReward(depositId);
    }

    /**
     * @notice Allows users to withdraw all their staked tokens and claim their reward tokens
     *         all in one transaction. Lock period needs to have ended.
     */
    function exit() external {
        UserStake[] storage userStakes = stakes[msg.sender];

        for (uint256 i = 0; i < userStakes.length; ++i) {
            // Get user's stake
            UserStake storage userStake = userStakes[i];
            uint256 depositAmount = userStake.amount;

            withdraw(depositAmount, i);
            getReward(i);
        }
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

        if (rewardRate > balance) revert ASR_RewardTooHigh();

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
        if (tokenAddress == address(rewardsToken) && totalDeposits != 0) revert ASR_RewardsToken();
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

        UserStake[] storage userStakes = stakes[account];

        if (account != address(0)) {
            for (uint256 i = 0; i < userStakes.length; ++i) {
                UserStake storage userStake = userStakes[i];
                (, uint256[] memory rewards) = earned(account);

                userStake.rewards = rewards[i];
                userStake.rewardPerTokenPaid = rewardPerTokenStored;
            }
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