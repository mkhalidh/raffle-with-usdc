# Deployment Guide

The same MetaMask test wallet acts as admin, deployer, and USDC sponsor.

## 1. Prerequisites

- Foundry (`forge`, `cast`, `anvil`)
- dedicated MetaMask test wallet
- Sepolia ETH, test USDC, and LINK
- Sepolia RPC endpoint and optional Etherscan API key

Never use a production wallet or commit a private key.

## 2. Environment

```bash
cp .env.example .env
```

```dotenv
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
PRIVATE_KEY=0xYOUR_METAMASK_TEST_WALLET_PRIVATE_KEY
SPONSOR_ADDRESS=0xYOUR_METAMASK_ADMIN_WALLET_ADDRESS
VRF_SUBSCRIPTION_ID=YOUR_FUNDED_CHAINLINK_VRF_SUBSCRIPTION_ID
RAFFLE_ADDRESS=0xDEPLOYED_RAFFLE_ADDRESS
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
```

Confirm that the key and sponsor address represent the same wallet:

```bash
cast wallet address --private-key $PRIVATE_KEY
```

The result must equal `SPONSOR_ADDRESS`. Only `.env.example` is public; `.env`
is ignored.

## 3. Pre-deployment verification

```bash
forge fmt --check
forge build
forge test -vv
```

Do not deploy if any test fails.

## 4. Local deployment

```bash
make anvil
# Run in a second terminal:
make deploy
# Put the printed Raffle address in RAFFLE_ADDRESS inside .env, then:
make approveUsdc
```

The local configuration deploys Chainlink mocks and MockUSDC, creates a VRF
subscription, mints 80 mock USDC to the admin, deploys Raffle, registers it as a
consumer, and approves exactly 5 mock USDC.

If `.env` contains a Sepolia `SPONSOR_ADDRESS`, unset it for the default Anvil
wallet or supply the matching available Anvil key.

## 5. Prepare Chainlink VRF on Sepolia

Create a VRF v2.5 subscription from the same admin wallet in Chainlink's
subscription manager, fund it with LINK, and copy its numeric ID into
`VRF_SUBSCRIPTION_ID` in `.env`. The deploy script deliberately rejects a zero
live-network subscription ID.

Using an existing on-chain ID avoids relying on a simulated subscription ID
during a multi-transaction Forge broadcast.

## 6. Sepolia deployment

The configured official Sepolia USDC address is:

```text
0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
```

Deploy:

```bash
make deploy ARGS="--network sepolia"
```

`DeployRaffle.s.sol` reads the config, uses `SPONSOR_ADDRESS` as deployer and
sponsor, deploys the Raffle with the funded subscription ID, and adds it as a
VRF consumer. Save the deployed Raffle address printed by Foundry.

Set that printed address as `RAFFLE_ADDRESS` in your local `.env` before the
approval step.

## 7. Admin approves 5 USDC

```bash
make approveUsdc ARGS="--network sepolia"
```

`ApproveUsdc.run()` reads `RAFFLE_ADDRESS`, then reads its USDC and sponsor, computes
`1 USDC * 5 players`, resets old allowance to zero, then approves `5_000_000`.

Equivalent MetaMask values:

```text
token:   Sepolia USDC
spender: deployed Raffle address
amount:  5 USDC (5_000_000 base units)
wallet:  admin/sponsor MetaMask account
```

Approval moves no USDC. Every accepted entry later pulls exactly 1 USDC.

Verify the allowance:

```bash
cast call <USDC_ADDRESS> \
  "allowance(address,address)(uint256)" \
  $SPONSOR_ADDRESS <RAFFLE_ADDRESS> \
  --rpc-url $SEPOLIA_RPC_URL
```

Expected immediately after approval: `5000000`.

## 8. Register Automation

Register a Chainlink Automation upkeep using:

- trigger: **Custom logic**
- target: deployed Raffle
- check data: `0x`
- adequate LINK funding

## 9. Participant entry

Each participant calls from a different wallet:

```bash
cast send <RAFFLE_ADDRESS> \
  "enterRaffle()" \
  --private-key <PARTICIPANT_TEST_PRIVATE_KEY> \
  --rpc-url $SEPOLIA_RPC_URL
```

Do not attach ETH value. The participant only pays gas.

## 10. Settlement and next lottery

After the interval, Automation calls `performUpkeep`, VRF returns randomness,
the winner receives the actual pot, and the Raffle automatically opens the next
lottery at the same address. There is no `startNextRound()` transaction. Approve
again only when remaining allowance is below the amount needed for new entries.

## 11. Deployment checks

```bash
cast call <RAFFLE_ADDRESS> "getSponsor()(address)" --rpc-url $SEPOLIA_RPC_URL
cast call <RAFFLE_ADDRESS> "getUsdc()(address)" --rpc-url $SEPOLIA_RPC_URL
cast call <RAFFLE_ADDRESS> "getSponsoredAmountPerEntry()(uint256)" --rpc-url $SEPOLIA_RPC_URL
cast call <RAFFLE_ADDRESS> "getMaxPlayers()(uint256)" --rpc-url $SEPOLIA_RPC_URL
cast call <RAFFLE_ADDRESS> "getCurrentLotteryId()(uint256)" --rpc-url $SEPOLIA_RPC_URL
```

Expected: admin wallet, official Sepolia USDC, `1000000`, `5`, and initially `1`.

## 12. Security checklist

- test-only wallet and network first
- real `.env` never committed
- exactly 5 USDC approval, never unlimited
- Raffle address verified before approval
- official USDC and Chainlink addresses confirmed
- complete test suite passing
- independent audit before mainnet
