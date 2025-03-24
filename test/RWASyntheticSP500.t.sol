// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {RWASyntheticSP500} from "../src/RWASyntheticSP500.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract RWASyntheticSP500Test is Test {
    RWASyntheticSP500 public rwaSyntheticSP500;
    MockPerpetualTrading public mockPerpetualTrading;
    MockPriceOracle public mockPriceOracle;
    MockUSDC public mockUSDC;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_PRICE = 5000 * 1e6; // $5000 in USDC decimals
    uint256 public constant MINT_AMOUNT = 1000 * 1e6;   // 1000 USDC
    uint256 public constant COLLATERAL_RATIO_TEST = 12000;   // 120% in basis points

    event AssetPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event TokensMinted(address indexed to, uint256 amount, uint256 collateralAmount);
    event TokensBurned(address indexed from, uint256 amount, uint256 collateralAmount);
    event CollateralAdded(address indexed user, uint256 amount);
    event CollateralRemoved(address indexed user, uint256 amount);
    event PositionUpdated(uint256 positionSize, uint256 collateralAmount);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock contracts
        mockUSDC = new MockUSDC();
        mockPriceOracle = new MockPriceOracle(address(mockUSDC));
        mockPerpetualTrading = new MockPerpetualTrading(address(mockUSDC));

        // Deploy RWASyntheticSP500 first so we can set its price
        rwaSyntheticSP500 = new RWASyntheticSP500(
            address(mockUSDC),
            address(mockPerpetualTrading),
            address(mockPriceOracle)
        );

        // Set initial price in the oracle
        mockPriceOracle.setPrice(address(rwaSyntheticSP500), INITIAL_PRICE);

        // RWASyntheticSP500 already deployed above

        // Mint some USDC to users for testing
        mockUSDC.mint(user1, 10000 * 1e6);
        mockUSDC.mint(user2, 10000 * 1e6);
    }

    function test_Initialization() public {
        assertEq(rwaSyntheticSP500.name(), "SP500 Synthetic Token");
        assertEq(rwaSyntheticSP500.symbol(), "sSP500");
        assertEq(address(rwaSyntheticSP500.baseAsset()), address(mockUSDC));
        assertEq(address(rwaSyntheticSP500.priceOracle()), address(mockPriceOracle));
        assertEq(address(rwaSyntheticSP500.perpetualTrading()), address(mockPerpetualTrading));
        // The contract has a constant COLLATERAL_RATIO of 5000 (50%)
        assertEq(rwaSyntheticSP500.COLLATERAL_RATIO(), 5000);
        assertEq(rwaSyntheticSP500.getAssetPrice(), INITIAL_PRICE);
    }

    function test_UpdateAssetPrice() public {
        uint256 newPrice = 5500 * 1e6; // $5500
        mockPriceOracle.setPrice(address(rwaSyntheticSP500), newPrice);

        vm.expectEmit(true, true, true, true);
        emit AssetPriceUpdated(INITIAL_PRICE, newPrice);
        
        rwaSyntheticSP500.updateAssetPrice();
        
        assertEq(rwaSyntheticSP500.getAssetPrice(), newPrice);
    }

    function test_MintTokens() public {
        uint256 mintAmount = MINT_AMOUNT;
        uint256 expectedCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        // Approve USDC spending
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), expectedCollateral);
        
        vm.expectEmit(true, true, true, true);
        emit TokensMinted(user1, mintAmount, expectedCollateral);
        
        rwaSyntheticSP500.mint(mintAmount);
        vm.stopPrank();
        
        assertEq(rwaSyntheticSP500.balanceOf(user1), mintAmount);
        assertEq(mockUSDC.balanceOf(address(rwaSyntheticSP500)), expectedCollateral);
        assertEq(rwaSyntheticSP500.getCollateralAmount(user1), expectedCollateral);
    }

    function test_BurnTokens() public {
        // First mint some tokens
        uint256 mintAmount = MINT_AMOUNT;
        uint256 expectedCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), expectedCollateral);
        rwaSyntheticSP500.mint(mintAmount);
        
        // Now burn half of the tokens
        uint256 burnAmount = mintAmount / 2;
        uint256 returnedCollateral = (burnAmount * expectedCollateral) / mintAmount;
        
        vm.expectEmit(true, true, true, true);
        emit TokensBurned(user1, burnAmount, returnedCollateral);
        
        rwaSyntheticSP500.burn(burnAmount);
        vm.stopPrank();
        
        assertEq(rwaSyntheticSP500.balanceOf(user1), mintAmount - burnAmount);
        assertEq(mockUSDC.balanceOf(address(rwaSyntheticSP500)), expectedCollateral - returnedCollateral);
        assertEq(rwaSyntheticSP500.getCollateralAmount(user1), expectedCollateral - returnedCollateral);
    }

    function test_AddCollateral() public {
        // First mint some tokens
        uint256 mintAmount = MINT_AMOUNT;
        uint256 initialCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), initialCollateral);
        rwaSyntheticSP500.mint(mintAmount);
        
        // Add more collateral
        uint256 additionalCollateral = 500 * 1e6;
        mockUSDC.approve(address(rwaSyntheticSP500), additionalCollateral);
        
        vm.expectEmit(true, true, true, true);
        emit CollateralAdded(user1, additionalCollateral);
        
        rwaSyntheticSP500.addCollateral(additionalCollateral);
        vm.stopPrank();
        
        assertEq(rwaSyntheticSP500.getCollateralAmount(user1), initialCollateral + additionalCollateral);
        assertEq(mockUSDC.balanceOf(address(rwaSyntheticSP500)), initialCollateral + additionalCollateral);
    }

    function test_RemoveCollateral() public {
        // First mint some tokens with excess collateral
        uint256 mintAmount = MINT_AMOUNT;
        uint256 initialCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        uint256 excessCollateral = 500 * 1e6;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), initialCollateral + excessCollateral);
        rwaSyntheticSP500.mint(mintAmount);
        rwaSyntheticSP500.addCollateral(excessCollateral);
        
        // Remove some of the excess collateral
        uint256 removeAmount = 300 * 1e6;
        
        vm.expectEmit(true, true, true, true);
        emit CollateralRemoved(user1, removeAmount);
        
        rwaSyntheticSP500.removeCollateral(removeAmount);
        vm.stopPrank();
        
        assertEq(rwaSyntheticSP500.getCollateralAmount(user1), initialCollateral + excessCollateral - removeAmount);
        assertEq(mockUSDC.balanceOf(address(rwaSyntheticSP500)), initialCollateral + excessCollateral - removeAmount);
    }

    function test_UpdatePosition() public {
        // First mint some tokens
        uint256 mintAmount = MINT_AMOUNT;
        uint256 initialCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), initialCollateral);
        rwaSyntheticSP500.mint(mintAmount);
        vm.stopPrank();
        
        // Update the position as the contract owner
        uint256 newPositionSize = 1500 * 1e6;
        uint256 newCollateralAmount = 2000 * 1e6;
        
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(newPositionSize, newCollateralAmount);
        
        rwaSyntheticSP500.updatePosition(newPositionSize, newCollateralAmount);
        
        assertEq(rwaSyntheticSP500.positionSize(), newPositionSize);
        assertEq(rwaSyntheticSP500.positionCollateral(), newCollateralAmount);
    }

    function test_RevertWhenInsufficientCollateral() public {
        uint256 mintAmount = MINT_AMOUNT;
        uint256 requiredCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        uint256 insufficientCollateral = requiredCollateral - 1;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), insufficientCollateral);
        
        vm.expectRevert("Insufficient collateral");
        rwaSyntheticSP500.mint(mintAmount);
        vm.stopPrank();
    }

    function test_RevertWhenRemovingTooMuchCollateral() public {
        // First mint some tokens
        uint256 mintAmount = MINT_AMOUNT;
        uint256 initialCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), initialCollateral);
        rwaSyntheticSP500.mint(mintAmount);
        
        // Try to remove too much collateral
        uint256 tooMuchCollateral = initialCollateral / 2; // This would make the position undercollateralized
        
        vm.expectRevert("Insufficient remaining collateral");
        rwaSyntheticSP500.removeCollateral(tooMuchCollateral);
        vm.stopPrank();
    }

    function test_RevertWhenBurningTooManyTokens() public {
        // First mint some tokens
        uint256 mintAmount = MINT_AMOUNT;
        uint256 initialCollateral = (mintAmount * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), initialCollateral);
        rwaSyntheticSP500.mint(mintAmount);
        
        // Try to burn more tokens than owned
        uint256 tooManyTokens = mintAmount + 1;
        
        vm.expectRevert("ERC20: burn amount exceeds balance");
        rwaSyntheticSP500.burn(tooManyTokens);
        vm.stopPrank();
    }

    function test_MultipleUsers() public {
        // User 1 mints tokens
        uint256 mintAmount1 = 1000 * 1e6;
        uint256 collateral1 = (mintAmount1 * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(rwaSyntheticSP500), collateral1);
        rwaSyntheticSP500.mint(mintAmount1);
        vm.stopPrank();
        
        // User 2 mints tokens
        uint256 mintAmount2 = 2000 * 1e6;
        uint256 collateral2 = (mintAmount2 * rwaSyntheticSP500.COLLATERAL_RATIO()) / 10000;
        
        vm.startPrank(user2);
        mockUSDC.approve(address(rwaSyntheticSP500), collateral2);
        rwaSyntheticSP500.mint(mintAmount2);
        vm.stopPrank();
        
        // Verify balances and collateral
        assertEq(rwaSyntheticSP500.balanceOf(user1), mintAmount1);
        assertEq(rwaSyntheticSP500.balanceOf(user2), mintAmount2);
        assertEq(rwaSyntheticSP500.getCollateralAmount(user1), collateral1);
        assertEq(rwaSyntheticSP500.getCollateralAmount(user2), collateral2);
        assertEq(mockUSDC.balanceOf(address(rwaSyntheticSP500)), collateral1 + collateral2);
        assertEq(rwaSyntheticSP500.totalSupply(), mintAmount1 + mintAmount2);
    }
}
