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
    ASS_ZeroAddress,
    ASS_ZeroAmount,
    ASS_RewardsPeriod,
    ASS_DepositToken,
    ASS_BalanceAmount,
    ASS_Locked,
    ASS_DepositCountExceeded,
    ASS_UpperLimitBlock,
    ASS_InvalidDelegationAddress,
    ASS_AmountTooBig
} from "../src/errors/SingleSidedStaking.sol";

/**
 * @title ArcadeSingleSidedStaking
 * @author Non-Fungible Technologies, Inc.
 *
 * @notice To optimize gas usage, unlockTimeStamp in struct UserDeposit is stored in
 *         uint32 format. This limits timestamp support to dates before 03:14:07 UTC on
 *         19 January 2038. Any time beyond this point will cause an overflow.
 *
 * The ArcadeSingleSidedStaking contract is set up like a traditional staking contract,
 * but with a twist: instead of earning tokens as rewards, users deposit their ARCD tokens
 * in the contract and get d’App points in return. These points are tallied up off-chain.
 * It’s a straightforward way for users to lock their ARCD and earn points that count
 * towards the $ARCD Rewards program and its Levels.
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
 * with a bonus multiplier that is contingent on the duration for which the user
 * chooses to lock their ARCD tokens. The available lock durations are categorized
 * as short, medium, and long. Each category is associated with a progressively
 * number of point rewards accounted for in the d'App, with the short duration offering
 * and the long duration offering the largest.
 *
 * When a user decides to lock their ARCD tokens for one of these durations,
 * their deposit bonus is calculated as:
 * (the user's deposited amount * multiplier for the chosen duration) + original
 * deposited amount.
 * This boosts the user's points in proportion to both the amount deposited and
 * the duration of the lock for the deposit.
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

    uint256 public constant SHORT_BONUS = 11e17;
    uint256 public constant MEDIUM_BONUS = 13e17;
    uint256 public constant LONG_BONUS = 15e17;

    uint256 public constant SHORT_LOCK_TIME = ONE_DAY * 30; // one month
    uint256 public constant MEDIUM_LOCK_TIME = ONE_DAY * 60; // two months
    uint256 public constant LONG_LOCK_TIME = ONE_DAY * 90; // three months

    // ============ Global State =============
    IERC20 public immutable arcd;

    uint256 public periodFinish;
    uint256 public pointsTrackingDuration = ONE_DAY * 30 * 6; // six months

    mapping(address => UserDeposit[]) public deposits;

    uint256 public totalDeposits;

    // ========================================== CONSTRUCTOR ===========================================
    /**
     * @notice Sets up the contract by initializing the staking and rewards tokens,
     *         and setting the owner and rewards distribution addresses.
     *
     * @param _owner                       The address of the contract owner.
     * @param _arcd                        The address of the deposited ERC20 token.
     */
    constructor(
        address _owner,
        address _arcd
    ) Ownable(_owner) {
        if (address(_arcd) == address(0)) revert ASS_ZeroAddress("arcd");

        arcd = IERC20(_arcd);
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
        UserDeposit[] storage userDeposits = deposits[account];

        uint256 numUserDeposits = userDeposits.length;
        for (uint256 i = 0; i < numUserDeposits; ++i) {
            UserDeposit storage userDeposit = userDeposits[i];
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
        depositBalance = deposits[account][depositId].amount;
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
        UserDeposit storage accountDeposit = deposits[account][depositId];

        lock = uint8(accountDeposit.lock);
        unlockTimestamp = accountDeposit.unlockTimestamp;
        amount = accountDeposit.amount;
    }

    /**
     * @notice Gives the last depositId, equivalent to userDeposits.length.
     *
     * @param account                           The user whose deposits to get.
     *
     * @return lastDepositId                    Id of the last deposit.
     */
    function getLastDepositId(address account) external view returns (uint256 lastDepositId) {
        lastDepositId = deposits[account].length - 1;
    }

    /**
     * @notice Gets all of a user's active deposits.
     *
     * @param account                           The user whose deposits to get.
     *
     * @return activeDeposits                   Array of id's of user's active deposits.
     */
    function getActiveDeposits(address account) external view returns (uint256[] memory) {
        UserDeposit[] storage userDeposits = deposits[account];
        uint256 activeCount = 0;

        uint256 numUserDeposits = userDeposits.length;
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

    /**
     * @notice Returns just the bonus amount for a deposit.
     *
     * @param account                           The user's account.
     * @param depositId                         The specified deposit to get the bonus amount for.
     *
     * @return bonusAmount                      Value of user deposit bonus.
     */
    function getDepositBonus(address account, uint256 depositId) public view returns (uint256 bonusAmount) {
        UserDeposit storage userDeposit = deposits[account][depositId];

        uint256 amount = userDeposit.amount;
        Lock lock = userDeposit.lock;

        (bonusAmount, ) = _calculateBonus(amount, lock);
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
        if (amount == 0) revert ASS_ZeroAmount();
        if (delegation == address(0)) revert ASS_ZeroAddress("delegation");

        uint256 userDepositCount = deposits[msg.sender].length;
        if (userDepositCount >= MAX_DEPOSITS) revert ASS_DepositCountExceeded();

        (, uint256 lockDuration)  = _calculateBonus(amount, lock);

        // update the vote power
        _addVotingPower(msg.sender, amount, delegation);

        // populate user stake information
        deposits[msg.sender].push(
            UserDeposit({
                amount: amount,
                unlockTimestamp: uint32(block.timestamp + lockDuration),
                lock: lock
            })
        );

        totalDeposits += amount;

        arcd.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, userDepositCount, amount);
    }

    /**
     * @notice Withdraws deposited tokens that are unlocked.  Allows for partial withdrawals.
     *
     * @param depositId                        The specified deposit to get the reward for.
     * @param amount                           The amount to be withdrawn from the user deposit.
     */
    function withdraw(uint256 amount, uint256 depositId) public whenNotPaused nonReentrant {
        if (amount == 0) revert ASS_ZeroAmount();
        UserDeposit storage accountDeposit = deposits[msg.sender][depositId];
        if (accountDeposit.amount == 0) revert ASS_BalanceAmount();
        if (block.timestamp < accountDeposit.unlockTimestamp) revert ASS_Locked();

        if (amount > accountDeposit.amount) amount = accountDeposit.amount;

        _subtractVotingPower(amount, msg.sender);

        accountDeposit.amount -= amount;

        totalDeposits -= amount;

        arcd.safeTransfer(msg.sender, amount);
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
    function exitAll() external whenNotPaused nonReentrant {
        UserDeposit[] storage userDeposits = deposits[msg.sender];
        uint256 totalWithdrawAmount = 0;
        uint256 totalVotingPower = 0;
        uint256 numUserDeposits = userDeposits.length;

        for (uint256 i = 0; i < numUserDeposits; ++i) {
            UserDeposit storage userDeposit = userDeposits[i];
            uint256 amount = userDeposit.amount;
            if (amount == 0 || block.timestamp < userDeposit.unlockTimestamp) continue;

            userDeposit.amount -= amount;

            totalVotingPower += amount;
            totalWithdrawAmount += amount;
        }

        if (totalVotingPower > 0) {
            _subtractVotingPower(totalVotingPower, msg.sender);
        }

        if (totalWithdrawAmount > 0) {
            totalDeposits -= totalWithdrawAmount;
            arcd.safeTransfer(msg.sender, totalWithdrawAmount);
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
        if (tokenAddress == address(arcd)) revert ASS_DepositToken();
        if (tokenAddress == address(0)) revert ASS_ZeroAddress("token");
        if (tokenAmount == 0) revert ASS_ZeroAmount();

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
        if (block.timestamp <= periodFinish) revert ASS_RewardsPeriod();

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
    /**
     * @notice Calculate the bonus for a user's deposit.
     *
     * @param amount                            The deposit amount.
     * @param lock                              The lock period committed.
     *
     * @return bonusAmount                      The bonus value of of the.
     * @return lockDuration                     The period duration for the selected lock.
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
     *         contract contract with 2 key modifications: it does not handle token transfers out of the
     *         contract as these are handled by the withdraw and exit functions. The function also adds an
     *         address account parameter to specify the user whose voting power needs updating.
     *         In the Locking Vault  msg.sender directly indicated the user, wheras in this context
     *         msg.sender refers to the contract itself. Therefore, we explicitly pass the user's address.
     *
     * @param amount                           The amount of token to withdraw.
     * @param account                          The funded account for the withdrawal.
     */
    function _subtractVotingPower(uint256 amount, address account) internal {
        if (amount > type(uint96).max) revert ASS_AmountTooBig();

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
     *         contract with 2 key modification: it reverts if the specified delegation address does not
     *         with the user's previously designated delegate, it does not handle token transfers into the
     *         contract as these are handled by the deposit function.
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
        if (amount > type(uint96).max) revert ASS_AmountTooBig();
        // No delegating to zero
        if (delegation == address(0)) revert ASS_ZeroAddress("delegation");

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
            revert ASS_InvalidDelegationAddress();
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
     *         power of a user. It is revised to no longer remove stale blocks from the queue, to
     *         address the problem of gas depletion encountered with overly long queues.
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
    ) external view override returns (uint256) {
        return queryVotePowerView(user, blockNumber);
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
        public
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
        if (newDelegate == address(0)) revert ASS_ZeroAddress("delegation");
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