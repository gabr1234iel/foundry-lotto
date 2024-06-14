// SPDX-license-identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test {

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
            link
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

    function testCantEnterWhenRaffleIsCalculatingWinner() public{
        vm.prank(PLAYER);
        raffle.enterRaffle{value: ticketPrice}();
        vm.warp(block.timestamp + raffleDuration + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: ticketPrice}();    
    }


}
