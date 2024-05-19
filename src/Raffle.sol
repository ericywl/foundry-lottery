// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle contract
 * @author ericywl
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRF v2
 */
contract Raffle is VRFConsumerBaseV2 {
    /** Errors */

    error Raffle__NotEnoughEthForEntranceFee();
    error Raffle__WinnerPrizeTransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 numPlayers, uint256 raffleState);
    error Raffle__NotOwner();

    /** Type declarations */

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** State variables */

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    // Whenever player enters raffle with entrance fee, we take 1% as profit
    uint256 private constant PER_ENTRY_PROFIT_BPS = 100;

    // Entrance fee to enter the raffle
    uint256 private immutable i_entranceFee;
    // Duration of the lottery in seconds
    uint256 private immutable i_interval;
    // VRF coordinator from Chainlink
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    // Gas lane limits the gas spent for each request
    bytes32 private immutable i_gasLane;
    // Subscription ID for Chainlink VRF
    uint64 private immutable i_subscriptionId;
    // Chainlink VRF callback gas limit
    uint32 private immutable i_callbackGasLimit;
    // Owner of the raffle
    address private immutable i_owner;

    // List of players that entered the raffle since s_lastTimestamp
    address payable[] private s_players;
    // The last player that won the lottery
    address payable private s_recentWinner;
    // State of the raffle, to control certain function behaviors
    RaffleState private s_raffleState;
    // Timestamp when the raffle started
    uint256 private s_lastTimestamp;
    // Profit from developing this raffle
    uint256 private s_profits;

    /** Events */

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinatorAddr,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorAddr) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorAddr);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        i_owner = msg.sender;
    }

    function calculateProfitPerEntry(
        uint256 fee
    ) public pure returns (uint256) {
        require((fee * PER_ENTRY_PROFIT_BPS) >= 10_000);
        return (fee * PER_ENTRY_PROFIT_BPS) / 10_000;
    }

    // Modifier that only allows owner to execute.
    modifier onlyOwner() {
        if (msg.sender != i_owner) revert Raffle__NotOwner();
        _;
    }

    // Withdraw profits from contract.
    function withdraw() external onlyOwner {
        uint256 profits = s_profits;
        s_profits = 0;

        payable(msg.sender).transfer(profits);
    }

    // Enter the raffle by paying the entrance fee.
    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthForEntranceFee();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        s_profits = s_profits + calculateProfitPerEntry(i_entranceFee);
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that Chainlink Automation will call to see if it's time to perform an upkeep.
     * @dev The following should be true for this to return true:
     * @dev     1. The time interval has passed between raffle runs
     * @dev     2. The raffle is in the OPEN state
     * @dev     3. The raffle has players
     * @dev     4. (Implicit) The subscription to Automation is funded with LINK
     *
     * @return upkeepNeeded Whether performUpkeep should be called.
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) > i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasPlayers;
        return (upkeepNeeded, "0x0");
    }

    /**
     * @dev This is the function that Chainlink Automation will call to perform the upkeep.
     * @dev We will use this function to initiate the winner-picking process by requesting
     * @dev a random number from Chainlink VRF.
     */
    function performUpkeep(bytes calldata /* performData */) external {
        // Sanity check so that we don't accidentally perform the upkeep unnecessarily
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                s_players.length,
                uint256(s_raffleState)
            );
        }

        // Set state to CALCULATING, and request random number
        s_raffleState = RaffleState.CALCULATING;
        i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
    }

    /**
     * @dev fulfillRandomWords will be called by Chainlink VRF to notify us that a random number has been generated.
     * @dev We will use this random number to pick the winner.
     *
     * @param randomWords The random number that we requested for, should be in the first index since we only
     *          requested one number.
     */
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // Pick the winner using the random number
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        uint256 winnerPrize = getCurrentPrize();

        // Set the recent winner variable, and reset the other variables
        s_recentWinner = winner;
        s_lastTimestamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        // Emit winner event
        emit PickedWinner(winner);

        // Transfer prize to winner
        (bool success, ) = winner.call{value: winnerPrize}("");
        if (!success) {
            revert Raffle__WinnerPrizeTransferFailed();
        }
    }

    /** Getter functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getCurrentPrize() public view returns (uint256) {
        return address(this).balance - s_profits;
    }
}
