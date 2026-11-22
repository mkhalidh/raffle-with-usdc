# Raffle with USDC

A sponsor-funded USDC raffle built with Foundry, Chainlink VRF v2.5, and
Chainlink Automation. The admin's MetaMask wallet is the deployer and sponsor.
Participants do not pay an entry fee; they only pay gas for `enterRaffle()`.

## Rules

| Setting | Value |
| --- | ---: |
| Sponsored amount per accepted entry | 1 USDC (`1_000_000` base units) |
| Maximum unique wallets per lottery | 5 |
| Admin approval for one full lottery | 5 USDC (`5_000_000` base units) |
| Participant USDC payment | 0 USDC |
| Prize | Actual USDC collected in the current lottery |
| Number of lotteries | Unlimited, sequentially in one contract |

If three users enter, the contract collects 3 USDC and the winner receives
3 USDC. A 5 USDC approval is only a spending limit; unused allowance does not
leave the admin wallet.

## Flow

1. The admin deploys the Raffle contract from their MetaMask wallet.
2. The same admin wallet approves the Raffle to spend up to 5 USDC.
3. A unique participant calls `enterRaffle()` without sending ETH or USDC.
4. The Raffle calls USDC `transferFrom(admin, raffle, 1 USDC)`.
5. The participant receives a logical ticket number through `TicketIssued`.
6. After the interval, Chainlink Automation calls `performUpkeep()`.
7. Chainlink VRF selects one ticket fairly.
8. The selected wallet receives the current USDC pot.
9. Players are cleared, the lottery ID increments, and the next lottery opens
   automatically in the same contract.

One wallet can enter only once in one lottery, but can enter again in the next
lottery. Tickets are event-based logical numbers, not NFTs.

## USDC approval

Approval is made on the USDC token contract. The Raffle address is the spender:

```text
spender = <DEPLOYED_RAFFLE_ADDRESS>
amount  = 5_000_000
```

The included script resets the old allowance to zero and approves exactly 5 USDC:

```bash
make approveUsdc ARGS="--network sepolia"
```

Approval does not transfer funds. Each successful entry consumes 1 USDC of
allowance. Before a later lottery, the admin can approve again when the remaining
allowance is insufficient. Unlimited approval is not used.

## Official USDC addresses

| Network | Chain ID | Address |
| --- | ---: | --- |
| Ethereum Mainnet | 1 | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| Ethereum Sepolia | 11155111 | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| Anvil | 31337 | A local 6-decimal `MockUSDC` is deployed |

Verify addresses against Circle's official
[USDC contract address list](https://developers.circle.com/stablecoins/usdc-contract-addresses)
before using another network.

## Setup

Requirements: Git, Foundry, a Sepolia RPC URL, Sepolia ETH for gas, test USDC,
and LINK for the VRF subscription.

```bash
git clone https://github.com/mkhalidh/raffle-with-usdc.git
cd raffle-with-usdc
forge install
cp .env.example .env
```

Fill `.env` locally:

```dotenv
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
PRIVATE_KEY=0xYOUR_METAMASK_TEST_WALLET_PRIVATE_KEY
SPONSOR_ADDRESS=0xYOUR_METAMASK_ADMIN_WALLET_ADDRESS
VRF_SUBSCRIPTION_ID=YOUR_FUNDED_CHAINLINK_VRF_SUBSCRIPTION_ID
RAFFLE_ADDRESS=0xDEPLOYED_RAFFLE_ADDRESS
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
```

`PRIVATE_KEY` and `SPONSOR_ADDRESS` must belong to the same MetaMask test
account. Never commit `.env` or use a wallet holding valuable real funds.

## Build and test

```bash
forge build
forge test -vv
forge coverage
forge fmt --check
```

The suite verifies admin approval, sponsor balance/allowance failures, unique
entries, ticket numbers, the player cap, upkeep, VRF settlement, exact USDC
prizes, and automatic opening of the next lottery.

## Deployment

Local:

```bash
make anvil
# In another terminal:
make deploy
# Copy the printed address into RAFFLE_ADDRESS in .env, then:
make approveUsdc
```

Sepolia:

```bash
make deploy ARGS="--network sepolia"
# Copy the printed address into RAFFLE_ADDRESS in .env, then:
make approveUsdc ARGS="--network sepolia"
```

For Sepolia, create and fund a Chainlink VRF v2.5 subscription first and put its
ID in `VRF_SUBSCRIPTION_ID`. The deployment script deploys the Raffle and
registers it as a VRF consumer. After deployment, register the Raffle as a
Chainlink Automation custom-logic upkeep.

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for the complete procedure and
[ROLES_AND_FUNCTIONS.md](ROLES_AND_FUNCTIONS.md) for function ownership.

## Main contract functions

- `enterRaffle()` — adds one unique wallet and pulls 1 USDC from the admin.
- `checkUpkeep()` — reports whether settlement conditions are ready.
- `performUpkeep()` — closes entries and requests VRF randomness.
- `fulfillRandomWords()` — selects the winner, resets state, and pays the pot.
- `getCurrentPot()` — returns the prize implied by current accepted entries.
- `getCurrentLotteryId()` — identifies the currently open lottery.

## Security notes

- Uses `SafeERC20` for token transfers.
- Updates lottery state before transferring the prize.
- Rejects duplicate entries and entries while calculating.
- Uses a capped 5 USDC approval instead of unlimited approval.
- Randomness comes from Chainlink VRF, not block values.
- Wallet uniqueness cannot prove human identity; use an allowlist if required.

This project has not been professionally audited. Use a testnet first.
