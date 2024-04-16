// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "../src/external/uniswap/interfaces/IUniswapV2Factory.sol";
import "../src/external/uniswap/interfaces/IUniswapV2Router02.sol";

import { IArcadeStakingRewards } from "../src/interfaces/IArcadeStakingRewards.sol";
import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// to run:
// forge script script/PoolInitiation.s.sol:PoolInitiation --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
contract PoolInitiation is Script {
    function run() external {
        address router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // mainnet
        address arcd = 0xe020B01B6fbD83066aa2e8ee0CCD1eB8d9Cc70bF; // mainnet

        // tokenAmount value changes dependent on price of ETH on deployment day
        // ETH today is ethPrice USDC and ARCD price is 0.39 USDC
        // tokenAmount = (0.1 * ethPrice) / 0.39
        uint tokenAmount = 787e18; // value to be updated on deployment day
        uint tokenAmountMin = tokenAmount;
        uint ethAmount = 1e17;
        uint ethAmountMin = ethAmount;

        vm.startBroadcast();

        IUniswapV2Router02 uniswapV2Router02 = IUniswapV2Router02(router);

        IERC20(arcd).approve(address(uniswapV2Router02), tokenAmount);

        uniswapV2Router02.addLiquidityETH{value: ethAmount}(
            arcd,
            tokenAmount,
            tokenAmountMin,
            ethAmountMin,
            msg.sender,
            block.timestamp + 15 minutes
        );

        vm.stopBroadcast();
    }
}