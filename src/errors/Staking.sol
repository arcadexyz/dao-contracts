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
 * @notice Previous rewards period must be complete
 *         to update rewards duration.
 */
error ASR_RewardsPeriod();

/**
 * @notice Staking token cannot be ERC20 recovered.
 */
error ASR_StakingToken();

/**
 * @notice notifyRewardAmount, reward too high.
 */
error ASR_RewardTooHigh();

/**
 * @notice User tries to withdraw an amount greater than
 *         than their balance.
 */
error ASR_BalanceAmount();

/**
 * @notice The caller attempted to stake with a lock value
 *         that does not correspond to a valid staking time.
 *
 */
error ASR_InvalidLockValue(uint256);

/**
 * @notice There is no stake for this caller.
 */
error ASR_NoStake();

/**
 * @notice Cannot withdraw a deposit which is still locked.
 *
 */
error ASR_Locked();