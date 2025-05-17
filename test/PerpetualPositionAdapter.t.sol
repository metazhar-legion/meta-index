// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PerpetualPositionWrapper} from "../src/PerpetualPositionWrapper.sol";
import {PerpetualPositionAdapter} from "../src/adapters/PerpetualPositionAdapter.sol";
import {MockPerpetualRouter} from "../src/mocks/MockPerpetualRouter.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IRWASyntheticToken} from "../src/interfaces/IRWASyntheticToken.sol";

contract PerpetualPositionAdapterTest is Test {
    // Test contracts
    PerpetualPositionWrapper public perpWrapper;
    PerpetualPositionAdapter public adapter;
    MockPerpetualRouter public router;
    MockPriceOracle public priceOracle;
    MockERC20 public usdc;
    
    // Test parameters
    bytes32 public marketId = bytes32("ETH-USD");
    uint256 public initialLeverage = 2;
    bool public isLong = true;
    string public assetSymbol = "ETH";
    uint256 public initialCollateral = 1000 * 10**6; // 1000 USDC
    
    // Events to test
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    function setUp() public {
        // Deploy mock contracts
        usdc = new MockERC20("USD Coin", "USDC", 6);
        priceOracle = new MockPriceOracle(address(usdc));
        router = new MockPerpetualRouter(address(priceOracle), address(usdc));
        
        // Set initial price in the oracle
        priceOracle.setPrice(address(usdc), 1 * 10**18); // 1 USDC = $1
        
        // Deploy perpetual position wrapper
        perpWrapper = new PerpetualPositionWrapper(
            address(router),
            address(usdc),
            address(priceOracle),
            marketId,
            initialLeverage,
            isLong,
            assetSymbol
        );
        
        // Deploy adapter
        adapter = new PerpetualPositionAdapter(
            address(perpWrapper),
            "ETH Perpetual Position",
            IRWASyntheticToken.AssetType.EQUITY_INDEX
        );
        
        // Transfer ownership of perpetual wrapper to adapter
        perpWrapper.transferOwnership(address(adapter));
        
        // Mint USDC to this contract
        usdc.mint(address(this), 10000 * 10**6); // 10,000 USDC
        
        // Approve USDC for adapter
        usdc.approve(address(adapter), type(uint256).max);
    }
    
    // Test initialization
    function testInitialization() public {
        // Check adapter state
        assertEq(address(adapter.perpWrapper()), address(perpWrapper), "Perpetual wrapper address mismatch");
        assertEq(address(adapter.baseAsset()), address(usdc), "Base asset mismatch");
        assertEq(address(adapter.priceOracle()), address(priceOracle), "Price oracle mismatch");
        
        // Check asset info
        IRWASyntheticToken.AssetInfo memory info = adapter.getAssetInfo();
        assertEq(info.name, "ETH Perpetual Position", "Asset name mismatch");
        assertEq(info.symbol, assetSymbol, "Asset symbol mismatch");
        assertEq(uint8(info.assetType), uint8(IRWASyntheticToken.AssetType.EQUITY_INDEX), "Asset type mismatch");
        assertEq(info.oracle, address(priceOracle), "Oracle address mismatch");
        assertEq(info.marketId, marketId, "Market ID mismatch");
        assertTrue(info.isActive, "Asset should be active");
    }
    
    // Test minting synthetic tokens
    function testMint() public {
        // Mint synthetic tokens
        adapter.mint(address(this), initialCollateral);
        
        // Check balances
        assertEq(adapter.balanceOf(address(this)), initialCollateral, "Synthetic token balance mismatch");
        assertEq(adapter.totalSupply(), initialCollateral, "Total supply mismatch");
        
        // Check that position was opened in the perpetual wrapper
        assertTrue(perpWrapper.positionOpen(), "Position should be open");
        assertEq(perpWrapper.collateralAmount(), initialCollateral, "Collateral amount mismatch");
    }
    
    // Test burning synthetic tokens
    function testBurn() public {
        // First mint tokens
        adapter.mint(address(this), initialCollateral);
        
        // Then burn them
        adapter.burn(address(this), initialCollateral);
        
        // Check balances
        assertEq(adapter.balanceOf(address(this)), 0, "Synthetic token balance should be zero");
        assertEq(adapter.totalSupply(), 0, "Total supply should be zero");
        
        // Check that position was closed in the perpetual wrapper
        assertFalse(perpWrapper.positionOpen(), "Position should be closed");
    }
    
    // Test updating price
    function testUpdatePrice() public {
        // First mint tokens to open a position
        adapter.mint(address(this), initialCollateral);
        
        // Set a new price in the oracle
        priceOracle.setPrice(address(usdc), 1.1 * 10**18); // USDC price increases to $1.10
        
        // Update price in the adapter
        adapter.updatePrice();
        
        // Check that the price was updated
        IRWASyntheticToken.AssetInfo memory info = adapter.getAssetInfo();
        assertTrue(info.lastUpdated > 0, "Last updated timestamp should be set");
        
        // The price should reflect the position value, which includes the profit from the price increase
        uint256 currentPrice = adapter.getCurrentPrice();
        assertTrue(currentPrice > initialCollateral, "Price should increase with profit");
    }
    
    // Test adjusting position size
    function testAdjustPositionSize() public {
        // First mint tokens to open a position
        adapter.mint(address(this), initialCollateral);
        
        // Add more collateral
        uint256 additionalCollateral = 500 * 10**6; // 500 USDC
        adapter.adjustPositionSize(additionalCollateral);
        
        // Check that the position was adjusted in the perpetual wrapper
        assertEq(perpWrapper.collateralAmount(), initialCollateral + additionalCollateral, "Collateral amount mismatch after adjustment");
    }
    
    // Test changing leverage
    function testChangeLeverage() public {
        // First mint tokens to open a position
        adapter.mint(address(this), initialCollateral);
        
        // Change leverage
        uint256 newLeverage = 3;
        adapter.changeLeverage(newLeverage);
        
        // Check that the leverage was changed in the perpetual wrapper
        assertEq(perpWrapper.leverage(), newLeverage, "Leverage mismatch after change");
    }
    
    // Test withdrawing base asset
    function testWithdrawBaseAsset() public {
        // First mint tokens to open a position
        adapter.mint(address(this), initialCollateral);
        
        // Set up the router to simulate profit
        router.setPositionValue(initialCollateral * 2); // Double the position value
        
        // Withdraw some base asset
        uint256 withdrawAmount = 200 * 10**6; // 200 USDC
        uint256 balanceBefore = usdc.balanceOf(address(this));
        
        // Transfer ownership to this contract for testing
        adapter.transferOwnership(address(this));
        
        // Withdraw base asset
        adapter.withdrawBaseAsset(withdrawAmount);
        
        // Check that the base asset was withdrawn
        uint256 balanceAfter = usdc.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, withdrawAmount, "Withdrawn amount mismatch");
    }
    
    // Test error cases
    function testErrorCases() public {
        // Test minting with zero amount
        vm.expectRevert(); // CommonErrors.ValueTooLow
        adapter.mint(address(this), 0);
        
        // Test minting to zero address
        vm.expectRevert(); // CommonErrors.ZeroAddress
        adapter.mint(address(0), initialCollateral);
        
        // Test burning with zero amount
        vm.expectRevert(); // CommonErrors.ValueTooLow
        adapter.burn(address(this), 0);
        
        // Test burning from zero address
        vm.expectRevert(); // CommonErrors.ZeroAddress
        adapter.burn(address(0), initialCollateral);
        
        // Test burning more than balance
        vm.expectRevert(); // CommonErrors.InsufficientBalance
        adapter.burn(address(this), initialCollateral);
        
        // Test adjusting position with zero amount
        vm.expectRevert(); // CommonErrors.ValueTooLow
        adapter.adjustPositionSize(0);
        
        // Test changing leverage to zero
        vm.expectRevert(); // CommonErrors.ValueTooLow
        adapter.changeLeverage(0);
        
        // Test withdrawing zero amount
        vm.expectRevert(); // CommonErrors.ValueTooLow
        adapter.withdrawBaseAsset(0);
    }
    
    // Test access control
    function testAccessControl() public {
        // First mint tokens to open a position
        adapter.mint(address(this), initialCollateral);
        
        // Create a new address
        address user = address(0x123);
        
        // Try to call adapter methods as non-owner
        vm.startPrank(user);
        
        // Test adjusting position as non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.adjustPositionSize(500 * 10**6);
        
        // Test changing leverage as non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.changeLeverage(3);
        
        // Test withdrawing base asset as non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.withdrawBaseAsset(200 * 10**6);
        
        // Test burning as non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.burn(address(this), initialCollateral);
        
        vm.stopPrank();
    }
    
    // Test emergency token recovery
    function testRecoverToken() public {
        // Mint some tokens to the adapter
        usdc.mint(address(adapter), 1000 * 10**6);
        
        // Recover the tokens
        adapter.recoverToken(address(usdc), address(this), 1000 * 10**6);
        
        // Check that the tokens were recovered
        assertEq(usdc.balanceOf(address(adapter)), 0, "Adapter should have no tokens left");
    }
}
