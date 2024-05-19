// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 entranceFee,
            uint256 interval,
            address vrfCoordinatorAddr,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address linkToken
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            // Create subscription since it is empty
            CreateSubscription subCreator = new CreateSubscription();
            subscriptionId = subCreator.createSubscription(vrfCoordinatorAddr);

            // Fund the above subscription
            FundSubscription subFunder = new FundSubscription();
            subFunder.fundSubscription(
                vrfCoordinatorAddr,
                subscriptionId,
                linkToken
            );
        }

        // Launch raffle
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            entranceFee,
            interval,
            vrfCoordinatorAddr,
            gasLane,
            subscriptionId,
            callbackGasLimit
        );
        vm.stopBroadcast();

        // Add consumer for subscription
        AddConsumer consumerAdder = new AddConsumer();
        consumerAdder.addConsumer(
            address(raffle),
            vrfCoordinatorAddr,
            subscriptionId
        );
        return (raffle, helperConfig);
    }
}
