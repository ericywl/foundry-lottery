// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "./token/LinkToken.sol";

contract CreateSubscription is Script {
    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }

    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , ) = helperConfig
            .activeNetworkConfig();
        return createSubscription(vrfCoordinator);
    }

    function createSubscription(
        address vrfCoordinator
    ) public returns (uint64) {
        console.log("Creating subscription on chain: ", block.chainid);

        vm.startBroadcast();
        uint64 subscriptionId = VRFCoordinatorV2Interface(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();

        console.log("Subscription Id: ", subscriptionId);
        return subscriptionId;
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether; // 3 LINK

    function run() external {
        fundSubscriptionUsingConfig();
    }

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subscriptionId,
            ,
            address linkToken
        ) = helperConfig.activeNetworkConfig();

        fundSubscription(vrfCoordinator, subscriptionId, linkToken);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint64 subscriptionId,
        address linkToken
    ) public {
        console.log("Funding subscription: ", subscriptionId);
        console.log("Using VRF coordinator: ", vrfCoordinator);
        console.log("On chain: ", block.chainid);

        if (block.chainid == 31337) {
            vm.startBroadcast();
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subscriptionId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(linkToken).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subscriptionId)
            );
            vm.stopBroadcast();
        }
    }
}

contract AddConsumer is Script {
    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );

        addConsumerUsingConfig(raffle);
    }

    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , uint64 subscriptionId, , ) = helperConfig
            .activeNetworkConfig();

        addConsumer(raffle, vrfCoordinator, subscriptionId);
    }

    function addConsumer(
        address raffle,
        address vrfCoordinator,
        uint64 subscriptionId
    ) public {
        console.log("Adding consumer contract: ", raffle);
        console.log("Using VRF coordinator: ", vrfCoordinator);
        console.log("On chain: ", block.chainid);

        vm.startBroadcast();
        VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(
            subscriptionId,
            raffle
        );
        vm.stopBroadcast();
    }
}
