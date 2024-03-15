// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./external/council/interfaces/IVotingVault.sol";
import "./external/council/libraries/History.sol";
import "./external/council/libraries/Storage.sol";

import "./interfaces/IArcadeSingleSidedStaking.sol";

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
 * @title ArcadeSingleSidedStaking
 * @author Non-Fungible Technologies, Inc.
 *
 * @notice To optimize gas usage, unlockTimeStamp in struct UserDeposit is stored in
 *         uint32 format. This limits timestamp support to dates before 03:14:07 UTC on
 *         19 January 2038. Any time beyond this point will cause an overflow.
 *
 * The ArcadeSingleSidedStaking contract works much like a traditional staking setup, but
 * with a twist: instead of earning ARCD tokens as rewards, users stash their ARCD tokens
 * in the contract and get d’App points in return. These points are tallied up off-chain.
 * It’s a straightforward way for users to lock their ARCD and earn points that count
 * towards something different, such as airdrops and unlocking d'App privileges.
 *
 * Users have the flexibility to make multiple deposits, each accruing points separately
 * until their lock period concludes. Upon depositing, users are required to commit to a
 * lock period where tokens are immovable, until the chosen lock period expires. Early
 * withdrawal is not permitted before the locking period is over.
 *
 * Should users choose not to withdraw their tokens post the lock period, these
 * funds will seamlessly transition into a subsequent points tracking cycle if
 * one should start. Unlike the initial deposit, the funds in the consequent point
 * tracking periods are not bound by a lock period and can be freely withdrawn anytime.
 *
 * The lock period gives users the opportunity to enhance their point earnings
 * with bonuses that are calcualted off-chain. These off-chain bonuses are
 * contingent on the duration for which the user chooses to lock their deposits.
 * The available lock durations are categorized as short, medium, and long.
 * Each category is associated with a progressively increasing number of point
 * rewards accounted for in the d'App, with the short duration offering the
 * smallest and the long duration offering the largest.
 *
 * In the exitAll() external function, it's necessary to limit the number of
 * processed transactions within the function's loops to prevent exceeding
 * the block gas limit. Because of this, the contract enforces a hard limit
 * on the number deposits a user can have per wallet address and consequently
 * on the number of iterations that can be processed in a single transaction.
 * This limit is defined by the MAX_DEPOSITS state variable. Should a user
 * necessitate making more than the MAX_DEPOSITS  number of deposits, they will
 * be required to use a different wallet address.
 *
 * The contract gives users governance capabilities by also serving as a voting
 * vault. When users deposit, they gain voting power which they can use in
 * ArcadeDAO governance. The voting power is automatically accrued to their account
 * and is delegated to their chosen delegatee's address on their behalf without the
 * need for them to call any additional transaction.
 * The ArcadeSingleSidedStaking contract governance functionality is adapted from the
 * Council LockingVault deployment at:
 * https://etherscan.io/address/0x7a58784063D41cb78FBd30d271F047F0b9156d6e#code
 *
 * Once a user makes their initial deposit, the voting power for any future deposits
 * will need to be delegated to the same address as the initial deposit. To assign a
 * different delegate, users are required to use the changeDelegate() function.
 * A user's voting power is determined by the quantity of ARCD tokens they have deposited.
 */

