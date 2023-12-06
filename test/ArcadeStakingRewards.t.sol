// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";
import { MockERC20 } from "../src/test/MockERC20.sol";

contract ArcadeStakingRewardsTest is Test {
    ArcadeStakingRewards stakingRewards;
    MockERC20 rewardsToken;
    MockERC20 stakingToken;

    address owner = address(0x1);
    address admin = address(0x2);
    address lender = address(0x3);

    function setUp() public {
        rewardsToken = new MockERC20("Rewards Token", "RWD");
        stakingToken = new MockERC20("Staking Token", "STK");
        stakingRewards = new ArcadeStakingRewards(owner, admin, address(rewardsToken), address(stakingToken));
    }

    function testGetReward() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100);

        // mint staking tokens to lender
        stakingToken.mint(lender, 20);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50);

        // increase blochain time by 2 days to be within the 7 day rewardsDuration period
        vm.warp(2 days);

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lender);
        stakingToken.approve(address(stakingRewards), 20);
        // lender stakes staking tokens
        stakingRewards.stake(20);

        uint256 reward = stakingRewards.earned(lender);
        // lender calls getReward
        stakingRewards.getReward();

        // check that lender has received rewardsTokens
        assertEq(rewardsToken.balanceOf(lender), reward);
    }
}
