// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./external/council/interfaces/IVotingVault.sol";
import "./external/council/libraries/History.sol";
import "./external/council/libraries/Storage.sol";

import "./interfaces/IArcadeStakingRewards.sol";
import "./ArcadeRewardsRecipient.sol";

import {
    ASR_ZeroAddress,
    ASR_ZeroAmount,
    ASR_RewardsPeriod,
    ASR_StakingToken,
    ASR_RewardTooHigh,
    ASR_BalanceAmount,
    ASR_Locked,
    ASR_RewardsToken,
    ASR_DepositCountExceeded,
    ASR_ZeroConversionRate,
    ASR_UpperLimitBlock,
    ASR_InvalidDelegationAddress,
    ASR_MinimumRewardAmount,
    ASR_ZeroRewardRate,
    ASR_AmountTooBig
} from "../src/errors/Staking.sol";

/**
 * @title ArcadeStakingRewards
 * @author Non-Fungible Technologies, Inc.
 *
 * @notice To optimize gas usage, unlockTimeStamp in struct UserStake is stored in
 *         uint32 format. This limits timestamp support to dates before 03:14:07 UTC on
 *         19 January 2038. Any time beyond this point will cause an overflow.
 *
 * The ArcadeStakingRewards contract is a fork of the Synthetix StakingRewards
 * contract.
 * https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
 *
 * The contract manages a staking mechanism where users can stake the ERC20 ARCD/WETH pair
 * token and earn rewards over time, paid in the ERC20 rewardsToken.  Rewards are earned
 * based on the amount of ARCD/WETH staked and the length of time staked.
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
 * transaction. This limit is defined by the MAX_DEPOSITS state variable.
 * Should a user necessitate making more than the MAX_DEPOSITS  number
 * of stakes, they will be required to use a different wallet address.
 *
 * The locking pool gives users governance capabilities by also serving as a
 * voting vault. When users stake, they gain voting power. They can use this voting
 * power to vote in ArcadeDAO governance. The voting power is automatically accrued
 * to their account and is delegated to their chosen delegatee's address on their
 * behalf without the need for them to call any additional transaction.
 * The ArcadeStakingRewards contract governance functionality is adapted from the
 * LockingVault deployment at:
 * https://etherscan.io/address/0x7a58784063D41cb78FBd30d271F047F0b9156d6e#code
 *
 * Once a user makes their initial stake, the voting power for any future stakes will
 * need to be delegated to the same address as the initial stake. To assign a
 * different delegate, users are required to use the changeDelegate() function.
 *
 * A user's voting power is determined by the quantity of ARCD/WETH pair tokens
 * they have staked. To calculate this voting power, an ARCD/WETH to ARCD
 * conversion rate is set in the contract at deployment and cannot be updated.
 * The user's ARCD amount is a product of their deposited ARCD/WETH amount and
 * the conversion rate.
 * The resulting ARCD value is then enhanced by the lock bonus multiplier, the
 * user has selected at the time of their token deposit.
 */

