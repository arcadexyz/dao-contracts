// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "v2-periphery/interfaces/IUniswapV2Router01.sol";

import "arcade-protocol/interfaces/ILoanCore.sol";
import "arcade-protocol/interfaces/IOriginationConfiguration.sol";

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

    // Uniswap V2 addresses
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    // Uniswap V3 Router address
    address public constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // ARCD/ETH pair address
    address public constant ARCD_WETH_PAIR = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    event BuyAnBurn(address feeToken, uint256 amountBurned, uint256 burnedAmount);

    /**
     * @notice Function to collect the fees from Loan Core and buy ARCD with the fees.
     *         After we recieve the ARCD, we will burn it.
     *
     * @dev This swap flow uses Uniswap V2 contracts.
     * @dev This function is callable by anyone.
     *
     * @param feeToken              The token to collect and burn
     *
     * @return burnedAmount         The amount of ARCD burned
     */
    function buyAndBurn(address feeToken) external returns (uint256 burnedAmount) {
        require(feeToken != ARCD, "FeeCollector: Cannot burn ARCD");
        require(feeToken != address(0), "FeeCollector: Cannot burn zero address");

        // Withdraw the fees from the Loan Core
        ILoanCore(LOAN_CORE).withdrawProtocolFees(feeToken, address(this));

        // get balance of this contract
        uint256 fees = IERC20(feeToken).balanceOf(address(this));
        require(fees > 0, "FeeCollector: No fees to burn");

        // get pair of feeToken and WETH
        address pairFeeWeth = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(feeToken, WETH);

        // Get the reserves of the pairFeeWeth
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pairFeeWeth).getReserves();

        // Get the amount of WETH for these fees
        uint256 wethAmount = IUniswapV2Router01(UNISWAP_V2_ROUTER).getAmountOut(feeAmount, reserve0, reserve1);

        // get the reserves of the ARCD/WETH pair
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(ARCD_WETH_PAIR).getReserves();

        // Get the amount of ARCD for the WETH
        uint256 arcdAmount = IUniswapV2Router01(UNISWAP_V2_ROUTER).getAmountOut(wethAmount, reserveA, reserveB);

        // swap path
        address[] memory path = new address[](3);
        path[0] = feeToken;
        path[1] = WETH;
        path[2] = ARCD;

        // Swap the ETH for ARCD
        uint256[] memory amounts = IUniswapV2Router(UNISWAP_V2_ROUTER).swapTokensForExactTokens(
            arcdAmount, fees, path, address(this), block.timestamp
        );

        // Burn the ARCD
        IERC20(ARCD).transfer(address(0), amounts[2]);

        emit BuyAnBurn(feeToken, fees, amounts[2]);

        return amounts[2];
    }
}
