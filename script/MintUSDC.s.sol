// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title MintUSDC
 * @dev Script to mint USDC to a specified address
 */
contract MintUSDC is Script {
    function run() external {
        uint256 deployerPrivateKey;

        // Try to get the private key from environment variable
        try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
            deployerPrivateKey = pk;
            console.log("Using private key from environment variable");
        } catch {
            // If environment variable not found, use the default Anvil private key
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            console.log("Using default Anvil private key");
        }

        // Get recipient address from command line or use default
        address recipient;
        try vm.envAddress("RECIPIENT") returns (address r) {
            recipient = r;
            console.log("Minting to address from environment variable:", recipient);
        } catch {
            // If no recipient specified, use the deployer address
            recipient = vm.addr(deployerPrivateKey);
            console.log("Minting to deployer address:", recipient);
        }

        // Get amount from command line or use default
        uint256 amount;
        try vm.envUint("AMOUNT") returns (uint256 a) {
            amount = a;
            console.log("Minting amount from environment variable:", amount);
        } catch {
            // If no amount specified, use 10,000 USDC
            amount = 10_000 * 1e6; // 10,000 USDC with 6 decimals
            console.log("Minting default amount:", amount);
        }

        vm.startBroadcast(deployerPrivateKey);

        // USDC address from deployment
        address usdcAddress = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
        MockERC20 usdc = MockERC20(usdcAddress);

        // Mint USDC to the recipient
        usdc.mint(recipient, amount);

        vm.stopBroadcast();

        console.log("Successfully minted", amount / 1e6, "USDC to", recipient);
        console.log("New balance:", usdc.balanceOf(recipient) / 1e6, "USDC");
    }
}
