# Roles and Functions

## Admin MetaMask wallet

The same wallet has three roles:

1. **Deployer** — broadcasts deployment.
2. **VRF setup account** — creates/funds the subscription and adds the consumer.
3. **USDC sponsor** — owns USDC and grants the Raffle a 5 USDC allowance.

The admin address is `SPONSOR_ADDRESS`. The `PRIVATE_KEY` used by Foundry must
belong to that same address. The Raffle has no owner withdrawal function and
cannot pull more than its ERC-20 allowance.

## Participants

Participants call `enterRaffle()` from their own wallets. They send no ETH and
approve no USDC; they only pay gas. One wallet can enter once per lottery and
can enter again when the next lottery opens.

## Chainlink roles

- **Automation** checks `checkUpkeep()` and calls `performUpkeep()` after the
  interval when the Raffle has at least one funded entry.
- **VRF** returns verifiable randomness used to select one current ticket.

## State-changing functions

### USDC `approve(raffle, 5_000_000)`

**Caller:** admin MetaMask wallet

**Contract called:** USDC token

**Purpose:** gives the Raffle a maximum 5 USDC spending allowance

**Fund movement:** none at approval time

The `ApproveUsdc` script sets the old allowance to zero, then sets 5 USDC.

### `Raffle.enterRaffle()`

**Caller:** participant wallet

**Value sent:** zero ETH and zero USDC

**Checks:** open state, unique wallet, fewer than five players

**Action:** records the player, calls USDC `transferFrom` for 1 USDC from the
admin, and emits `TicketIssued`

If admin balance or allowance is insufficient, the whole entry reverts.

### `Raffle.performUpkeep(bytes)`

**Caller:** normally Chainlink Automation; anyone may call it when conditions
are valid

**Checks:** interval elapsed, Raffle open, players exist, pot funded

**Action:** changes state to `CALCULATING` and requests VRF randomness

### `Raffle.fulfillRandomWords(...)`

**Caller:** only the configured VRF coordinator through the inherited callback

**Action:** selects the winning ticket, stores winner data, clears players,
increments lottery ID, reopens the Raffle, and transfers the actual USDC pot

## Read functions

| Function | Meaning |
| --- | --- |
| `getRaffleState()` | `OPEN` or `CALCULATING` |
| `getCurrentLotteryId()` | Current sequential lottery number |
| `getCurrentPot()` | Accepted entries multiplied by 1 USDC |
| `getNumberOfPlayers()` | Current participant count |
| `getPlayer(index)` | Wallet at a zero-based position |
| `getLastEnteredLotteryId(player)` | Last lottery entered by a wallet |
| `getRecentWinner()` | Most recently selected winner |
| `getRecentWinningTicket()` | One-based winning ticket number |
| `getUsdc()` | Configured USDC address |
| `getSponsor()` | Admin/sponsor wallet address |
| `getSponsoredAmountPerEntry()` | 1 USDC in base units |
| `getMaxPlayers()` | Maximum unique wallets, currently 5 |
| `getInterval()` | Minimum time before upkeep |
| `getLastTimeStamp()` | Timestamp of the last completed lottery |

## Events

- `TicketIssued(lotteryId, ticketNumber, player)` — accepted entry and logical
  ticket. It is not an NFT.
- `RequestedRaffleWinner(requestId)` — VRF request created.
- `WinnerPicked(player, lotteryId, ticketNumber, prize)` — final winner and
  exact USDC paid.

## Automatic next lottery

No admin call starts lottery #2. After VRF settlement, players are deleted,
`currentLotteryId` increases, and state returns to `OPEN` at the same contract
address. The admin only restores allowance when it becomes insufficient.
