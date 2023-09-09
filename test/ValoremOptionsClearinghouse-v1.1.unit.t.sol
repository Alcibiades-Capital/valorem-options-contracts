// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import {pp, SolPretty} from "SolPretty/SolPretty.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "./utils/BaseClearinghouseTest.sol";

/// @notice Unit tests for ValoremOptionsClearinghouse v1.1.0
contract ValoremOptionsClearinghousev11UnitTest is BaseClearinghouseTest {
    using SolPretty for string;

    /*//////////////////////////////////////////////////////////////
    // Clearinghouse v1.1.0
    //////////////////////////////////////////////////////////////*/

    function test_claimAssignmentStatus() public {
        uint112 amountWritten = 5;
        uint256 expectedFee = _calculateFee(testUnderlyingAmount * amountWritten);
        uint256 expectedClaimId = testOptionId + 1;

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        // Post-write conditions
        assertEq(claimId, expectedClaimId, "claimId");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice Claim NFT");
        assertEq(engine.balanceOf(ALICE, testOptionId), amountWritten, "Alice Option tokens");
        assertEq(
            IERC20(testUnderlyingAsset).balanceOf(ALICE),
            STARTING_BALANCE_WETH - (testUnderlyingAmount * amountWritten) - expectedFee,
            "Alice underlying"
        );
        assertEq(IERC20(testExerciseAsset).balanceOf(ALICE), STARTING_BALANCE, "Alice exercise"); // no change
        assertEq(engine.feeBalance(testUnderlyingAsset), expectedFee, "Fee balance underlying");
        assertEq(engine.feeBalance(testExerciseAsset), 0, "Fee balance exercise"); // no fee assessed on exercise asset during write()

        // Unassigned
        IValoremOptionsClearinghouse.Claim memory unassigned = engine.claim(claimId);
        emit log("Unassigned Claim ---------");
        emit log_named_string("amountWritten", pp(unassigned.amountWritten, 18, 0));
        emit log_named_string("amountExercised", pp(unassigned.amountExercised, 18, 0));
        uint256 assignmentPercentage = unassigned.amountExercised / unassigned.amountWritten;
        emit log_named_uint("percentage", assignmentPercentage);
        // if amountExercised == 0, claim is unassigned

        // Partially Assigned
        vm.prank(ALICE);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 5, "");

        vm.prank(BOB);
        engine.exercise(testOptionId, 1);

        IValoremOptionsClearinghouse.Claim memory partiallyAssigned = engine.claim(claimId);
        emit log("Partially Assigned Claim ---------");
        emit log_named_string("amountWritten", pp(partiallyAssigned.amountWritten, 18, 0));
        emit log_named_string("amountExercised", pp(partiallyAssigned.amountExercised, 18, 0));
        assignmentPercentage = partiallyAssigned.amountExercised / partiallyAssigned.amountWritten;
        emit log_named_uint("percentage", assignmentPercentage); // TODO use scalar
        // if amountExercised > 0 && amountWritten > amountExercised, claim is partially assigned

        // Fully Assigned
        vm.prank(BOB);
        engine.exercise(testOptionId, 4);

        IValoremOptionsClearinghouse.Claim memory fullyAssigned = engine.claim(claimId);
        emit log("Fully Assigned Claim ---------");
        emit log_named_string("amountWritten", pp(fullyAssigned.amountWritten, 18, 0));
        emit log_named_string("amountExercised", pp(fullyAssigned.amountExercised, 18, 0));
        assignmentPercentage = fullyAssigned.amountExercised / fullyAssigned.amountWritten;
        emit log_named_uint("percentage", assignmentPercentage);
        // if amountWritten == amountExercised, claim is fully assigned
    }

    /*//////////////////////////////////////////////////////////////
    // net(uint256 optionId) external
    //////////////////////////////////////////////////////////////*/

    // TODO

    function test_net_whenUnassigned() public {
        uint256 balanceA = ERC20A.balanceOf(ALICE);
        uint256 balanceB = ERC20B.balanceOf(ALICE);

        // Alice writes 10 Options
        vm.startPrank(ALICE);
        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });
        uint256 claimId = engine.write(optionId, 10);

        uint256 expectedWriteAmount = 10 * 1 ether;

        assertEq(engine.balanceOf(ALICE, optionId), 10, "Alice option tokens before");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens before");
        assertEq(
            ERC20A.balanceOf(ALICE),
            balanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
            "Alice underlying asset before"
        );
        assertEq(ERC20B.balanceOf(ALICE), balanceB, "Alice exercise asset before");

        // Alice nets offsetting positions after no Options have been exercised
        engine.net(claimId);

        assertEq(engine.balanceOf(ALICE, optionId), 0, "Alice option tokens after");
        assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim tokens after");
        assertEq(ERC20A.balanceOf(ALICE), balanceA - _calculateFee(expectedWriteAmount), "Alice underlying asset after"); // still less write fee
        assertEq(ERC20B.balanceOf(ALICE), balanceB, "Alice exercise asset after");
    }

    function test_net_whenPartiallyExercised() public {
        uint256 aliceBalanceA = ERC20A.balanceOf(ALICE);
        uint256 aliceBalanceB = ERC20B.balanceOf(ALICE);
        uint256 bobBalanceA = ERC20A.balanceOf(BOB);
        uint256 bobBalanceB = ERC20B.balanceOf(BOB);

        // Alice writes 10 Options
        vm.startPrank(ALICE);
        uint256 optionId = engine.newOptionType({
            underlyingAsset: address(ERC20A),
            underlyingAmount: 1 ether,
            exerciseAsset: address(ERC20B),
            exerciseAmount: 8 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });
        uint256 claimId = engine.write(optionId, 10);

        uint256 expectedWriteAmount = 10 * 1 ether;
        uint256 expectedExerciseAmount = 3 * 8 ether;

        assertEq(engine.balanceOf(ALICE, optionId), 10, "Alice option tokens before");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens before");
        assertEq(
            ERC20A.balanceOf(ALICE),
            aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
            "Alice underlying asset before"
        );
        assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB, "Alice exercise asset before");

        // Alice transfers 3 Options to Bob
        engine.safeTransferFrom(ALICE, BOB, optionId, 3, "");
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, optionId), 7, "Alice option tokens after transfer");
        assertEq(engine.balanceOf(ALICE, claimId), 1, "Alice claim tokens after transfer");

        // Bob exercises 3 Options
        vm.prank(BOB);
        engine.exercise(optionId, 3);

        assertEq(
            ERC20A.balanceOf(ALICE),
            aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount),
            "Alice underlying asset after exercise"
        );
        assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB, "Alice exercise asset after exercise");
        assertEq(ERC20A.balanceOf(BOB), bobBalanceA + (3 * 1 ether), "Bob underlying asset after exercise");
        assertEq(
            ERC20B.balanceOf(BOB),
            bobBalanceB - expectedExerciseAmount - _calculateFee(expectedExerciseAmount),
            "Bob exercise asset after exercise"
        );

        // Alice closes remaining 7 Options and gets collateral back from 3 Options that Bob exercised
        engine.net(claimId);

        assertEq(engine.balanceOf(ALICE, optionId), 0, "Alice option tokens after close");
        assertEq(engine.balanceOf(ALICE, claimId), 0, "Alice claim tokens after close");
        assertEq(
            ERC20A.balanceOf(ALICE),
            aliceBalanceA - expectedWriteAmount - _calculateFee(expectedWriteAmount) + (3 * 1 ether),
            "Alice underlying asset after close"
        );
        assertEq(ERC20B.balanceOf(ALICE), aliceBalanceB + expectedExerciseAmount, "Alice exercise asset after close");
        assertEq(ERC20A.balanceOf(BOB), bobBalanceA + (3 * 1 ether), "Bob underlying asset after close");
        assertEq(
            ERC20B.balanceOf(BOB),
            bobBalanceB - expectedExerciseAmount - _calculateFee(expectedExerciseAmount),
            "Bob exercise asset after close"
        );
    }

    // TODO remaining scenarios

    /*//////////////////////////////////////////////////////////////
    // redeem() early
    //////////////////////////////////////////////////////////////*/

    // TODO
}
