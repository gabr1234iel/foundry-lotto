// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Errors */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    //Events
    event EnteredRaffle(address indexed participant);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 ticketPrice;
    uint256 raffleDuration;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            ticketPrice,
            raffleDuration,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitsInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////
    // enterraffle //
    /////////////////

    function testRaffleRevertsIfNotEnoughEthSent() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleEnterSuccessRecordPlayer() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: ticketPrice}();
        address playerRecorded = raffle.getParticipantOfIndex(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnRaffleEntry() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: ticketPrice}();
    }

    function testCantEnterWhenRaffleIsCalculatingWinner() public raffleEntered {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: ticketPrice}();
    }

    ///////////////////
    // checkUpkeep   //
    ///////////////////

    function testCheckUpkeepReturnsFalseIfNoBalance() public {
        vm.warp(block.timestamp + raffleDuration + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        vm.prank(PLAYER);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughtTimeHasntPassed() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: ticketPrice}();
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood()
        public
        raffleEntered
    {
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded);
    }

    ///////////////////
    // performUpkeep //
    ///////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        raffleEntered
    {
        raffle.performUpkeep("");
        assert(
            raffle.getRaffleState() == Raffle.RaffleState.CALCULATING_WINNER
        );
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numParticipants = 0;
        uint256 raffleState = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                raffleState,
                numParticipants
            )
        );
        raffle.performUpkeep("");
    }

    // What if i want to test with an output of event?

    function testPerformUpkeepUpdatesRaffleStateAndEmitRequestId()
        public
        raffleEntered
    {
        vm.recordLogs();
        raffle.performUpkeep(""); //emit req id
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(rState == Raffle.RaffleState.CALCULATING_WINNER);
    }

    //////////////////////////
    // fulfillRandomWords   //
    //////////////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    //final test
    function testFulFillRandomWordsPicksAWinnerResetsAndSendMoney() public raffleEntered skipFork{
        address expectedWinner = address(1);

        //Arrange
        uint256 totalParticipants = 5;
        for (uint256 i = 1; i < totalParticipants; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: ticketPrice}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        //Act
        vm.recordLogs();
        raffle.performUpkeep(""); //emit req id
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        //pretend to be chainlink vrf
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState rState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 numParticipants = raffle.getParticipants().length;
        uint256 prize = ticketPrice * (totalParticipants);

        assert(recentWinner == expectedWinner);
        assert(rState == Raffle.RaffleState.OPEN);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
        assert(numParticipants == 0);
    }

    //modifiers
    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: ticketPrice}();
        vm.warp(block.timestamp + raffleDuration + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if(block.chainid != 31337){
            return;
        }
        _;
    }
}
