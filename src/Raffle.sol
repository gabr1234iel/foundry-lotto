// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title A simple raffle
 * @author gabr1234iel
 * @notice This contract is for creating a simple raffle contract
 * @dev Implements Chainlink VRFv2
 */

// Imports
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    // Errors
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        RaffleState state,
        uint256 participants
    );

    // Constants
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // Type Declarations
    enum RaffleState {
        OPEN,
        CALCULATING_WINNER
    }

    // State Variables
    uint256 private immutable i_ticketPrice;
    uint256 private immutable i_raffleDuration;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint256 private s_lastTimeStamp;
    address payable[] private s_participants;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    // Events
    event EnteredRaffle(address indexed participant);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 ticketPrice,
        uint256 raffleDuration,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_ticketPrice = ticketPrice;
        i_raffleDuration = raffleDuration;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_ticketPrice) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_participants.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    function checkUpkeep(
        bytes memory /*checkdata*/
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_raffleDuration);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = address(this).balance > 0;
        bool hasParticipants = s_participants.length > 0;
        upkeepNeeded = (timeHasPassed &&
            isOpen &&
            hasBalance &&
            hasParticipants);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_raffleState,
                s_participants.length
            );
        }

        s_raffleState = RaffleState.CALCULATING_WINNER;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        // Checks
        // Effects
        uint256 winnerIndex = randomWords[0] % s_participants.length;
        address payable winner = s_participants[winnerIndex];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_participants = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(winner);
        // Interactions
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // Getter Functions

    function getTicketPrice() public view returns (uint256) {
        return i_ticketPrice;
    }

    function getRaffleDuration() public view returns (uint256) {
        return i_raffleDuration;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getParticipants() public view returns (address payable[] memory) {
        return s_participants;
    }

    function getParticipantOfIndex(uint256 index)
        public
        view
        returns (address)
    {
        return s_participants[index];
    }


}
