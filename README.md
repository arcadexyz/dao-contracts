# ArcadeStakingRewards

## Overview

ArcadeStakingRewards is inspired by the [Synthetix StakingRewards](https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol) system. The contract facilitates a staking mechanism where users can stake ERC20 tokens `stakingToken` to earn rewards over time in the form of another ERC20 token `rewardsToken`. The rewards depend on the amount staked and the duration of the stake.

## Features

### Flexible Staking and Lock Periods

- **Multiple Deposits:** Users can make multiple deposits, with each deposit accruing rewards independently until the staking period ends.
- **Lock Period:** Upon staking, users must commit to a fixed lock period, during which funds are immovable. Early withdrawal before this period ends is not permitted.
- **Automatic Re-staking:** Post-lock period, funds automatically enter the next staking cycle without a lock period, allowing for withdrawal at any time.

### Reward Enhancement through Lock Periods

- **Bonus Multipliers:** The contract offers bonus multipliers based on the chosen lock period (short, medium, or long), incentivizing longer commitments.
- **Reward Calculation:** Total reward = staked amount + (staked amount * chosen duration multiplier).

### Gas Limit Considerations

- **Iteration Limits:** Functions like `exitAll()` and `claimRewardAll()` have a limit on iterations to prevent exceeding the block gas limit.
- **MAX_DEPOSITS:** A cap (defined by `MAX_DEPOSITS` variable) is set on the number of deposits per wallet to manage iterations within a single transaction. Users needing more stakes must use additional wallet addresses.

### Governance and Voting

`ArcadeStakingRewards.sol` utilizes the [Council Kit](https://github.com/delvtech/council-kit/wiki/Voting-Vaults-Overview) LockingVault deployment [here](https://etherscan.io/address/0x7a58784063D41cb78FBd30d271F047F0b9156d6e#code) as its governance operations foundation.

- **Voting Power:** Staking tokens in the locking pool grants users voting power in ArcadeDAO governance, proportional to their staked amount plus any bonuses. A user's voting power is determined by the quantity of ARCDWETH pair tokens they have staked. To calculate their voting power, an ARCD/WETH to ARCD conversion rate is set in the contract at deployment time and stored in an immutable state variable. The user's ARCD amount is the product of their deposited ARCD/WETH amount and the immutable conversion rate. The resulting voting power is amplified by the lock multiplier that users choose upon staking.
- **Automatic Delegation:** Voting power is automatically accrued and delegated without additional transactions by the user.

## Development and Testing

To build and test ArcadeStakingRewards contract, use:

- **Build:** `$ forge build`
- **Test:** `$ forge test`

---