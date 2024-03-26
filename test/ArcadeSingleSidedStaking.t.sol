// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { IArcadeSingleSidedStaking } from "../src/interfaces/IArcadeSingleSidedStaking.sol";
import { ArcadeSingleSidedStaking } from "../src/ArcadeSingleSidedStaking.sol";
import { AirdropSingleSidedStaking } from "../src/AirdropSingleSidedStaking.sol";
import { MockERC20 } from "../src/test/MockERC20.sol";

contract ArcadeSingleSidedStakingTest is Test {
    using SafeERC20 for IERC20;

    ArcadeSingleSidedStaking singleSidedStaking;
    AirdropSingleSidedStaking airdropSingleSidedStaking;

    MockERC20 arcd;
    MockERC20 otherToken;

    uint32 public constant ONE_DAY = 1 days;
    uint32 public constant ONE_MONTH = 30 days;
    uint32 public constant TWO_MONTHS = 60 days;
    uint32 public constant FIVE_MONTHS = 150 days;
    uint256 public constant MAX_DEPOSITS = 20;

    address zeroAddress = address(0x0);
    address owner = address(0x1);
    address userA = address(0x2);
    address userB = address(0x3);
    address userC = address(0x4);
    address airdropDistributor = address(0x5);

    uint256 currentBlock = 101;
    uint256 currentTime;

    function setUp() public {
        otherToken = new MockERC20("Other Token", "OTHR");
        arcd = new MockERC20("ARCD Token", "ARCD");

        currentTime = block.timestamp;

        singleSidedStaking = new ArcadeSingleSidedStaking(
            owner,
            address(arcd)
        );
    }

    function testConstructorZeroAddress() public {
        bytes4 selector = bytes4(keccak256("ASS_ZeroAddress(string)"));

        vm.expectRevert(abi.encodeWithSelector(selector, "arcd"));
        singleSidedStaking = new ArcadeSingleSidedStaking(
            owner,
            address(0)
        );
    }

    function testDeposit() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);

        // user deposits tokens
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 userVotingPower = singleSidedStaking.queryVotePowerView(userB, currentBlock);
        assertEq(userVotingPower, depositAmount);

        uint256 poolTotalDeposits = singleSidedStaking.totalSupply();
        assertEq(poolTotalDeposits, depositAmount);

        uint256 userBal = arcd.balanceOf(userA);
        assertEq(userBal, 0);
    }

    function testDepositZeroToken() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASS_ZeroAmount()"));

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(selector));
        singleSidedStaking.deposit(0, userB, IArcadeSingleSidedStaking.Lock.Short);
    }

    function testWithdraw() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 userVotingPower = singleSidedStaking.queryVotePowerView(userB, currentBlock);
        assertEq(userVotingPower, depositAmount);

        uint256 poolTotalDepositsBeforeWithdraw = singleSidedStaking.totalSupply();
        uint256 balanceBeforeWithdraw = arcd.balanceOf(userA);

        // increase blockchain time to end of lock duration
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        singleSidedStaking.withdraw(depositAmount, 0);
        vm.stopPrank();

        uint256 userVotingPowerAfter = singleSidedStaking.queryVotePowerView(userB, block.number);
        assertEq(userVotingPowerAfter, 0);

        uint256 balanceAfterWithdraw = arcd.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = singleSidedStaking.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + depositAmount);
        assertEq(poolTotalDepositsBeforeWithdraw, depositAmount);
        assertEq(poolTotalDepositsAfterWithdraw, 0);
    }

    function testExitAll() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        singleSidedStaking.deposit(depositAmount / 3, userB, IArcadeSingleSidedStaking.Lock.Medium);
        singleSidedStaking.deposit(depositAmount / 3, userB, IArcadeSingleSidedStaking.Lock.Long);
        singleSidedStaking.deposit(depositAmount / 3, userB, IArcadeSingleSidedStaking.Lock.Short);
        vm.stopPrank();

        uint256 userVotingPower = singleSidedStaking.queryVotePowerView(userB, currentBlock);
        uint256 tolerance = 1e1;
        assertApproxEqAbs(userVotingPower, depositAmount, tolerance);

        uint256 poolTotalDepositsBeforeWithdraw = singleSidedStaking.totalSupply();
        uint256 balanceBeforeWithdraw = arcd.balanceOf(userA);

        // increase blockchain time by the long lock duration
        vm.warp(block.timestamp + FIVE_MONTHS);

        vm.prank(userA);
        singleSidedStaking.exitAll();
        uint256 balanceAfterWithdraw = arcd.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = singleSidedStaking.totalSupply();

        uint256 userVotingPowerAfter = singleSidedStaking.queryVotePowerView(userB, block.number);
        assertEq(userVotingPowerAfter, 0);

        assertApproxEqAbs(balanceAfterWithdraw, balanceBeforeWithdraw + depositAmount, tolerance);
        assertApproxEqAbs(poolTotalDepositsBeforeWithdraw, depositAmount, tolerance);
        assertEq(poolTotalDepositsAfterWithdraw, 0);
    }

    function testExit() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 userVotingPower = singleSidedStaking.queryVotePowerView(userB, currentBlock);
        assertEq(userVotingPower, depositAmount);

        uint256 poolTotalDepositsBeforeWithdraw = singleSidedStaking.totalSupply();
        uint256 balanceBeforeWithdraw = arcd.balanceOf(userA);

        assertEq(arcd.balanceOf(userA), 0);

        // increase blockchain time to end lock period
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        singleSidedStaking.exit(0);
        vm.stopPrank();

        //confirm that delegatee no longer has voting power
        uint256 userVotingPowerAfter = singleSidedStaking.queryVotePowerView(userB, block.number);
        assertEq(userVotingPowerAfter, 0);

        uint256 balanceAfterWithdraw = arcd.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = singleSidedStaking.totalSupply();

        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw + depositAmount);
        assertEq(poolTotalDepositsBeforeWithdraw, depositAmount);
        assertEq(poolTotalDepositsAfterWithdraw, 0);
    }

    function testWithdrawZeroToken() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Long);

        bytes4 selector = bytes4(keccak256("ASS_ZeroAmount()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        singleSidedStaking.withdraw(0, 0);
    }

    function testWithdrawMoreThanBalance() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Short);
        vm.stopPrank();

        // user balance is 0
        assertEq(arcd.balanceOf(userA), 0);

        // increase blockchain time to end of lock period
        vm.warp(block.timestamp + ONE_MONTH);

        // user tries to withdraw more than their deposit
        vm.startPrank(userA);
        singleSidedStaking.withdraw(30e18, 0);
        vm.stopPrank();

        // only their deposit amount is withdrawn
        assertEq(arcd.balanceOf(userA), depositAmount);
    }

    function testPartialWithdrawAfterLock() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 userVotingPower = singleSidedStaking.queryVotePowerView(userB, currentBlock);
        assertEq(userVotingPower, depositAmount);

        uint256 poolTotalDepositsBeforeWithdraw = singleSidedStaking.totalSupply();

        // increase blockchain to end lock period
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        singleSidedStaking.withdraw(depositAmount / 2, 0);
        vm.stopPrank();

        uint256 userVotingPowerAfter = singleSidedStaking.queryVotePowerView(userB, block.timestamp);
        uint256 tolerance = 1e1;
        assertApproxEqAbs(userVotingPowerAfter, depositAmount / 2, tolerance);

        uint256 balanceAfterWithdraw = arcd.balanceOf(userA);
        uint256 poolTotalDepositsAfterWithdraw = singleSidedStaking.totalSupply();

        assertEq(balanceAfterWithdraw, depositAmount / 2);
        assertEq(poolTotalDepositsBeforeWithdraw, depositAmount);
        assertEq(poolTotalDepositsAfterWithdraw, depositAmount / 2);
    }

    function testCustomRevertRecoverERC20() public {
        setUp();

        bytes4 selector = bytes4(keccak256("ASS_DepositToken()"));
        vm.expectRevert(abi.encodeWithSelector(selector));

        vm.prank(owner);
        singleSidedStaking.recoverERC20(address(arcd), 1e18);

        bytes4 selector2 = bytes4(keccak256("ASS_ZeroAddress(string)"));
        vm.expectRevert(abi.encodeWithSelector(selector2, "token"));

        vm.prank(owner);
        singleSidedStaking.recoverERC20(address(0), 1e18);

        bytes4 selector3 = bytes4(keccak256("ASS_ZeroAmount()"));
        vm.expectRevert(abi.encodeWithSelector(selector3));

        vm.prank(owner);
        singleSidedStaking.recoverERC20(address(otherToken), 0);
    }

    function testTokenRecoverERC20() public {
        setUp();

        otherToken.mint(userA, 20e18);
        uint256 userDepositAmount = otherToken.balanceOf(userA);

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        otherToken.approve(address(singleSidedStaking), userDepositAmount);
        IERC20(address(otherToken)).safeTransfer(address(singleSidedStaking), userDepositAmount);
        vm.stopPrank();

        uint256 contractBal = otherToken.balanceOf(address(singleSidedStaking));
        assertEq(contractBal, userDepositAmount);

        vm.startPrank(owner);
        singleSidedStaking.recoverERC20(address(otherToken), userDepositAmount);
        vm.stopPrank();

        uint256 contractBal2 = otherToken.balanceOf(address(singleSidedStaking));
        assertEq(contractBal2, 0);
    }

    function testInvalidDepositId() public {
        setUp();

        bytes4 selector = bytes4(keccak256("Panic(uint256)"));
        // expect the 0x32 panic code for array out-of-bounds access
        vm.expectRevert(abi.encodeWithSelector(selector, 0x32));

        vm.startPrank(userA);
        singleSidedStaking.withdraw(20e18, 0);
    }

    function testNoDeposit() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 userDepositAmount = arcd.balanceOf(userA);

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), userDepositAmount);
        // userA deposits tokens
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        // increase blockchain time by the medium lock duration
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        singleSidedStaking.withdraw(userDepositAmount, 0);

        bytes4 selector = bytes4(keccak256("ASS_BalanceAmount()"));

        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSelector(selector));
        singleSidedStaking.withdraw(userDepositAmount, 0);
    }

    function testInvalidLockValue() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        uint256 invalidLock = 3;
        bytes4 selector = bytes4(keccak256("Panic(uint256)"));

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);

        // expect the 0x21 panic code for invalid enum values
        vm.expectRevert(abi.encodeWithSelector(selector, 0x21));

        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock(invalidLock));
    }

    function testGetUserDeposit() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 userDepositAmount = arcd.balanceOf(userA) / 3;

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), userDepositAmount * 3);
        // userA deposits once
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Short);

        // userA makes a second deposit
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);

        // userA makes a third deposit
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Long);
        vm.stopPrank();

        (uint8 lock, uint32 unlockTimestamp, uint256 amount) = singleSidedStaking.getUserDeposit(userA, 1);

        assertEq(lock, uint256(IArcadeSingleSidedStaking.Lock.Medium));
        uint256 tolerance = 1;
        assertApproxEqAbs(unlockTimestamp, TWO_MONTHS, tolerance);
        assertEq(amount, userDepositAmount);
    }

    function testGetActiveDeposits() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 userDepositAmount = arcd.balanceOf(userA) / 3;

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), userDepositAmount * 3);
        // userA deposits once
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Short);
        // userA makes a second deposit
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        // userA makes a third deposit
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Long);
        vm.stopPrank();

        // increase blockchain time to end of rewards period
        vm.warp(block.timestamp + 8 days);

        // get the user's active deposits
        uint256[] memory activeDepositIds = singleSidedStaking.getActiveDeposits(userA);
        assertEq(activeDepositIds.length, 3);

        // increase blockchain time to end lock period
        vm.warp(block.timestamp + TWO_MONTHS);

        vm.startPrank(userA);
        singleSidedStaking.exit(1);
        vm.stopPrank();

        uint256[] memory activeDepositIdsAfter = singleSidedStaking.getActiveDeposits(userA);
        assertEq(activeDepositIdsAfter.length, 2);
    }

    function testGetLastDepositId() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 userDepositAmount = arcd.balanceOf(userA) / 3;

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), userDepositAmount * 3);

        // userA deposits tokens
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Long);
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Short);
        vm.stopPrank();

        uint256 lastDepositId = singleSidedStaking.getLastDepositId(userA);
        assertEq(lastDepositId, 2);
    }

    function testBalanceOf() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        // userA deposits tokens
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 depositBalance = singleSidedStaking.balanceOfDeposit(userA, 0);
        assertEq(depositBalance, depositAmount);
    }

    /**
    * 1 user makes multiple deposits. Each deposit has a different lock period and is a different
    * amount. After the lock period, the user calls exit().
    */
    function testMultipleDeposits_Exit() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 userDepositAmount = arcd.balanceOf(userA);
        arcd.mint(userA, 50e18);
        uint256 userDepositAmount2 = arcd.balanceOf(userA) - userDepositAmount;

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), userDepositAmount);
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        arcd.approve(address(singleSidedStaking), userDepositAmount2);
        singleSidedStaking.deposit(userDepositAmount2, userB, IArcadeSingleSidedStaking.Lock.Long);
        vm.stopPrank();

        uint256 balanceOfA = singleSidedStaking.getTotalUserDeposits(userA);
        assertEq(balanceOfA, userDepositAmount + userDepositAmount2);

        uint256 lastStakeId = singleSidedStaking.getLastDepositId(userA);
        assertEq(lastStakeId, 1);

        // increase blockchain time to end long lock period
        vm.warp(block.timestamp + FIVE_MONTHS);

        // userA withdraws
        vm.startPrank(userA);
        singleSidedStaking.exitAll();
        vm.stopPrank();

        assertEq(userDepositAmount + userDepositAmount2, arcd.balanceOf(userA));
    }

    function testMaxDepositsRevert() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 userDepositAmount = arcd.balanceOf(userA) / 20;

        bytes4 selector = bytes4(keccak256("ASS_DepositCountExceeded()"));

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), userDepositAmount * 20);

        // tries to deposit more than MAX_DEPOSITS
        for (uint256 i = 0; i < 20; i++) {
            singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Short);
        }

        vm.expectRevert(abi.encodeWithSelector(selector));
        singleSidedStaking.deposit(userDepositAmount, userB, IArcadeSingleSidedStaking.Lock.Short);
        vm.stopPrank();
    }

    function testChangeDelegation() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA) / 2;

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);

        // user deposits tokens
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 userVotingPower = singleSidedStaking.queryVotePowerView(userB, currentBlock);
        assertEq(userVotingPower, depositAmount);

        bytes4 selector = bytes4(keccak256("ASS_ZeroAddress(string)"));
        vm.expectRevert(abi.encodeWithSelector(selector, "delegation"));

        vm.prank(userA);
        singleSidedStaking.changeDelegation(zeroAddress);

        vm.prank(userA);
        singleSidedStaking.changeDelegation(userC);

        uint256 userVotingPowerB = singleSidedStaking.queryVotePowerView(userB, block.timestamp);
        //confirm that delegatee user got the voting power
        uint256 userVotingPowerC = singleSidedStaking.queryVotePowerView(userC, block.timestamp);
        assertEq(userVotingPowerB, 0);
        assertEq(userVotingPowerC, depositAmount);

        uint256 poolTotalDeposits = singleSidedStaking.totalSupply();
        assertEq(poolTotalDeposits, depositAmount);
    }

    function testZeroAddressDelegate() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA) / 2;

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASS_ZeroAddress(string)"));

        // user approves singleSidedStaking contract to spend tokens
        vm.prank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(selector, "delegation"));
        // user deposits delegating to zero address
        singleSidedStaking.deposit(depositAmount, zeroAddress, IArcadeSingleSidedStaking.Lock.Medium);
    }

    function testPauseUnpause() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA);

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        // user approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        singleSidedStaking.deposit(depositAmount / 2, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        vm.prank(owner);
        singleSidedStaking.pause();

        bytes4 selector = bytes4(keccak256("EnforcedPause()"));

        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSelector(selector));
        singleSidedStaking.deposit(depositAmount / 2, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        vm.prank(owner);
        singleSidedStaking.unpause();

        vm.startPrank(userA);
        singleSidedStaking.deposit(depositAmount / 2, userB, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 poolTotalDeposits = singleSidedStaking.totalSupply();
        assertEq(poolTotalDeposits, depositAmount);
    }

    function testMultipleDelegateesRevert() public {
        setUp();

        arcd.mint(userA, 20e18);
        uint256 depositAmount = arcd.balanceOf(userA) / 2;

        // increase blockchain time by 2 days
        vm.warp(block.timestamp + 2 days);

        bytes4 selector = bytes4(keccak256("ASS_InvalidDelegationAddress()"));

        // user approves singleSidedStaking contract to spend arcd tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount * 2);
        // user deposits tokens
        singleSidedStaking.deposit(depositAmount, userB, IArcadeSingleSidedStaking.Lock.Medium);

        // user deposits delegating to a different delegatee
        vm.expectRevert(abi.encodeWithSelector(selector));
        singleSidedStaking.deposit(depositAmount, userC, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 userVotingPower = singleSidedStaking.queryVotePowerView(userB, currentBlock);
        assertEq(userVotingPower, depositAmount);
    }

    /**
    * 2 users deposit at the same time, user 2 deposits half the amount of user 1.
    */
    function testScenario1() public {
        setUp();

        arcd.mint(userA, 20e18);
        arcd.mint(userB, 10e18);

        uint256 depositAmount = arcd.balanceOf(userA);

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        // user deposits tokens
        singleSidedStaking.deposit(depositAmount, userC, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        // userB approves singleSidedStaking contract to spend tokens
        vm.startPrank(userB);
        arcd.approve(address(singleSidedStaking), depositAmount / 2);
        // user deposits tokens
        singleSidedStaking.deposit(depositAmount / 2, userC, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 votingPower = singleSidedStaking.queryVotePowerView(userC, currentBlock);
        assertEq(votingPower, depositAmount + depositAmount / 2);

        uint256 totalSupply = singleSidedStaking.totalSupply();
        assertEq(totalSupply, depositAmount + depositAmount / 2);
    }

    /**
    * 1 users deposits. halfway throught the tracking period, the second user deposits.
    */
    function testScenario2() public {
        setUp();

        arcd.mint(userA, 20e18);
        arcd.mint(userB, 10e18);

        uint256 depositAmount = arcd.balanceOf(userA);

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        // user deposits tokens
        singleSidedStaking.deposit(depositAmount, userC, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 votingPower = singleSidedStaking.queryVotePowerView(userC, currentBlock);
        assertEq(votingPower, depositAmount);

        uint256 totalSupply = singleSidedStaking.totalSupply();
        assertEq(totalSupply, depositAmount);

        // increase blockchain to half of tracking period
        vm.warp(currentTime + 4 days);

        // userB approves singleSidedStaking contract to spend tokens
        vm.startPrank(userB);
        arcd.approve(address(singleSidedStaking), depositAmount / 2);
        // user deposits tokens
        singleSidedStaking.deposit(depositAmount / 2, userC, IArcadeSingleSidedStaking.Lock.Medium);
        vm.stopPrank();

        uint256 votingPower2 = singleSidedStaking.queryVotePowerView(userC, currentBlock);
        assertEq(votingPower2, depositAmount + depositAmount / 2);

        uint256 totalSupply2 = singleSidedStaking.totalSupply();
        assertEq(totalSupply2, depositAmount + depositAmount / 2);
    }

    /**
    * 2 users make multiple deposits. the second user withdraws half of one of their deposits.
    */
    function testScenario3() public {
        setUp();

        arcd.mint(userA, 40e18);
        arcd.mint(userB, 20e18);

        uint256 depositAmount = arcd.balanceOf(userA);

        // userA approves singleSidedStaking contract to spend tokens
        vm.startPrank(userA);
        arcd.approve(address(singleSidedStaking), depositAmount);
        // user deposits tokens
        singleSidedStaking.deposit(depositAmount / 2, userC, IArcadeSingleSidedStaking.Lock.Medium);
        singleSidedStaking.deposit(depositAmount / 2, userC, IArcadeSingleSidedStaking.Lock.Short);
        vm.stopPrank();

        // userB approves singleSidedStaking contract to spend tokens
        vm.startPrank(userB);
        arcd.approve(address(singleSidedStaking), depositAmount / 2);
        // user deposits tokens
        singleSidedStaking.deposit(depositAmount / 4, userC, IArcadeSingleSidedStaking.Lock.Medium);
        singleSidedStaking.deposit(depositAmount / 4, userC, IArcadeSingleSidedStaking.Lock.Short);
        vm.stopPrank();

        // increase blockchain to after lock period
        vm.warp(currentTime + TWO_MONTHS);

        // userB withdraws half of their first deposit
        vm.startPrank(userB);
        singleSidedStaking.withdraw(depositAmount / 4, 0);
        vm.stopPrank();

        uint256 votingPower = singleSidedStaking.queryVotePowerView(userC, currentBlock);
        assertEq(votingPower, depositAmount + depositAmount / 4);

        uint256 totalSupply = singleSidedStaking.totalSupply();
        assertEq(totalSupply, depositAmount + depositAmount / 4);
    }

    function airdropSetUp() public {
        setUp();

        airdropSingleSidedStaking = new AirdropSingleSidedStaking(
            owner,
            address(arcd),
            airdropDistributor
        );
    }

    function testAirdropZeroAddressConstructor() public {
        bytes4 selector = bytes4(keccak256("ASS_ZeroAddress(string)"));

        vm.expectRevert(abi.encodeWithSelector(selector, "airdropDistribution"));
        airdropSingleSidedStaking = new AirdropSingleSidedStaking(
            owner,
            address(arcd),
            address(0)
        );
    }

    function testAirdropCallerNoAuthorized() public {
        airdropSetUp();

        bytes4 selector = bytes4(keccak256("ASS_CallerNotAirdropDistribution()"));

        vm.expectRevert(abi.encodeWithSelector(selector));
        vm.startPrank(userA);
            airdropSingleSidedStaking.airdropReceive(
                userB,
                750e17,
                userC,
                IArcadeSingleSidedStaking.Lock.Short
            );
        vm.stopPrank();
    }

    function testAirdropReceive() public {
        airdropSetUp();

        arcd.mint(airdropDistributor, 1000e18);

        vm.startPrank(airdropDistributor);
            arcd.approve(address(airdropSingleSidedStaking), 1000e18);

            airdropSingleSidedStaking.airdropReceive(
                userA,
                75e17,
                userB,
                IArcadeSingleSidedStaking.Lock.Short
            );
        vm.stopPrank();

        uint256 userVotingPowerAfter = airdropSingleSidedStaking.queryVotePowerView(userB, block.timestamp);
        assertGt(userVotingPowerAfter, 0);

        uint256 totalDeposits = airdropSingleSidedStaking.totalSupply();
        assertEq(totalDeposits, 75e17);

        (uint8 lock, uint32 unlockTimestamp, uint256 amount) = airdropSingleSidedStaking.getUserDeposit(userA, 0);

        assertEq(lock, uint256(IArcadeSingleSidedStaking.Lock.Short));
        uint256 tolerance = 1;
        assertApproxEqAbs(unlockTimestamp, ONE_MONTH, tolerance);
        assertEq(amount, 75e17);
    }
}

