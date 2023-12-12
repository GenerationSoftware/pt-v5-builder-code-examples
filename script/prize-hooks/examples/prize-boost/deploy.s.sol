// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";

import { PrizeBoostHook } from "src/prize-hooks/examples/prize-boost/PrizeBoostHook.sol";
import { IERC20 } from "openzeppelin/interfaces/IERC20.sol";

contract DeployPrizeBoostHook is Script {
    function run() public {
        vm.startBroadcast();

        console2.log("Deploying PrizeBoostHook...");

        if (block.chainid != 10) revert("Not deploying on Optimism...");

        IERC20 boostToken = IERC20(address(0x395Ae52bB17aef68C2888d941736A71dC6d4e125)); // POOL on optimism
        address vault = address(0xE3B3a464ee575E8E25D2508918383b89c832f275); // pUSDC.e on Optimism
        uint256 boostAmount = 1e18;
        uint8 maxTier = 3;

        new PrizeBoostHook(vault, boostToken, boostAmount, maxTier);

        vm.stopBroadcast();
    }
}