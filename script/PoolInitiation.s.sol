// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "../src/external/uniswap/interfaces/IUniswapV2Factory.sol";
import "../src/external/uniswap/interfaces/IUniswapV2Router02.sol";

import { IArcadeStakingRewards } from "../src/interfaces/IArcadeStakingRewards.sol";
import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// to run:  TODO: Update $FORK_RPC_URL when running on Mainnet
// forge script script/PoolInitiation.s.sol:PoolInitiation --rpc-url $FORK_RPC_URL --broadcast --private-key $PRIVATE_KEY
contract PoolInitiation is Script {
    function run() external {
        address router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        address arcd = 0xe020B01B6fbD83066aa2e8ee0CCD1eB8d9Cc70bF;

        uint tokenAmount = 334e18; // TODO: Update all values as needed
        uint ethAmount = 1e17;
        uint tokenAmountMin = 1e18;
        uint ethAmountMin = 1e16;
        address to = 0x6c6F915B21d43107d83c47541e5D29e872d82Da6;
        uint deadline = block.timestamp + (15 * 60); // 15 minutes from now;

        vm.startBroadcast();

        IUniswapV2Router02 uniswapRouter02 = IUniswapV2Router02(router);

        IERC20(arcd).approve(address(uniswapRouter02), tokenAmount);

        uniswapRouter02.addLiquidityETH{value: 100000000000000000}(
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