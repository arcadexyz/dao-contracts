// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @notice This script is used to generate calldata to be used in AIP2
 *
 * to run:
 * forge script script/AIP2Calldata.s.sol --fork-url <your-mainnet-rpc-url> --block-number 19683254 -vvv
 */
interface ITimelock {
    function callTimestamps(bytes32) external view returns (uint256);
    function registerCall(bytes32 callHash) external;
    function execute(address[] memory targets, bytes[] calldata calldatas) external;
}

interface IArcadeCoreVoting {
    enum Ballot {
        YES,
        NO,
        MAYBE
    }

    struct Proposal {
        // hash of this proposal's intended function calls
        bytes32 proposalHash;
        // block of the proposal creation
        uint128 created;
        // timestamp when the proposal can execute
        uint128 unlock;
        // expiration time of a proposal
        uint128 expiration;
        // the quorum required for the proposal to execute
        uint128 quorum;
        // [yes, no, maybe] voting power
        uint128[3] votingPower;
        // Timestamp after which if the call has not been executed it cannot be executed
        uint128 lastCall;
    }

    function proposal(
        address[] calldata votingVaults,
        bytes[] calldata extraVaultData,
        address[] calldata targets,
        bytes[] calldata calldatas,
        uint256 lastCall,
        Ballot ballot
    ) external;

    function vote(address[] memory votingVaults, bytes[] memory extraVaultData, uint256 proposalId, Ballot ballot)
        external
        returns (uint256);

    function execute(uint256 proposalId, address[] memory targets, bytes[] memory calldatas) external;

    function getProposalVotingPower(uint256 proposalId) external view returns (uint128[3] memory);

    function approvedVaults(address) external view returns (bool);
}

contract AIP2Calldata is Script {
    uint256 public constant DAY_IN_BLOCKS = 7150;
    uint256 public lockDuration = DAY_IN_BLOCKS * 3;

    // mainnet governance contracts
    ITimelock public timelock = ITimelock(0x47511465C397875deAb7cf8f008d7922D041fF01);
    IArcadeCoreVoting public arcadeCoreVoting = IArcadeCoreVoting(0x54B7235dB74103395dD48A2c3dd993E3b7d39856);
    address public teamVestingVault = 0xae40Af135C060E10b218C617c2d74A370B09C40F;

    // mainnet staking contracts
    address public stakingRewardsAddress = 0x80bDdd56b947c547Ab8964D80E98E42Ff77a5793;
    address public singleSidedStakingAddress = 0x72854FBb44d3dd87109D46a9298AEB0d018740f0;

    // mainnet actors
    address public whale1 = 0xF70f7c0fCD743b2c03b823672A0B02B6a1e1bA20; // 4,463,281 ARCD
    address public whale2 = 0x6888d7Ef74b081060a0165E336A9d03b809098BE; // 4,463,281 ARCD

    function run() external {
        address[] memory timelockTargets = new address[](2);
        timelockTargets[0] = address(arcadeCoreVoting);
        timelockTargets[1] = address(arcadeCoreVoting);

        bytes memory coreVotingCalldata1 =
            abi.encodeWithSignature("changeVaultStatus(address,bool)", stakingRewardsAddress, true);
        bytes memory coreVotingCalldata2 =
            abi.encodeWithSignature("changeVaultStatus(address,bool)", singleSidedStakingAddress, true);
        bytes[] memory timelockCalldatas = new bytes[](2);
        timelockCalldatas[0] = coreVotingCalldata1;
        timelockCalldatas[1] = coreVotingCalldata2;

        bytes32 timelockCallHash = keccak256(abi.encode(timelockTargets, timelockCalldatas));
        // console2.logBytes32(timelockCallHash);

        bytes memory timelockCalldata = abi.encodeWithSignature("registerCall(bytes32)", timelockCallHash);
        console2.log("Calldata to be used in proposal");
        console2.logBytes(timelockCalldata);

        // create proposal in CoreVoting
        address[] memory votingVaults = new address[](1);
        bytes[] memory extraVaultData = new bytes[](1);
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);

        votingVaults[0] = teamVestingVault;
        extraVaultData[0] = bytes("");
        targets[0] = address(timelock);
        calldatas[0] = timelockCalldata;

        vm.prank(whale1);
        arcadeCoreVoting.proposal(
            votingVaults, extraVaultData, targets, calldatas, block.number + 1000000, IArcadeCoreVoting.Ballot.YES
        );

        // ensure the proposal is created
        uint128[3] memory propVotes = arcadeCoreVoting.getProposalVotingPower(17);
        assert(propVotes[0] == 4_463_281 ether);

        // second vote passes the proposal with their vote
        // quorum is 6 million ARCD
        vm.prank(whale2);
        arcadeCoreVoting.vote(votingVaults, extraVaultData, 17, IArcadeCoreVoting.Ballot.YES);

        // ensure the vote is counted
        uint128[3] memory propVotes2 = arcadeCoreVoting.getProposalVotingPower(17);
        assert(propVotes2[0] == 4_463_281 ether + 4_463_281 ether);

        // fast forward to the end of the voting time
        vm.roll(block.number + lockDuration);

        // execute the proposal
        arcadeCoreVoting.execute(17, targets, calldatas);

        // ensure the proposal is executed
        uint128[3] memory propVotes3 = arcadeCoreVoting.getProposalVotingPower(17);
        assert(propVotes3[0] == 0);

        // ensure the timelock call is executed
        uint256 callTimestamp = timelock.callTimestamps(timelockCallHash);
        assert(callTimestamp > 0);

        // fast forward to the end of the timelock lock duration
        vm.warp(block.timestamp + 19488 + 1); // timelock wait time is 19488 seconds ~ 5.4 hours

        // execute the timelock call
        address[] memory timelockTargetsExecute = new address[](2);
        bytes[] memory timelockCalldatasExecute = new bytes[](2);

        timelockTargetsExecute[0] = address(arcadeCoreVoting);
        timelockTargetsExecute[1] = address(arcadeCoreVoting);

        timelockCalldatasExecute[0] = coreVotingCalldata1;
        timelockCalldatasExecute[1] = coreVotingCalldata2;

        timelock.execute(timelockTargetsExecute, timelockCalldatasExecute);

        // verify the voting vaults have been added to core voting
        assert(arcadeCoreVoting.approvedVaults(stakingRewardsAddress));
        assert(arcadeCoreVoting.approvedVaults(singleSidedStakingAddress));
    }
}
