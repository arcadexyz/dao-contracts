## This repository serves as a central hub for contracts related to ArcadeDAO and its initiatives. It represents a collective effort shaped by the community and for the community.

<br>

## ArcadeStakingRewards

### Contract Overview

ArcadeStakingRewards is inspired by the [Synthetix StakingRewards](https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol) system. The contract facilitates a staking mechanism where users can stake ERC20 tokens `stakingToken` to earn rewards over time in the form of another ERC20 token `rewardsToken`. The rewards depend on the amount staked and the duration of the stake.

### Features

#### Flexible Staking and Lock Periods

- **Multiple Deposits:** Users can make multiple deposits, with each deposit accruing rewards independently until the staking period ends.
- **Lock Period:** Upon staking, users must commit to a fixed lock period, during which funds are immovable. Early withdrawal before this period ends is not permitted.
- **Automatic Re-staking:** Post-lock period, funds automatically enter the next staking cycle without a lock period, allowing for withdrawal at any time.

#### Reward Enhancement through Lock Periods

- **Bonus Multipliers:** The contract offers bonus multipliers based on the chosen lock period (short, medium, or long), incentivizing longer commitments.
- **Reward Calculation:** Total reward = staked amount + (staked amount * chosen duration multiplier).

#### Gas Limit Considerations

- **Iteration Limits:** Functions like `exitAll()` and `claimRewardAll()` have a limit on iterations to prevent exceeding the block gas limit.
- **MAX_DEPOSITS:** A cap (defined by `MAX_DEPOSITS` variable) is set on the number of deposits per wallet to manage iterations within a single transaction. Users needing more stakes must use additional wallet addresses.

#### Governance and Voting

`ArcadeStakingRewards.sol` utilizes the [Council Kit](https://github.com/delvtech/council-kit/wiki/Voting-Vaults-Overview) LockingVault deployment [here](https://etherscan.io/address/0x7a58784063D41cb78FBd30d271F047F0b9156d6e#code) as its governance operations foundation.

- **Voting Power:** Staking tokens grant users voting power in ArcadeDAO governance. A user’s voting power is determined by the quantity of ARCDWETH tokens they have committed and its representation of the user’s ARCD holdings in the ARCDWETH UniswapV2Pair contract.  To calculate the user's voting power, a conversion rate is set in the locking pool at deployment time. The user’s voting power is the product of their deposited ARCDWETH stake amount and this conversion rate.

- **Automatic Delegation:** Voting power is automatically accrued and delegated without additional transactions by the user.

### Known Gotchas

- **Utilization of Unaccrued Reward Tokens:** Un-accrued reward tokens should be incorporated into new `reward` amounts specified in future `notifyRewardAmount()` calls. This is necessary because these tokens cannot be retrieved by `recoverERC20()` unless the contract's `totalSupply()` equals zero, a condition that may never be met given the likelihood of continuous stakeholder participation.


<br>


## Development and Testing

To build and test any of the contracts, use:

- **Build:** `$ forge build`
- **Test:** `$ forge test`