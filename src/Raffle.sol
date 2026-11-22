// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {
    IERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Sponsor-funded USDC raffle
 * @notice The sponsor pays one fixed USDC amount for every unique wallet that enters.
 * @dev Chainlink Automation closes each lottery and Chainlink VRF selects its winner.
 */
contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;

    error Raffle__UpkeepNotNeeded(uint256 currentPot, uint256 numPlayers, uint256 raffleState);
    error Raffle__RaffleNotOpen();
    error Raffle__AlreadyEntered();
    error Raffle__RaffleFull();
    error Raffle__InvalidConfiguration();

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint256 private immutable i_interval;
    IERC20 private immutable i_usdc;
    address private immutable i_sponsor;
    uint256 private immutable i_sponsoredAmountPerEntry;
    uint256 private immutable i_maxPlayers;

    uint256 private s_lastTimeStamp;
    uint256 private s_currentLotteryId = 1;
    uint256 private s_recentWinningTicket;
    address private s_recentWinner;
    address[] private s_players;
    RaffleState private s_raffleState;
    mapping(address player => uint256 lotteryId) private s_lastEnteredLottery;

    event RequestedRaffleWinner(uint256 indexed requestId);
    event TicketIssued(uint256 indexed lotteryId, uint256 indexed ticketNumber, address indexed player);
    event WinnerPicked(address indexed player, uint256 indexed lotteryId, uint256 indexed ticketNumber, uint256 prize);

    constructor(
        uint256 subscriptionId,
        bytes32 gasLane,
        uint256 interval,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2,
        address usdc,
        address sponsor,
        uint256 sponsoredAmountPerEntry,
        uint256 maxPlayers
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        if (usdc == address(0) || sponsor == address(0) || sponsoredAmountPerEntry == 0 || maxPlayers == 0) {
            revert Raffle__InvalidConfiguration();
        }
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_interval = interval;
        i_callbackGasLimit = callbackGasLimit;
        i_usdc = IERC20(usdc);
        i_sponsor = sponsor;
        i_sponsoredAmountPerEntry = sponsoredAmountPerEntry;
        i_maxPlayers = maxPlayers;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    /**
     * @notice Enters the caller once in the current lottery and issues a logical ticket.
     * @dev The entrant pays no USDC. One entry amount is pulled from the sponsor allowance.
     */
    function enterRaffle() external {
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();
        if (s_players.length >= i_maxPlayers) revert Raffle__RaffleFull();
        if (s_lastEnteredLottery[msg.sender] == s_currentLotteryId) revert Raffle__AlreadyEntered();

        uint256 ticketNumber = s_players.length + 1;
        s_lastEnteredLottery[msg.sender] = s_currentLotteryId;
        s_players.push(msg.sender);

        // forge-lint: disable-next-line(arbitrary-send-erc20)
        i_usdc.safeTransferFrom(i_sponsor, address(this), i_sponsoredAmountPerEntry);
        emit TicketIssued(s_currentLotteryId, ticketNumber, msg.sender);
    }

    function checkUpkeep(bytes memory) public view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentPot = getCurrentPot();
        bool timePassed = block.timestamp - s_lastTimeStamp > i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasPlayers = s_players.length > 0;
        bool hasFundedPot = currentPot > 0 && i_usdc.balanceOf(address(this)) >= currentPot;

        upkeepNeeded = timePassed && isOpen && hasPlayers && hasFundedPot;
        performData = bytes("");
    }

    function performUpkeep(bytes calldata) external override {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(getCurrentPot(), s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256, uint256[] calldata randomWords) internal override {
        uint256 playerCount = s_players.length;
        uint256 winnerIndex = randomWords[0] % playerCount;
        uint256 winningTicket = winnerIndex + 1;
        uint256 completedLotteryId = s_currentLotteryId;
        uint256 prize = playerCount * i_sponsoredAmountPerEntry;
        address winner = s_players[winnerIndex];

        s_recentWinner = winner;
        s_recentWinningTicket = winningTicket;
        delete s_players;
        s_currentLotteryId = completedLotteryId + 1;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;

        i_usdc.safeTransfer(winner, prize);
        emit WinnerPicked(winner, completedLotteryId, winningTicket, prize);
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() external pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() external pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getRecentWinningTicket() external view returns (uint256) {
        return s_recentWinningTicket;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getCurrentLotteryId() external view returns (uint256) {
        return s_currentLotteryId;
    }

    function getCurrentPot() public view returns (uint256) {
        return s_players.length * i_sponsoredAmountPerEntry;
    }

    function getUsdc() external view returns (address) {
        return address(i_usdc);
    }

    function getSponsor() external view returns (address) {
        return i_sponsor;
    }

    function getSponsoredAmountPerEntry() external view returns (uint256) {
        return i_sponsoredAmountPerEntry;
    }

    function getMaxPlayers() external view returns (uint256) {
        return i_maxPlayers;
    }

    function getLastEnteredLotteryId(address player) external view returns (uint256) {
        return s_lastEnteredLottery[player];
    }
}
