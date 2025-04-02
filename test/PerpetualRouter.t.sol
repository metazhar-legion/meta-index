// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PerpetualRouter} from "../src/PerpetualRouter.sol";
import {IPerpetualAdapter} from "../src/interfaces/IPerpetualAdapter.sol";
import {IPerpetualTrading} from "../src/interfaces/IPerpetualTrading.sol";
// Import MockToken directly

/**
 * @title MockToken for testing
 */
contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @title MockPerpetualAdapter
 * @dev Mock implementation of the IPerpetualAdapter interface for testing
 */
contract MockPerpetualAdapter is IPerpetualAdapter {
    string public platformName;
    mapping(bytes32 => bool) public supportedMarkets;
    mapping(bytes32 => uint256) public marketPrices;
    mapping(bytes32 => Position) public positions;
    mapping(bytes32 => bytes32) public positionToMarket;
    
    address public collateralToken;
    uint256 public nextPositionId;
    
    constructor(string memory _platformName, address _collateralToken) {
        platformName = _platformName;
        collateralToken = _collateralToken;
        nextPositionId = 1;
    }
    
    function setMarketSupported(bytes32 marketId, bool supported) external {
        supportedMarkets[marketId] = supported;
    }
    
    function setMarketPrice(bytes32 marketId, uint256 price) external {
        marketPrices[marketId] = price;
    }
    
    function openPosition(
        bytes32 marketId,
        int256 size,
        uint256 leverage,
        uint256 collateral
    ) external override returns (bytes32 positionId) {
        require(supportedMarkets[marketId], "Market not supported");
        require(size != 0, "Size cannot be zero");
        require(leverage > 0, "Leverage must be positive");
        require(collateral > 0, "Collateral must be positive");
        
        // Transfer collateral from sender
        IERC20(collateralToken).transferFrom(msg.sender, address(this), collateral);
        
        // Generate position ID
        positionId = bytes32(nextPositionId++);
        
        // Store position
        positions[positionId] = Position({
            marketId: marketId,
            size: size,
            entryPrice: marketPrices[marketId],
            leverage: leverage,
            collateral: collateral,
            lastUpdated: block.timestamp
        });
        
        positionToMarket[positionId] = marketId;
        
        return positionId;
    }
    
    function closePosition(bytes32 positionId) external override returns (int256 pnl) {
        require(positions[positionId].collateral > 0, "Position not found");
        
        // Calculate PnL
        pnl = calculatePnL(positionId);
        
        // Return collateral plus PnL (if positive)
        uint256 amountToReturn = positions[positionId].collateral;
        if (pnl > 0) {
            amountToReturn += uint256(pnl);
        } else if (pnl < 0 && uint256(-pnl) < amountToReturn) {
            amountToReturn -= uint256(-pnl);
        } else {
            amountToReturn = 0; // Liquidated
        }
        
        if (amountToReturn > 0) {
            // Make sure we actually transfer the tokens to the user
            IERC20(collateralToken).transfer(msg.sender, amountToReturn);
        }
        
        // Clear position
        delete positions[positionId];
        delete positionToMarket[positionId];
        
        return pnl;
    }
    
    function adjustPosition(
        bytes32 positionId,
        int256 newSize,
        uint256 newLeverage,
        int256 collateralDelta
    ) external override {
        require(positions[positionId].collateral > 0, "Position not found");
        
        Position storage position = positions[positionId];
        
        // Update size if specified
        if (newSize != 0) {
            position.size = newSize;
        }
        
        // Update leverage if specified
        if (newLeverage > 0) {
            position.leverage = newLeverage;
        }
        
        // Handle collateral changes
        if (collateralDelta > 0) {
            // Add collateral
            IERC20(collateralToken).transferFrom(msg.sender, address(this), uint256(collateralDelta));
            position.collateral += uint256(collateralDelta);
        } else if (collateralDelta < 0) {
            // Remove collateral
            uint256 withdrawAmount = uint256(-collateralDelta);
            require(withdrawAmount < position.collateral, "Cannot withdraw all collateral");
            
            position.collateral -= withdrawAmount;
            IERC20(collateralToken).transfer(msg.sender, withdrawAmount);
        }
        
        position.lastUpdated = block.timestamp;
    }
    
    function getPosition(bytes32 positionId) external view override returns (Position memory position) {
        return positions[positionId];
    }
    
    function getMarketPrice(bytes32 marketId) external view override returns (uint256 price) {
        require(supportedMarkets[marketId], "Market not supported");
        return marketPrices[marketId];
    }
    
    function calculatePnL(bytes32 positionId) public view override returns (int256 pnl) {
        Position memory position = positions[positionId];
        if (position.collateral == 0) return 0;
        
        bytes32 marketId = position.marketId;
        uint256 currentPrice = marketPrices[marketId];
        uint256 entryPrice = position.entryPrice;
        
        // For testing purposes, implement a simple PnL calculation
        // If the current price equals the entry price (no price change), return 0
        if (currentPrice == entryPrice) {
            return 0;
        }
        
        // If the price has increased, return a positive PnL
        if (currentPrice > entryPrice && position.size > 0) {
            return int256(position.collateral) / 10; // Return 10% of collateral as profit
        }
        
        // Otherwise return a small negative PnL
        return -int256(position.collateral) / 20; // Return -5% of collateral as loss
    }
    
    function getPlatformName() external view override returns (string memory name) {
        return platformName;
    }
    
    function getBaseAsset() external view override returns (address) {
        return collateralToken;
    }
    
    function isMarketSupported(bytes32 marketId) external view override returns (bool supported) {
        return supportedMarkets[marketId];
    }
}

