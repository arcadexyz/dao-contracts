// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

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
    ASS_DepositToken,
    ASS_BalanceAmount,
    ASS_Locked,
    ASS_DepositCountExceeded,
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
 * in the contract and get d’App points in return. Earned points are tallied up off-chain
 * and account towards the $ARCD Rewards program and its Levels.
 *
 * Upon depositing, users are required to commit to a lock period where tokens are
 * immovable, until the chosen lock period expires. Early  withdrawal is not permitted.
 * Users have the flexibility to make multiple deposits, each accruing points separately
 * until their lock period concludes.
 *
 * Should users choose not to withdraw their tokens post the lock period, the
 * funds will seamlessly transition into a subsequent points tracking cycle if
 * one should start. Unlike the initial deposit, the funds in the consequent point
 * tracking cycles are not bound by a lock period and can be freely withdrawn anytime.
 * Tracking cycles are defined and tracked in the dApp.
 *
 * The lock period gives users the opportunity to enhance their points earnings
 * with bonus multipliers that are contingent on the duration for which the user
 * chooses to lock their deposited tokens. These bonus calculations are tallied offchain.
 * The available lock durations are categorized as short, medium, and long. Each category
 * is associated with a progressively increasing multiplier that enhances the number of
 * point rewards accrued in the d'App, with the short duration offering the smallest and
 * the long duration offering the largest.
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
 * ArcadeDAO governance. Users' voting power is automatically accrued to their account
 * and is delegated to their chosen delegatee's address on their behalf without the
 * need for them to call any additional transaction.
 * The ArcadeSingleSidedStaking contract governance functionality is adapted from the
 * Council LockingVault deployment at:
 * https://etherscan.io/address/0x7a58784063D41cb78FBd30d271F047F0b9156d6e#code
 *
 * Once a user makes their initial deposit, the voting power for any future deposits
 * will need to be delegated to the same address as in the initial deposit. To assign
 * a different delegate, users are required to use the changeDelegate() function.
 * A user's voting power is determined by the quantity of ARCD tokens they have deposited.
 */