contract ArcadeSingleSidedStaking is IArcadeSingleSidedStaking, IVotingVault, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Bring library into scope
    using History for History.HistoricalBalances;

    // ============================================ STATE ==============================================
    // ============== Constants ==============
    uint256 public constant ONE = 1e18;
    uint256 public constant ONE_DAY = 1 days;
    uint256 public constant MAX_DEPOSITS = 20;

    uint256 public constant SHORT_LOCK_TIME = ONE_DAY * 30; // one month
    uint256 public constant MEDIUM_LOCK_TIME = ONE_DAY * 60; // two months
    uint256 public constant LONG_LOCK_TIME = ONE_DAY * 90; // three months

    // ============ Global State =============
    IERC20 public immutable arcdToken;

    uint256 public periodFinish;
    uint256 public pointsTrackingDuration = ONE_DAY * 30 * 6; // six months

    mapping(address => UserDeposit[]) public userDeposits;

    uint256 public totalDeposits;

    // ========================================== CONSTRUCTOR ===========================================
    /**
     * @notice Sets up the contract by initializing the staking and rewards tokens,
     *         and setting the owner and rewards distribution addresses.
     *
     * @param _owner                       The address of the contract owner.
     * @param _arcdToken                   The address of the deposited ERC20 token.
     */
    constructor(
        address _owner,
        address _arcdToken
    ) Ownable(_owner) {
        if (address(_arcdToken) == address(0)) revert ASR_ZeroAddress("arcdToken");

        arcdToken = IERC20(_rewardsToken);
    }

    // ========================================== VIEW FUNCTIONS =========================================
    /**
     * @notice Returns the total amount of deposited tokens held in the contract.
     *
     * @return uint256                     The amount of deposited tokens.
     */
    function totalSupply() external view returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice Returns the amount of tokens deposited by a user account.
     *
     * @param account                       The address of the account.
     *
     * @return userBalance                  The total amount that the user has deposited.
     */
    function getTotalUserDeposits(address account) external view returns (uint256 userBalance) {
        UserDeposit[] storage accountDeposits = userDeposits[account];

        uint256 numUserDeposits = accountDeposits.length;
        for (uint256 i = 0; i < numUserDeposits; ++i) {
            UserDeposit storage userDeposit = accountDeposits[i];
            userBalance += userDeposit.amount;
        }
    }

    /**
     * @notice Returns the amount of deposited tokens pertaining to a specific deposit.
     *
     * @param account                       The address of the account.
     * @param depositId                     The specified deposit to get the balance of.
     *
     * @return depositBalance               The total amount committed to the deposit.
     */
    function balanceOfDeposit(address account, uint256 depositId) external view returns (uint256 depositBalance) {
        depositBalance = userDeposits[account][depositId].amount;
    }

    // /**
    //  * @notice Returns the last timestamp at which rewards can be calculated and
    //  *         be accounted for.
    //  *
    //  * @return uint256                       The timestamp record after which rewards
    //  *                                       can no longer be calculated.
    //  */
    // function lastTimeRewardApplicable() public view returns (uint256) {
    //     return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    // }

    /**
     * @notice Returns information about a deposit.

     * @param account                           The user whose deposit to get.
     * @param depositId                         The specified deposit to get.
     *
     * @return lock                             Lock period committed.
     * @return unlockTimestamp                  Timestamp marking the end of the lock period.
     * @return amount                           Amount deposited.
     */
    function getUserDeposit(address account, uint256 depositId) external view returns (
        uint8 lock,
        uint32 unlockTimestamp,
        uint256 amount)
    {
        UserDeposit storage accountDeposit = userDeposits[account][depositId];

        lock = uint8(userDeposit.lock);
        unlockTimestamp = userDeposit.unlockTimestamp;
        amount = userDeposit.amount;
    }

    /**
     * @notice Gives the last depositId, equivalent to accountDeposits.length.
     *
     * @param account                           The user whose deposits to get.
     *
     * @return lastDepositId                    Id of the last deposit.
     */
    function getLastDepositId(address account) external view returns (uint256 lastDepositId) {
        lastDepositId = userDeposits[account].length - 1;
    }

    /**
     * @notice Gets all of a user's active deposits.
     *
     * @param account                           The user whose deposits to get.
     *
     * @return activeDeposits                   Array of id's of user's active deposits.
     */
    function getActiveDeposits(address account) external view returns (uint256[] memory) {
        UserDeposit[] storage accountDeposits = userDeposits[account];
        uint256 activeCount = 0;

        uint256 numUserDeposits = accountDeposits.length;
        for (uint256 i = 0; i < numUserDeposits; ++i) {
            UserDeposit storage userDeposit = userDeposits[i];
            if (userDeposit.amount > 0) {
                activeCount++;
            }
        }

        uint256[] memory activeDeposits = new uint256[](activeCount);
        uint256 activeIndex;

        for (uint256 i = 0; i < numUserDeposits; ++i) {
            if (userDeposits[i].amount > 0) {
                activeDeposits[activeIndex] = i;
                activeIndex++;
            }
        }

        return activeDeposits;
    }

    // ========================================= MUTATIVE FUNCTIONS ========================================
    /**
     * @notice Allows users to deposit their tokens, which are then tracked in the contract. The total
     *         supply of deposited tokens and individual user balances are updated accordingly.
     *
     * @param amount                           The amount of tokens the user wishes to deposit and lock.
     * @param delegation                       The address to which the user's voting power will be delegated.
     * @param lock                             The locking period for the deposited tokens.
     */
    function deposit(
        uint256 amount,
        address delegation,
        Lock lock
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert ASR_ZeroAmount();
        if (delegation == address(0)) revert ASR_ZeroAddress("delegation");

        uint256 userDepositCount = stakes[msg.sender].length;
        if (userDepositCount >= MAX_DEPOSITS) revert ASR_DepositCountExceeded();

        // update the vote power
        _addVotingPower(msg.sender, votingPowerToAdd, delegation);

        // populate user stake information
        userDeposits[msg.sender].push(
            UserDeposit({
                amount: amount,
                unlockTimestamp: uint32(block.timestamp + lockDuration),
                lock: lock
            })
        );

        totalDeposits += amount;

        arcdToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, userDepositCount, amount);
    }

    /**
     * @notice Withdraws deposited tokens that are unlocked.  Allows for partial withdrawals.
     *
     * @param depositId                        The specified deposit to get the reward for.
     * @param amount                           The amount to be withdrawn from the user deposit.
     */
    function withdraw(uint256 amount, uint256 depositId) public whenNotPaused nonReentrant {
        if (amount == 0) revert ASR_ZeroAmount();
        UserDeposit storage accountDeposit = userDeposits[msg.sender][depositId];
        if (accountDeposit.amount == 0) revert ASR_BalanceAmount();
        if (block.timestamp < accountDeposit.unlockTimestamp) revert ASR_Locked();

        if (amount > accountDeposit.amount) amount = accountDeposit.amount;

        _subtractVotingPower(amount, msg.sender);

        accountDeposit.amount -= amount;

        totalDeposits -= amount;

        arcdToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Allows users to withdraw deposited tokens and claim their rewards
     *         for a specific deposit id, all in one transaction.
     *         Lock period needs to have ended.
     *
     * @param depositId                        The specified deposit to exit.
     */
    function exit(uint256 depositId) external {
        withdraw(type(uint256).max, depositId);
    }

    /**
     * @notice Allows users to withdraw all their deposited tokens in one transaction.
     *         Lock period needs to have ended.
     */
    function exitAll() external nonReentrant {
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
            rewardsToken.safeTransfer(msg.sender, totalRewardAmount);
        }
    }

    // ======================================== RESTRICTED FUNCTIONS =========================================
    /**
     * @notice Allows the contract owner to recover ERC20 tokens locked in the contract. TODO: rethink this
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
     * @notice An only owner function to set the duration of the tracking period. The previous
     *         tracking period must be complete before a new duration can be set.
     *
     * @param _pointsTrackingDuration              The amount of time the tracking period will be.
     */
    function setRewardsDuration(uint256 _pointsTrackingDuration) external whenNotPaused onlyOwner {
        if (block.timestamp <= periodFinish) revert ASR_RewardsPeriod();

        pointsTrackingDuration = _pointsTrackingDuration;

        emit RewardsDurationUpdated(pointsTrackingDuration);
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

    // TODO: getVotingPower() function is needed

    /**
     * @notice This internal function adapted from the external withdraw function from the LockingVault
     *         contract. The function adds an address account parameter to specify the user whose voting
     *         power needs updating.
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
        // Transfers the result to the sender
        token.transfer(account, amount);
    }

    /**
     * @notice This internal function is adapted from the external deposit function from the LockingVault
     *         contract with 1 key modification: it reverts if the specified delegation address does not
     *         with the user's previously designated delegate.
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

        uint96 castAmount = SafeCast.toUint96(amount);

        // Move the tokens into this contract
        token.transferFrom(msg.sender, address(this), amount);

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