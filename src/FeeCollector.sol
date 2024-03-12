// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeCollector {
    // ERC20 token addresses
    address public constant ARCD = 0x1337DEF16F9B486fAEd0293eb623Dc8395dFE46a;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant wstETH = 0x0630103eAD9bCF6DAEF3fe2F0cE9e3F2fC5F6d2a;

    // V3 Lending Protocol addresses
    // NOTE: Change these to V4 after testing and integrate witht he OCConfiguration
    address public constant LOAN_CORE;
    address public constant ORIGINATION_CONFIGURATION;

    // Uniswap V2 Router address
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Uniswap V3 Router address
    address public constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /**
     * @notice Function to collect the fees from Loan Core and buy ARCD with the fees.
     *         After we recieve the ARCD, we will burn it.
     *
     * @dev This function is callable by anyone.
     */
    function buyAndBurn() external returns (uint256 burnedAmount) {
        // Get the fees from the Loan Core
        uint256 fees = ILoanCore(LOAN_CORE).getFees();

        // Get the ARCD/ETH pair address
        address pair = IUniswapV2Factory(IUniswapV2Router(UNISWAP_V2_ROUTER).factory()).getPair(ARCD, WETH);

        // Get the ARCD/ETH reserves
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();

        // Get the ARCD/ETH price
        uint256 price = IUniswapV2Router(UNISWAP_V2_ROUTER).getAmountOut(1e18, reserve0, reserve1);

        // Get the amount of ARCD to buy
        uint256 amount = fees / price;

        // Swap the ETH for ARCD
        IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: fees}(
            amount, getPathForETHtoARCD(), address(this), block.timestamp
        );

        // Burn the ARCD
        IERC20(ARCD).transfer(address(0));
    }
}
