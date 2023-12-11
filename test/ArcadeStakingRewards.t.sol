// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";
import { MockERC20 } from "../src/test/MockERC20.sol";

/**
 * Needed test:
    * user tries to stake 0 tokens
    * user tries to stake very large amount excedding token supply
    * user tries to withdraw more than their balance
    * changes in reward rate impacting users who staked before and after the change
    * test function recoverERC20
    * when users stake and unstake in the same block
    * reward calculation accuracy over different periods for different amounts
    * accuracy for reward distribution when users stake or withdraw at diffrerent times in the same reward period
    * test for all custom errors
    * test for state changes via events
 */

contract ArcadeStakingRewardsTest is Test {
    ArcadeStakingRewards stakingRewards;
    MockERC20 rewardsToken;
    MockERC20 stakingToken;

    address owner = address(0x1);
    address admin = address(0x2);
    address lenderA = address(0x3);
    address lenderB = address(0x4);
    address lenderC = address(0x5);
    address lenderD = address(0x6);

    function setUp() public {
        rewardsToken = new MockERC20("Rewards Token", "RWD");
        stakingToken = new MockERC20("Staking Token", "STK");
        stakingRewards = new ArcadeStakingRewards(owner, admin, address(rewardsToken), address(stakingToken));

        // set rewards to duration to an even number of days for easier testing
        vm.prank(owner);
        stakingRewards.setRewardsDuration(8 days);
    }

    // test scenarios to add:
    // 1. user stakes tokens
    // 2. user withdraws tokens
    // 3. user gets rewards
    // 4. user exits
    // 5. user withdraws rewards
    // 6. notifyRewardAmount is called with a new reward rate. getRewardForDuration should return the new reward rate
    // 13. 1 user stakes, halfway through the staking period, notifyRewardAmount is called again
    //    with a reward rate that is half of the first. user 1's earned rewards should be half of the original amount
    // 11. 1 user stakes, halfway through the staking period, they withdraw the amount they originally staked.
    //     User 1's rewards should be half what is anticipated for the original amount.
    // 12. 1 user stakes. At the end of the staking period, they stake once again. While staking the second time,
    //     they call getReward(). Theri rewads balance should be the amount anticipated for the first stake.
    // 14. what happens if a user does not withdraw their stake at the rewards period?
    // 15. a user stakes. does not withdraw their reward or their stake. they withdraw their rewards round of staking
    // wiht a new after a second rewards period.



    /** TODO: FIX THIS TEST
    * A user stakes. At the end of the reward period, their balance of the reward token
    * equals their reward earned amount.
    */
    function testGetReward() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100);
        // mint staking tokens to lender
        stakingToken.mint(lenderA, 20);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(60);

        // increase blochain time by 2 days
        vm.warp(1 days);

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20);
        // lender stakes staking tokens
        stakingRewards.stake(20);

        vm.warp(3 days);

        uint256 reward = stakingRewards.earned(lenderA);
        console.log("REWARD", reward);
        // lender calls getReward
        stakingRewards.getReward();

        // check that lender has received rewardsTokens
        assertEq(rewardsToken.balanceOf(lenderA), reward);
    }

    /**
    * 2 users stake the same amount, one starts halfway into the staking period.
    */
    function testScenario7() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);
        // mint staking tokens to lenderB
        stakingToken.mint(lenderB, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // increase blochain time by 1/2 of the rewards period
        vm.warp(block.timestamp + 4 days);

        // lenderB approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderB);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // increase blochain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // get rewards earned by lenderB
        uint256 earnedB = stakingRewards.earned(lenderB);

        // user B should earn 25% of total rewards
        assertEq(earnedB, rewardForDuration / 4);
        // user A should earn 75% of total rewards
        assertEq(earnedA, (rewardForDuration * 3) /4);
    }

    /**
    * 2 users stake the same time, user 2 stakes half the amount of user 1.
    */
    function testScenario8() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);
        // mint staking tokens to lenderB
        stakingToken.mint(lenderB, 10e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // lenderB approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderB);
        stakingToken.approve(address(stakingRewards), 10e18);
        // lender stakes staking tokens
        stakingRewards.stake(10e18);
        vm.stopPrank();

        // increase blochain time to end the rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // get rewards earned by lenderB
        uint256 earnedB = stakingRewards.earned(lenderB);

        // user B should earn 1/3 of total rewards
        assertEq(earnedB, rewardForDuration / 3);
        // user A should earn 2/3 of total rewards
        assertEq(earnedA, (rewardForDuration * 2) / 3);
    }

    /**
    * 1 user stakes, halfway through the staking period, they add to their stake
    * an amount equal the first amount they staked.
    */
    function testScenario9() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 10e18);
        // lender stakes staking tokens
        stakingRewards.stake(10e18);
        vm.stopPrank();

        // increase blochain time by 4 days
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for 1/2 the duration
        uint256 rewardForDurationHalfway = stakingRewards.getRewardForDuration();

        // lenderA stakes more
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 10e18);
        // lender stakes staking tokens
        stakingRewards.stake(10e18);
        vm.stopPrank();

        // increase blochain time to end the rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // user A should earn 100% of total rewards
        assertEq(earnedA, rewardForDuration);

        // Rewards for the first half of the rewards duration should equal to the total rewards
        // for the entire duration because the staking amount was doubled halfway through the period
        assertEq(rewardForDurationHalfway, rewardForDuration);
    }

    /**
    * 2 users stake on the same day. One user unstakes halfway through the rewards period.
    */
    function testScenario10() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);
        // mint staking tokens to lenderB
        stakingToken.mint(lenderB, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // lenderB approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderB);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // increase blochain time to end of day 4
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for 1/2 the duration
        uint256 rewardForDurationHalfway = stakingRewards.getRewardForDuration();
        console.log("rewardForDurationHalfway", rewardForDurationHalfway);

        // lenderA unstakes
        vm.startPrank(lenderA);
        // lender withdraws staking tokens
        stakingRewards.withdraw(20e18);
        vm.stopPrank();

        // increase blochain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        console.log("rewardForDuration", rewardForDuration);

        // get rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);
        console.log("earnedA", earnedA);

        // get rewards earned by lenderB
        uint256 earnedB = stakingRewards.earned(lenderB);
        console.log("earnedB", earnedB);

        // user A should earn 1/3 of total rewards
        assertApproxEqAbs(earnedA, rewardForDuration / 4, 0);

        // user A should earn 2/3 of total rewards
        assertApproxEqAbs(earnedB, (rewardForDuration * 3) / 4, 0);

        // Rewards for the first half of the rewards duration should equal to the total rewards
        // for the entire duration because the staking amount was halved but the period was doubled
        assertEq(rewardForDurationHalfway, rewardForDuration);
    }

}