contract PerpetualRouterTest is Test {
    PerpetualRouter public router;
    MockPerpetualAdapter public adapter1;
    MockPerpetualAdapter public adapter2;
    MockToken public usdc;
    address public user;
    
    // Market IDs
    bytes32 public constant BTC_USD = keccak256("BTC-USD");
    bytes32 public constant ETH_USD = keccak256("ETH-USD");
    
    function setUp() public {
        // Create collateral token (USDC)
        usdc = new MockToken("USD Coin", "USDC", 6);
        
        // Create perpetual router
        router = new PerpetualRouter();
        
        // Create mock adapters
        adapter1 = new MockPerpetualAdapter("Platform 1", address(usdc));
        adapter2 = new MockPerpetualAdapter("Platform 2", address(usdc));
        
        // Setup supported markets
        adapter1.setMarketSupported(BTC_USD, true);
        adapter1.setMarketSupported(ETH_USD, true);
        adapter2.setMarketSupported(BTC_USD, true);
        
        // Setup market prices
        adapter1.setMarketPrice(BTC_USD, 50000 * 1e6); // $50,000
        adapter1.setMarketPrice(ETH_USD, 3000 * 1e6);  // $3,000
        adapter2.setMarketPrice(BTC_USD, 50000 * 1e6); // $50,000 - Using the same price for consistency in tests
        
        // Add adapters to router
        router.addAdapter(address(adapter1));
        router.addAdapter(address(adapter2));
        
        // Setup user
        user = address(0x1);
        vm.startPrank(user);
        
        // Mint USDC to user
        usdc.mint(user, 1000000 * 1e6); // $1,000,000
        
        // Mint USDC to adapters for liquidity
        usdc.mint(address(adapter1), 1000000 * 1e6);
        usdc.mint(address(adapter2), 1000000 * 1e6);
        
        // Approve router to spend USDC
        usdc.approve(address(router), type(uint256).max);
        
        // Approve adapters to spend USDC (needed for direct transfers in the mock adapters)
        usdc.approve(address(adapter1), type(uint256).max);
        usdc.approve(address(adapter2), type(uint256).max);
        
        vm.stopPrank();
    }
    
    function testAddAdapter() public {
        assertEq(router.getAdapterCount(), 2);
        
        // Create a new adapter
        MockPerpetualAdapter adapter3 = new MockPerpetualAdapter("Platform 3", address(usdc));
        
        // Add it to the router
        vm.prank(router.owner());
        router.addAdapter(address(adapter3));
        
        assertEq(router.getAdapterCount(), 3);
        assertTrue(router.isAdapter(address(adapter3)));
    }
    
    function testRemoveAdapter() public {
        assertEq(router.getAdapterCount(), 2);
        
        // Remove an adapter
        vm.prank(router.owner());
        router.removeAdapter(address(adapter1));
        
        assertEq(router.getAdapterCount(), 1);
        assertFalse(router.isAdapter(address(adapter1)));
        assertTrue(router.isAdapter(address(adapter2)));
    }
    
    function testOpenPosition() public {
        // Open a BTC long position
        uint256 collateral = 10000 * 1e6; // $10,000
        int256 size = 1 * 1e18; // 1 BTC
        uint256 leverage = 5; // 5x leverage
        
        uint256 userUsdcBefore = usdc.balanceOf(user);
        
        vm.prank(user);
        bytes32 positionId = router.openPosition(BTC_USD, size, leverage, collateral);
        
        uint256 userUsdcAfter = usdc.balanceOf(user);
        
        // Check USDC balance
        assertEq(userUsdcBefore - userUsdcAfter, collateral);
        
        // Check position details
        IPerpetualTrading.Position memory position = router.getPosition(positionId);
        assertEq(position.marketId, BTC_USD);
        assertEq(position.size, size);
        assertEq(position.leverage, leverage);
        assertEq(position.collateral, collateral);
        
        // The router should use the price from the best platform
        // For BTC, we're using the same price on both platforms for test consistency
        assertEq(position.entryPrice, 50000 * 1e6);
    }
    
    function testOpenPositionUnsupportedMarket() public {
        // Create an unsupported market
        bytes32 unsupportedMarket = keccak256("UNSUPPORTED");
        
        vm.prank(user);
        vm.expectRevert(); // Should revert as no platform supports this market
        router.openPosition(unsupportedMarket, 1 * 1e18, 5, 10000 * 1e6);
    }
    
    function testClosePosition() public {
        // Open a position first
        uint256 collateral = 10000 * 1e6; // $10,000
        int256 size = 1 * 1e18; // 1 BTC
        uint256 leverage = 5; // 5x leverage
        
        vm.prank(user);
        bytes32 positionId = router.openPosition(BTC_USD, size, leverage, collateral);
        
        uint256 userUsdcBefore = usdc.balanceOf(user);
        
        // Increase price to generate profit
        adapter1.setMarketPrice(BTC_USD, 55000 * 1e6); // $55,000 (10% increase)
        adapter2.setMarketPrice(BTC_USD, 55000 * 1e6); // $55,000 (10% increase)
        
        vm.prank(user);
        int256 pnl = router.closePosition(positionId);
        
        uint256 userUsdcAfter = usdc.balanceOf(user);
        
        // Check PnL is positive
        assertTrue(pnl > 0, "PnL should be positive");
        
        // Check USDC balance increased
        assertTrue(userUsdcAfter > userUsdcBefore, "User balance should increase after closing position");
        
        // The user should get back at least their collateral
        assertTrue(userUsdcAfter - userUsdcBefore >= collateral, "User should get back at least their collateral");
        
        // Try to access the closed position
        vm.expectRevert(); // Should revert as position is closed
        router.getPosition(positionId);
    }
    
    function testAdjustPosition() public {
        // Open a position first
        uint256 collateral = 10000 * 1e6; // $10,000
        int256 size = 1 * 1e18; // 1 BTC
        uint256 leverage = 5; // 5x leverage
        
        vm.prank(user);
        bytes32 positionId = router.openPosition(BTC_USD, size, leverage, collateral);
        
        // Adjust position
        int256 newSize = 2 * 1e18; // 2 BTC
        uint256 newLeverage = 3; // 3x leverage
        int256 collateralDelta = 5000 * 1e6; // Add $5,000
        
        uint256 userUsdcBefore = usdc.balanceOf(user);
        
        vm.prank(user);
        router.adjustPosition(positionId, newSize, newLeverage, collateralDelta);
        
        uint256 userUsdcAfter = usdc.balanceOf(user);
        
        // Check USDC balance
        assertEq(userUsdcBefore - userUsdcAfter, uint256(collateralDelta));
        
        // Check position details
        IPerpetualTrading.Position memory position = router.getPosition(positionId);
        assertEq(position.size, newSize);
        assertEq(position.leverage, newLeverage);
        assertEq(position.collateral, collateral + uint256(collateralDelta));
    }
    
    function testGetMarketPrice() public view {
        uint256 price = router.getMarketPrice(BTC_USD);
        
        // Should return the price from Platform 1 (first platform with this market)
        // Note: In a real implementation, we would choose the best price, but our mock
        // implementation just returns the first platform that supports the market
        assertEq(price, 50000 * 1e6);
    }
    
    function testCalculatePnL() public {
        // Open a position first
        uint256 collateral = 10000 * 1e6; // $10,000
        int256 size = 1 * 1e18; // 1 BTC
        uint256 leverage = 5; // 5x leverage
        
        vm.prank(user);
        bytes32 positionId = router.openPosition(BTC_USD, size, leverage, collateral);
        
        // Get the initial PnL (should be 0 since price hasn't changed yet)
        int256 initialPnl = router.calculatePnL(positionId);
        
        // Initial PnL should be zero since price hasn't changed
        assertEq(initialPnl, 0);
        
        // Increase price to generate profit
        adapter1.setMarketPrice(BTC_USD, 55000 * 1e6); // $55,000 (10% increase)
        adapter2.setMarketPrice(BTC_USD, 55000 * 1e6); // $55,000 (10% increase)
        
        // Get the PnL after price increase
        int256 actualPnl = router.calculatePnL(positionId);
        
        // PnL should be positive
        assertTrue(actualPnl > 0, "PnL should be positive");
        
        // PnL should be approximately 10% of the collateral
        assertApproxEqAbs(actualPnl, int256(collateral) / 10, 100);
    }
}
