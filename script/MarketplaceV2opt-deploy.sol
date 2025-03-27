// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/MarketplaceV2opt.sol";
import "../mocks/MyTestToken.sol";

contract DeployMarketplaceV2 is Script {
    function run() external returns (MarketplaceV2opt) {
        vm.startBroadcast();
        // Deploy the Marketplace contract
        MarketplaceV2opt marketplace = new MarketplaceV2opt();
        MyTestToken testToken = new MyTestToken("ipfs://QmXf3J9");
        vm.stopBroadcast();
        console.log(
            "MarketplaceV2opt deployed at address:",
            address(marketplace)
        );
        console.log("TestToken deployed at address:", address(testToken));
        return marketplace;
    }
}
