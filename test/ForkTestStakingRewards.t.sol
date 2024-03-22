// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";

import "../src/external/uniswap/interfaces/IUniswapV2Factory.sol";
import "../src/external/uniswap/interfaces/IUniswapV2Pair.sol";
import "../src/external/uniswap/interfaces/IUniswapV2Router01.sol";

import { IArcadeStakingRewards } from "../src/interfaces/IArcadeStakingRewards.sol";
import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract testForkMainnetStakingRewards is Test {
    IUniswapV2Factory uniswapFactory;
    IUniswapV2Pair uniswapPair;
    IUniswapV2Router01 uniswapRouter;
    ArcadeStakingRewards stakingRewards;

    address factoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address ARCD = 0xe020B01B6fbD83066aa2e8ee0CCD1eB8d9Cc70bF;

    address tokenA = WETH;
    address tokenB = ARCD;
    address wethWhale = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address arcdWhale = 0xDD7a92062d1939357FB17A66288cdE30b3711E53;

    address owner = 0x6c6F915B21d43107d83c47541e5D29e872d82Da6;
    address rewardsDistribution = 0x6c6F915B21d43107d83c47541e5D29e872d82Da6;
    address user1;
    address user2;

    uint256 lpToArcdRate = 62;

    function setUp() public {
        uniswapFactory = IUniswapV2Factory(factoryAddress);
        uniswapRouter = IUniswapV2Router01(uniswapRouterAddress);

        user1 = vm.addr(1);
        user2 = vm.addr(2);
    }

    function testUserFlow() public {
        setUp();

        // call createPair for LP token creation
        address pairAddress = uniswapFactory.createPair(tokenA, tokenB);

        assertTrue(pairAddress != address(0), "Pair creation failed");
        console.log("Pair created at address: ", pairAddress);

        // get the pair instance
        uniswapPair = IUniswapV2Pair(pairAddress);

        // fund user1 with WETH and ARCD
        vm.startPrank(wethWhale);
            IERC20(WETH).transfer(user1, 1e18);
        vm.stopPrank();

        vm.startPrank(arcdWhale);
            IERC20(ARCD).transfer(user1, 4000e17);
        vm.stopPrank();
        console.log("user1 WETH balance: ", IERC20(WETH).balanceOf(user1));
        console.log("user1 ARCD balance: ", IERC20(ARCD).balanceOf(user1));

        // user1 deposits ARC and WETH to receive LP tokens
        vm.startPrank(user1);
        // user1 approves the uniswapRouter to spend their tokens
        IERC20(WETH).approve(uniswapRouterAddress, 1e17); // approve WETH
        IERC20(ARCD).approve(uniswapRouterAddress, 3835e17); // approve ARCD

        (,, uint256 liquidity) = uniswapRouter.addLiquidity(
            tokenA,
            tokenB,
            1e17,
            3835e17,
            1,
            1,
            user1,
            block.timestamp + 15
        );
        vm.stopPrank();
        assertEq(liquidity, IERC20(pairAddress).balanceOf(user1));
        console.log("User1 LP token Balance: ", IERC20(pairAddress).balanceOf(user1));

        // deploy StakingRewards contract using the LP pair address
        stakingRewards = new ArcadeStakingRewards(
            owner,
            rewardsDistribution,
            ARCD,
            pairAddress,
            lpToArcdRate
        );
        assertTrue(address(stakingRewards) != address(0), "StakingRewards deplyment failed");
        console.log("StakingRewards deployed at address: ", address(stakingRewards));

        // fund stakingRewards contract with ARCD
        vm.startPrank(arcdWhale);
            IERC20(ARCD).transfer(address(stakingRewards), 2e24);
        vm.stopPrank();
        console.log("StakingRewards ARCD balance: ", IERC20(ARCD).balanceOf(address(stakingRewards)));

        // rewardsDistribution calls notifyRewardAmount
        vm.prank(rewardsDistribution);
        stakingRewards.notifyRewardAmount(1e24);

        // user1 deposits their LP tokens in the locking pool
        vm.startPrank(user1);
        IERC20(pairAddress).approve(address(stakingRewards), liquidity);
        stakingRewards.deposit(liquidity, user2, IArcadeStakingRewards.Lock.Short);
        vm.stopPrank();

        assertEq(stakingRewards.balanceOfDeposit(user1, 0), liquidity);
        assertEq(stakingRewards.queryVotePowerView(user2, block.number), stakingRewards.convertLPToArcd(liquidity));
        console.log("User2 vote power: ", stakingRewards.queryVotePowerView(user2, block.number));
    }
}