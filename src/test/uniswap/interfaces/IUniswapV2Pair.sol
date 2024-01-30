pragma solidity 0.8.20;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
// added "get" to the function name to avoid conflict with IUniswapV2ERC20
    //function getName() external pure returns (string memory);
    //function getSymbol() external pure returns (string memory);
// added "get" to the function name to avoid conflict with IUniswapV2ERC20
    //function getDecimals() external pure returns (uint8);
// added "get" to the function name to avoid conflict with IUniswapV2ERC20
    //function getTotalSupply() external view returns (uint);
    //function getBalanceOf(address owner) external view returns (uint);
// added "get" to the function name to avoid conflict with IUniswapV2ERC20
    //function getAllowance(address owner, address spender) external view returns (uint);
// added "spender" to the function name to avoid conflict with IUniswapV2ERC20
    //function approveSpender(address spender, uint value) external returns (bool);
// added "value" to the function name to avoid conflict with IUniswapV2ERC20
    //function transferValue(address to, uint value) external returns (bool);
    //function transferFromValue(address from, address to, uint value) external returns (bool);
// added "get" to the function name to avoid conflict with IUniswapV2ERC20
    //function getDOMAIN_SEPARATOR() external view returns (bytes32);
    //function getPERMIT_TYPEHASH() external pure returns (bytes32);
    //function getNonces(address owner) external view returns (uint);
// added "Operator" to the function name to avoid conflict with IUniswapV2ERC20
    //function permitOperator(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}