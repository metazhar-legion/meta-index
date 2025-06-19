// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

/**
 * @title SimpleTest
 * @notice A minimal test file that should compile quickly
 */
contract SimpleTest is Test {
    function setUp() public {
        // Empty setup
    }
    
    function test_Simple() public pure {
        // Simple assertion that will always pass
        assertTrue(true, "This test should always pass");
    }
}
