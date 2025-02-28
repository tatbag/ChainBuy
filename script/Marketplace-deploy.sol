// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/Marketplace.sol";
import "../mocks/MyTestToken.sol";

contract DeployMarketplace is Script {
    function run() external returns (Marketplace) {
        vm.startBroadcast();
        // Deploy the Marketplace contract
        Marketplace marketplace = new Marketplace();
        MyTestToken testToken = new MyTestToken("ipfs://QmXf3J9");
        vm.stopBroadcast();
        console.log("Marketplace deployed at address:", address(marketplace));
        console.log("TestToken deployed at address:", address(testToken));
        return marketplace;
    }
}
