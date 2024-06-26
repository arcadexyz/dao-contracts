// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

/**
 * @title SingleSidedStaking
 * @author Non-Fungible Technologies, Inc.
 *
 * This file contains all custom errors for the ArcadeSingleSidedStaking contract.
 * All errors are prefixed by  "ASS_" for ArcadeSingleSidedStaking. Errors located in one place
 * to make it possible to holistically look at all the failure cases.
 */

// ==================================== Arcade Single Sided Staking Errors ======================================

/**
 * @notice Zero address passed in where not allowed.
 * @param addressType                The name of the parameter for which a zero
 *                                   address was provided.
 */
error ASS_ZeroAddress(string addressType);

/**
 * @notice Cannot withdraw or stake amount zero.
 */
error ASS_ZeroAmount();

/**
 * @notice Deposit token cannot be ERC20 recovered.
 */
error ASS_DepositToken();

/**
 * @notice User tries to withdraw an amount greater than
 *         than their balance.
 */
error ASS_BalanceAmount();

/**
 * @notice Cannot withdraw a deposit which is still locked.
 */
error ASS_Locked();

/**
 * @notice Deposits number is larger than MAX_ITERATIONS.
 *
 */
error ASS_DepositCountExceeded();

/**
 * @notice The provided delegate address does not match their initial delegate.
 */
 error ASS_InvalidDelegationAddress();

/**
 * @notice Amount cannot exceed the maximum value that can be held by a uint96.
 */
 error ASS_AmountTooBig();

// ==================================== Airdrop Single Sided Staking Errors ======================================

 /**
 * @notice The caller is not authorized to make this call.
 */
 error ASS_CallerNotAirdropDistribution();

