// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./utils/BaseTest.sol";
import "./utils/InvariantTest.sol";

import {OptionWriter} from "./actors/OptionWriter.sol";
import {OptionHolder} from "./actors/OptionHolder.sol";
import {ProtocolAdmin} from "./actors/ProtocolAdmin.sol";
import {Timekeeper} from "./actors/Timekeeper.sol";

/// @notice Invariant tests for OptionSettlementEngine
contract OptionSettlementEngineInvariantTest is BaseTest, InvariantTest {
    OptionWriter internal writer;
    OptionHolder internal holder;
    ProtocolAdmin internal admin;
    Timekeeper internal timekeeper;

    function setUp() public override {
        super.setUp();

        writer = new OptionWriter(engine);
        holder = new OptionHolder(engine);
        admin = new ProtocolAdmin(engine);
        timekeeper = new Timekeeper();

        targetContract(address(writer));
        targetContract(address(holder));
        targetContract(address(admin));
        targetContract(address(timekeeper));

        excludeContract(address(engine));
        excludeContract(address(generator));

        targetSender(address(0xDEAD));

        console.logString("setUp");
    }

    function testInitial() public {
        assertEq(engine.feeTo(), FEE_TO);
        assertEq(engine.feesEnabled(), true);
    }

    function invariant_alwaysBlue() public {
        assertTrue(true);
    }
}
