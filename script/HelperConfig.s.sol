// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LinkToken} from "../test/mocks/LinkToken.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";
import {LocalVRFCoordinatorV2_5Mock} from "../test/mocks/LocalVRFCoordinatorV2_5Mock.sol";
import {Script, console2} from "forge-std/Script.sol";

abstract contract CodeConstants {
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9;
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15;

    uint256 public constant SPONSORED_AMOUNT_PER_ENTRY = 1e6;
    uint256 public constant MAX_PLAYERS = 5;
    uint256 public constant LOCAL_SPONSOR_BALANCE = 80e6;

    address public constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 subscriptionId;
        bytes32 gasLane;
        uint256 automationUpdateInterval;
        uint32 callbackGasLimit;
        address vrfCoordinatorV2_5;
        address link;
        address usdc;
        uint256 sponsoredAmountPerEntry;
        uint256 maxPlayers;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetEthConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(uint256 chainId, NetworkConfig memory networkConfig) public {
        networkConfigs[chainId] = networkConfig;
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinatorV2_5 != address(0)) {
            return networkConfigs[chainId];
        }
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        }
        revert HelperConfig__InvalidChainId();
    }

    function getMainnetEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            subscriptionId: vm.envOr("VRF_SUBSCRIPTION_ID", uint256(0)),
            gasLane: 0x9fe0eebf5e446e3c998ec9bb19951541aee00bb90ea201ae456421a2ded86805,
            automationUpdateInterval: 30,
            callbackGasLimit: 500_000,
            vrfCoordinatorV2_5: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909,
            link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            sponsoredAmountPerEntry: SPONSORED_AMOUNT_PER_ENTRY,
            maxPlayers: MAX_PLAYERS,
            account: _configuredAdminWallet()
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            subscriptionId: vm.envOr("VRF_SUBSCRIPTION_ID", uint256(0)),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            automationUpdateInterval: 30,
            callbackGasLimit: 500_000,
            vrfCoordinatorV2_5: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            sponsoredAmountPerEntry: SPONSORED_AMOUNT_PER_ENTRY,
            maxPlayers: MAX_PLAYERS,
            account: _configuredAdminWallet()
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.vrfCoordinatorV2_5 != address(0)) {
            return localNetworkConfig;
        }

        address adminWallet = _configuredAdminWallet();
        console2.log("Deploying local Chainlink and USDC mocks");
        if (block.number == 0) vm.roll(1);
        vm.startBroadcast();
        LocalVRFCoordinatorV2_5Mock vrfCoordinator =
            new LocalVRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK, MOCK_WEI_PER_UINT_LINK);
        LinkToken link = new LinkToken();
        MockUSDC usdc = new MockUSDC();
        uint256 subscriptionId = vrfCoordinator.createDeterministicSubscription();
        vrfCoordinator.fundSubscription(subscriptionId, 3 ether);
        usdc.mint(adminWallet, LOCAL_SPONSOR_BALANCE);
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            subscriptionId: subscriptionId,
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            automationUpdateInterval: 30,
            callbackGasLimit: 500_000,
            vrfCoordinatorV2_5: address(vrfCoordinator),
            link: address(link),
            usdc: address(usdc),
            sponsoredAmountPerEntry: SPONSORED_AMOUNT_PER_ENTRY,
            maxPlayers: MAX_PLAYERS,
            account: adminWallet
        });
        return localNetworkConfig;
    }

    function _configuredAdminWallet() private view returns (address) {
        return vm.envOr("SPONSOR_ADDRESS", FOUNDRY_DEFAULT_SENDER);
    }
}
