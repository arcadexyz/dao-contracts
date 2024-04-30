// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @notice This script is used to generate calldata to be used in AIP2
 *
 * @dev the new proposal ID that is created for the proposal is hardcoded to 17. If the script is
 *      run at a different block number, the proposal ID may be different. The whales voting power
 *      are also hardcoded and may need to be updated.
 *
 * to run:
 * forge script script/AIP2CalldataUseGSC.s.sol --fork-url <your-mainnet-rpc-url> --block-number 19745889 -vvv
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

interface IGSCVotingVault {
    function proveMembership(address[] memory, bytes[] memory) external;
}

interface IVotingVault {
    function queryVotePowerView(address, uint256) external view returns (uint256);
}

contract AIP2CalldataUseGSC is Script {
    uint256 public constant DAY_IN_BLOCKS = 7150;
    uint256 public lockDuration = DAY_IN_BLOCKS * 3;
    uint256 public gscLockDuration = 2165; // blocks

    // mainnet governance contracts
    ITimelock public timelock = ITimelock(0x47511465C397875deAb7cf8f008d7922D041fF01);

    IArcadeCoreVoting public arcadeCoreVoting = IArcadeCoreVoting(0x54B7235dB74103395dD48A2c3dd993E3b7d39856);
    IArcadeCoreVoting public gscCoreVoting = IArcadeCoreVoting(0x2b6F11B2A783C928799C4E561dA89cD06894A279);

    address public teamVestingVault = 0xae40Af135C060E10b218C617c2d74A370B09C40F;
    IGSCVotingVault public gscVotingVault = IGSCVotingVault(0xFd2D1c8809A271e892046A23185423a52A149F62);

    // mainnet staking contracts
    address public stakingRewardsAddress = 0x80bDdd56b947c547Ab8964D80E98E42Ff77a5793;
    address public singleSidedStakingAddress = 0x72854FBb44d3dd87109D46a9298AEB0d018740f0;

    // mainnet actors
    address public whale1 = 0xF70f7c0fCD743b2c03b823672A0B02B6a1e1bA20; // 4,463,281 ARCD (GSC)
    address public whale2 = 0x20091502AdA3cCC55FFDe01bB29376cA3CD9E0A0; // 1,747,187 ARCD (GSC)
    address public whale3 = 0x6888d7Ef74b081060a0165E336A9d03b809098BE; // 4,463,281 ARCD (not-GSC)

    function run() external {
        ///
        ///
        /// @notice Create proposal calldata
        ///
        ///

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
        bytes memory timelockCalldata = abi.encodeWithSignature("registerCall(bytes32)", timelockCallHash);

        address[] memory votingVaults1;
        bytes[] memory extraVaultData1;
        address[] memory targets1 = new address[](1);
        bytes[] memory calldatas1 = new bytes[](1);

        targets1[0] = address(timelock);
        calldatas1[0] = timelockCalldata;
        bytes memory gscCoreVotingCalldata = abi.encodeWithSignature(
            "proposal(address[],bytes[],address[],bytes[],uint256,uint8)",
            votingVaults1, // empty array
            extraVaultData1, // empty array
            targets1,
            calldatas1,
            block.number + 1000000,
            IArcadeCoreVoting.Ballot.YES
        );
        console2.log("Target contract to be used in the GSC proposal");
        console2.logAddress(address(arcadeCoreVoting));
        console2.log("Calldata to be used in GSC proposal");
        console2.logBytes(gscCoreVotingCalldata);

        ///
        ///
        /// @notice Execute proposal calldata on mainnet fork
        ///
        ///

        // whale3 adds themself to the GSC
        address[] memory proveMembershipVaults = new address[](1);
        bytes[] memory proveMembershipExtraData = new bytes[](1);
        proveMembershipVaults[0] = address(teamVestingVault);
        proveMembershipExtraData[0] = bytes("");

        vm.prank(whale3);
        gscVotingVault.proveMembership(proveMembershipVaults, proveMembershipExtraData);

        // fast forward 4 day GSC idle period
        vm.warp(block.timestamp + 345600);

        address[] memory votingVaults2 = new address[](1);
        bytes[] memory extraVaultData2 = new bytes[](1);
        address[] memory targets2 = new address[](1);
        bytes[] memory calldatas2 = new bytes[](1);

        votingVaults2[0] = address(gscVotingVault);
        extraVaultData2[0] = bytes("");
        targets2[0] = address(arcadeCoreVoting);
        calldatas2[0] = gscCoreVotingCalldata;

        // whale account creates the proposal in GSC CoreVoting
        vm.prank(whale1);
        gscCoreVoting.proposal(
            votingVaults2, extraVaultData2, targets2, calldatas2, block.number + 1000000, IArcadeCoreVoting.Ballot.YES
        );

        // ensure the proposal is created
        uint128[3] memory propVotes = gscCoreVoting.getProposalVotingPower(0);
        assert(propVotes[0] == 1);

        // whale2 votes
        vm.prank(whale2);
        gscCoreVoting.vote(votingVaults2, extraVaultData2, 0, IArcadeCoreVoting.Ballot.YES);

        // whale3 votes
        vm.prank(whale3);
        gscCoreVoting.vote(votingVaults2, extraVaultData2, 0, IArcadeCoreVoting.Ballot.YES);

        // fast forward to the end of the voting time
        vm.roll(block.number + gscLockDuration);

        // execute the proposal
        gscCoreVoting.execute(0, targets2, calldatas2);

        // ensure the proposal is executed
        uint128[3] memory propVotes3 = gscCoreVoting.getProposalVotingPower(0);
        assert(propVotes3[0] == 0);

        // whale1 and whale3 vote to pass the proposal
        // quorum is 6 million ARCD
        address[] memory votingVaultsWhale = new address[](1);
        bytes[] memory extraVaultDataWhale = new bytes[](1);

        votingVaultsWhale[0] = teamVestingVault;
        extraVaultDataWhale[0] = bytes("");
        vm.prank(whale1);
        arcadeCoreVoting.vote(votingVaultsWhale, extraVaultDataWhale, 17, IArcadeCoreVoting.Ballot.YES);

        vm.prank(whale3);
        arcadeCoreVoting.vote(votingVaultsWhale, extraVaultDataWhale, 17, IArcadeCoreVoting.Ballot.YES);

        // ensure the votes are counted
        uint128[3] memory propVotes5 = arcadeCoreVoting.getProposalVotingPower(17);
        assert(propVotes5[0] == 4_463_281 ether + 4_463_281 ether);

        // fast forward to the end of the voting time
        vm.roll(block.number + lockDuration);

        // execute the proposal
        arcadeCoreVoting.execute(17, targets1, calldatas1);

        // ensure the proposal is executed
        uint128[3] memory propVotes6 = arcadeCoreVoting.getProposalVotingPower(17);
        assert(propVotes6[0] == 0);

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
