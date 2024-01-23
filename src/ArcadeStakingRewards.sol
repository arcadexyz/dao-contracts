// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./external/LockingVault.sol";

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
    ASR_InvalidDepositId,
    ASR_DepositCountExceeded
} from "../src/errors/Staking.sol";

/**
 * TODO next:
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
 *
 * In the exitAll() and claimRewardAll() external functions, it's necessary to
 * limit the number of iterations processed within these functions' loops to
 * prevent exceeding the block gas limit. Because of this, the contract enforces
 * a hard limit on the number deposits a user can have per wallet address and
 * consequently on the number of iterations that can be processed in a single
 * transaction. This limit is defined by the MAX_IDEPOSITS state variable.
 * Should a user necessitate making more than the MAX_DEPOSITS  number
 * of stakes, they will be required to use a different wallet address.
 */

contract ArcadeStakingRewards is ERC20, ERC20Burnable, IArcadeStakingRewards, ArcadeRewardsRecipient, LockingVault, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============================================ STATE ==============================================
    // ============== Constants ==============
    uint256 public constant ONE = 1e18;
    uint256 public constant MAX_DEPOSITS = 20;

    uint256 public immutable SHORT_BONUS;
    uint256 public immutable MEDIUM_BONUS;
    uint256 public immutable LONG_BONUS;

    uint256 public immutable SHORT_LOCK_TIME;
    uint256 public immutable MEDIUM_LOCK_TIME;
    uint256 public immutable LONG_LOCK_TIME;

    // ============ Global State =============
    IERC20 public immutable rewardsToken;
    IERC20 public immutable stakingToken;
    ERC20 public immutable trackingToken;
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
     * @param tokenName                    The full name of the ERC20 token.
     * @param tokenSymbol                  The symbol abbreviation of the ERC20 token.
     */
    constructor(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _trackingToken,
        uint256 shortLockTime,
        uint256 mediumLockTime,
        uint256 longLockTime,
        uint256 shortBonus,
        uint256 mediumBonus,
        uint256 longBonus,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) Ownable(_owner) LockingVault(ERC20(_trackingToken), staleBlockLag) {
        if (address(_rewardsDistribution) == address(0)) revert ASR_ZeroAddress();
        if (address(_rewardsToken) == address(0)) revert ASR_ZeroAddress();
        if (address(_stakingToken) == address(0)) revert ASR_ZeroAddress();
        if (address(_trackingToken) == address(0)) revert ASR_ZeroAddress();
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        trackingToken = ERC20(_trackingToken);
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
    function totalPoolDeposits() external view returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice Returns the amount of staking tokens staked by a user account.
     *
     * @param account                       The address of the account.
     *
     * @return userBalance                  The total amount that the user is staking.
     */
    function getTotalUserDeposits(address account) external view returns (uint256 userBalance) {
        UserStake[] storage userStakes = stakes[account];
        userBalance = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            UserStake storage userStake = userStakes[i];
            userBalance += userStake.amount;
        }
    }

    /**
     * @notice Returns the amount of staking tokens staked in a specific deposit.
     *
     * @param account                       The address of the account.
     * @param depositId                     The specified deposit to get the balance of.
     *
     * @return depositBalance               The total amount staked in the deposit.
     */
    function balanceOfDeposit(address account, uint256 depositId) external view returns (uint256) {
        UserStake[] storage userStakes = stakes[account];
        UserStake storage userStake = userStakes[depositId];

        uint256 depositBalance = userStake.amount;

        return depositBalance;
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

        uint256 timePassed = lastTimeRewardApplicable() - lastUpdateTime;
        uint256 durationRewards = timePassed * rewardRate;
        uint256 updatedRewardsPerToken = (durationRewards * ONE) / totalDepositsWithBonus;

        return rewardPerTokenStored + updatedRewardsPerToken;
    }

    /**
     * @notice Returns the reward amount for a deposit.
     *
     * @param account                         The address of the user that is staking.
     * @param depositId                       The specified deposit to get the reward for.
     *
     * @return rewards                        Rewards amounts earned for each deposit.
     */
    function getPendingRewards(address account, uint256 depositId) public view returns (uint256) {
        UserStake[] storage userStakes = stakes[account];
        UserStake storage userStake = userStakes[depositId];

        uint256 stakeAmountWithBonus = getAmountWithBonus(account, depositId);

        uint256 userRewardPerTokenPaid = userStake.rewardPerTokenPaid;
        uint256 userRewards = userStake.rewards;

        uint256 rewards = ((stakeAmountWithBonus * (rewardPerToken() - userRewardPerTokenPaid)) / ONE + userRewards);

        return rewards;
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
     * @notice Returns information about a deposit.

     * @param account                           The user whose stakes to get.
     * @param depositId                         The specified deposit to get.
     *
     * @return lock                             Lock period committed.
     * @return unlockTimestamp                  Timestamp marking the end of the lock period.
     * @return amount                           Amount staked.
     * @return rewardPerTokenPaid               Reward per token accounted for.
     * @return rewards                          Amount of rewards accrued.
     */
    function getUserStake(address account, uint256 depositId) external view returns (uint8 lock, uint32 unlockTimestamp, uint256 amount, uint256 rewardPerTokenPaid, uint256 rewards) {
        UserStake[] storage userStakes = stakes[account];
        UserStake storage userStake = userStakes[depositId];

        lock = uint8(userStake.lock);
        unlockTimestamp = userStake.unlockTimestamp;
        amount = userStake.amount;
        rewardPerTokenPaid = userStake.rewardPerTokenPaid;
        rewards = userStake.rewards;
    }

    /**
     * @notice Gives the current depositId, equivalent to userStakes.length.
     *
     * @param account                           The user whose stakes to get.
     *
     * @return lastDepositId                    Id of the last stake.
     */
    function getLastDepositId(address account) public view returns (uint256) {
        uint256 lastDepositId = stakes[account].length - 1;

        return lastDepositId;
    }

    /**
     * @notice Gets all of a user's active stakes.
     *
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
     *         Also gets the amount of rewards for each deposit.
     *
     * @return rewardedDeposits                 Array of id's of user's stakes holding
     *                                          rewards.
     * @return rewardsArray                     Array of user's rewards.
     */
    function getDepositIndicesWithRewards() public view returns (uint256[] memory, uint256[] memory) {
       uint256[] memory rewards = new uint256[](stakes[msg.sender].length);

        UserStake[] storage userStakes = stakes[msg.sender];
        uint256 rewarded = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            uint256 stakeAmountWithBonus = getAmountWithBonus(msg.sender, i);
            if (stakeAmountWithBonus == 0) continue;

            UserStake storage userStake = userStakes[i];
            uint256 userRewardPerTokenPaid = userStake.rewardPerTokenPaid;
            uint256 userRewards = userStake.rewards;

            rewards[i] = ((stakeAmountWithBonus * (rewardPerToken() - userRewardPerTokenPaid)) / ONE + userRewards);

            if (rewards[i] > 0) {
                rewarded++;
            }
        }

        uint256[] memory rewardedDeposits = new uint256[](rewarded);
        uint256[] memory rewardAmounts = new uint256[](rewarded);
        uint256 rewardedIndex = 0;

        for (uint256 i = 0; i < rewards.length; ++i) {
            if (rewards[i] > 0) {
                rewardedDeposits[rewardedIndex] = i;
                rewardAmounts[rewardedIndex] = rewards[i];
                rewardedIndex++;
            }
        }

        return (rewardedDeposits, rewardAmounts);
    }

    /**
     * @notice Returns just the "amount with bonus" for a deposit, which is not stored
     *         in the struct
     *
     * @param account                           The user's account.
     * @param depositId                         The specified deposit to get the amount
     *                                          with bonus for.
     *
     * @return amountWithBonus                  Value of user stake with bonus.
     */
    function getAmountWithBonus(address account, uint256 depositId) public view returns (uint256) {
        UserStake[] storage userStakes = stakes[account];

        UserStake storage userStake = userStakes[depositId];
        uint256 amount = userStake.amount;
        Lock lock = userStake.lock;

        // Accounting with bonus
        (uint256 bonus,) = _getBonus(lock);
        uint256 amountWithBonus = (amount + ((amount * bonus) / ONE));

        return amountWithBonus;
    }

    /**
     * @notice Get pending reward for user deposits, not stored in struct.
     *
     * @param account                           The user's account.
     *
     * @return totalRewards                     Value of a user's rewards across all deposits.
     */
    function getTotalUserPendingRewards(address account) external view returns (uint256) {
        UserStake[] storage userStakes = stakes[account];
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            totalRewards += getPendingRewards(account, i);
        }

        return totalRewards;
    }

    /**
     * @notice Get all user's deposits with their bonuses.
     *
     * @param account                           The user's account.
     *
     * @return totalRewards                     Value of a user's rewards across all deposits.
     */
    function getTotalUserDepositsWithBonus(address account) public view returns (uint256) {
        UserStake[] storage userStakes = stakes[account];
        uint256 totalDepositsWithBonuses = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            totalDepositsWithBonuses += getAmountWithBonus(account, i);
        }

        return totalDepositsWithBonuses;
    }


    // ========================================= MUTATIVE FUNCTIONS ========================================
    /**
     * @notice Allows users to stake their tokens, which are then tracked in the contract. The total
     *         supply of staked tokens and individual user balances are updated accordingly.
     * @dev    Valid lock values are 0 (one 28 day cycle), 1 (two 28 day cycle), and 2 (three 28 day cycle).
     *
     * @param amount                            The amount of tokens the user stakes.
     * @param lock                              The amount of time to lock the stake for.
     * @param firstDelegation                   The address to delegate voting power to.
     */
    function stake(uint256 amount, Lock lock, address firstDelegation) external nonReentrant whenNotPaused updateReward {
        if (amount == 0) revert ASR_ZeroAmount();

        if ((stakes[msg.sender].length + 1) > MAX_DEPOSITS) revert ASR_DepositCountExceeded();

        // Accounting with bonus
        (uint256 bonus, uint256 lockDuration) = _getBonus(lock);
        uint256 amountWithBonus = amount + ((amount * bonus) / ONE);

        // mint tracking tokens equal to amountWithBonus on user behalf
        _mint(address(this), amountWithBonus);
        // lock the tracking tokens into the governance vault for vote power delegation
        this.deposit(msg.sender, amountWithBonus, firstDelegation);

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
     * @notice Allows users to do partial token withdraws for specific deposits.
     *         The total supply of staked tokens and individual user balances
     *         are updated accordingly.
     *
     * @param amount                           The amount of tokens the user withdraws.
     * @param depositId                        The specified deposit to withdraw.
     */
    function withdrawFromStake(uint256 amount, uint256 depositId) public nonReentrant updateReward {
        if (amount == 0) revert ASR_ZeroAmount();
        if (depositId >= stakes[msg.sender].length) revert ASR_InvalidDepositId();

        (uint256 withdrawAmount, uint256 reward) = _calculateWithdrawalAndReward(msg.sender, amount, depositId);

        UserStake storage userStake = stakes[msg.sender][depositId];
        Lock lock = userStake.lock;
        // Accounting with bonus
        (uint256 bonus,) = _getBonus(lock);
        uint256 trackingWithdrawAmount = (amount + ((amount * bonus) / ONE));
        this.withdraw(trackingWithdrawAmount, msg.sender);

        if (withdrawAmount > 0) {
            stakingToken.safeTransfer(msg.sender, withdrawAmount);
        }

        if (reward > 0) {
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward, depositId);
        }
    }

    /**
     * @notice Enables the claim of accumulated rewards.
     *
     * @param depositId                        The specified deposit to get the reward for.
     */
    function claimReward(uint256 depositId) public nonReentrant updateReward {
        uint256 reward = 0;

        reward = _claimReward(depositId);

        if (reward > 0) {
            rewardsToken.safeTransfer(msg.sender, reward);
        }
    }

    /**
     * @notice Enables the claim of all accumulated rewards in one transaction.
     */
    function claimRewardAll() external nonReentrant updateReward {
        UserStake[] storage userStakes = stakes[msg.sender];
        uint256 totalReward = 0;

        for (uint256 i = 0; i < userStakes.length; ++i) {
            totalReward += _claimReward(i);
        }

        if (totalReward > 0) {
            rewardsToken.safeTransfer(msg.sender, totalReward);
        }
    }

    /**
     * @notice Allows users to withdraw staked tokens and claim their rewards
     *         for a specific deposit id, all in one transaction.
     *         Lock period needs to have ended.
     *
     * @param depositId                        The specified deposit to exit.
     */
    function exit(uint256 depositId) external {
        if (depositId >= stakes[msg.sender].length) revert ASR_InvalidDepositId();

        UserStake storage userStake = stakes[msg.sender][depositId];
        uint256 amount = userStake.amount;

        withdrawFromStake(amount, depositId);
    }

    /**
     * @notice Allows users to withdraw all their staked tokens and claim their reward tokens
     *         all in one transaction. Lock period needs to have ended.
     */
    function exitAll() public nonReentrant updateReward {
        UserStake[] storage userStakes = stakes[msg.sender];
        uint256 totalWithdrawAmount = 0;
        uint256 totalRewardAmount = 0;

        uint256 votePower = getTotalUserDepositsWithBonus(msg.sender);
        this.withdraw(votePower, msg.sender);

        for (uint256 i = 0; i < userStakes.length; ++i) {
            UserStake storage userStake = userStakes[i];
            uint256 depositAmount = userStake.amount;

            if (depositAmount == 0 || block.timestamp < userStake.unlockTimestamp) continue;

            (uint256 withdrawAmount, uint256 reward) = _withdraw(msg.sender, depositAmount, i);
            totalWithdrawAmount += withdrawAmount;
            totalRewardAmount += reward;

            if (reward > 0) {
                emit RewardPaid(msg.sender, reward, i);
            }
        }

        if (totalWithdrawAmount > 0) {
            stakingToken.safeTransfer(msg.sender, totalWithdrawAmount);
        }

        if (totalRewardAmount > 0) {
            rewardsToken.safeTransfer(msg.sender, totalRewardAmount);
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
    function notifyRewardAmount(uint256 reward) external override onlyRewardsDistribution updateReward {
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
     * @notice Updates the global reward counter.
     */
    modifier updateReward {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        _;
    }

    /**
     * @notice Withdraws staked tokens that are unlocked.
     *
     * @param depositId                        The specified deposit to get the reward for.
     * @param amount                           The amount to be withdrawn.
     * @param user                             The account whose stake is being withdrawn.
     *
     * @return amountToWithdraw                The staked amount which will be withdrawn.
     * @return reward                          The reward amount which will be withdrawn.
     */
    function _withdraw(address user, uint256 amount, uint256 depositId) internal returns (uint256 amountToWithdraw, uint256 reward) {
        UserStake storage userStake = stakes[user][depositId];
        amountToWithdraw = amount;

        _updateRewardForDeposit(user, depositId);

        // Update user stake
        userStake.amount -= amount;

        reward = userStake.rewards;
        userStake.rewards = 0;

        (uint256 bonus,) = _getBonus(userStake.lock);
        uint256 amountToWithdrawWithBonus = amount + (amount * bonus) / ONE;

        totalDeposits -= amount;
        totalDepositsWithBonus -= amountToWithdrawWithBonus;

        emit Withdrawn(user, amount);

        return (amountToWithdraw, reward);
    }

    /**
     * @notice Claim accumulated rewards.
     *
     * @param depositId                        The specified deposit to get the reward for.
     *
     * @return reward                          The reward amount claimed.
     */
    function _claimReward(uint256 depositId) internal returns (uint256 reward) {
        UserStake storage userStake = stakes[msg.sender][depositId];

        _updateRewardForDeposit(msg.sender, depositId);

        reward = userStake.rewards;

        if (reward > 0) {
            userStake.rewards = 0;
            emit RewardPaid(msg.sender, reward, depositId);
        }

        return reward;
    }

    /**
     * @notice Updates the reward calculation for a user before executing any transaction such as
     *         staking, withdrawing, or reward claiming, to ensure the correct calculation of
     *         rewards for the user.
     *
     * @param account                              The address of the user account to update the
     *                                             reward calculation for.
     * @param depositId                            The specified deposit id to update the reward for.
     */
    function _updateRewardForDeposit(address account, uint256 depositId) internal {
        UserStake storage userStake = stakes[account][depositId];
        if (userStake.amount == 0) return;

        uint256 earnedReward = getPendingRewards(account, depositId);
        userStake.rewards += earnedReward;
        userStake.rewardPerTokenPaid = rewardPerTokenStored;
    }

    /**
     * @notice Calculates stake amount to withdraw and reward amount to claim.
     *
     * @param user                             The account to make the calculations for.
     * @param amount                           The amount of tokens the being withdrawn.
     * @param depositId                        The user's specified deposit id.
     *
     * @return withdrawAmount                  The staked amount which will be withdrawn.
     * @return reward                          The reward amount which will be withdrawn.
     */
    function _calculateWithdrawalAndReward(address user, uint256 amount, uint256 depositId) internal returns (uint256, uint256) {
        UserStake storage userStake = stakes[user][depositId];
        uint256 depositAmount = userStake.amount;

        if (depositAmount == 0) revert ASR_NoStake();
        if (amount > depositAmount) revert ASR_BalanceAmount();
        if (block.timestamp < userStake.unlockTimestamp) revert ASR_Locked();

        (uint256 withdrawAmount, uint256 reward) = _withdraw(user, amount, depositId);

        return (withdrawAmount, reward);
    }

    /**
     * @dev Maps Lock enum values to corresponding lengths of time and reward bonuses.
     *
     * @param _lock                            The lock value.
     *
     * @return bonus                           The bonus amount associated with the lock.
     * @return lockDuration                    The amount of time that the stake will be locked.
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