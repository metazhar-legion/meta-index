// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {PerpetualPositionWrapper} from "../src/PerpetualPositionWrapper.sol";
import {MockPerpetualRouter} from "../src/mocks/MockPerpetualRouter.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

/**
 * @title PerpetualPositionWrapperTest
 * @dev Test contract for PerpetualPositionWrapper
 */
contract PerpetualPositionWrapperTest is Test {
    // Test contracts
    PerpetualPositionWrapper public wrapper;
    MockPerpetualRouter public router;
    MockPriceOracle public priceOracle;
    MockUSDC public usdc;
    
    // Test parameters
    address public deployer = address(this);
    address public user = address(0x1);
    bytes32 public marketId = keccak256("BTC-USD");
    uint256 public leverage = 2;
    bool public isLong = true;
    string public assetSymbol = "BTC";
    
    // Setup function
    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        priceOracle = new MockPriceOracle(address(usdc));
        router = new MockPerpetualRouter(address(priceOracle), address(usdc));
        
        // Set up market in router
        router.addMarket(
            marketId,
            "Bitcoin/USD",
            address(0x1234), // Mock BTC address
            address(usdc),
            5 // Max leverage
        );
        
        // Set initial price
        priceOracle.setPrice(address(0x1234), 50000 * 1e18); // $50,000 per BTC
        
        // Deploy wrapper
        wrapper = new PerpetualPositionWrapper(
            address(router),
            address(usdc),
            address(priceOracle),
            marketId,
            leverage,
            isLong,
            assetSymbol
        );
        
        // Mint USDC to wrapper for testing
        usdc.mint(address(wrapper), 10000 * 1e6); // 10,000 USDC
    }
    
    // Test opening a position
    function testOpenPosition() public {
        // Open position with 1,000 USDC
        wrapper.openPosition(1000 * 1e6);
        
        // Check position details
        (
            uint256 size,
            uint256 collateral,
            uint256 currentPrice,
            int256 pnl,
            bool isActive
        ) = wrapper.getPositionDetails();
        
        // Verify position was opened correctly
        assertEq(size, 2000 * 1e6, "Position size should be 2,000 USDC (2x leverage)");
        assertEq(collateral, 1000 * 1e6, "Collateral should be 1,000 USDC");
        assertEq(currentPrice, 50000 * 1e18, "Current price should be $50,000");
        assertEq(pnl, 0, "PnL should be 0 initially");
        assertTrue(isActive, "Position should be active");
        
        // Verify position value
        uint256 positionValue = wrapper.getPositionValue();
        assertEq(positionValue, 1000 * 1e6, "Position value should equal collateral initially");
    }
    
    // Test position profit
    function testPositionProfit() public {
        // Open position with 1,000 USDC
        wrapper.openPosition(1000 * 1e6);
        
        // Increase price by 10%
        priceOracle.setPrice(address(0x1234), 55000 * 1e18); // $55,000 per BTC
        
        // Check position details
        (
            ,
            ,
            ,
            int256 pnl,
            
        ) = wrapper.getPositionDetails();
        
        // For a long position with 2x leverage, a 10% price increase should result in ~20% profit
        // Expected profit: 1000 * 0.2 = 200 USDC
        assertGt(pnl, 190 * 1e6, "PnL should be approximately 200 USDC");
        assertLt(pnl, 210 * 1e6, "PnL should be approximately 200 USDC");
        
        // Verify position value
        uint256 positionValue = wrapper.getPositionValue();
        assertGt(positionValue, 1190 * 1e6, "Position value should include profit");
        assertLt(positionValue, 1210 * 1e6, "Position value should include profit");
    }
    
    // Test position loss
    function testPositionLoss() public {
        // Open position with 1,000 USDC
        wrapper.openPosition(1000 * 1e6);
        
        // Decrease price by 10%
        priceOracle.setPrice(address(0x1234), 45000 * 1e18); // $45,000 per BTC
        
        // Check position details
        (
            ,
            ,
            ,
            int256 pnl,
            
        ) = wrapper.getPositionDetails();
        
        // For a long position with 2x leverage, a 10% price decrease should result in ~20% loss
        // Expected loss: 1000 * 0.2 = 200 USDC
        assertLt(pnl, -190 * 1e6, "PnL should be approximately -200 USDC");
        assertGt(pnl, -210 * 1e6, "PnL should be approximately -200 USDC");
        
        // Verify position value
        uint256 positionValue = wrapper.getPositionValue();
        assertLt(positionValue, 810 * 1e6, "Position value should reflect loss");
        assertGt(positionValue, 790 * 1e6, "Position value should reflect loss");
    }
    
    // Test closing a position with profit
    function testClosePositionWithProfit() public {
        // Open position with 1,000 USDC
        wrapper.openPosition(1000 * 1e6);
        
        // Increase price by 10%
        priceOracle.setPrice(address(0x1234), 55000 * 1e18); // $55,000 per BTC
        
        // Get initial USDC balance
        uint256 initialBalance = usdc.balanceOf(address(wrapper));
        
        // Mint additional USDC to the router to simulate profit
        usdc.mint(address(router), 200 * 1e6); // 200 USDC profit
        
        // Close position
        wrapper.closePosition();
        
        // Verify position is closed
        (
            ,
            ,
            ,
            ,
            bool isActive
        ) = wrapper.getPositionDetails();
        
        assertFalse(isActive, "Position should be closed");
        
        // Verify USDC balance increased due to profit
        uint256 finalBalance = usdc.balanceOf(address(wrapper));
        assertGt(finalBalance, initialBalance, "Balance should increase after closing profitable position");
        
        // Verify position value is 0
        uint256 positionValue = wrapper.getPositionValue();
        assertEq(positionValue, 0, "Position value should be 0 after closing");
    }
    
    // Test closing a position with loss
    function testClosePositionWithLoss() public {
        // Open position with 1,000 USDC
        wrapper.openPosition(1000 * 1e6);
        
        // Decrease price by 10%
        priceOracle.setPrice(address(0x1234), 45000 * 1e18); // $45,000 per BTC
        
        // Get initial USDC balance
        uint256 initialBalance = usdc.balanceOf(address(wrapper));
        
        // Close position
        wrapper.closePosition();
        
        // Verify position is closed
        (
            ,
            ,
            ,
            ,
            bool isActive
        ) = wrapper.getPositionDetails();
        
        assertFalse(isActive, "Position should be closed");
        
        // Verify USDC balance decreased due to loss
        uint256 finalBalance = usdc.balanceOf(address(wrapper));
        // The router returns 80% of the 1000 USDC collateral (20% loss)
        uint256 expectedBalance = initialBalance + (1000 * 1e6 * 4 / 5); // Initial balance plus 80% of 1000 USDC
        assertEq(finalBalance, expectedBalance, "Balance should reflect 20% loss after closing position");
        
        // Verify position value is 0
        uint256 positionValue = wrapper.getPositionValue();
        assertEq(positionValue, 0, "Position value should be 0 after closing");
    }
    
    // Test adjusting position size
    function testAdjustPosition() public {
        // Open position with 1,000 USDC
        wrapper.openPosition(1000 * 1e6);
        
        // Adjust position to 1,500 USDC collateral
        wrapper.adjustPosition(1500 * 1e6);
        
        // Check position details
        (
            uint256 size,
            uint256 collateral,
            ,
            ,
            
        ) = wrapper.getPositionDetails();
        
        // Verify position was adjusted correctly
        assertEq(collateral, 1500 * 1e6, "Collateral should be 1,500 USDC");
        assertEq(size, 3000 * 1e6, "Position size should be 3,000 USDC (2x leverage)");
        
        // Adjust position down to 800 USDC collateral
        wrapper.adjustPosition(800 * 1e6);
        
        // Check position details again
        (
            size,
            collateral,
            ,
            ,
            
        ) = wrapper.getPositionDetails();
        
        // Verify position was adjusted correctly
        assertEq(collateral, 800 * 1e6, "Collateral should be 800 USDC");
        assertEq(size, 1600 * 1e6, "Position size should be 1,600 USDC (2x leverage)");
    }
    
    // Test changing leverage
    function testChangeLeverage() public {
        // Open position with 1,000 USDC
        wrapper.openPosition(1000 * 1e6);
        
        // Change leverage to 3x
        wrapper.setLeverage(3);
        
        // Check position details
        (
            uint256 size,
            uint256 collateral,
            ,
            ,
            
        ) = wrapper.getPositionDetails();
        
        // Verify leverage was changed correctly
        assertEq(collateral, 1000 * 1e6, "Collateral should remain 1,000 USDC");
        assertEq(size, 3000 * 1e6, "Position size should be 3,000 USDC (3x leverage)");
    }
    
    // Test withdrawing unused funds
    function testWithdrawBaseAsset() public {
        // Open position with 1,000 USDC (out of 10,000 available)
        wrapper.openPosition(1000 * 1e6);
        
        // Withdraw 5,000 USDC to user
        wrapper.withdrawBaseAsset(5000 * 1e6, user);
        
        // Verify user received the funds
        assertEq(usdc.balanceOf(user), 5000 * 1e6, "User should receive 5,000 USDC");
        
        // Verify wrapper still has enough for the position
        assertEq(usdc.balanceOf(address(wrapper)), 4000 * 1e6, "Wrapper should have 4,000 USDC left");
        
        // Try to withdraw too much (should fail)
        vm.expectRevert();
        wrapper.withdrawBaseAsset(4000 * 1e6, user);
    }
    
    // Test emergency token recovery
    function testRecoverToken() public {
        // Mint some other token to the wrapper
        MockUSDC otherToken = new MockUSDC();
        otherToken.mint(address(wrapper), 5000 * 1e6);
        
        // Recover the token
        wrapper.recoverToken(address(otherToken), 5000 * 1e6, user);
        
        // Verify user received the tokens
        assertEq(otherToken.balanceOf(user), 5000 * 1e6, "User should receive 5,000 tokens");
    }
}