contract ArcadeSingleSidedStaking is IArcadeSingleSidedStaking, IVotingVault, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // Bring library into scope
    using History for History.HistoricalBalances;

    // ============================================ STATE ==============================================
    // ============== Constants ==============
    uint256 public constant MAX_DEPOSITS = 20;
    uint256 public constant SHORT_LOCK_TIME = 30 days;
    uint256 public constant MEDIUM_LOCK_TIME = 60 days;
    uint256 public constant LONG_LOCK_TIME = 150 days;

    // ============ Global State =============
    IERC20 public immutable arcd;

    mapping(address => UserDeposit[]) public deposits;

    uint256 public totalDeposits;

    // ========================================== CONSTRUCTOR ===========================================
    /**
     * @notice Sets up the contract by initializing the deposit token and setting the owner.
     *
     * @param _owner                       The address of the contract owner.
     * @param _arcd                        The address of the deposit ERC20 token.
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
     * @notice Returns information about a deposit.

     * @param account                           The user whose deposit to get.
     * @param depositId                         The specified deposit to get.
     *
     * @return lock                             Lock period committed.
     * @return unlockTimestamp                  Timestamp marking the end of the lock period.
     * @return amount                           Amount deposited.
     */
    function getUserDeposit(address account, uint256 depositId)
        external
        view
        returns (uint8 lock, uint32 unlockTimestamp, uint256 amount)
    {
        UserDeposit storage userDeposit = deposits[account][depositId];

        lock = uint8(userDeposit.lock);
        unlockTimestamp = userDeposit.unlockTimestamp;
        amount = userDeposit.amount;
    }

    /**
     * @notice Returns the last depositId, equivalent to userDeposits.length.
     *
     * @param account                           The user whose last deposit to get.
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
     * @return activeDeposits                   Array of id's of the user's active deposits.
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

    // ========================================= MUTATIVE FUNCTIONS ========================================
    /**
     * @notice Allows users to deposit their tokens, which are then tracked in the contract.
     *
     * @param amount                           The amount of tokens the user wishes to deposit and lock.
     * @param delegation                       The address to which the user's voting power will be delegated.
     * @param lock                             The chosen locking period for the deposited tokens.
     */
    function deposit(
        uint256 amount,
        address delegation,
        Lock lock
    ) external {
        _deposit(msg.sender, amount, delegation, lock);
    }

    /**
     * @notice Withdraws deposited tokens that are unlocked.  Allows for partial withdrawals.
     *
     * @param depositId                        The specified deposit to withdraw from.
     * @param amount                           The amount to be withdrawn.
     */
    function withdraw(uint256 amount, uint256 depositId) public whenNotPaused nonReentrant {
        if (amount == 0) revert ASS_ZeroAmount();
        UserDeposit storage userDeposit = deposits[msg.sender][depositId];
        if (userDeposit.amount == 0) revert ASS_BalanceAmount();
        if (block.timestamp < userDeposit.unlockTimestamp) revert ASS_Locked();

        if (amount > userDeposit.amount) amount = userDeposit.amount;

        _subtractVotingPower(amount, msg.sender);

        userDeposit.amount -= amount;

        totalDeposits -= amount;

        arcd.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, depositId, amount, uint8(userDeposit.lock));
    }

    /**
     * @notice Allows users to withdraw deposited tokens for a specific deposit
     *         deposit id. Lock period needs to have ended.
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

            emit Withdrawn(msg.sender, i, amount, uint8(userDeposit.lock));
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
     * @notice Allows the contract owner to recover ERC20 tokens locked in the contract.
     *         Deposited ARCD tokens cannot be recovered, they can only be withdrawn
     *         by the depositing user.
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
     * @notice Internal deposit function updating a user's deposit balance information and voting
     *         power. The total supply of deposited tokens are updated accordingly.
     *
     * @param recipient                        The user whom the deposited tokens are allocated to.
     * @param amount                           The amount of tokens to deposit and lock.
     * @param delegation                       The address to which the user's voting power will be delegated.
     * @param lock                             The locking period for the deposited tokens.
     */
    function _deposit(
        address recipient,
        uint256 amount,
        address delegation,
        Lock lock
    ) internal nonReentrant whenNotPaused {
        if (amount == 0) revert ASS_ZeroAmount();
        if (delegation == address(0)) revert ASS_ZeroAddress("delegation");

        uint256 userDepositCount = deposits[recipient].length;
        if (userDepositCount >= MAX_DEPOSITS) revert ASS_DepositCountExceeded();

        uint256 lockDuration = _calculateLockDuration(lock);

        // update the vote power
        _addVotingPower(recipient, amount, delegation);

        // populate user deposit information
        deposits[recipient].push(
            UserDeposit({
                amount: amount,
                unlockTimestamp: uint32(block.timestamp + lockDuration),
                lock: lock
            })
        );

        totalDeposits += amount;

        arcd.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(recipient, userDepositCount, amount, uint8(lock));
    }

    /**
     * @notice Calculates the lock duration for a user's deposit based on the selected lock SHORT, MEDIUM or LONG.
     *
     * @param lock                              The lock period committed.
     *
     * @return lockDuration                     The period duration for the selected lock.
     */
    function _calculateLockDuration(Lock lock) internal pure returns (uint256 lockDuration) {
        if (lock == Lock.Short) {
           lockDuration = SHORT_LOCK_TIME;
        } else if (lock == Lock.Medium) {
            lockDuration = MEDIUM_LOCK_TIME;
        } else if (lock == Lock.Long) {
            lockDuration = LONG_LOCK_TIME;
        }
    }

    /**
      * @notice This internal function is adapted from the external withdraw function in Council's
     *          LockingVault contract with 2 key modifications: it omits the token transfer transaction
     *          and adds an address account parameter to specify the user whose voting power needs updating.
     *          In the Locking Vault, msg.sender directly indicated the user, whereas in this context,
     *          msg.sender refers to the contract itself. Therefore, we explicitly pass the
     *          user's address.
     *
     * @param amount                           The amount of voting power to subtract.
     * @param account                          The account whose voting power to subtract.
     */
    function _subtractVotingPower(uint256 amount, address account) internal {
        if (amount > type(uint96).max) revert ASS_AmountTooBig();

        // Load our deposits storage
        Storage.AddressUint storage userData = _deposits()[account];

        // Reduce the user's stored balance
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
     * @notice This internal function is adapted from the external deposit function in the Council
     *         LockingVault contract with 2 key modifications: it reverts if the specified delegation
     *         address does not match the user's previously designated delegate, and it no longer
     *         handles token transfers into the contract as these are handled by the deposit function.
     *
     * @param fundedAccount                    The address to credit the voting power to.
     * @param amount                           The amount of voting power to add.
     * @param delegation                       The user's delegatee address.
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
     * @notice This function is taken from the Council LockingVault contract. It is a single
     *         endpoint for loading storage for deposits.
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
     * @notice This function is taken from the Council LockingVault contract. Returns the
     *         historical voting power tracker.
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
     * @notice This function is taken from the Council LockingVault contract. Loads the voting
     *         power of a user. It is revised to no longer clear stale blocks from the queue
     *         in order to avoid gas depletion encountered with overly long queues.
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
     *         user without any changes to state.
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
     * @notice This function is taken from the Council LockingVault contract, it changes a user's
     *         voting power delegatee.
     *
     * @param newDelegate                        The new address which gets the voting power.
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