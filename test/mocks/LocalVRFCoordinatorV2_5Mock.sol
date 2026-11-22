// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/**
 * @dev The upstream v2.5 mock derives subscription IDs from the previous block
 * hash. Forge script simulation and broadcast can therefore derive different
 * local IDs. This local-only helper creates deterministic subscription ID 1.
 */
contract LocalVRFCoordinatorV2_5Mock is VRFCoordinatorV2_5Mock {
    uint256 private constant LOCAL_SUBSCRIPTION_ID = 1;

    constructor(uint96 baseFee, uint96 gasPriceLink, int256 weiPerUnitLink)
        VRFCoordinatorV2_5Mock(baseFee, gasPriceLink, weiPerUnitLink)
    {}

    function createDeterministicSubscription() external returns (uint256 subId) {
        subId = LOCAL_SUBSCRIPTION_ID;
        if (s_subscriptionConfigs[subId].owner != address(0)) revert InvalidSubscription();

        address[] memory consumers = new address[](0);
        s_subscriptions[subId] = Subscription({balance: 0, nativeBalance: 0, reqCount: 0});
        s_subscriptionConfigs[subId] =
            SubscriptionConfig({owner: msg.sender, requestedOwner: address(0), consumers: consumers});

        emit SubscriptionCreated(subId, msg.sender);
    }
}
