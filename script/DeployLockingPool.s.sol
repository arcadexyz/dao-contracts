// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import { console } from "forge-std/Test.sol";
import "./Config.sol";

import { ArcadeStakingRewards } from "../src/ArcadeStakingRewards.sol";

contract DeployLockingPool is Script, Config {
    function run() external {
        console.log("OWNER:", OWNER);
        console.log("ADMIN:", FOUNDATION_MULTISIG);

        vm.startBroadcast();

        ArcadeStakingRewards stakingRewards = new ArcadeStakingRewards(
            OWNER_ADDRESS,
            FOUNDATION_MULTISIG,
            ARCD_ADDRESS,
            LP_TOKEN_ADDRESS,
            ONE_MONTH,
            TWO_MONTHS,
            THREE_MONTHS,
            SHORT_LOCK_BONUS_MULTIPLIER,
            MEDIUM_LOCK_BONUS_MULTIPLIER,
            LONG_LOCK_BONUS_MULTIPLIER,
            LP_TO_ARCD_CONVERSION_RATE
        );
        console.log("ArcadeStakingRewards deployed to:", address(stakingRewards));

        vm.stopBroadcast();

        console.log("Success! Deployment complete.");
    }
}