contract ArcadeStakingRewards is IArcadeStakingRewards, ArcadeRewardsRecipient, IVotingVault, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Bring library into scope
    using History for History.HistoricalBalances;

    // ============================================ STATE ==============================================
    // ============== Constants ==============
    uint256 public constant ONE = 1e18;
    uint256 public constant ONE_DAY = 1 days;
    uint256 public constant MAX_DEPOSITS = 20;
    uint256 public constant LP_TO_ARCD_DENOMINATOR = 1e3;

    uint256 public constant SHORT_BONUS = 11e17;
    uint256 public constant MEDIUM_BONUS = 13e17;
    uint256 public constant LONG_BONUS = 15e17;

    uint256 public constant SHORT_LOCK_TIME = ONE_DAY * 30; // one month
    uint256 public constant MEDIUM_LOCK_TIME = ONE_DAY * 60; // two months
    uint256 public constant LONG_LOCK_TIME = ONE_DAY * 90; // three months

    // ============ Global State =============
    uint256 public immutable LP_TO_ARCD_RATE;
    IERC20 public immutable rewardsToken;
    IERC20 public immutable arcdWethLP;

    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardsDuration = ONE_DAY * 30 * 6; // six months
    uint256 public notifiedRewardAmount;
    uint256 public rewardPerTokenStored;
    uint256 public rewardRate;

    mapping(address => UserStake[]) public stakes;

    uint256 public totalDeposits;
    uint256 public totalDepositsWithBonus;
    uint256 public unclaimedRewards;

    // ========================================== CONSTRUCTOR ===========================================
    /**
     * @notice Sets up the contract by initializing the staking and rewards tokens,
     *         and setting the owner and rewards distribution addresses.
     *
     * @param _owner                       The address of the contract owner.
     * @param _rewardsDistribution         The address of the entity setting the rules
     *                                     of how rewards are distributed.
     * @param _rewardsToken                The address of the rewards ERC20 token.
     * @param _arcdWethLP                  The address of the staking ERC20 token.
     * @param _lpToArcdRate                Immutable ARCD/WETH to ARCD conversion rate.
     */
    constructor(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _arcdWethLP,
        uint256 _lpToArcdRate
    ) Ownable(_owner) ArcadeRewardsRecipient(_rewardsDistribution) {
        if (address(_rewardsToken) == address(0)) revert ASR_ZeroAddress("rewardsToken");
        if (address(_arcdWethLP) == address(0)) revert ASR_ZeroAddress("arcdWethLP");
        if (_lpToArcdRate == 0) revert ASR_ZeroConversionRate();

        rewardsToken = IERC20(_rewardsToken);
        arcdWethLP = IERC20(_arcdWethLP);
        LP_TO_ARCD_RATE = _lpToArcdRate;
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
    function getTotalUserDeposits(address account) external view returns (uint256 userBalance) {
        UserStake[] storage userStakes = stakes[account];

        uint256 numUserStakes = userStakes.length;
        for (uint256 i = 0; i < numUserStakes; ++i) {
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
    function balanceOfDeposit(address account, uint256 depositId) external view returns (uint256 depositBalance) {
        depositBalance = stakes[account][depositId].amount;
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
     * @return uint256                        Unclaimed rewards.
     */
    function rewardPerToken() public view returns (uint256, uint256) {
        if (totalDepositsWithBonus == 0) {
            return (rewardPerTokenStored, unclaimedRewards);
        }

        uint256 timePassed = lastTimeRewardApplicable() - lastUpdateTime;
        uint256 durationRewards = timePassed * rewardRate;
        uint256 updatedRewardsPerToken = (durationRewards * ONE) / totalDepositsWithBonus;

        return (rewardPerTokenStored + updatedRewardsPerToken, unclaimedRewards + durationRewards);
    }

    /**
     * @notice Returns the reward amount for a deposit.
     *
     * @param account                         The address of the user that is staking.
     * @param depositId                       The specified deposit to get the reward for.
     *
     * @return rewards                        Rewards amounts earned for each deposit.
     */
    function getPendingRewards(address account, uint256 depositId) external view returns (uint256 rewards) {
        UserStake storage userStake = stakes[account][depositId];

        rewards = _getPendingRewards(userStake);
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
    function getUserStake(address account, uint256 depositId) external view returns (
        uint8 lock,
        uint32 unlockTimestamp,
        uint256 amount,
        uint256 rewardPerTokenPaid,
        uint256 rewards)
    {
        UserStake storage userStake = stakes[account][depositId];

        lock = uint8(userStake.lock);
        unlockTimestamp = userStake.unlockTimestamp;
        amount = userStake.amount;
        rewardPerTokenPaid = userStake.rewardPerTokenPaid;
        rewards = _getPendingRewards(userStake);
    }

    /**
     * @notice Gives the current depositId, equivalent to userStakes.length.
     *
     * @param account                           The user whose stakes to get.
     *
     * @return lastDepositId                    Id of the last stake.
     */
    function getLastDepositId(address account) external view returns (uint256 lastDepositId) {
        lastDepositId = stakes[account].length - 1;
    }

    /**
     * @notice Gets all of a user's active stakes.
     *
     * @param account                           The user whose stakes to get.
     *
     * @return activeStakes                     Array of id's of user's active stakes.
     */
    function getActiveStakes(address account) external view returns (uint256[] memory) {
        UserStake[] storage userStakes = stakes[account];
        uint256 activeCount = 0;

        uint256 numUserStakes = userStakes.length;
        for (uint256 i = 0; i < numUserStakes; ++i) {
            UserStake storage userStake = userStakes[i];
            if (userStake.amount > 0) {
                activeCount++;
            }
        }

        uint256[] memory activeStakes = new uint256[](activeCount);
        uint256 activeIndex;

        for (uint256 i = 0; i < numUserStakes; ++i) {
            if (userStakes[i].amount > 0) {
                activeStakes[activeIndex++] = i;
            }
        }

        return activeStakes;
    }

    /**
     * @notice Gets all of a user's deposit ids for stakes that are holding a reward.
     *         Also gets the amount of rewards for each deposit.
     *
     * @param account                           The user whose deposit indices to get.
     *
     * @return rewardedDeposits                 Array of id's of user's stakes holding
     *                                          rewards.
     * @return rewardsArray                     Array of user's rewards.
     */
    function getDepositIndicesWithRewards(address account) external view returns (uint256[] memory, uint256[] memory) {
        UserStake[] storage userStakes = stakes[account];
        uint256 numUserStakes = userStakes.length;
        uint256[] memory rewards = new uint256[](numUserStakes);
        uint256 rewarded = 0;

        (uint256 updatedRewardPerToken,) = rewardPerToken();

        for (uint256 i = 0; i < numUserStakes; ++i) {
            UserStake storage userStake = userStakes[i];
            uint256 stakeAmountWithBonus = _getAmountWithBonus(userStake);
            if (stakeAmountWithBonus == 0) continue;

            uint256 userRewardPerTokenPaid = userStake.rewardPerTokenPaid;

            rewards[i] = ((stakeAmountWithBonus * (updatedRewardPerToken - userRewardPerTokenPaid)) / ONE);

            if (rewards[i] > 0) {
                rewarded++;
            }
        }

        uint256[] memory rewardedDeposits = new uint256[](rewarded);
        uint256[] memory rewardAmounts = new uint256[](rewarded);
        uint256 rewardedIndex = 0;

        uint256 numRewards = rewards.length;
        for (uint256 i = 0; i < numRewards; ++i) {
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
    function getAmountWithBonus(address account, uint256 depositId) external view returns (uint256 amountWithBonus) {
        UserStake storage userStake = stakes[account][depositId];

        amountWithBonus = _getAmountWithBonus(userStake);
    }

    /**
     * @notice Get pending reward for user deposits, not stored in struct.
     *
     * @param account                           The user's account.
     *
     * @return totalRewards                     Value of a user's rewards across all deposits.
     */
    function getTotalUserPendingRewards(address account) external view returns (uint256 totalRewards) {
        UserStake[] storage userStakes = stakes[account];

        uint256 numUserStakes = userStakes.length;
        for (uint256 i = 0; i < numUserStakes; ++i) {
            UserStake storage userStake = userStakes[i];
            totalRewards += _getPendingRewards(userStake);
        }
    }

    /**
     * @notice Get all user's deposits with their bonuses.
     *
     * @param account                           The user's account.
     *
     * @return totalDepositsWithBonuses         Value of a user's deposits with bonuses across all deposits.
     */
    function getTotalUserDepositsWithBonus(address account) external view returns (uint256 totalDepositsWithBonuses) {
        UserStake[] storage userStakes = stakes[account];

        uint256 numUserStakes = userStakes.length;
        for (uint256 i = 0; i < numUserStakes; ++i) {
            UserStake storage userStake = userStakes[i];
            totalDepositsWithBonuses += _getAmountWithBonus(userStake);
        }
    }

    /**
     * @notice Converts the user's staked LP token value to an ARCD token amount based on the
     *         immutable rate set in this contract.
     *
     * @param arcdWethLPAmount                  The LP token amount to use for the conversion.
     *
     * @return uint256                          Value of ARCD.
     */
    function convertLPToArcd(uint256 arcdWethLPAmount) public view returns (uint256) {
        return (arcdWethLPAmount * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;
    }

    // ========================================= MUTATIVE FUNCTIONS ========================================
    /**
     * @notice Allows users to stake their tokens, which are then tracked in the contract. The total
     *         supply of staked tokens and individual user balances are updated accordingly.
     *
     * @param amount                           The amount of tokens the user wishes to deposit and stake.
     * @param delegation                       The address to which the user's voting power will be delegated.
     * @param lock                             The locking period for the staked tokens.
     */
    function deposit(
        uint256 amount,
        address delegation,
        Lock lock
    ) external nonReentrant whenNotPaused updateReward {
        if (amount == 0) revert ASR_ZeroAmount();
        if (delegation == address(0)) revert ASR_ZeroAddress("delegation");

        uint256 userStakeCount = stakes[msg.sender].length;
        if (userStakeCount >= MAX_DEPOSITS) revert ASR_DepositCountExceeded();

        (uint256 amountWithBonus, uint256 lockDuration)  = _calculateBonus(amount, lock);

        uint256 votingPowerToAdd = convertLPToArcd(amount);

        // update the vote power to equal the amount staked with bonus
        _addVotingPower(msg.sender, votingPowerToAdd, delegation);

        // populate user stake information
        stakes[msg.sender].push(
            UserStake({
                amount: amount,
                unlockTimestamp: uint32(block.timestamp + lockDuration),
                rewardPerTokenPaid: rewardPerTokenStored,
                lock: lock
            })
        );

        totalDeposits += amount;
        totalDepositsWithBonus += amountWithBonus;

        arcdWethLP.safeTransferFrom(msg.sender, address(this), amount);

        // if this is the first stake and the reward amount is notified, begin
        // reward emissions
        if (notifiedRewardAmount > 0) {
            _startRewardEmission(notifiedRewardAmount);
        }

        emit Staked(msg.sender, userStakeCount, amount);
    }

    /**
     * @notice Enables the claim of accumulated rewards.
     *
     * @param depositId                        The specified deposit to get the reward for.
     */
    function claimReward(uint256 depositId) external whenNotPaused nonReentrant updateReward {
        UserStake storage userStake = stakes[msg.sender][depositId];
        if (userStake.amount == 0) revert ASR_BalanceAmount();

        uint256 reward = _getPendingRewards(userStake);

        _processReward(userStake, reward);
    }

    /**
     * @notice Enables the claim of all accumulated rewards in one transaction.
     */
    function claimRewardAll() external whenNotPaused nonReentrant updateReward {
        UserStake[] storage userStakes = stakes[msg.sender];
        uint256 totalReward = 0;

        uint256 numUserStakes = userStakes.length;
        for (uint256 i = 0; i < numUserStakes; ++i) {
            UserStake storage userStake = userStakes[i];

            uint256 reward = _getPendingRewards(userStake);
            totalReward += reward;

            if (reward > 0) {
                userStake.rewardPerTokenPaid = rewardPerTokenStored;

                emit RewardPaid(msg.sender, reward, i);
            }
        }

        if (totalReward > 0) {
            unclaimedRewards -= totalReward;
            rewardsToken.safeTransfer(msg.sender, totalReward);
        }
    }

    /**
     * @notice Withdraws staked tokens that are unlocked.  Allows for partial withdrawals.
     *
     * @param depositId                        The specified deposit to get the reward for.
     * @param amount                           The amount to be withdrawn from the user stake.
     */
    function withdraw(uint256 amount, uint256 depositId) public whenNotPaused nonReentrant updateReward {
        if (amount == 0) revert ASR_ZeroAmount();
        UserStake storage userStake = stakes[msg.sender][depositId];
        if (userStake.amount == 0) revert ASR_BalanceAmount();
        if (block.timestamp < userStake.unlockTimestamp) revert ASR_Locked();

        if (amount > userStake.amount) amount = userStake.amount;

        (uint256 amountWithBonus, ) = _calculateBonus(amount, userStake.lock);
        uint256 votePowerToSubtract = convertLPToArcd(amount);

        _subtractVotingPower(votePowerToSubtract, msg.sender);

        uint256 reward = _getPendingRewards(userStake);

        userStake.amount -= amount;

        totalDeposits -= amount;
        totalDepositsWithBonus -= amountWithBonus;

        _processReward(userStake, reward);

        arcdWethLP.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Allows users to withdraw staked tokens and claim their rewards
     *         for a specific deposit id, all in one transaction.
     *         Lock period needs to have ended.
     *
     * @param depositId                        The specified deposit to exit.
     */
    function exit(uint256 depositId) external {
        withdraw(type(uint256).max, depositId);
    }

    /**
     * @notice Allows users to withdraw all their staked tokens and claim their reward
     *         tokens all in one transaction. Lock period needs to have ended.
     */
    function exitAll() external whenNotPaused nonReentrant updateReward {
        UserStake[] storage userStakes = stakes[msg.sender];
        uint256 totalWithdrawAmount = 0;
        uint256 totalRewardAmount = 0;
        uint256 totalVotingPower = 0;
        uint256 amountWithBonusToSubtract = 0;
        uint256 numUserStakes = userStakes.length;

        for (uint256 i = 0; i < numUserStakes; ++i) {
            UserStake storage userStake = userStakes[i];
            uint256 amount = userStake.amount;
            if (amount == 0 || block.timestamp < userStake.unlockTimestamp) continue;

            (uint256 amountWithBonus, ) = _calculateBonus(amount, userStake.lock);
            uint256 votePowerToSubtract = convertLPToArcd(amount);

            uint256 reward = _getPendingRewards(userStake);

            userStake.amount -= amount;

            amountWithBonusToSubtract += amountWithBonus;
            totalVotingPower += votePowerToSubtract;
            totalWithdrawAmount += amount;
            totalRewardAmount += reward;

            if (reward > 0) {
                userStake.rewardPerTokenPaid = rewardPerTokenStored;

                emit RewardPaid(msg.sender, reward, i);
            }
        }

        if (totalVotingPower > 0) {
            _subtractVotingPower(totalVotingPower, msg.sender);
        }

        if (amountWithBonusToSubtract > 0) {
            totalDepositsWithBonus -= amountWithBonusToSubtract;
        }

        if (totalWithdrawAmount > 0) {
            totalDeposits -= totalWithdrawAmount;
            arcdWethLP.safeTransfer(msg.sender, totalWithdrawAmount);
        }

        if (totalRewardAmount > 0) {
            unclaimedRewards -= totalRewardAmount;
            rewardsToken.safeTransfer(msg.sender, totalRewardAmount);
        }
    }

    // ======================================== RESTRICTED FUNCTIONS =========================================
    /**
     * @notice Notifies the contract of new rewards available for distribution. Reward emissions is delayed
     *         until the first user stakes.
     *         Can only be called by the rewardsDistribution address.
     *
     * @dev To avoid rounding errors, the notified reward amount is adjusted to be divisible by the
     *      rewardsDuration if necessary. This rounding down will evenutally result in an amount of
     *      "leftover" rewards not being distributed.  The leftover amount will need to be periodically
     *       recovered by the owner at times when the pool is not active.
     *
     *
     * @param reward                            The amount of new reward tokens.
     */
    function notifyRewardAmount(uint256 reward) external override whenNotPaused onlyRewardsDistribution updateReward {
        if (reward < ONE) revert ASR_MinimumRewardAmount();

        // check that the reward is divisible by the rewardsDuration
        // to avoid rounding errors
        uint256 remainder = reward % rewardsDuration;

        if (remainder > 0) {
            reward -= remainder;
        }

        if (totalDeposits > 0) {
            _startRewardEmission(reward);
        } else {
            notifiedRewardAmount += reward;
        }

        emit RewardAdded(reward);
    }

    /**
     * @notice Allows the contract owner to recover ERC20 tokens locked in the contract.
     *         Reward tokens can be recovered only if the total staked amount is zero.
     *
     * @param tokenAddress                       The address of the token to recover.
     * @param tokenAmount                        The amount of token to recover.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(arcdWethLP)) revert ASR_StakingToken();
        if (tokenAddress == address(rewardsToken) && totalDeposits != 0) revert ASR_RewardsToken();
        if (tokenAddress == address(0)) revert ASR_ZeroAddress("token");
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
    function setRewardsDuration(uint256 _rewardsDuration) external whenNotPaused onlyOwner {
        if (block.timestamp <= periodFinish) revert ASR_RewardsPeriod();

        rewardsDuration = _rewardsDuration;

        emit RewardsDurationUpdated(rewardsDuration);
    }

    /**
     * @notice Pauses the contract, callable by only the owner. Reversible.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, callable by only the owner. Reversible.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================== HELPERS ===============================================
    /**
     * @notice Updates the global reward counter.
     */
    modifier updateReward {
        (rewardPerTokenStored, unclaimedRewards) = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        _;
    }

    /**
     * @notice Triggers reward emissions when the first user stakes and if there is a reward amount.
     *         Adjusts the rewardRate rate at which rewards will be distributed to users to over the
     *         remaining duration of the reward period.
     *
     * @param reward                            The amount of reward tokens to distribute.
     */
    function _startRewardEmission(uint256 reward) private {
        uint256 leftover;

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));

        if (reward + leftover + unclaimedRewards > balance) revert ASR_RewardTooHigh();

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        notifiedRewardAmount = 0;

        emit RewardEmissionActivated(reward, periodFinish);
    }

    /**
     * @notice Handles the updating of the reward state of a specific stake and transfers
     *         the reward amount to the staker.
     *
     * @param userStake                         The user's stake object.
     * @param reward                            The reward amount.
     */
    function _processReward(UserStake storage userStake, uint256 reward) internal {
        if (reward > 0) {
            unclaimedRewards -= reward;

            userStake.rewardPerTokenPaid = rewardPerTokenStored;
            rewardsToken.safeTransfer(msg.sender, reward);

            emit RewardPaid(msg.sender, reward, stakes[msg.sender].length - 1);
        }
    }

    /**
     * @notice Calculates the total amount for a user's stake including the bonus based on
     *         the stake's lock period.
     *
     * @param userStake                         The user's stake object.
     *
     * @return amountWithBonus                  The total amount including the bonus.
     */
    function _getAmountWithBonus(UserStake storage userStake) internal view returns (uint256 amountWithBonus) {
        uint256 amount = userStake.amount;
        Lock lock = userStake.lock;

        (amountWithBonus, ) = _calculateBonus(amount, lock);
    }


    /**
     * @notice Calculates the pending rewards of a user's stake.
     *
     * @param userStake                         The user's stake object.
     *
     * @return rewards                          The amount of user rewards.
     */
    function _getPendingRewards(UserStake storage userStake) internal view returns (uint256 rewards) {
        uint256 stakeAmountWithBonus = _getAmountWithBonus(userStake);

        uint256 userRewardPerTokenPaid = userStake.rewardPerTokenPaid;
        (uint256 updatedRewardPerToken,) = rewardPerToken();

        rewards = ((stakeAmountWithBonus * (updatedRewardPerToken - userRewardPerTokenPaid)) / ONE);
    }

    /**
     * @notice Calculate the bonus for a user's stake.
     *
     * @param amount                            The stake amount.
     * @param lock                              The lock period committed.
     *
     * @return bonusAmount                      The bonus value of of the.
     */
    function _calculateBonus(uint256 amount, Lock lock) internal pure returns (uint256 bonusAmount, uint256 lockDuration) {
        uint256 bonus;

        if (lock == Lock.Short) {
           bonus = SHORT_BONUS;
           lockDuration = SHORT_LOCK_TIME;
        } else if (lock == Lock.Medium) {
            bonus = MEDIUM_BONUS;
            lockDuration = MEDIUM_LOCK_TIME;
        } else if (lock == Lock.Long) {
            bonus = LONG_BONUS;
            lockDuration = LONG_LOCK_TIME;
        }

        bonusAmount = amount + (amount * bonus) / ONE;
    }

    /**
     * @notice This internal function adapted from the external withdraw function from the LockingVault
     *         contract, with a key modification: it omits the token transfer transaction. This
     *         is because the tokens are already present within the vault. Additionally, the function
     *         adds an address account parameter to specify the user whose voting power needs updating.
     *         In the Locking Vault  msg.sender directly indicated the user, wheras in this
     *         context msg.sender refers to the contract itself. Therefore, we explicitly pass the
     *         user's address.
     *
     * @param amount                           The amount of token to withdraw.
     * @param account                          The funded account for the withdrawal.
     */
    function _subtractVotingPower(uint256 amount, address account) internal {
        if (amount > type(uint96).max) revert ASR_AmountTooBig();

        // Load our deposits storage
        Storage.AddressUint storage userData = _deposits()[account];

        // Reduce the user's stored balance
        // If properly optimized this block should result in 1 sload 1 store
        userData.amount -= uint96(amount);
        address delegate = userData.who;

        // Reduce the delegate voting power
        // Get the storage pointer
        History.HistoricalBalances memory votingPower = _votingPower();
        // Load the most recent voter power stamp
        uint256 delegateeVotes = votingPower.loadTop(delegate);
        // remove the votes from the delegate
        votingPower.push(delegate, delegateeVotes - amount);
        // Emit an event to track votes
        emit VoteChange(account, delegate, -1 * int256(amount));
    }

    /**
     * @notice This internal function is adapted from the external deposit function from the LockingVault
     *         contract, with 2 key modification: it omits the token transfer transaction and reverts if the
     *         specified delegation address does not align with the user's previously designated delegate.
     *
     * @param fundedAccount                    The address to credit this deposit to.
     * @param amount                           The amount of token which is deposited.
     * @param delegation                       Delegation address.
     */
    function _addVotingPower(
        address fundedAccount,
        uint256 amount,
        address delegation
    ) internal {
        if (amount > type(uint96).max) revert ASR_AmountTooBig();
        // No delegating to zero
        if (delegation == address(0)) revert ASR_ZeroAddress("delegation");

        // Load our deposits storage
        Storage.AddressUint storage userData = _deposits()[fundedAccount];
        // Load who has the user's votes
        address delegate = userData.who;

        if (delegate == address(0)) {
            // If the user is un-delegated we delegate to their indicated address
            delegate = delegation;
            // Set the delegation
            userData.who = delegate;
        } if (delegation != delegate) {
            revert ASR_InvalidDelegationAddress();
        }
        // Now we increase the user's balance
        userData.amount += uint96(amount);

        // Next we increase the delegation to their delegate
        // Get the storage pointer
        History.HistoricalBalances memory votingPower = _votingPower();
        // Load the most recent voter power stamp
        uint256 delegateeVotes = votingPower.loadTop(delegate);
        // Emit an event to track votes
        emit VoteChange(fundedAccount, delegate, int256(amount));
        // Add the newly deposited votes to the delegate
        votingPower.push(delegate, delegateeVotes + amount);
    }

    /**
     * @notice This function is taken from the LockingVault contract. It is a single endpoint
     *        for loading storage for deposits.
     *
     * @return                                  A storage mapping which can be used to look
     *                                          up deposit data.
     */
    function _deposits()
        internal
        pure
        returns (mapping(address => Storage.AddressUint) storage)
    {
        // This call returns a storage mapping with a unique non overwrite-able storage location
        // which can be persisted through upgrades, even if they change storage layout
        return (Storage.mappingAddressToPackedAddressUint("deposits"));
    }

    /**
     * @notice This function is taken from the LockingVault contract. Returns the historical
     *         voting power tracker.
     *
     *
     * @return                                  A struct which can push to and find items in
     *                                          block indexed storage.
     */
    function _votingPower()
        internal
        pure
        returns (History.HistoricalBalances memory)
    {
        // This call returns a storage mapping with a unique non overwrite-able storage location
        // which can be persisted through upgrades, even if they change storage layout
        return (History.load("votingPower"));
    }

    /**
     * @notice This function is taken from the LockingVault contract. Attempts to load the voting
     *         power of a user.
     *         It is revised to no longer remove stale blocks from the queue, to address the problem
     *         of gas depletion encountered with overly long queues.
     *
     * @param user                              The address we want to load the voting power of.
     * @param blockNumber                       The block number we want the user's voting power at.
     *
     * @return                                  The number of votes.
     */
    function queryVotePower(
        address user,
        uint256 blockNumber,
        bytes calldata
    ) external override returns (uint256) {
        return this.queryVotePowerView(user, blockNumber);
    }

    /**
     * @notice This function is taken from the LockingVault contract. Loads the voting power of a
     *         user without changing state.
     *
     * @param user                              The address we want to load the voting power of.
     * @param blockNumber                       The block number we want the user's voting power at.
     *
     * @return                                  The number of votes.
     */
    function queryVotePowerView(address user, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        // Get our reference to historical data
        History.HistoricalBalances memory votingPower = _votingPower();
        // Find the historical datum
        return votingPower.find(user, blockNumber);
    }

    /**
     * @notice This function is taken from the LockingVault contract, it changes a user's voting power.
     *
     * @param newDelegate                        The new address which gets voting power.
     */
    function changeDelegation(address newDelegate) external {
        // No delegating to zero
        if (newDelegate == address(0)) revert ASR_ZeroAddress("delegation");
        // Get the stored user data
        Storage.AddressUint storage userData = _deposits()[msg.sender];
        // Get the user balance
        uint256 userBalance = uint256(userData.amount);
        address oldDelegate = userData.who;
        // Reset the user delegation
        userData.who = newDelegate;
        // Reduce the old voting power
        // Get the storage pointer
        History.HistoricalBalances memory votingPower = _votingPower();
        // Load the old delegate's voting power
        uint256 oldDelegateVotes = votingPower.loadTop(oldDelegate);
        // Reduce the old voting power
        votingPower.push(oldDelegate, oldDelegateVotes - userBalance);
        // Emit an event to track votes
        emit VoteChange(msg.sender, oldDelegate, -1 * int256(userBalance));
        // Get the new delegate's votes
        uint256 newDelegateVotes = votingPower.loadTop(newDelegate);

        // Store the increase in power
        votingPower.push(newDelegate, newDelegateVotes + userBalance);
        // Emit an event tracking this voting power change
        emit VoteChange(msg.sender, newDelegate, int256(userBalance));
    }
}