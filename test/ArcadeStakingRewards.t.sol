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
    uint256 public constant ONE_DAY = 60 * 60 * 24;
    uint256 public constant ONE_WEEK = ONE_DAY * 7;
    uint256 public constant TWO_WEEKS = ONE_WEEK * 2;
    uint256 public constant THREE_WEEKS = ONE_WEEK * 3;

    address owner = address(0x1);
    address admin = address(0x2);
    address userA = address(0x3);
    address userB = address(0x4);

    function setUp() public {
        rewardsToken = new MockERC20("Rewards Token", "RWD");
        stakingToken = new MockERC20("Staking Token", "STK");
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(rewardsToken),
            address(stakingToken),
            ONE_WEEK,
            TWO_WEEKS,
            THREE_WEEKS,
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
        stakingRewards = new ArcadeStakingRewards(
            owner,
            address(0),
            address(rewardsToken),
            address(stakingToken),
            ONE_WEEK,
            TWO_WEEKS,
            THREE_WEEKS,
            1.1e18,
            1.3e18,
            1.5e18
        );

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(0),
            address(stakingToken),
            ONE_WEEK,
            TWO_WEEKS,
            THREE_WEEKS,
            1.1e18,
            1.3e18,
            1.5e18
        );

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(rewardsToken),
            address(0),
            ONE_WEEK,
            TWO_WEEKS,
            THREE_WEEKS,
            1.1e18,
            1.3e18,
            1.5e18
        );
    }

    function testStake() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake);

        // user stakes staking tokens
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Medium);

        uint256 poolTotalSupply = stakingRewards.totalSupply();
        assertEq(poolTotalSupply, userStake);
    }

    function testStakeZeroToken() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASR_ZeroAmount()"));

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake);

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.stake(0, IArcadeStakingRewards.Lock.Short);
    }

    function testWithdraw() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Medium);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(userA);

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + TWO_WEEKS);

        stakingRewards.withdraw(userStake, 0);
        uint256 balanceAfterWithdraw = stakingToken.balanceOf(userA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
    }

    function testWithdrawAll() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake * 3);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake * 3);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Medium);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Long);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Short);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(userA);

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + THREE_WEEKS);

        stakingRewards.withdrawAll();
        uint256 balanceAfterWithdraw = stakingToken.balanceOf(userA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + (userStake * 3));
        assertEq(poolTotalSupplyBeforeWithdraw, userStake * 3);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
    }

    function testWithdrawZeroToken() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Long);

        bytes4 selector = bytes4(keccak256("ASR_ZeroAmount()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.withdraw(0, 0);
    }

    function testWithdrawMoreThanBalance() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Short);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASR_BalanceAmount()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.withdraw(30e18, 0);
    }

    // Partial withdraw after lock period.
    function testPartialWithdrawAfterLock() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Medium);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();

        // increase blocckhain to end lock period
        vm.warp(block.timestamp + TWO_WEEKS);

        stakingRewards.withdraw(userStake / 2, 0);
        uint256 balanceAfterWithdraw = stakingToken.balanceOf(userA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, userStake / 2);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, userStake / 2);
    }

    function testClaimReward() public {
        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // on the same day as the reward amount and period are set,
        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);

        // increase blockchain time to the end of the reward period
        vm.warp(block.timestamp + 8 days);

        uint256 reward = stakingRewards.earned(userA, 0);

        // user calls getReward
        stakingRewards.claimReward(0);

        // check that user has received rewardsTokens
        assertEq(rewardsToken.balanceOf(userA), reward);
    }

    function testClaimRewardAll() public {
        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, 20e18 * 2);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // on the same day as the reward amount and period are set,
        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18 * 2);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);

        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Long);

        // increase blockchain time to the end of the reward period
        vm.warp(block.timestamp + 8 days);

        uint256 reward = stakingRewards.earned(userA, 0);
        uint256 reward1 = stakingRewards.earned(userA, 1);

        // user calls getRewards
        stakingRewards.claimRewardAll();

        // check that user has received rewardsTokens
        assertEq(rewardsToken.balanceOf(userA), reward + reward1);
    }

    function testExitAll() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake * 2);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake * 2);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Medium);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Long);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(userA);

        assertEq(rewardsToken.balanceOf(userA), 0);

        // increase blockhain to end lock period
        vm.warp(block.timestamp + THREE_WEEKS);

        uint256 reward = stakingRewards.earned(userA, 0);
        uint256 reward2 = stakingRewards.earned(userA, 1);

        vm.startPrank(userA);
        stakingRewards.exitAll();

        uint256 balanceAfterWithdraw = stakingToken.balanceOf(userA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake * 2);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake * 2);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
        assertEq(rewardsToken.balanceOf(userA), reward + reward2);
    }

    function testExit() public {
        setUp();

        uint256 userStake = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to user
        stakingToken.mint(userA, userStake);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStake);
        stakingRewards.stake(userStake, IArcadeStakingRewards.Lock.Medium);

        uint256 poolTotalSupplyBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = stakingToken.balanceOf(userA);

        assertEq(rewardsToken.balanceOf(userA), 0);

        // increase blockhain to end lock period
        vm.warp(block.timestamp + TWO_WEEKS);

        uint256 reward = stakingRewards.earned(userA, 0);

        vm.startPrank(userA);
        stakingRewards.exit(0);

        uint256 balanceAfterWithdraw = stakingToken.balanceOf(userA);
        uint256 poolTotalSupplyAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalSupplyBeforeWithdraw, userStake);
        assertEq(poolTotalSupplyAfterWithdraw, 0);
        assertEq(rewardsToken.balanceOf(userA), reward);
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
        stakingRewards.recoverERC20(address(0), 1e18);

        bytes4 selector3 = bytes4(keccak256("ASR_ZeroAmount()"));
        vm.expectRevert(abi.encodeWithSelector(selector3));

        vm.prank(owner);
        stakingRewards.recoverERC20(address(rewardsToken), 0);
    }

    function testRewardsTokenRecoverERC20() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Short);

        bytes4 selector = bytes4(keccak256("ASR_RewardsToken()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        vm.startPrank(owner);
        stakingRewards.recoverERC20(address(rewardsToken), 1e18);
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

    function testInvalidDepositId() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        bytes4 selector = bytes4(keccak256("ASR_InvalidDepositId()"));

        vm.expectRevert(abi.encodeWithSelector(selector));

        vm.startPrank(userA);
        stakingRewards.withdraw(20e18, 0);
    }

    function testNoStake() public {
        setUp();

        uint256 userStakeAmount = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + TWO_WEEKS);

        vm.startPrank(userA);
        stakingRewards.withdraw(20e18, 0);

        bytes4 selector = bytes4(keccak256("ASR_NoStake()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        vm.startPrank(userA);
        stakingRewards.withdraw(20e18, 0);
    }

    function testInvalidLockValue() public {
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        uint256 invalidLock = uint256(IArcadeStakingRewards.Lock.Invalid);
        bytes4 selector = bytes4(keccak256("ASR_InvalidLockValue(uint256)"));

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);

        vm.expectRevert(abi.encodeWithSelector(selector, invalidLock));

        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Invalid);
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
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time
        vm.warp(block.timestamp + 8 days);

        IArcadeStakingRewards.UserStake [] memory userStake = stakingRewards.getUserStakes(userA);
        uint256 userStakedAmount = stakingRewards.balanceOf(userA);

        assertEq(userStake[0].amount, userStakedAmount);
        assertEq(uint256(userStake[0].lock), uint256(IArcadeStakingRewards.Lock.Medium));
        assertEq(userStake[0].unlockTimestamp, (block.timestamp + TWO_WEEKS) - 8 days);
    }

    function testGetActiveStakes() public {
        setUp();

        uint256 userStakeAmount = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount * 3);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes once
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Short);

        // userA makes a second deposit
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);

        // userA makes a third deposit
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of rewards period
        vm.warp(block.timestamp + 8 days);

        // get the user's active stakes
        uint256[] memory activeStakeIds = stakingRewards.getActiveStakes(userA);
        assertEq(activeStakeIds.length, 3);

        // increase blockchain time to end lock period
        vm.warp(block.timestamp + TWO_WEEKS);

        vm.startPrank(userA);
        stakingRewards.exit(1);
        vm.stopPrank();

        uint256[] memory activeStakeIdsAfter = stakingRewards.getActiveStakes(userA);
        assertEq(activeStakeIdsAfter.length, 2);
    }

    function testDetDepositIndicesWithRewards() public {
        setUp();

        uint256 userStakeAmount = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount * 3);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes once
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Short);

        // userA makes a second deposit
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);

        // userA makes a third deposit
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of rewards period
        vm.warp(block.timestamp + 8 days);

        // get the user's active stakes
        uint256[] memory activeStakeIds = stakingRewards.getActiveStakes(userA);
        assertEq(activeStakeIds.length, 3);

        // increase blockchain time to end lock period
        vm.warp(block.timestamp + THREE_WEEKS);

        // get rewards earned by userA
        uint256 rewardA = stakingRewards.earned(userA, 0);
        uint256 rewardA2 = stakingRewards.earned(userA, 2);

        vm.startPrank(userA);
        stakingRewards.exit(1);
        (uint256[] memory rewardedDeposits, uint256[] memory rewardAmounts) = stakingRewards.getDepositIndicesWithRewards();
        vm.stopPrank();

        assertEq(rewardedDeposits.length, 2);
        assertEq(rewardAmounts.length, 2);
        assertEq(rewardAmounts[0], rewardA);
        assertEq(rewardAmounts[1], rewardA2);
    }

    function testGetAmountWithBonus() public {
        setUp();

        uint256 userStakeAmount = 20e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        uint256 userAmountWithBonus = stakingRewards.getAmountWithBonus(userA, 0);
        assertEq(userAmountWithBonus, (userStakeAmount + ((userStakeAmount / 1e18) * 1.3e18)));
    }

    function testRewardPerToken() public {
        setUp();

        uint256 userStakeAmount = 20e18;
        uint256 rewardAmount = 100e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        uint256 rewardPerTokenAmount = stakingRewards.rewardPerToken();
        // since no user has deposited into contract, rewardPerToken should be 0
        assertEq(rewardPerTokenAmount, 0);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time
        vm.warp(block.timestamp + 8 days);

        IArcadeStakingRewards.UserStake memory userStake;
        // Retrieve the entire struct from the mapping
        (
            userStake.lock,
            userStake.unlockTimestamp,
            userStake.amount,
            userStake.rewardPerTokenPaid,
            userStake.rewards
        ) = stakingRewards.stakes(userA, 0);

        uint256 rewardPerTokenAmount2 = stakingRewards.rewardPerToken();
        uint256 rewardRate = rewardAmount / 8 days;
        uint256 amountStakedWithBonus = stakingRewards.getAmountWithBonus(userA, 0);

        assertEq(rewardPerTokenAmount2, (8 days * rewardRate * 1e18) / amountStakedWithBonus);
    }

    /**
    * 2 users stake the same amount, one starts halfway into the staking period.
    */
    function testScenario1() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, 20e18);
        // mint staking tokens to userB
        stakingToken.mint(userB, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time by 1/2 of the rewards period
        vm.warp(block.timestamp + 4 days);

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by userA
        uint256 rewardA = stakingRewards.earned(userA, 0);

        // get rewards earned by userB
        uint256 rewardB  = stakingRewards.earned(userB, 0);

        uint256 tolerance = 1e2;
        // user B should earn 25% of total rewards
        assertApproxEqAbs(rewardB, rewardForDuration / 4, tolerance);
        // user A should earn 75% of total rewards
        assertApproxEqAbs(rewardA, (rewardForDuration * 3) / 4, tolerance);
    }

    /**
    * 2 users stake at the same time, user 2 stakes half the amount of user 1.
    */
    function testScenario2() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, 20e18);
        // mint staking tokens to userB
        stakingToken.mint(userB, 10e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        stakingToken.approve(address(stakingRewards), 10e18);
        // user stakes staking tokens
        stakingRewards.stake(10e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end the rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by userA
        uint256 rewardA = stakingRewards.earned(userA, 0);
        // get rewards earned by userB
        uint256 rewardB = stakingRewards.earned(userB, 0);

        uint256 tolerance = 1e2;
        // user B should earn 1/3 of total rewards
        assertApproxEqAbs(rewardB, rewardForDuration / 3, tolerance);
        // user A should earn 2/3 of total rewards
        assertApproxEqAbs(rewardA, (rewardForDuration * 2) / 3, tolerance);
    }

    /**
    * 1 user stakes on the same day. Second user stakes halfway through the rewards period.
    */
    function testScenario3() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, 20e18);
        // mint staking tokens to userB
        stakingToken.mint(userB, 20e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to half of reward period
        vm.warp(block.timestamp + 4 days);

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // userA unstakes
        vm.startPrank(userA);

        bytes4 selector = bytes4(keccak256("ASR_Locked()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        // user withdraws staking tokens
        stakingRewards.withdraw(20e18, 0);
        vm.stopPrank();

        // increase blockchain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        // get rewards earned by userA
        uint256 rewardA = stakingRewards.earned(userA, 0);
        // get rewards earned by userB
        uint256 rewardB = stakingRewards.earned(userB, 0);

        assertApproxEqAbs(rewardA, (((rewardForDuration / 8) * 4) + ((rewardForDuration / 8) * 4) / 2), 1e5);
        assertApproxEqAbs(rewardB, ((rewardForDuration / 8) * 4) / 2, 1e1);
        assertEq(rewardA, rewardB * 3);
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
        // mint staking tokens to userA
        stakingToken.mint(userA, 20e18);

        // Admin calls notifyRewardAmount to set the reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end of day 4
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for 1/2 the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // rewards earned by userA
        uint256 earnedA = stakingRewards.earned(userA, 0);

        // Admin calls notifyRewardAmount to set the reward rate to half of the
        // initial amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(25e18);

        // increase blockchain time to half of the new rewards period
        vm.warp(block.timestamp + 4 days);

        vm.prank(userA);
        // user withdraws reward tokens from the first reward period
        // and half of the second
        stakingRewards.claimReward(0);

        // increase blockchain time to the end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration2 = stakingRewards.getRewardForDuration();

        // get rewards earned by userA after the first reward rate change
        uint256 earnedA2 = stakingRewards.earned(userA, 0);

        // user A earns equal amounts for both reward periods
        assertEq(earnedA, earnedA2);

        // Rewards for the first half of the rewards duration should equal to the total rewards
        // for the entire duration of the second reward period because the staking amount was
        // halved but the reward period was doubled
        assertEq(rewardForDuration, rewardForDuration2);
    }

    /**
    * 1 user stakes. After the end of the staking rewards period, notifyRewardAmount is called again
    * with an reward amount that is half of the previous one.
    */
    function testScenario5() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, 20e18);

        // Admin calls notifyRewardAmount to set the reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.stake(20e18, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for full the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        // rewards earned by userA
        uint256 earnedA = stakingRewards.earned(userA, 0);

        // increase blockchain time for 5 days in between 2 reward periods
        vm.warp(block.timestamp + 5 days);

        // Admin calls notifyRewardAmount to set a new reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(25e18);

        // increase blockchain time to end of the new rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the new duration
        uint256 rewardForDuration2 = stakingRewards.getRewardForDuration();
        // rewards earned by userA
        uint256 earnedA2 = stakingRewards.earned(userA, 0);

        // Rewards for the second staking period is half of the first staking period
        assertEq(rewardForDuration / 2, rewardForDuration2);

        uint256 tolerance = 1e10;
        assertApproxEqAbs(earnedA2, earnedA + rewardForDuration2, tolerance);
    }

    /**
    * 1 user makes multiple deposits. Each deposit has a different lock period and is a different
    * amount. After the lock period, the user calls exit().
    */
    function testMultipleDeposits_Exit() public {
        setUp();

        uint256 userStakeAmount = 20e18;
        uint256 userStakeAmount2 = 10e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount + userStakeAmount2);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount2);
        // userB stakes staking tokens
        stakingRewards.stake(userStakeAmount2, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of long lock period
        vm.warp(block.timestamp + 8 days);

        uint256 rewardPerTokenAmount = stakingRewards.rewardPerToken();

        uint256 balanceOfA = stakingRewards.balanceOf(userA);
        assertEq(balanceOfA, userStakeAmount + userStakeAmount2);

        IArcadeStakingRewards.UserStake[] memory allUserStakes = stakingRewards.getUserStakes(userA);
        assertEq(allUserStakes.length, 2);

        uint256 stakedAmountWithBonus = (userStakeAmount + ((userStakeAmount / 1e18) * 1.3e18));
        uint256 stakedAmountWithBonus2 = (userStakeAmount2 + ((userStakeAmount2 / 1e18) * 1.5e18));

        // rewards earned by userA
        uint256 rewards = stakingRewards.earned(userA, 0);
        uint256 rewards1 = stakingRewards.earned(userA, 1);
        assertEq(stakingRewards.getAmountWithBonus(userA, 0), stakedAmountWithBonus);
        assertEq(stakingRewards.getAmountWithBonus(userA, 1), stakedAmountWithBonus2);

        uint256 tolerance = 1e10;
        assertApproxEqAbs(rewards, ((((stakedAmountWithBonus) * rewardPerTokenAmount)) / ONE), tolerance);
        assertApproxEqAbs(rewards1, ((((stakedAmountWithBonus2) * rewardPerTokenAmount)) / ONE), tolerance);

        // increase blocckhain to end long lock period
        vm.warp(block.timestamp + THREE_WEEKS);

        // userA withdraws
        vm.startPrank(userA);
        stakingRewards.exitAll();
        vm.stopPrank();

        assertEq(userStakeAmount + userStakeAmount2, stakingToken.balanceOf(userA));
        assertEq(rewards + rewards1, rewardsToken.balanceOf(userA));
    }

    /**
    * 2 users makes multiple deposits with 4 days in between (half the reward period). After the
    * lock period, userB partially withdraws 1/2 of their second deposit. notifyRewardAmount() is
    * is called a second time. After the reward period, userA and userB withdraw.
    */
    function testMultipleDeposits_PartialWithdraw() public {
        setUp();

        uint256 userStakeAmount = 20e18;
        uint256 userStakeAmount2 = 10e18;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 200e18);
        // mint staking tokens to userA
        stakingToken.mint(userA, userStakeAmount + userStakeAmount2);
        // mint staking tokens to userB
        stakingToken.mint(userB, userStakeAmount + userStakeAmount2);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        uint256 currentTime = block.timestamp;

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        stakingToken.approve(address(stakingRewards), userStakeAmount + userStakeAmount2);
        // userA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);

        // userB stakes staking tokens
        stakingRewards.stake(userStakeAmount2, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        uint256 fourDaysLater = currentTime + 4 days;
        // increase blockchain time to half of the rewards period
        vm.warp(fourDaysLater);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        stakingToken.approve(address(stakingRewards), userStakeAmount + userStakeAmount2);
        // userA stakes staking tokens
        stakingRewards.stake(userStakeAmount, IArcadeStakingRewards.Lock.Medium);

        // userB stakes staking tokens
        stakingRewards.stake(userStakeAmount2, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        uint256 afterLock = currentTime + THREE_WEEKS;
        // increase blockchain time to end long lock cycle
        vm.warp(afterLock);

        // check that the rewards of userA are double of those of user B
        uint256 rewardsA = stakingRewards.earned(userA, 0);
        uint256 rewardsA1 = stakingRewards.earned(userA, 1);
        uint256 rewardsB = stakingRewards.earned(userB, 0);
        uint256 rewardsB1 = stakingRewards.earned(userB, 1);

        uint256 tolerance = 1e2;
        assertApproxEqAbs(rewardsA / 3, rewardsB, tolerance);
        assertApproxEqAbs(rewardsA1 / 3, rewardsB1, tolerance);

        uint256 currentTime2 = block.timestamp;

        // userB withdraws 1/2 of their second
         vm.startPrank(userB);
         stakingRewards.withdraw(userStakeAmount2 / 2 , 1);
         vm.stopPrank();

        // Admin calls notifyRewardAmount again to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);
        vm.stopPrank();

        // increase blockchain time to end long staking period
        uint256 eightDaysLater = currentTime2 + 8 days;
        vm.warp(eightDaysLater);

        uint256 rewardsA_ = stakingRewards.earned(userA, 0);
        uint256 rewardsA1_ = stakingRewards.earned(userA, 1);
        uint256 rewardsB_ = stakingRewards.earned(userB, 0);
        uint256 rewardsB1_ = stakingRewards.earned(userB, 1);

        assertApproxEqAbs(rewardsA_ - rewardsA , rewardsB_ - rewardsB, tolerance);

        // userA withdraws
        vm.startPrank(userA);
        stakingRewards.exitAll();
        vm.stopPrank();

        // userB withdraws
        vm.startPrank(userB);
        stakingRewards.exitAll();
        vm.stopPrank();

        assertEq(userStakeAmount + userStakeAmount2, stakingToken.balanceOf(userA));
        assertEq(userStakeAmount + userStakeAmount2, stakingToken.balanceOf(userB));

        assertEq(rewardsA_ + rewardsA1_, rewardsToken.balanceOf(userA));
        assertEq(rewardsB_ + rewardsB1_ + rewardsB1, rewardsToken.balanceOf(userB));

        uint256 tolerance2 = 1e7;
        assertApproxEqAbs(0, rewardsToken.balanceOf(address(stakingRewards)), tolerance2);
        assertEq(0, stakingToken.balanceOf(address(stakingRewards)));
    }
}

