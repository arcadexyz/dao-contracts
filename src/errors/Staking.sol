// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

/**
 * @title Staking
 * @author Non-Fungible Technologies, Inc.
 *
 * This file contains all custom errors for the ArcadeStakingRewards contract.
 * All errors are prefixed by  "ASR_" for ArcadeStakingRewards. Errors located in one place
 * to make it possible to holistically look at all the failure cases.
 */

// ==================================== Arcade Staking Rewards Errors ======================================
/**
 * @notice Zero address passed in where not allowed.
 */
error ASR_ZeroAddress();

/**
 * @notice Cannot withdraw or stake amount zero.
 */
error ASR_ZeroAmount();

/**
 * @notice ARCDWETH to ARCD conversion rate cannot be zero.
 */
error ASR_ZeroConversionRate();

/**
 * @notice Previous rewards period must be complete
 *         to update rewards duration.
 */
error ASR_RewardsPeriod();

/**
 * @notice Staking token cannot be ERC20 recovered.
 */
error ASR_StakingToken();

/**
 * @notice Reward + leftover must be less than contract reward balance.
 *         This keeps the reward in a range less than 2^256 / 10^18
 *         and prevents overflow.
 */
error ASR_RewardTooHigh();

/**
 * @notice User tries to withdraw an amount greater than
 *         than their balance.
 */
error ASR_BalanceAmount();

/**
 * @notice There is no stake for this caller.
 */
error ASR_NoStake();

/**
 * @notice Cannot withdraw a deposit which is still locked.
 */
error ASR_Locked();

/**
 * @notice Cannot withdraw reward tokens unless totalDeposits == 0 to
 *         safeguard rewardsRate.
 *
 */
error ASR_RewardsToken();

/**
 * @notice The depositId does not exist.
 *
 */
error ASR_InvalidDepositId();

/**
 * @notice Deposits number is larger than MAX_ITERATIONS.
 *
 */
error ASR_DepositCountExceeded();

/**
 * @notice The provided stale block number is too high.
 *
 */
error ASR_UpperLimitBlock(uint256);