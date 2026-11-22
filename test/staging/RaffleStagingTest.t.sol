// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {
    IERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract RaffleStagingTest is Test {
    Raffle private raffle;
    IERC20 private usdc;
    uint256 private interval;
    address private vrfCoordinator;
    address private player = makeAddr("player");

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        HelperConfig helperConfig;
        (raffle, helperConfig) = deployer.run();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        interval = config.automationUpdateInterval;
        vrfCoordinator = config.vrfCoordinatorV2_5;
        usdc = IERC20(config.usdc);
    }

    modifier raffleEntered() {
        vm.prank(player);
        raffle.enterRaffle();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier onlyOnDeployedContracts() {
        if (block.chainid == 31337) return;
        try vm.activeFork() returns (uint256) {
            return;
        } catch {
            _;
        }
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public onlyOnDeployedContracts raffleEntered {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(0, address(raffle));

        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(1, address(raffle));
    }

    function testFulfillmentPaysUsdcAndResetsLottery() public onlyOnDeployedContracts raffleEntered {
        uint256 prize = raffle.getCurrentPot();
        uint256 startingLotteryId = raffle.getCurrentLotteryId();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId = _findRequestId(logs);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));

        address winner = raffle.getRecentWinner();
        assertEq(winner, player);
        assertEq(usdc.balanceOf(winner), prize);
        assertEq(raffle.getCurrentLotteryId(), startingLotteryId + 1);
        assertEq(raffle.getNumberOfPlayers(), 0);
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    function _findRequestId(Vm.Log[] memory logs) private view returns (uint256) {
        bytes32 signature = keccak256("RequestedRaffleWinner(uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(raffle) && logs[i].topics[0] == signature) {
                return uint256(logs[i].topics[1]);
            }
        }
        revert("request id not found");
    }
}
