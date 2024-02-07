// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

contract Config {
    uint256 public constant SHORT_LOCK_BONUS_MULTIPLIER = 1.1e18;
    uint256 public constant MEDIUM_LOCK_BONUS_MULTIPLIER = 1.3e18;
    uint256 public constant LONG_LOCK_BONUS_MULTIPLIER = 1.5e18;

    address public constant OWNER_ADDRESS = 0x9b419fd36837558D8A3197a28a5e580AcE44f64F; // address TO BE CONFIRMED / UPDATED
    address public constant FOUNDATION_MULTISIG = 0xE004727641b3C9A2441eE21fa73BEc51f6029543; // mainnet address TO BE CONFIRMED

    uint256 public immutable LP_TO_ARCD_CONVERSION_RATE = 2; // placeholder value to be updated

    address public constant ARCD_ADDRESS = 0x9b419fd36837558D8A3197a28a5e580AcE44f64F; // placeholder, needs to be updated
    address public constant LP_TOKEN_ADDRESS = 0x9b419fd36837558D8A3197a28a5e580AcE44f64F; // placeholder, needs to be updated

    uint256 public constant ONE_DAY = 60 * 60 * 24;
    uint256 public constant ONE_MONTH = ONE_DAY * 30;
    uint256 public constant TWO_MONTHS = ONE_MONTH * 2;
    uint256 public constant THREE_MONTHS = ONE_MONTH * 3;
}