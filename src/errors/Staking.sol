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
 * @notice Zero amount staking not allowed.
 */
error ASR_CannotStakeZero();

/**
 * @notice Reward period expired.
 */
error ASR_RewardTimeNotApplicable();