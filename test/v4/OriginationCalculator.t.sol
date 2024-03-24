// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";

contract OriginationCalculator is Test {
    struct RolloverAmounts {
        uint256 needFromBorrower;
        uint256 leftoverPrincipal;
        uint256 amountFromLender;
        uint256 amountToOldLender;
        uint256 amountToLender;
        uint256 amountToBorrower;
        uint256 interestAmount;
    }

    function setUp() public {}

    function test_rolloverAmountsBase() public view {
        uint256 oldBalance = 100 ether;
        uint256 oldInterestAmount = 10 ether;
        uint256 newPrincipalAmount = 100 ether;
        address lender = address(0x1);
        address oldLender = address(0x2);
        uint256 principalFee = oldBalance * 1e2 / 1e4; // 1% = 1 ether
        uint256 interestFee = oldInterestAmount * 1e2 / 1e4; // 1% = 0.1 ether

        RolloverAmounts memory amounts = rolloverAmounts(
            oldBalance, oldInterestAmount, newPrincipalAmount, lender, oldLender, principalFee, interestFee
        );

        console.log("amountFromLender: %d", amounts.amountFromLender);
        console.log("interestAmount: %d", amounts.interestAmount);
        console.log("needFromBorrower: %d", amounts.needFromBorrower);
        console.log("leftoverPrincipal: %d", amounts.leftoverPrincipal);
        console.log("amountToBorrower: %d", amounts.amountToBorrower);
        console.log("amountToOldLender: %d", amounts.amountToOldLender);
        console.log("amountToLender: %d", amounts.amountToLender);
    }

    function test_rolloverAmountsSameLenderFuzz(
        uint256 oldBalance,
        uint256 oldInterestAmount,
        uint256 newPrincipalAmount,
        uint256 principalFee,
        uint256 interestFee
    ) public view {
        address lender = address(0x1);
        address oldLender = lender;

        vm.assume(oldBalance > 0);
        vm.assume(oldBalance < 1e32);
        vm.assume(oldInterestAmount > 0);
        vm.assume(newPrincipalAmount > 0);
        vm.assume(newPrincipalAmount < 1e32);
        vm.assume(oldInterestAmount < oldBalance);
        vm.assume(principalFee < oldBalance / 2); // 50% max
        vm.assume(interestFee < oldInterestAmount / 2); // 50% max

        RolloverAmounts memory amounts = rolloverAmounts(
            oldBalance, oldInterestAmount, newPrincipalAmount, lender, oldLender, principalFee, interestFee
        );

        // use amounts.amountFromLender because lenders are the same
        uint256 settledAmount = amounts.leftoverPrincipal + amounts.needFromBorrower;

        require(
            amounts.amountToOldLender + amounts.amountToLender + amounts.amountToBorrower <= settledAmount,
            "amounts mismatch"
        );
    }

    function test_rolloverAmountsDiffLenderFuzz(
        uint256 oldBalance,
        uint256 oldInterestAmount,
        uint256 newPrincipalAmount,
        uint256 principalFee,
        uint256 interestFee
    ) public view {
        address lender = address(0x1);
        address oldLender = address(0x2);

        vm.assume(oldBalance > 0);
        vm.assume(oldBalance < 1e32);
        vm.assume(oldInterestAmount > 0);
        vm.assume(newPrincipalAmount > 0);
        vm.assume(newPrincipalAmount < 1e32);
        vm.assume(oldInterestAmount < oldBalance);
        vm.assume(principalFee < oldBalance / 2); // 50% max
        vm.assume(interestFee < oldInterestAmount / 2); // 50% max

        RolloverAmounts memory amounts = rolloverAmounts(
            oldBalance, oldInterestAmount, newPrincipalAmount, lender, oldLender, principalFee, interestFee
        );

        // use amounts.amountFromLender because lenders are not the same
        uint256 settledAmount = amounts.amountFromLender + amounts.needFromBorrower;

        require(
            amounts.amountToOldLender + amounts.amountToLender + amounts.amountToBorrower <= settledAmount,
            "amounts mismatch"
        );
    }

    // https://github.com/arcadexyz/arcade-protocol/blob/fee-reno/contracts/origination/OriginationCalculator.sol
    function rolloverAmounts(
        uint256 oldBalance,
        uint256 oldInterestAmount,
        uint256 newPrincipalAmount,
        address lender,
        address oldLender,
        uint256 principalFee,
        uint256 interestFee
    ) public pure returns (RolloverAmounts memory amounts) {
        amounts.amountFromLender = newPrincipalAmount;
        amounts.interestAmount = oldInterestAmount;

        uint256 repayAmount = oldBalance + oldInterestAmount;
        uint256 totalFees = principalFee + interestFee;

        // Calculate net amounts based on if repayment amount for old loan is
        // greater than new loan principal
        if (repayAmount > newPrincipalAmount) {
            // amount to collect from borrower
            unchecked {
                amounts.needFromBorrower = repayAmount - newPrincipalAmount;
            }

            if (amounts.needFromBorrower < totalFees) {
                // if the amount to collect from the borrower is less than the total fees, the
                // lender pays the difference
                amounts.leftoverPrincipal = totalFees - amounts.needFromBorrower;
            }
        } else if (repayAmount < newPrincipalAmount) {
            // amount to collect from lender (either old or new)
            unchecked {
                amounts.leftoverPrincipal = newPrincipalAmount + totalFees - repayAmount;
            }
            // amount to send to borrower
            unchecked {
                amounts.amountToBorrower = newPrincipalAmount - repayAmount;
            }
        } else {
            // no leftover principal, fees paid by the lender
            amounts.leftoverPrincipal = totalFees;
        }

        // Calculate lender amounts based on if the lender is the same as the old lender
        if (lender != oldLender) {
            // different lenders, repay old lender
            amounts.amountToOldLender = repayAmount - totalFees;

            // different lender, amountToLender is zero
        } else {
            // same lender amountToOldLender is zero

            // same lender, so check if the amount to collect from the lender is less than
            // the amount the lender is owed for the old loan. If so, the lender is owed the
            // difference
            if (amounts.needFromBorrower > 0 && repayAmount - totalFees > newPrincipalAmount) {
                unchecked {
                    amounts.amountToLender = repayAmount - totalFees - newPrincipalAmount;
                }
            }
        }
    }
}
