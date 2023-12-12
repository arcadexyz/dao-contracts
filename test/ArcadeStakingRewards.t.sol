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
    * test function recoverERC20
    * when users stake and unstake in the same block
    * reward calculation accuracy over different periods for different amounts
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

    function testStake() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lender
        stakingToken.mint(lenderA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blochain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), userStake);
        // lender stakes staking tokens
        stakingRewards.stake(userStake);

        uint256 poolTotalSupply = stakingRewards.totalSupply();

        assertEq(poolTotalSupply, userStake);
    }

    function testWithdraw() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lender
        stakingToken.mint(lenderA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blochain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(lenderA);

        stakingRewards.withdraw(userStake);
        uint256 balanceAfterWithdraw = stakingToken.balanceOf(lenderA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
    }

    function testPartialWithdraw() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lender
        stakingToken.mint(lenderA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blochain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();

        stakingRewards.withdraw(userStake / 2);
        uint256 balanceAfterWithdraw = stakingToken.balanceOf(lenderA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, userStake / 2);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, userStake / 2);
    }

    function testGetReward() public {
        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lender
        stakingToken.mint(lenderA, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blochain time by 2 days
        vm.warp(block.timestamp + 3 days);

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);

        vm.warp(block.timestamp + 5 days);

        uint256 reward = stakingRewards.earned(lenderA);
        // lender calls getReward
        stakingRewards.getReward();

        // check that lender has received rewardsTokens
        assertEq(rewardsToken.balanceOf(lenderA), reward);
    }

    function testExit() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lender
        stakingToken.mint(lenderA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(lenderA);

        assertEq(rewardsToken.balanceOf(lenderA), 0);

        vm.warp(block.timestamp + 8 days);

        uint256 reward = stakingRewards.earned(lenderA);

        stakingRewards.exit();
        uint256 balanceAfterWithdraw = stakingToken.balanceOf(lenderA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
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
    * 2 users stake at the same time, user 2 stakes half the amount of user 1.
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
    * an amount equal the first amount they are staking.
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

        // lenderA unstakes
        vm.startPrank(lenderA);
        // lender withdraws staking tokens
        stakingRewards.withdraw(20e18);
        vm.stopPrank();

        // increase blochain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        // get rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);
        // get rewards earned by lenderB
        uint256 earnedB = stakingRewards.earned(lenderB);

        // user A should earn 1/3 of total rewards
        assertApproxEqAbs(earnedA, rewardForDuration / 4, 0);

        // user A should earn 2/3 of total rewards
        assertApproxEqAbs(earnedB, (rewardForDuration * 3) / 4, 0);

        // Rewards for the first half of the rewards duration should equal to the total rewards
        // for the entire duration because the staking amount was halved but the period was doubled
        assertEq(rewardForDurationHalfway, rewardForDuration);
    }

    /**
    * 1 user stakes, halfway through the staking period, notifyRewardAmount is called
    * with a reward amount that is half of the original. (period is extended but reward
    * amount is halved)
    */
    function testScenario11() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);

        // Admin calls notifyRewardAmount to set the reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // increase blochain time to end of day 4
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for 1/2 the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // Admin calls notifyRewardAmount to set the reward rate to half of the
        // initial amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(25e18);

        // increase blochain time to half of the new rewards period
        vm.warp(block.timestamp + 4 days);

        vm.prank(lenderA);
        // lender withdraws reward tokens from the first reward period
        // and half of the second
        stakingRewards.getReward();

        // increase blochain time to the end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration2 = stakingRewards.getRewardForDuration();

        // get rewards earned by lenderA after the first reward rate change
        uint256 earnedA3 = stakingRewards.earned(lenderA);

        // user A earns equal amounts for both reward periods
        assertEq(earnedA, earnedA3);

        // Rewards for the first half of the rewards duration should equal to the total rewards
        // for the entire duration of the second reward period because the staking amount was
        // halved but the reward period was doubled
        assertEq(rewardForDuration, rewardForDuration2);
    }

    /**
    * 1 user stakes. At the end of the staking period, they do not withdraw, so their tokens
    * are staked once more when a new notifyRewardAmount is called with an reward amount that is
    * half of the previous one. They call getReward() after the second staking rewards period is
    * complete.
    */
    function testScenario12() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);

        // Admin calls notifyRewardAmount to set the reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // increase blochain time to end rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for full the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        // rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // increase blochain time for 5 days in between 2 reward periods
        vm.warp(block.timestamp + 5 days);

        // Admin calls notifyRewardAmount to set a new reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(25e18);

        // increase blochain time to end of the rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the new duration
        uint256 rewardForDuration2 = stakingRewards.getRewardForDuration();
        // rewards earned by lenderA
        uint256 earnedA2 = stakingRewards.earned(lenderA);

        vm.prank(lenderA);
        // lender withdraws all reward tokens
        stakingRewards.getReward();

        // Rewards for the second staking period is half of the first staking period
        assertEq(rewardForDuration / 2, rewardForDuration2);
        // user earns rewards for both staking periods because they did not withdraw
        assertEq(earnedA2, earnedA + rewardForDuration2);
    }

    /**
    * 1 user stakes, halfway through the staking period, they withdraw the amount they staked.
    */
    function testScenario13() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);

        // Admin calls notifyRewardAmount to set the reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18);
        vm.stopPrank();

        // increase blockchain time to 1/2 rewards period duration
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for full the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        // rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // user earns 1/2 of rewards duration because they withdrew halfway through the period
        assertEq(earnedA, rewardForDuration / 2);

        vm.prank(lenderA);
        // lender withdraws all reward tokens
        stakingRewards.getReward();

        assertEq(rewardsToken.balanceOf(lenderA), earnedA);
    }
}