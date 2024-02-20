// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { IArcadeStakingRewards } from "../src/interfaces/IArcadeStakingRewards.sol";
import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";
import { MockERC20 } from "../src/test/MockERC20.sol";

contract ArcadeStakingRewardsTest is Test {
    ArcadeStakingRewards stakingRewards;

    MockERC20 rewardsToken;
    MockERC20 lpToken;
    MockERC20 otherToken;

    uint256 public constant ONE = 1e18;
    uint32 public constant ONE_DAY = 60 * 60 * 24;
    uint32 public constant ONE_MONTH = ONE_DAY * 30;
    uint32 public constant TWO_MONTHS = ONE_MONTH * 2;
    uint32 public constant THREE_MONTHS = ONE_MONTH * 3;
    uint256 public constant MAX_DEPOSITS = 20;
    uint256 public constant LP_TO_ARCD_DENOMINATOR = 1e3;
    uint256 public immutable LP_TO_ARCD_RATE = 2;

    address zeroAddress = address(0x0);
    address owner = address(0x1);
    address admin = address(0x2);
    address userA = address(0x3);
    address userB = address(0x4);
    address userC = address(0x5);
    address userD = address(0x6);

    // staleBlockNum has to be a number in the past, lower than the current block number.
    // upon deployment, update staleBlockNum to be relevant in the realm of mainnet
    uint256 STALE_BLOCK_LAG = 100;
    uint256 currentBlock = 101;
    uint256 currentTime;

    function setUp() public {
        rewardsToken = new MockERC20("Rewards Token", "RWD");
        otherToken = new MockERC20("Other Token", "OTHR");
        lpToken = new MockERC20("LP Token", "LPT");

        // advance the block number to a number higher than the STALE_BLOCK_LAG
        vm.roll(101);

        currentTime = block.timestamp;

        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(rewardsToken),
            address(lpToken),
            ONE_MONTH,
            TWO_MONTHS,
            THREE_MONTHS,
            LP_TO_ARCD_RATE,
            STALE_BLOCK_LAG
        );

        // set rewards to duration to an even number of days for easier testing
        vm.prank(owner);
        stakingRewards.setRewardsDuration(8 days);
    }

    function testConvertLPToArcd() public {
        setUp();

        lpToken.mint(userA, 20e18);

        uint256 userStake = lpToken.balanceOf(userA);
        uint256 convertedStake = stakingRewards.convertLPToArcd(userStake);

        assertEq(convertedStake, (userStake * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR);
    }

    function testConstructorZeroAddress() public {
        bytes4 selector = bytes4(keccak256("ASR_ZeroAddress(string)"));
        bytes4 selector2 = bytes4(keccak256("ASR_ZeroConversionRate()"));

        vm.expectRevert(abi.encodeWithSelector(selector, "rewardsDistribution"));
        stakingRewards = new ArcadeStakingRewards(
            owner,
            address(0),
            address(rewardsToken),
            address(lpToken),
            ONE_MONTH,
            TWO_MONTHS,
            THREE_MONTHS,
            LP_TO_ARCD_RATE,
            STALE_BLOCK_LAG
        );

        vm.expectRevert(abi.encodeWithSelector(selector, "rewardsToken"));
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(0),
            address(lpToken),
            ONE_MONTH,
            TWO_MONTHS,
            THREE_MONTHS,
            LP_TO_ARCD_RATE,
            STALE_BLOCK_LAG
        );

        vm.expectRevert(abi.encodeWithSelector(selector, "arcdWethLP"));
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(rewardsToken),
            address(0),
            ONE_MONTH,
            TWO_MONTHS,
            THREE_MONTHS,
            LP_TO_ARCD_RATE,
            STALE_BLOCK_LAG
        );

        vm.expectRevert(abi.encodeWithSelector(selector2));
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(rewardsToken),
            address(lpToken),
            ONE_MONTH,
            TWO_MONTHS,
            THREE_MONTHS,
            0,
            STALE_BLOCK_LAG
        );
    }

    function testUpperLimitBlock() public {
        bytes4 selector = bytes4(keccak256("ASR_UpperLimitBlock(uint256)"));
        uint256 STALE_BLOCK_LAG2 = 105;

        vm.expectRevert(abi.encodeWithSelector(selector, STALE_BLOCK_LAG2));
        stakingRewards = new ArcadeStakingRewards(
            owner,
            admin,
            address(rewardsToken),
            address(lpToken),
            ONE_MONTH,
            TWO_MONTHS,
            THREE_MONTHS,
            LP_TO_ARCD_RATE,
            STALE_BLOCK_LAG2
        );
    }

    function testDeposit() public {
        setUp();

        lpToken.mint(userA, 20e18);

        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);

        // user stakes staking tokens
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        //confirm that delegatee user got voting power eq. to
        // amount staked with bonus
        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);
        uint256 votePowerWithBonus = (stakingRewards.getAmountWithBonus(userA, 0) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;
        assertEq(userVotingPower, votePowerWithBonus);

        uint256 poolTotalDeposits = stakingRewards.totalSupply();
        assertEq(poolTotalDeposits, userStake);
    }

    function testStakeZeroToken() public {
        setUp();

        // LP pool mints LP tokens to userA
        lpToken.mint(userA, 20e18);
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        uint256 userStake = lpToken.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASR_ZeroAmount()"));

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.deposit(0, userB, IArcadeStakingRewards.Lock.Short);
    }

    function testWithdraw() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        //confirm that delegatee user got voting power eq. to
        // amount staked with bonus
        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);
        uint256 votePowerWithBonus = (stakingRewards.getAmountWithBonus(userA, 0) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;
        assertEq(userVotingPower, votePowerWithBonus);

        uint256 poolTotalDepositsBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = lpToken.balanceOf(userA);

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        stakingRewards.withdraw(userStake, 0);
        vm.stopPrank();

        //confirm that delegatee user got voting power eq. to
        // amount staked with bonus
        uint256 userVotingPowerAfter = stakingRewards.queryVotePowerView(userB, block.number);
        assertEq(userVotingPowerAfter, 0);

        uint256 balanceAfterWithdraw = lpToken.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalDepositsBeforeWithdraw, userStake);
        assertEq(poolTotalDepositsAfterWithdraw, 0);
    }

    function testExitAll() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake / 3, userB, IArcadeStakingRewards.Lock.Medium);
        stakingRewards.deposit(userStake / 3, userB, IArcadeStakingRewards.Lock.Long);
        stakingRewards.deposit(userStake / 3, userB, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        //confirm that delegatee user got voting power eq. to
        // amount staked with bonus
        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);
        uint256 votePowerWithBonusAll = (stakingRewards.getTotalUserDepositsWithBonus(userA) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;

        uint256 tolerance = 1e2;
        assertApproxEqAbs(userVotingPower, votePowerWithBonusAll, tolerance);

        uint256 poolTotalDepositsBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = lpToken.balanceOf(userA);

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + THREE_MONTHS);

        vm.prank(userA);
        stakingRewards.exitAll();
        uint256 balanceAfterWithdraw = lpToken.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = stakingRewards.totalSupply();

        uint256 userVotingPowerAfter = stakingRewards.queryVotePowerView(userB, block.number);
        uint256 tolerance2 = 1e7;
        assertApproxEqAbs(userVotingPowerAfter, 0, tolerance2);

        assertApproxEqAbs(balanceAfterWithdraw, balanceBeforeWithdraw + userStake, tolerance);
        assertApproxEqAbs(poolTotalDepositsBeforeWithdraw, userStake, tolerance);
        assertEq(poolTotalDepositsAfterWithdraw, 0);
    }

    function testExit() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        //confirm that delegatee user got voting power eq. to
        // amount staked with bonus
        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);
        uint256 votePowerWithBonus = (stakingRewards.getAmountWithBonus(userA, 0) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;
        assertEq(userVotingPower, votePowerWithBonus);

        uint256 poolTotalDepositsBeforeWithdraw = stakingRewards.totalSupply();
        uint256 balanceBeforeWithdraw = lpToken.balanceOf(userA);

        assertEq(rewardsToken.balanceOf(userA), 0);

        // increase blockhain to end lock period
        vm.warp(block.timestamp + TWO_MONTHS);

        uint256 reward = stakingRewards.getPendingRewards(userA, 0);

        vm.startPrank(userA);
        stakingRewards.exit(0);
        vm.stopPrank();

        //confirm that delegatee no longer has voting power
        uint256 userVotingPowerAfter = stakingRewards.queryVotePowerView(userB, block.number);
        assertEq(userVotingPowerAfter, 0);

        uint256 balanceAfterWithdraw = lpToken.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + userStake);
        assertEq(poolTotalDepositsBeforeWithdraw, userStake);
        assertEq(poolTotalDepositsAfterWithdraw, 0);
        assertEq(rewardsToken.balanceOf(userA), reward);
    }

    function testWithdrawZeroToken() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Long);

        bytes4 selector = bytes4(keccak256("ASR_ZeroAmount()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.withdraw(0, 0);
    }

    function testWithdrawMoreThanBalance() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // LOCKING POOL LP TOKEN STAKING FLOW
        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASR_BalanceAmount()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        vm.startPrank(userA);
        stakingRewards.withdraw(30e18, 0);
        vm.stopPrank();
    }

    // Partial withdraw after lock period.
    function testPartialWithdrawAfterLock() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        //confirm that delegatee user got voting power eq. to
        // amount staked with bonus
        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);
        uint256 votePowerWithBonus = (stakingRewards.getAmountWithBonus(userA, 0) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;
        assertEq(userVotingPower, votePowerWithBonus);

        uint256 poolTotalDepositsBeforeWithdraw = stakingRewards.totalSupply();

        // increase blocckhain to end lock period
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        stakingRewards.withdraw(userStake / 2, 0);
        vm.stopPrank();

        uint256 userVotingPowerAfter = stakingRewards.queryVotePowerView(userB, block.timestamp);
        uint256 tolerance = 1e1;
        assertApproxEqAbs(userVotingPowerAfter, votePowerWithBonus / 2, tolerance);

        uint256 balanceAfterWithdraw = lpToken.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = stakingRewards.totalSupply();

        assertEq(balanceAfterWithdraw, userStake / 2);
        assertEq(poolTotalDepositsBeforeWithdraw, userStake);
        assertEq(poolTotalDepositsAfterWithdraw, userStake / 2);
    }

    function testClaimReward() public {
        setUp();

        lpToken.mint(userA, 20e18);

        // LOCKING POOL LP TOKEN STAKING FLOW
        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // on the same day as the reward amount and period are set,
        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), 20e18);
        // user stakes staking tokens
        stakingRewards.deposit(20e18, userB, IArcadeStakingRewards.Lock.Medium);

        // increase blockchain time to the end of the reward period
        vm.warp(block.timestamp + 8 days);

        uint256 reward = stakingRewards.getPendingRewards(userA, 0);

        // user calls getReward
        stakingRewards.claimReward(0);

        // check that user has received rewardsTokens
        assertEq(rewardsToken.balanceOf(userA), reward);
    }

    function testClaimRewardAll() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA) / 2;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);

        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // on the same day as the reward amount and period are set,
        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake * 2);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);

        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Long);

        // increase blockchain time to the end of the reward period
        vm.warp(block.timestamp + 8 days);

        uint256 reward = stakingRewards.getPendingRewards(userA, 0);
        uint256 reward1 = stakingRewards.getPendingRewards(userA, 1);

        // user calls getRewards
        stakingRewards.claimRewardAll();

        // check that user has received rewardsTokens
        assertEq(rewardsToken.balanceOf(userA), reward + reward1);
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
        stakingRewards.recoverERC20(address(lpToken), 1e18);

        bytes4 selector2 = bytes4(keccak256("ASR_ZeroAddress(string)"));
        vm.expectRevert(abi.encodeWithSelector(selector2, "token"));

        vm.prank(owner);
        stakingRewards.recoverERC20(address(0), 1e18);

        bytes4 selector3 = bytes4(keccak256("ASR_ZeroAmount()"));
        vm.expectRevert(abi.encodeWithSelector(selector3));

        vm.prank(owner);
        stakingRewards.recoverERC20(address(rewardsToken), 0);
    }

    function testRewardsTokenRecoverERC20() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount);
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);

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

        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        stakingRewards.withdraw(userStakeAmount, 0);

        bytes4 selector = bytes4(keccak256("ASR_BalanceAmount()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        vm.startPrank(userA);
        stakingRewards.withdraw(userStakeAmount, 0);
    }

    function testInvalidLockValue() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        uint256 invalidLock = 3;
        bytes4 selector = bytes4(keccak256("Panic(uint256)"));

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);

        // expect the 0x21 panic code for invalid enum values
        vm.expectRevert(abi.encodeWithSelector(selector, 0x21));

        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock(invalidLock));
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

    function testGetTotalUserPendingRewards() public {
        setUp();

        // LP pool mints LP tokens to userA
        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA) / 3;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes once
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);

        // userA makes a second deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);

        // userA makes a third deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of rewards period
        vm.warp(block.timestamp + 8 days);

        uint256 userPendingRewards = stakingRewards.getTotalUserPendingRewards(userA);

        uint256 tolerance = 1e6;
        assertApproxEqAbs(userPendingRewards, 100e18, tolerance);
    }

    function testGetUserStake() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA) / 3;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes once
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);

        // userA makes a second deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);

        // userA makes a third deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of rewards period
        vm.warp(block.timestamp + 8 days);

        (uint8 lock, uint32 unlockTimestamp, uint256 amount, , ) = stakingRewards.getUserStake(userA, 1);

        assertEq(lock, uint256(IArcadeStakingRewards.Lock.Medium));
        uint256 tolerance = 1;
        assertApproxEqAbs(unlockTimestamp, TWO_MONTHS, tolerance);
        assertEq(amount, userStakeAmount);
    }

    function testGetActiveStakes() public {
        setUp();

        // LP pool mints LP tokens to userA
        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA) / 3;

        // mint rewardsTokens to stakingRewards contract
        uint256 rewardAmount = 100e18;
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes once
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);
        // userA makes a second deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
        // userA makes a third deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of rewards period
        vm.warp(block.timestamp + 8 days);

        // get the user's active stakes
        uint256[] memory activeStakeIds = stakingRewards.getActiveStakes(userA);
        assertEq(activeStakeIds.length, 3);

        // increase blockchain time to end lock period
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        stakingRewards.exit(1);
        vm.stopPrank();

        uint256[] memory activeStakeIdsAfter = stakingRewards.getActiveStakes(userA);
        assertEq(activeStakeIdsAfter.length, 2);
    }

    function testGetDepositIndicesWithRewards() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA) / 3;

        // LOCKING POOL LP TOKEN STAKING FLOW
        // mint rewardsTokens to stakingRewards contract
        uint256 rewardAmount = 100e18;
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes once
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);
        // userA makes a second deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
        // userA makes a third deposit
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of rewards period
        vm.warp(block.timestamp + 8 days);

        // get the user's active stakes
        uint256[] memory activeStakeIds = stakingRewards.getActiveStakes(userA);
        assertEq(activeStakeIds.length, 3);

        // increase blockchain time to end lock period
        vm.warp(block.timestamp + THREE_MONTHS);

        // get rewards earned by userA
        uint256 rewardA = stakingRewards.getPendingRewards(userA, 0);
        uint256 rewardA2 = stakingRewards.getPendingRewards(userA, 2);

        vm.startPrank(userA);
        stakingRewards.claimReward(1);
        vm.stopPrank();

        (uint256[] memory rewardedDeposits, uint256[] memory rewardAmounts) = stakingRewards.getDepositIndicesWithRewards(userA);

        assertEq(rewardedDeposits.length, 2);
        assertEq(rewardAmounts.length, 2);
        assertEq(rewardAmounts[0], rewardA);
        assertEq(rewardAmounts[1], rewardA2);
    }

    function testGetAmountWithBonus() public {
        setUp();

        // LP pool mints LP tokens to userA
        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        uint256 rewardAmount = 100e18;
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        uint256 votePowerWithBonus = (stakingRewards.getAmountWithBonus(userA, 0) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;
        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);
        assertEq(votePowerWithBonus, userVotingPower);
    }

    function testGetTotalUserDepositsWithBonus() public {
        setUp();

        // LP pool mints LP tokens to userA
        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA) / 3;

        // mint rewardsTokens to stakingRewards contract
        uint256 rewardAmount = 100e18;
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes staking tokens
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Long);
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        uint256 amountWithBonus1 = stakingRewards.getAmountWithBonus(userA, 0);
        uint256 amountWithBonus2 = stakingRewards.getAmountWithBonus(userA, 1);
        uint256 amountWithBonus3 = stakingRewards.getAmountWithBonus(userA, 2);

        uint256 totalDepositsWithBonus = stakingRewards.getTotalUserDepositsWithBonus(userA);
        assertEq(totalDepositsWithBonus, amountWithBonus1 + amountWithBonus2 + amountWithBonus3);
    }

    function testGetLastDepositId() public {
        setUp();

        // LP pool mints LP tokens to userA
        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA) / 3;

        // mint rewardsTokens to stakingRewards contract
        uint256 rewardAmount = 100e18;
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount * 3);
        // userA stakes staking tokens
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Long);
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        uint256 lastDepositId = stakingRewards.getLastDepositId(userA);
        assertEq(lastDepositId, 2);
    }

    function testRewardPerToken() public {
        setUp();

        // LP pool mints LP tokens to userA
        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        uint256 rewardAmount = 100e18;
        rewardsToken.mint(address(stakingRewards), rewardAmount);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(rewardAmount);

        uint256 rewardPerTokenAmount = stakingRewards.rewardPerToken();
        // since no user has deposited into contract, rewardPerToken should be 0
        assertEq(rewardPerTokenAmount, 0);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount);
        // userA stakes staking tokens
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
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

    function testBalanceOf() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // userA stakes staking tokens
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        uint256 depositBalance = stakingRewards.balanceOfDeposit(userA, 0);
        assertEq(depositBalance, userStake);
    }

    /**
    * 2 users stake the same amount, one starts halfway into the staking period.
    */
    function testScenario1() public {
        // deploy and initialize contracts, set rewards duration to 8 days
        setUp();

        lpToken.mint(userA, 20e18);
        lpToken.mint(userB, 20e18);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        uint256 userStake = lpToken.balanceOf(userA);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time by 1/2 of the rewards period
        vm.warp(block.timestamp + 4 days);

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by userA
        uint256 rewardA = stakingRewards.getPendingRewards(userA, 0);

        // get rewards earned by userB
        uint256 rewardB  = stakingRewards.getPendingRewards(userB, 0);

        uint256 tolerance = 1e3;
        // user B should earn 25% of total rewards
        assertApproxEqAbs(rewardB, rewardForDuration / 4, tolerance);
        // user A should earn 75% of total rewards
        assertApproxEqAbs(rewardA, (rewardForDuration * 3) / 4, tolerance);
    }

    /**
    * 2 users stake at the same time, user 2 stakes half the amount of user 1.
    */
    function testScenario2() public {
        setUp();

        lpToken.mint(userA, 20e18);
        lpToken.mint(userB, 20e18);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        uint256 userStake = lpToken.balanceOf(userA);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        lpToken.approve(address(stakingRewards), userStake / 2);
        // user stakes staking tokens
        stakingRewards.deposit(userStake / 2, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end the rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // get rewards earned by userA
        uint256 rewardA = stakingRewards.getPendingRewards(userA, 0);
        // get rewards earned by userB
        uint256 rewardB = stakingRewards.getPendingRewards(userB, 0);

        uint256 tolerance = 1e3;
        // user B should earn 1/3 of total rewards
        assertApproxEqAbs(rewardB, rewardForDuration / 3, tolerance);
        // user A should earn 2/3 of total rewards
        assertApproxEqAbs(rewardA, (rewardForDuration * 2) / 3, tolerance);
    }

    /**
    * 1 user stakes, second user stakes halfway through the rewards period.
    */
    function testScenario3() public {
        setUp();

        lpToken.mint(userA, 20e18);
        lpToken.mint(userB, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to half of reward period
        vm.warp(block.timestamp + 4 days);

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // userA unstakes
        vm.startPrank(userA);

        bytes4 selector = bytes4(keccak256("ASR_Locked()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        // user withdraws staking tokens
        stakingRewards.withdraw(userStake, 0);
        vm.stopPrank();

        // increase blockchain time to end the rewards period
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        // get rewards earned by userA
        uint256 rewardA = stakingRewards.getPendingRewards(userA, 0);
        // get rewards earned by userB
        uint256 rewardB = stakingRewards.getPendingRewards(userB, 0);

        assertApproxEqAbs(rewardA, (((rewardForDuration / 8) * 4) + ((rewardForDuration / 8) * 4) / 2), 1e5);
        assertApproxEqAbs(rewardB, ((rewardForDuration / 8) * 4) / 2, 1e3);
        assertApproxEqAbs(rewardA, rewardB * 3, 1e3);
    }

    /**
    * 1 user stakes, halfway through the staking period, notifyRewardAmount is called
    * with a reward amount that is half of the original. (period is extended but reward
    * amount is halved)
    */
    function testScenario4() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end of day 4
        vm.warp(block.timestamp + 4 days);

        // get the total rewards for 1/2 the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();

        // rewards earned by userA
        uint256 earnedA = stakingRewards.getPendingRewards(userA, 0);

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
        uint256 earnedA2 = stakingRewards.getPendingRewards(userA, 0);

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
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end rewards period
        vm.warp(block.timestamp + 8 days);

        // get the total rewards for full the duration
        uint256 rewardForDuration = stakingRewards.getRewardForDuration();
        // rewards earned by userA
        uint256 earnedA = stakingRewards.getPendingRewards(userA, 0);

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
        uint256 earnedA2 = stakingRewards.getPendingRewards(userA, 0);

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

        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA);
        lpToken.mint(userA, 50e18);
        uint256 userStakeAmount2 = lpToken.balanceOf(userA) - userStakeAmount;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount);
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Medium);
        lpToken.approve(address(stakingRewards), userStakeAmount2);
        stakingRewards.deposit(userStakeAmount2, userB, IArcadeStakingRewards.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of staking period
        vm.warp(block.timestamp + 8 days);

        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);

        uint256 balanceOfA = stakingRewards.getTotalUserDeposits(userA);
        assertEq(balanceOfA, userStakeAmount + userStakeAmount2);

        uint256 lastStakeId = stakingRewards.getLastDepositId(userA);
        assertEq(lastStakeId, 1);

        // rewards earned by userA
        uint256 rewards = stakingRewards.getPendingRewards(userA, lastStakeId - 1);
        uint256 rewards1 = stakingRewards.getPendingRewards(userA, lastStakeId);
        assertEq(
            (
                ((stakingRewards.getAmountWithBonus(userA, lastStakeId - 1) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR)
                +
                ((stakingRewards.getAmountWithBonus(userA, lastStakeId) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR)
            )
            , userVotingPower
        );

        // increase blocckhain to end long lock period
        vm.warp(block.timestamp + THREE_MONTHS);

        // userA withdraws
        vm.startPrank(userA);
        stakingRewards.exitAll();
        vm.stopPrank();

        assertEq(userStakeAmount + userStakeAmount2, lpToken.balanceOf(userA));
        assertEq(rewards + rewards1, rewardsToken.balanceOf(userA));
    }

    /**
    * 2 users makes multiple deposits with 4 days in between (half the reward period). After the
    * lock period, userB partially withdraws 1/2 of their second deposit. notifyRewardAmount() is
    * is called a second time. After the reward period, userA and userB withdraw.
    */
    function testMultipleDeposits_PartialWithdraw() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA);
        lpToken.mint(userA, 50e18);
        uint256 userStakeAmount2 = lpToken.balanceOf(userA) - userStakeAmount;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount + userStakeAmount2);
        stakingRewards.deposit(userStakeAmount, userC, IArcadeStakingRewards.Lock.Medium);
        stakingRewards.deposit(userStakeAmount2, userC, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        uint256 fourDaysLater = currentTime + 4 days;
        // increase blockchain time to half of the rewards period
        vm.warp(fourDaysLater);

        lpToken.mint(userB, 20e18);
        uint256 userStakeAmountB = lpToken.balanceOf(userB);
        lpToken.mint(userB, 50e18);
        uint256 userStakeAmountB2 = lpToken.balanceOf(userB) - userStakeAmountB;

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        lpToken.approve(address(stakingRewards), userStakeAmountB + userStakeAmountB2);
        // userA stakes staking tokens
        stakingRewards.deposit(userStakeAmountB, userD, IArcadeStakingRewards.Lock.Medium);
        // userB stakes staking tokens
        stakingRewards.deposit(userStakeAmountB2, userD, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        uint256 afterLock = currentTime + THREE_MONTHS;
        // increase blockchain time to end long lock cycle
        vm.warp(afterLock);

        // check that the rewards of userA are double of those of user B
        uint256 rewardsA = stakingRewards.getPendingRewards(userA, 0);
        uint256 rewardsA1 = stakingRewards.getPendingRewards(userA, 1);
        uint256 rewardsB = stakingRewards.getPendingRewards(userB, 0);
        uint256 rewardsB1 = stakingRewards.getPendingRewards(userB, 1);

        uint256 tolerance = 1e3;
        assertApproxEqAbs(rewardsA / 3, rewardsB, tolerance);
        assertApproxEqAbs(rewardsA1 / 3, rewardsB1, tolerance);

        uint256 currentTime2 = block.timestamp;

        // userB withdraws 1/2 of their second deposit
        vm.startPrank(userB);
        stakingRewards.withdraw(userStakeAmountB2 / 2, 1);
        vm.stopPrank();

        // Admin calls notifyRewardAmount again to set the reward rate
        rewardsToken.mint(address(stakingRewards), 100e18);
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time to end long staking period
        uint256 eightDaysLater = currentTime2 + 8 days;
        vm.warp(eightDaysLater);

        uint256 rewardsA_ = stakingRewards.getPendingRewards(userA, 0);
        uint256 rewardsA1_ = stakingRewards.getPendingRewards(userA, 1);
        uint256 rewardsB_ = stakingRewards.getPendingRewards(userB, 0);
        uint256 rewardsB1_ = stakingRewards.getPendingRewards(userB, 1);

        uint256 tolerance2 = 1e4;
        assertApproxEqAbs(rewardsA_ - rewardsA , rewardsB_ - rewardsB, tolerance2);

        // userB withdraws
        vm.startPrank(userB);
        stakingRewards.exitAll();
        vm.stopPrank();
        assertEq(userStakeAmountB + userStakeAmountB2, lpToken.balanceOf(userB));
        assertEq(rewardsB_ + rewardsB1_ + rewardsB1, rewardsToken.balanceOf(userB));

        // userA withdraws
        vm.startPrank(userA);
        stakingRewards.exitAll();
        vm.stopPrank();
        assertEq(userStakeAmount + userStakeAmount2, lpToken.balanceOf(userA));
        assertEq(rewardsA_ + rewardsA1_, rewardsToken.balanceOf(userA));

        assertEq(0, lpToken.balanceOf(address(stakingRewards)));
    }

    function testMaxDepositsRevert() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStakeAmount = lpToken.balanceOf(userA) / 20;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        bytes4 selector = bytes4(keccak256("ASR_DepositCountExceeded()"));

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStakeAmount * 20);

        // tries to stake more than MAX_DEPOSITS
        for (uint256 i = 0; i < 20; i++) {
            stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);
        }

        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.deposit(userStakeAmount, userB, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();
    }

    function testChangeDelegation() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA) / 2;

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);

        // user stakes staking tokens
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        //confirm that delegatee user got voting power eq. to
        // amount staked with bonus
        uint256 userVotingPower = stakingRewards.queryVotePowerView(userB, currentBlock);
        uint256 votePowerWithBonus = (stakingRewards.getAmountWithBonus(userA, 0) * LP_TO_ARCD_RATE) / LP_TO_ARCD_DENOMINATOR;
        assertEq(userVotingPower, votePowerWithBonus);

        bytes4 selector = bytes4(keccak256("ASR_ZeroAddress(string)"));
        vm.expectRevert(abi.encodeWithSelector(selector, "delegation"));

        vm.prank(userA);
        stakingRewards.changeDelegation(zeroAddress);

        vm.prank(userA);
        stakingRewards.changeDelegation(userC);

        uint256 userVotingPowerB = stakingRewards.queryVotePowerView(userB, block.timestamp);
        //confirm that delegatee user got the voting power
        uint256 userVotingPowerC = stakingRewards.queryVotePowerView(userC, block.timestamp);
        assertEq(userVotingPowerB, 0);
        assertEq(userVotingPowerC, votePowerWithBonus);

        uint256 poolTotalDeposits = stakingRewards.totalSupply();
        assertEq(poolTotalDeposits, userStake);
    }

    function testPauseUnpause() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake / 2, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        vm.prank(owner);
        stakingRewards.pause();

        bytes4 selector = bytes4(keccak256("EnforcedPause()"));

        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSelector(selector));
        stakingRewards.deposit(userStake / 2, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        vm.prank(owner);
        stakingRewards.unpause();

        vm.startPrank(userA);
        stakingRewards.deposit(userStake / 2, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        uint256 poolTotalDeposits = stakingRewards.totalSupply();
        assertEq(poolTotalDeposits, userStake);
    }

    function testUserStakeDeletedAfterExit() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake, userB, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        stakingRewards.exit(0);
        vm.stopPrank();

        (
            uint8 lock,
            uint32 unlockTimestamp,
            uint256 amount,
            uint256 rewardPerTokenPaid,
            uint256 rewards
        ) = stakingRewards.getUserStake(userA, 0);

        assertEq(lock, 0);
        assertEq(unlockTimestamp, 0);
        assertEq(amount, 0);
        assertEq(rewardPerTokenPaid, 0);
        assertEq(rewards, 0);
    }

    function testUserStakeDeletedAfterExitAll() public {
        setUp();

        lpToken.mint(userA, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(100e18);

        // user approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        stakingRewards.deposit(userStake/2, userB, IArcadeStakingRewards.Lock.Medium);
        stakingRewards.deposit(userStake/2, userB, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        stakingRewards.exitAll();
        vm.stopPrank();

        (
            uint8 lock,
            uint32 unlockTimestamp,
            uint256 amount,
            uint256 rewardPerTokenPaid,
            uint256 rewards
        ) = stakingRewards.getUserStake(userA, 0);
        assertEq(lock, 0);
        assertEq(unlockTimestamp, 0);
        assertEq(amount, 0);
        assertEq(rewardPerTokenPaid, 0);
        assertEq(rewards, 0);

        (
            uint8 lock2,
            uint32 unlockTimestamp2,
            uint256 amount2,
            uint256 rewardPerTokenPaid2,
            uint256 rewards2
        ) = stakingRewards.getUserStake(userA, 1);
        assertEq(lock2, 0);
        assertEq(unlockTimestamp2, 0);
        assertEq(amount2, 0);
        assertEq(rewardPerTokenPaid2, 0);
        assertEq(rewards2, 0);
    }

    // A user stakes. After the reward period is complete, notifyRewardAmount is called
    // again with a higher amount.
    // User rewards for the first period are not boosted by the new higher rewards rate.
    function testNoOverdrawOnRateChange() public {
        setUp();

        lpToken.mint(userA, 20e18);
        lpToken.mint(userB, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(25e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end of the rewards period
        vm.warp(block.timestamp + 8 days);

        // rewards earned by userA
        uint256 earnedA = stakingRewards.getPendingRewards(userA, 0);

        // increase blockchain time for 5 days in between 2 reward periods
        vm.warp(block.timestamp + 5 days);

        // Admin calls notifyRewardAmount with double the initial reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end of the new rewards period
        vm.warp(block.timestamp + 8 days);

        // rewards earned by userB
        uint256 earnedB = stakingRewards.getPendingRewards(userB, 0);

        // The total rewards for userA is the amount they earned in the
        // first period plus an amount equivalent to what userB earned
        // when they started staking in the second period.
        uint256 earnedA2 = stakingRewards.getPendingRewards(userA, 0);

        // Rewards for the second staking period is half of the first staking period
        assertEq(earnedA2, earnedA + earnedB);
    }

    // A user stakes. Before the reward period is complete, notifyRewardAmount is called
    // again with a higher amount.
    // User rewards for the first half of the period are not boosted by the new higher rewards rate.
    function testNoOverdrawOnRateChange2() public {
        setUp();

        lpToken.mint(userA, 20e18);
        lpToken.mint(userB, 20e18);
        uint256 userStake = lpToken.balanceOf(userA);

        // mint rewardsTokens to stakingRewards contract
        rewardsToken.mint(address(stakingRewards), 100e18);
        // Admin calls notifyRewardAmount to set the reward rate
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(25e18);

        // userA approves stakingRewards contract to spend staking tokens
        vm.startPrank(userA);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to middle of the rewards period
        vm.warp(currentTime + 4 days);

        // rewards earned by userA
        uint256 earnedA = stakingRewards.getPendingRewards(userA, 0);

        // Admin calls notifyRewardAmount with double the initial reward amount
        vm.prank(admin);
        stakingRewards.notifyRewardAmount(50e18);

        // userB approves stakingRewards contract to spend staking tokens
        vm.startPrank(userB);
        lpToken.approve(address(stakingRewards), userStake);
        // user stakes staking tokens
        stakingRewards.deposit(userStake, userC, IArcadeStakingRewards.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time to end of the first rewards period
        vm.warp(currentTime + 8 days);

        // rewards earned by userB
        uint256 earnedB = stakingRewards.getPendingRewards(userB, 0);

        // The total rewards for userA is the amount they earned in the
        // first half of the period plus an amount equivalent to what userB
        // earned when they started staking in the middle of the period.
        uint256 earnedA2 = stakingRewards.getPendingRewards(userA, 0);

        // Rewards for the second staking period is half of the first staking period
        assertEq(earnedA2, earnedA + earnedB);
    }
}

