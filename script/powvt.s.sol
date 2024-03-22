// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/ArcadeStakingRewards.sol";

/**
 * To run this script, you need to set the following environment variables:
 * - PRIVATE_KEY: the private key of the deployer
 * - MAINNET_FORK_RPC_URL: the RPC url of the mainnet fork
 *
 * To run this script use:
 * `forge script script/powvt.s.sol:MyScript --fork-url $MAINNET_FORK_RPC_URL --broadcast --legacy -vvvv`
 * Must use `--legacy` flag to disable EIP1559 tx's, otherwise script with not able to estimate gas and fail.
 */
contract MyScript is Script {
    function run() external {
        // constructor arguments
        address deployer = 0x0a606524006a48C4D93662aA935AEC203CaC98C1;
        address owner = 0x21aDafAA34d250a4fa0f8A4d2E2424ABa0cEE563;
        address rewardsManager = 0x21aDafAA34d250a4fa0f8A4d2E2424ABa0cEE563;
        address rewardsToken = 0xB0790126c419bBfC999eeCf2b8A6Cd139Da84ec8;
        address stakingToken = 0x0a606524006a48C4D93662aA935AEC203CaC98C1;
        uint256 lpToArcdRate = 1000;

        vm.deal(deployer, 1 ether);

        console.logUint(deployer.balance);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ArcadeStakingRewards asr =
            new ArcadeStakingRewards(owner, rewardsManager, rewardsToken, stakingToken, lpToArcdRate);

        vm.stopBroadcast();
    }
}
