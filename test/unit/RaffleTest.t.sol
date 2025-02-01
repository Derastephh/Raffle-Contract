// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    address DERA = makeAddr("dera");
    uint256 constant STARTING_DERA_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    event RaffleEntered(address indexed participants);
    event WinnerPicked(address indexed s_winner);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(DERA, STARTING_DERA_BALANCE);
    }

    modifier raffleEntered() {
        vm.prank(DERA);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testBalaceRaffle() public {
        console.log(address(raffle).balance);
    }

    function testRaffleStateOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testEnterRaffleMsgValue() public {
        vm.prank(DERA);
        vm.expectRevert(Raffle.Raffle__TooMuchEthSent.selector);
        // uint256 valuee = raffle.enterRaffle{value: 0.001 ether}();
        raffle.enterRaffle{value: 0.05 ether}();
    }

    function testGetParticipants() public {
        vm.prank(DERA);
        raffle.enterRaffle{value: entranceFee}();
        assertEq(raffle.getParticipants(0), DERA);
        console.log(raffle.getParticipants(0), DERA);
    }

    function testEntranceFee() public {
        uint256 valuee = raffle.getEntranceFee();
        assert(valuee == entranceFee);
        console.log(valuee, entranceFee);
    }

    function testEmitEvent() public {
        vm.prank(DERA);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(DERA);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testRaffleStateIsCalculating() public raffleEntered {
        raffle.performUpkeep("");

        vm.prank(DERA);
        vm.expectRevert(Raffle.Raffle__RaffleNotOPen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testRaffleUpkeepIsFalseIfNoBalance() public {
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == false);
    }

    function testUpkeepIsFalseIfRaffleNotOpen() public raffleEntered {
        raffle.performUpkeep("");

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == false);
    }

    function testEmitRequestIdFromPerformUpkeep() public raffleEntered {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];

        Raffle.RaffleState state = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(state) == 1);
    }

    function testFulfillRandomWordsCanBeCalledAfterPerformUpKeep(
        uint256 randomRequestId
    ) public raffleEntered {
        vm.expectRevert();
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsResetsAndPicksAWinnerToSendMoney()
        public
        raffleEntered
    {
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTime = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        address recentWinner = raffle.getWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTime = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTime > startingTime);
    }
}
