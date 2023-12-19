// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { IArcadeStakingRewards } from "../src/interfaces/IArcadeStakingRewards.sol";
import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";
import { MockERC20 } from "../src/test/MockERC20.sol";

contract ArcadeStakingRewardsTest is Test {
    ArcadeStakingRewards stakingRewards;
    MockERC20 rewardsToken;
    MockERC20 stakingToken;

    uint256 public constant ONE = 1e18;
    uint256 public constant ONE_CYCLE = 60 * 60 * 24 * 28; // 28 days
    uint256 public constant TWO_CYCLE = ONE_CYCLE * 2;
    uint256 public constant THREE_CYCLE = ONE_CYCLE * 3;

    address owner = address(0x1);
    address admin = address(0x2);
    address lenderA = address(0x3);
    address lenderB = address(0x4);
    address lenderC = address(0x5);
    address lenderD = address(0x6);

    function setUp() public {
        rewardsToken = new MockERC20("Rewards Token", "RWD");
        stakingToken = new MockERC20("Staking Token", "STK");
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(rewardsToken),
            address(stakingToken),
            ONE_CYCLE,
            TWO_CYCLE,
            THREE_CYCLE,
            1.1e18,
            1.3e18,
            1.5e18
        );

        // set rewards to duration to an even number of days for easier testing
        vm.prank(owner);
        stakingRewards.setRewardsDuration(8 days);
    }

    function testConstructorZeroAddress() public {
        bytes4 selector = bytes4(keccak256("ASR_ZeroAddress()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards = new ArcadeStakingRewards(owner, address(0x0000000000000000000000000000000000000000), address(rewardsToken), address(stakingToken), ONE_CYCLE, TWO_CYCLE, THREE_CYCLE, 1.1e18, 1.3e18, 1.5e18);

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards = new ArcadeStakingRewards(owner, admin, address(0x0000000000000000000000000000000000000000), address(stakingToken), ONE_CYCLE, TWO_CYCLE, THREE_CYCLE, 1.1e18, 1.3e18, 1.5e18);

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards = new ArcadeStakingRewards(owner, admin, address(rewardsToken), address(0x0000000000000000000000000000000000000000), ONE_CYCLE, TWO_CYCLE, THREE_CYCLE, 1.1e18, 1.3e18, 1.5e18);
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
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.medium);

        uint256 poolTotalSupply = stakingRewards.totalSupply();

        assertEq(poolTotalSupply, userStake);
    }

    function testStakeZeroToken() public {
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

        bytes4 selector = bytes4(keccak256("ASR_ZeroAmount()"));

        // lender approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), userStake);

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.stake(0, IArcadeStakingRewards.Lock.short);
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
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.medium);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(lenderA);

        // increase blochain time by the medium lock duration
        vm.warp(block.timestamp + TWO_CYCLE);

        stakingRewards.withdraw(userStake);
        uint256 balanceAfterWithdraw = stakingToken.balanceOf(lenderA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
    }

    function testWithdrawZeroToken() public {
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
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.long);

        bytes4 selector = bytes4(keccak256("ASR_ZeroAmount()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.withdraw(0);
    }

    function testWithdrawMoreThanBalance() public {
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
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.short);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASR_BalanceAmount()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.withdraw(30e18);
    }

    // Partial withdraw after lock period.
    function testPartialWithdrawAfterLock() public {
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
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.medium);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();

        // increase blocckhain to end lock period
        vm.warp(block.timestamp + TWO_CYCLE);

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
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);

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
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.medium);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(lenderA);

        assertEq(rewardsToken.balanceOf(lenderA), 0);

        // increase blockhain to end lock period
        vm.warp(block.timestamp + TWO_CYCLE);

        uint256 reward = stakingRewards.earned(lenderA);

        vm.startPrank(lenderA);
        stakingRewards.exit();

        uint256 balanceAfterWithdraw = stakingToken.balanceOf(lenderA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
        assertEq(rewardsToken.balanceOf(lenderA), reward);
    }

    function testrecoverERC20() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        uint256 balanceBefore = rewardsToken.balanceOf(owner);

        vm.prank(owner);
        stakingRewards.recoverERC20(address(rewardsToken), 100e18);

        uint256 balanceAfter = rewardsToken.balanceOf(owner);

        assertEq(balanceAfter, balanceBefore + 100e18);
    }

    function testRewardTooHigh() public {
        setUp();

        bytes4 selector = bytes4(keccak256("ASR_RewardTooHigh()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(1e18);
    }

    function testCustomRevertRecoverERC20() public {
        setUp();

        bytes4 selector = bytes4(keccak256("ASR_StakingToken()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        vm.prank(owner);
        stakingRewards.recoverERC20(address(stakingToken), 1e18);

        bytes4 selector2 = bytes4(keccak256("ASR_ZeroAddress()"));
        vm.expectRevert(abi.encodeWithSelector(selector2));

        vm.prank(owner);
        stakingRewards.recoverERC20(address(0x0000000000000000000000000000000000000000), 1e18);

        bytes4 selector3 = bytes4(keccak256("ASR_ZeroAmount()"));
        vm.expectRevert(abi.encodeWithSelector(selector3));

        vm.prank(owner);
        stakingRewards.recoverERC20(address(rewardsToken), 0);
    }

    function testCustomRevertSetRewardsDuration() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        bytes4 selector = bytes4(keccak256("ASR_RewardsPeriod()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        vm.prank(owner);
        stakingRewards.setRewardsDuration(7);

        //increase blockchain time past 8 day rewards duration
        vm.warp(block.timestamp + 8 days);

        vm.expectRevert(abi.encodeWithSelector(selector));
        vm.prank(owner);
        stakingRewards.setRewardsDuration(7);
    }

    function testNoStake() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        bytes4 selector = bytes4(keccak256("ASR_NoStake()"));

        vm.expectRevert(abi.encodeWithSelector(selector));

        vm.startPrank(lenderA);
        stakingRewards.withdraw(20e18);
    }

    function testInvalidLockValue() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        uint256 invalidLock = uint256(IArcadeStakingRewards.Lock.invalid);
        bytes4 selector = bytes4(keccak256("ASR_InvalidLockValue(uint256)"));

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), 20e18);

         vm.expectRevert(abi.encodeWithSelector(selector, invalidLock));

        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.invalid);
    }

    function testLastTimeRewardApplicable() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        // reward period duration is set to 8 days (691201 seconds)
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        uint256 lastTimeRewardApplicable = stakingRewards.lastTimeRewardApplicable();

        assertApproxEqAbs(lastTimeRewardApplicable, 8 days, 1e10);
    }

    function testGetUserStakes() public {
        setUp();

        uint256 userStakeAmount = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, userStakeAmount);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), userStakeAmount);
        // lenderA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // increase blochain time
        vm.warp(block.timestamp + 8 days);

        IArcadeStakingRewards.UserStake memory userStake = stakingRewards.getUserStakes(lenderA);
        uint256 userStakedAmount = stakingRewards.balanceOf(lenderA);

        assertEq(userStake.amount, userStakedAmount);
        assertEq(uint256(userStake.lock), uint256(IArcadeStakingRewards.Lock.medium));
        assertEq(userStake.unlockTimestamp, (block.timestamp + TWO_CYCLE) - 8 days);
        assertEq(userStake.amountWithBonus, (userStake.amount + (userStake.amount / 1e18) * 1.3e18));
    }

    function testRewardPerToken() public {
        setUp();

        uint256 userStakeAmount = 20e18;
        uint256 rewardAmount = 100e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // mint staking tokens to lenderA
        stakingToken.mint(lenderA, userStakeAmount);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        uint256 rewardPerTokenAmount = stakingRewards.rewardPerToken();
        // since no user has deposited into contract, rewardPerToken should be 0
        assertEq(rewardPerTokenAmount, 0);

        // lenderA approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderA);
        stakingToken.approve(address(stakingRewards), userStakeAmount);
        // lenderA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // increase blochain time
        vm.warp(block.timestamp + 8 days);

        IArcadeStakingRewards.UserStake memory userStake;
        // Retrieve the entire struct from the mapping
        (userStake.amount, userStake.amountWithBonus, userStake.unlockTimestamp, userStake.rewardPerTokenPaid, userStake.rewards, userStake.lock) = stakingRewards.stakes(lenderA);

        uint256 rewardPerTokenAmount2 = stakingRewards.rewardPerToken();
        uint256 rewardRate = rewardAmount / 8 days;

        assertEq(rewardPerTokenAmount2, (8 days * rewardRate * 1e18) / userStake.amountWithBonus);
    }

    /**
    * 2 users stake the same amount, one starts halfway into the staking period.
    */
    function testScenario1() public {
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
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // increase blochain time by 1/2 of the rewards period
        vm.warp(block.timestamp + 4 days);

        // lenderB approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderB);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // increase blochain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // get rewards earned by lenderB
        uint256 earnedB = stakingRewards.earned(lenderB);

        uint256 tolerance = 1e2;
        // user B should earn 25% of total rewards
        assertApproxEqAbs(earnedB, rewardForDuration / 4, tolerance);
        // user A should earn 75% of total rewards
        assertApproxEqAbs(earnedA, (rewardForDuration * 3) /4, tolerance);
    }

    /**
    * 2 users stake at the same time, user 2 stakes half the amount of user 1.
    */
    function testScenario2() public {
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
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // lenderB approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderB);
        stakingToken.approve(address(stakingRewards), 10e18);
        // lender stakes staking tokens
        stakingRewards.stake(10e18, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // increase blochain time to end the rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by lenderA
        uint256 earnedA = stakingRewards.earned(lenderA);

        // get rewards earned by lenderB
        uint256 earnedB = stakingRewards.earned(lenderB);

        uint256 tolerance = 1e2;
        // user B should earn 1/3 of total rewards
        assertApproxEqAbs(earnedB, rewardForDuration / 3, tolerance);
        // user A should earn 2/3 of total rewards
        assertApproxEqAbs(earnedA, (rewardForDuration * 2) / 3, tolerance);
    }

    /**
    * 1 user stakes on the same day. Second user stakes halfway through the rewards period.
    */
    function testScenario3() public {
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
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // increase blockchain time to half of reward period
        vm.warp(block.timestamp + 4 days);

        // lenderB approves stakingRewards contract to spend staking tokens
        vm.startPrank(lenderB);
        stakingToken.approve(address(stakingRewards), 20e18);
        // lender stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);
        vm.stopPrank();

        // lenderA unstakes
        vm.startPrank(lenderA);

        bytes4 selector = bytes4(keccak256("ASR_Locked()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

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

        assertApproxEqAbs(earnedA, (((rewardForDuration / 8) * 4) + ((rewardForDuration / 8) * 4) / 2), 1e5);
        assertApproxEqAbs(earnedB, ((rewardForDuration / 8) * 4) / 2, 1e1);

        assertEq(earnedA, earnedB * 3);
    }

    /**
    * 1 user stakes, halfway through the staking period, notifyRewardAmount is called
    * with a reward amount that is half of the original. (period is extended but reward
    * amount is halved)
    */
    function testScenario4() public {
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
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);
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
    * 1 user stakes. After the end of the staking rewards period, notifyRewardAmount is called again
    * with an reward amount that is half of the previous one.
    * They call getReward() after the second staking rewards period is complete.
    */
    function testScenario5() public {
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
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.medium);
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

        // increase blochain time to end of the new rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the new duration
        uint256 rewardForDuration2 = stakingRewards.getRewardForDuration();
        // rewards earned by lenderA
        uint256 earnedA2 = stakingRewards.earned(lenderA);

        // Rewards for the second staking period is half of the first staking period
        assertEq(rewardForDuration / 2, rewardForDuration2);

        uint256 tolerance = 1e10;
        assertApproxEqAbs(earnedA2, earnedA + rewardForDuration2, tolerance);
    }
}