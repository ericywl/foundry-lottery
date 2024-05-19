// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "../../script/Interactions.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract InteractionsTest is Test {
    CreateSubscription subCreator;
    FundSubscription subFunder;
    AddConsumer consumerAdder;

    address vrfCoordinator;
    address linkToken;

    function setUp() public {
        subCreator = new CreateSubscription();
        subFunder = new FundSubscription();

        HelperConfig helperConfig = new HelperConfig();
        (, , vrfCoordinator, , , , linkToken) = helperConfig
            .activeNetworkConfig();
    }

    function testCanCreateSubscription() public {
        uint64 subscriptionId = subCreator.createSubscriptionUsingConfig();
        assert(subscriptionId > 0);
    }

    function testCanFundSubscription() public {
        uint64 subscriptionId = subCreator.createSubscription(vrfCoordinator);

        vm.recordLogs();
        subFunder.fundSubscription(vrfCoordinator, subscriptionId, linkToken);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 eventHash = entries[0].topics[0];
        uint64 emitSubId = uint64(uint256(entries[0].topics[1]));
        assertEq(
            eventHash,
            keccak256("SubscriptionFunded(uint64,uint256,uint256)")
        );
        assertEq(emitSubId, subscriptionId);
    }

    function testCanAddConsumer() public {
        DeployRaffle deployer = new DeployRaffle();
        (Raffle raffle, ) = deployer.run();

        uint64 subscriptionId = subCreator.createSubscription(vrfCoordinator);

        vm.recordLogs();
        consumerAdder.addConsumer(
            address(raffle),
            vrfCoordinator,
            subscriptionId
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 eventHash = entries[0].topics[0];
        uint64 emitSubId = uint64(uint256(entries[0].topics[1]));
        address emitConsumer = address(uint160(uint256(entries[0].topics[2])));
        assertEq(eventHash, keccak256("ConsumerAdded(uint64,address)"));
        assertEq(emitSubId, subscriptionId);
        assertEq(emitConsumer, address(raffle));
    }
}
