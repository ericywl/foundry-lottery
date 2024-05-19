// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /** Events */
    event EnteredRaffle(address indexed player);

    Raffle raffle;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinatorAddr;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address linkTokenAddr;

    address public PLAYER_1 = makeAddr("player_1");
    address public PLAYER_2 = makeAddr("player_2");

    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        HelperConfig helperConfig;
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinatorAddr,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            linkTokenAddr
        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER_1, STARTING_USER_BALANCE);
        vm.deal(PLAYER_2, STARTING_USER_BALANCE);
    }

    function testRaffleInitializeInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /** Enter raffle */

    function testRaffleRevertWhenDontPayEnough() public {
        vm.prank(PLAYER_1);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthForEntranceFee.selector);
        raffle.enterRaffle{value: entranceFee - 1}();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER_1);
        raffle.enterRaffle{value: entranceFee}();
        vm.prank(PLAYER_2);
        raffle.enterRaffle{value: entranceFee}();

        assertEq(raffle.getPlayer(0), PLAYER_1);
        assertEq(raffle.getPlayer(1), PLAYER_2);
    }

    function testRaffleEmitsEventOnEntrance() public {
        // https://book.getfoundry.sh/cheatcodes/prank
        vm.prank(PLAYER_2);
        // https://book.getfoundry.sh/cheatcodes/expect-emit
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER_2);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsNotOpen() public {
        // Enter raffle first time
        vm.prank(PLAYER_1);
        raffle.enterRaffle{value: entranceFee}();

        // Now that we have a player, we do a time-skip (by setting block timestamp and number) so that
        // the performUpkeep function can be run
        // https://book.getfoundry.sh/cheatcodes/warp
        vm.warp(block.timestamp + interval + 1);
        // https://book.getfoundry.sh/cheatcodes/roll
        vm.roll(block.number + 1);

        // Manually running this function causes the raffle state to change
        raffle.performUpkeep("");
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);

        // We try to enter raffle again, but because raffle state is calculating, we expect a revert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER_2);
        raffle.enterRaffle{value: entranceFee}();
    }

    /** Check upkeep */

    function testCheckUpkeepReturnsFalseIfNotEnoughTimePassed() public {
        // There are players
        vm.prank(PLAYER_2);
        raffle.enterRaffle{value: entranceFee}();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfNoPlayers() public {
        // Enough time has passed
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        // There are players
        vm.prank(PLAYER_2);
        raffle.enterRaffle{value: entranceFee}();
        // Enough time has passed
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // We are however performing upkeep
        raffle.performUpkeep("");

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueIfAllOkay() public {
        // There are players
        vm.prank(PLAYER_1);
        raffle.enterRaffle{value: entranceFee}();
        // Enough time has passed
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    /** Perform upkeep */

    modifier checkUpkeepTrue() {
        // There are players
        vm.prank(PLAYER_1);
        raffle.enterRaffle{value: entranceFee}();
        // Enough time has passed
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepCanRunIfCheckUpkeepTrue() public checkUpkeepTrue {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepFalse() public {
        // There are players
        vm.prank(PLAYER_1);
        raffle.enterRaffle{value: entranceFee}();

        // https://book.getfoundry.sh/cheatcodes/expect-revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                1, // number of players
                0 // raffle state
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsEvent()
        public
        checkUpkeepTrue
    {
        vm.recordLogs();
        raffle.performUpkeep(""); // This should emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[0].topics[2];
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(raffleState == Raffle.RaffleState.CALCULATING);
    }

    /** Fulfill random words */

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 requestId // fuzzing the request IDs
    ) public checkUpkeepTrue {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatorAddr).fulfillRandomWords(
            requestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksWinnerAndSendsMoney()
        public
        checkUpkeepTrue
    {
        // Add other random players
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, STARTING_USER_BALANCE); // prank + deal
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 previousTimestamp = raffle.getLastTimestamp();
        uint256 prize = raffle.getCurrentPrize();

        vm.recordLogs();
        raffle.performUpkeep(""); // This should emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[0].topics[2];

        // Pretend to be VRF to get random number and pick winner
        VRFCoordinatorV2Mock(vrfCoordinatorAddr).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Raffle state reset
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        // Number of players reset
        assert(raffle.getNumberOfPlayers() == 0);
        // Timestamp updated
        assert(raffle.getLastTimestamp() > previousTimestamp);
        // Has a recent winner
        assert(raffle.getRecentWinner() != address(0));
        // Winner got the prize
        assertEq(
            raffle.getRecentWinner().balance,
            STARTING_USER_BALANCE + prize - entranceFee
        );
    }

    /** Withdrawal */

    function testOwnerWithdrawProfitsIsOnePercent() public {
        vm.prank(PLAYER_1);
        raffle.enterRaffle{value: entranceFee}();
        // We should only have entrance fee in balance
        assertEq(address(raffle).balance, entranceFee);

        uint256 startingOwnerBalance = raffle.getOwner().balance;
        vm.prank(raffle.getOwner());
        raffle.withdraw();

        // Owner get 1%, the balance remaining is 99%
        uint256 ownerProfits = raffle.getOwner().balance - startingOwnerBalance;
        assertEq(ownerProfits, (entranceFee / 100));
        assertEq(address(raffle).balance, (entranceFee * 99) / 100);
    }

    function testOwnerCannotOverWithdraw() public {
        vm.prank(PLAYER_1);
        raffle.enterRaffle{value: entranceFee}();
        // We should only have entrance fee in balance
        assertEq(address(raffle).balance, entranceFee);

        uint256 startingOwnerBalance = raffle.getOwner().balance;
        vm.prank(raffle.getOwner());
        raffle.withdraw();
        vm.prank(raffle.getOwner());
        raffle.withdraw();

        // Owner withdrew twice, but doesn't get more than 1%
        uint256 ownerProfits = raffle.getOwner().balance - startingOwnerBalance;
        assertEq(ownerProfits, (entranceFee / 100));
    }
}
