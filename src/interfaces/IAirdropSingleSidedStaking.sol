// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./IArcadeSingleSidedStaking.sol";

interface IAirdropSingleSidedStaking is  IArcadeSingleSidedStaking {
    event AirdropDistributionSet(address indexed airdropDistribution);

    function airdropReceive(
        address recipient,
        uint256 amount,
        address delegation,
        Lock lock
    ) external;

    function setAirdropDistribution(address _airdropDistribution) external;

    function airdropDistribution() external view returns (address);
}
