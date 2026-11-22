// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Raffle} from "../../src/Raffle.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

contract RaffleTest is Test {
    event RequestedRaffleWinner(uint256 indexed requestId);
    event TicketIssued(uint256 indexed lotteryId, uint256 indexed ticketNumber, address indexed player);
    event WinnerPicked(address indexed player, uint256 indexed lotteryId, uint256 indexed ticketNumber, uint256 prize);

    uint96 private constant MOCK_BASE_FEE = 0.25 ether;
    uint96 private constant MOCK_GAS_PRICE_LINK = 1e9;
    int256 private constant MOCK_WEI_PER_UINT_LINK = 4e15;
    uint256 private constant LINK_BALANCE = 100 ether;
    uint256 private constant INTERVAL = 30;
    uint256 private constant SPONSORED_AMOUNT_PER_ENTRY = 1e6;
    uint256 private constant MAX_PLAYERS = 5;
    uint256 private constant ROUND_BUDGET = SPONSORED_AMOUNT_PER_ENTRY * MAX_PLAYERS;
    uint256 private constant ADMIN_STARTING_USDC_BALANCE = 80e6;
    uint32 private constant CALLBACK_GAS_LIMIT = 500_000;
    bytes32 private constant GAS_LANE = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    Raffle private raffle;
    MockUSDC private usdc;
    VRFCoordinatorV2_5Mock private vrfCoordinator;
    uint256 private subscriptionId;
    address private adminWallet = makeAddr("admin-metamask-wallet");
    address private player = makeAddr("player");

    function setUp() external {
        usdc = new MockUSDC();
        vrfCoordinator = new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK, MOCK_WEI_PER_UINT_LINK);

        subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subscriptionId, LINK_BALANCE);

        raffle = new Raffle(
            subscriptionId,
            GAS_LANE,
            INTERVAL,
            CALLBACK_GAS_LIMIT,
            address(vrfCoordinator),
            address(usdc),
            adminWallet,
            SPONSORED_AMOUNT_PER_ENTRY,
            MAX_PLAYERS
        );
        vrfCoordinator.addConsumer(subscriptionId, address(raffle));

        usdc.mint(adminWallet, ADMIN_STARTING_USDC_BALANCE);
        vm.prank(adminWallet);
        usdc.approve(address(raffle), ROUND_BUDGET);
    }

    function testInitializesWithSponsoredUsdcConfiguration() public view {
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
        assertEq(raffle.getCurrentLotteryId(), 1);
        assertEq(raffle.getUsdc(), address(usdc));
        assertEq(raffle.getSponsor(), adminWallet);
        assertEq(raffle.getSponsoredAmountPerEntry(), SPONSORED_AMOUNT_PER_ENTRY);
        assertEq(raffle.getMaxPlayers(), MAX_PLAYERS);
        assertEq(raffle.getCurrentPot(), 0);
    }

    function testRejectsInvalidSponsoredConfiguration() public {
        vm.expectRevert(Raffle.Raffle__InvalidConfiguration.selector);
        _deployRaffle(address(0), adminWallet, SPONSORED_AMOUNT_PER_ENTRY, MAX_PLAYERS);

        vm.expectRevert(Raffle.Raffle__InvalidConfiguration.selector);
        _deployRaffle(address(usdc), address(0), SPONSORED_AMOUNT_PER_ENTRY, MAX_PLAYERS);

        vm.expectRevert(Raffle.Raffle__InvalidConfiguration.selector);
        _deployRaffle(address(usdc), adminWallet, 0, MAX_PLAYERS);

        vm.expectRevert(Raffle.Raffle__InvalidConfiguration.selector);
        _deployRaffle(address(usdc), adminWallet, SPONSORED_AMOUNT_PER_ENTRY, 0);
    }

    function testAdminWalletApprovesExactlyFiveUsdcForOneFullLottery() public view {
        assertEq(usdc.allowance(adminWallet, address(raffle)), ROUND_BUDGET);
    }

    function testEntryPullsOneUsdcFromAdminSponsorAndIssuesTicket() public {
        uint256 adminBalanceBefore = usdc.balanceOf(adminWallet);

        vm.expectEmit(true, true, true, true, address(raffle));
        emit TicketIssued(1, 1, player);
        _enter(player);

        assertEq(raffle.getPlayer(0), player);
        assertEq(raffle.getNumberOfPlayers(), 1);
        assertEq(raffle.getCurrentPot(), SPONSORED_AMOUNT_PER_ENTRY);
        assertEq(usdc.balanceOf(adminWallet), adminBalanceBefore - SPONSORED_AMOUNT_PER_ENTRY);
        assertEq(usdc.balanceOf(address(raffle)), SPONSORED_AMOUNT_PER_ENTRY);
        assertEq(usdc.balanceOf(player), 0);
    }

    function testEntriesIssueSequentialLogicalTickets() public {
        address secondPlayer = makeAddr("second-player");

        _enter(player);
        vm.expectEmit(true, true, true, true, address(raffle));
        emit TicketIssued(1, 2, secondPlayer);
        _enter(secondPlayer);

        assertEq(raffle.getPlayer(1), secondPlayer);
        assertEq(raffle.getCurrentPot(), 2 * SPONSORED_AMOUNT_PER_ENTRY);
    }

    function testWalletCannotEnterTwiceInSameLottery() public {
        _enter(player);

        vm.expectRevert(Raffle.Raffle__AlreadyEntered.selector);
        _enter(player);
    }

    function testSixthWalletCannotEnterFullLottery() public {
        for (uint256 i = 1; i <= MAX_PLAYERS; i++) {
            _enter(address(uint160(i)));
        }

        vm.expectRevert(Raffle.Raffle__RaffleFull.selector);
        _enter(address(uint160(MAX_PLAYERS + 1)));
    }

    function testEntryRevertsWhenAdminAllowanceIsInsufficient() public {
        vm.prank(adminWallet);
        usdc.approve(address(raffle), 0);

        vm.expectRevert();
        _enter(player);
    }

    function testEntryRevertsWhenAdminBalanceIsInsufficient() public {
        vm.prank(adminWallet);
        usdc.transfer(makeAddr("sink"), ADMIN_STARTING_USDC_BALANCE);

        vm.expectRevert();
        _enter(player);
    }

    function testPlayerCannotEnterWhileRaffleIsCalculating() public {
        _enter(player);
        _requestRandomWinner();

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        _enter(makeAddr("late-player"));
    }

    function testCheckUpkeepReturnsFalseWithoutPlayers() public {
        _advancePastInterval();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseBeforeIntervalPasses() public {
        _enter(player);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWithCollectedUsdcPlayerAndElapsedInterval() public {
        _enter(player);
        _advancePastInterval();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepRevertsWhenConditionsAreNotMet() public {
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, 0, 0, uint256(Raffle.RaffleState.OPEN))
        );
        raffle.performUpkeep("");
    }

    function testFulfillmentPaysActualUsdcPotAndAutomaticallyOpensNextLottery() public {
        address secondPlayer = address(1);
        address thirdPlayer = address(2);
        _enter(player);
        _enter(secondPlayer);
        _enter(thirdPlayer);

        uint256 prize = 3 * SPONSORED_AMOUNT_PER_ENTRY;
        uint256 requestId = _requestRandomWinner();
        vrfCoordinator.fulfillRandomWords(requestId, address(raffle));

        address winner = raffle.getRecentWinner();
        uint256 winningTicket = raffle.getRecentWinningTicket();
        assertTrue(winner == player || winner == secondPlayer || winner == thirdPlayer);
        assertGe(winningTicket, 1);
        assertLe(winningTicket, 3);
        assertEq(usdc.balanceOf(winner), prize);
        assertEq(usdc.balanceOf(address(raffle)), 0);
        assertEq(raffle.getNumberOfPlayers(), 0);
        assertEq(raffle.getCurrentPot(), 0);
        assertEq(raffle.getCurrentLotteryId(), 2);
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    function testWalletCanEnterAgainAfterAutomaticLotteryReset() public {
        _enter(player);
        uint256 requestId = _requestRandomWinner();
        vrfCoordinator.fulfillRandomWords(requestId, address(raffle));

        vm.expectEmit(true, true, true, true, address(raffle));
        emit TicketIssued(2, 1, player);
        _enter(player);

        assertEq(raffle.getPlayer(0), player);
        assertEq(raffle.getCurrentLotteryId(), 2);
    }

    function _enter(address entrant) private {
        vm.prank(entrant);
        raffle.enterRaffle();
    }

    function _deployRaffle(address token, address raffleSponsor, uint256 amount, uint256 maxPlayers)
        private
        returns (Raffle)
    {
        return new Raffle(
            subscriptionId,
            GAS_LANE,
            INTERVAL,
            CALLBACK_GAS_LIMIT,
            address(vrfCoordinator),
            token,
            raffleSponsor,
            amount,
            maxPlayers
        );
    }

    function _advancePastInterval() private {
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.roll(block.number + 1);
    }

    function _requestRandomWinner() private returns (uint256 requestId) {
        _advancePastInterval();
        vm.recordLogs();
        raffle.performUpkeep("");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("RequestedRaffleWinner(uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(raffle) && logs[i].topics[0] == eventSignature) {
                return uint256(logs[i].topics[1]);
            }
        }
        revert("request id not found");
    }
}
