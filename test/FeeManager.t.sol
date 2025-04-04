// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

contract FeeManagerTest is Test {
    FeeManager public feeManager;
    
    address public owner = address(1);
    address public vault = address(2);
    address public user = address(3);
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant INITIAL_MANAGEMENT_FEE = 100; // 1%
    uint256 public constant INITIAL_PERFORMANCE_FEE = 1000; // 10%
    
    function setUp() public {
        vm.startPrank(owner);
        feeManager = new FeeManager();
        vm.stopPrank();
    }
    
    // Test initialization
    function test_Initialization() public view {
        assertEq(feeManager.managementFeePercentage(), INITIAL_MANAGEMENT_FEE);
        assertEq(feeManager.performanceFeePercentage(), INITIAL_PERFORMANCE_FEE);
        assertEq(feeManager.owner(), owner);
    }
    
    // Test setting management fee
    function test_SetManagementFee() public {
        vm.startPrank(owner);
        
        uint256 newFee = 200; // 2%
        feeManager.setManagementFeePercentage(newFee);
        
        assertEq(feeManager.managementFeePercentage(), newFee);
        
        vm.stopPrank();
    }
    
    // Test setting management fee with invalid value
    function test_SetManagementFeeInvalidValue() public {
        vm.startPrank(owner);
        
        uint256 invalidFee = 600; // 6%, max is 5%
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueOutOfRange.selector, invalidFee, 0, 500));
        feeManager.setManagementFeePercentage(invalidFee);
        
        vm.stopPrank();
    }
    
    // Test setting management fee as non-owner
    function test_SetManagementFeeNonOwner() public {
        vm.startPrank(user);
        
        uint256 newFee = 200; // 2%
        vm.expectRevert();
        feeManager.setManagementFeePercentage(newFee);
        
        vm.stopPrank();
    }
    
    // Test setting performance fee
    function test_SetPerformanceFee() public {
        vm.startPrank(owner);
        
        uint256 newFee = 1500; // 15%
        feeManager.setPerformanceFeePercentage(newFee);
        
        assertEq(feeManager.performanceFeePercentage(), newFee);
        
        vm.stopPrank();
    }
    
    // Test setting performance fee with invalid value
    function test_SetPerformanceFeeInvalidValue() public {
        vm.startPrank(owner);
        
        uint256 invalidFee = 3500; // 35%, max is 30%
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueOutOfRange.selector, invalidFee, 0, 3000));
        feeManager.setPerformanceFeePercentage(invalidFee);
        
        vm.stopPrank();
    }
    
    // Test setting performance fee as non-owner
    function test_SetPerformanceFeeNonOwner() public {
        vm.startPrank(user);
        
        uint256 newFee = 1500; // 15%
        vm.expectRevert();
        feeManager.setPerformanceFeePercentage(newFee);
        
        vm.stopPrank();
    }
    
    // Test calculating management fee for the first time
    function test_CalculateManagementFeeFirstTime() public {
        uint256 totalAssetsValue = 1_000_000 * 10**18; // $1M
        uint256 currentTimestamp = block.timestamp;
        
        uint256 managementFee = feeManager.calculateManagementFee(vault, totalAssetsValue, currentTimestamp);
        
        // First time should return 0
        assertEq(managementFee, 0);
        
        // Check that timestamp was set
        assertEq(feeManager.lastFeeCollectionTimestamps(vault), currentTimestamp);
    }
    
    // Test calculating management fee after time has passed
    function test_CalculateManagementFeeAfterTime() public {
        uint256 totalAssetsValue = 1_000_000 * 10**18; // $1M
        uint256 initialTimestamp = block.timestamp;
        
        // First call to set the initial timestamp
        feeManager.calculateManagementFee(vault, totalAssetsValue, initialTimestamp);
        
        // Fast forward 1 year
        uint256 oneYearLater = initialTimestamp + 365 days;
        
        // Calculate fee after 1 year
        uint256 managementFee = feeManager.calculateManagementFee(vault, totalAssetsValue, oneYearLater);
        
        // Expected fee: $1M * 1% = $10,000
        uint256 expectedFee = (totalAssetsValue * INITIAL_MANAGEMENT_FEE) / BASIS_POINTS;
        assertEq(managementFee, expectedFee);
        
        // Check that timestamp was updated
        assertEq(feeManager.lastFeeCollectionTimestamps(vault), oneYearLater);
    }
    
    // Test calculating management fee for partial year
    function test_CalculateManagementFeePartialYear() public {
        uint256 totalAssetsValue = 1_000_000 * 10**18; // $1M
        uint256 initialTimestamp = block.timestamp;
        
        // First call to set the initial timestamp
        feeManager.calculateManagementFee(vault, totalAssetsValue, initialTimestamp);
        
        // Fast forward 6 months
        uint256 sixMonthsLater = initialTimestamp + 182.5 days;
        
        // Calculate fee after 6 months
        uint256 managementFee = feeManager.calculateManagementFee(vault, totalAssetsValue, sixMonthsLater);
        
        // Expected fee: $1M * 1% * (182.5/365) = $5,000
        uint256 expectedFee = (totalAssetsValue * INITIAL_MANAGEMENT_FEE * (sixMonthsLater - initialTimestamp)) / (BASIS_POINTS * 365 days);
        assertEq(managementFee, expectedFee);
    }
    
    // Test calculating management fee with changing asset value
    function test_CalculateManagementFeeChangingAssetValue() public {
        uint256 initialAssetsValue = 1_000_000 * 10**18; // $1M
        uint256 initialTimestamp = block.timestamp;
        
        // First call to set the initial timestamp
        feeManager.calculateManagementFee(vault, initialAssetsValue, initialTimestamp);
        
        // Fast forward 1 year and increase asset value
        uint256 oneYearLater = initialTimestamp + 365 days;
        uint256 newAssetsValue = 1_500_000 * 10**18; // $1.5M
        
        // Calculate fee after 1 year with new asset value
        uint256 managementFee = feeManager.calculateManagementFee(vault, newAssetsValue, oneYearLater);
        
        // Expected fee: $1.5M * 1% = $15,000
        uint256 expectedFee = (newAssetsValue * INITIAL_MANAGEMENT_FEE) / BASIS_POINTS;
        assertEq(managementFee, expectedFee);
    }
    
    // Test calculating performance fee with no appreciation
    function test_CalculatePerformanceFeeNoAppreciation() public {
        uint256 currentSharePrice = 1 * 10**18; // $1 per share
        uint256 totalSupply = 1_000_000 * 10**18; // 1M shares
        uint8 decimals = 18;
        
        // Set initial high water mark
        vm.startPrank(owner);
        feeManager.setHighWaterMark(vault, currentSharePrice);
        vm.stopPrank();
        
        // Calculate performance fee
        uint256 performanceFee = feeManager.calculatePerformanceFee(vault, currentSharePrice, totalSupply, decimals);
        
        // Expected fee: 0 (no appreciation)
        assertEq(performanceFee, 0);
        
        // High water mark should remain the same
        assertEq(feeManager.highWaterMarks(vault), currentSharePrice);
    }
    
    // Test calculating performance fee with appreciation
    function test_CalculatePerformanceFeeWithAppreciation() public {
        uint256 initialSharePrice = 1 * 10**18; // $1 per share
        uint256 newSharePrice = 1.2 * 10**18; // $1.20 per share
        uint256 totalSupply = 1_000_000 * 10**18; // 1M shares
        uint8 decimals = 18;
        
        // Set initial high water mark
        vm.startPrank(owner);
        feeManager.setHighWaterMark(vault, initialSharePrice);
        vm.stopPrank();
        
        // Calculate performance fee
        uint256 performanceFee = feeManager.calculatePerformanceFee(vault, newSharePrice, totalSupply, decimals);
        
        // Expected fee: (1.2 - 1) * 10% * 1M = 20,000
        uint256 appreciation = newSharePrice - initialSharePrice;
        uint256 feePerShare = (appreciation * INITIAL_PERFORMANCE_FEE) / BASIS_POINTS;
        uint256 expectedFee = (feePerShare * totalSupply) / 10**decimals;
        assertEq(performanceFee, expectedFee);
        
        // High water mark should be updated to new share price
        assertEq(feeManager.highWaterMarks(vault), newSharePrice);
    }
    
    // Test calculating performance fee with different decimals
    function test_CalculatePerformanceFeeWithDifferentDecimals() public {
        uint256 initialSharePrice = 1 * 10**6; // $1 per share
        uint256 newSharePrice = 1.2 * 10**6; // $1.20 per share
        uint256 totalSupply = 1_000_000 * 10**6; // 1M shares
        uint8 decimals = 6;
        
        // Set initial high water mark
        vm.startPrank(owner);
        feeManager.setHighWaterMark(vault, initialSharePrice);
        vm.stopPrank();
        
        // Calculate performance fee
        uint256 performanceFee = feeManager.calculatePerformanceFee(vault, newSharePrice, totalSupply, decimals);
        
        // Expected fee: (1.2 - 1) * 10% * 1M = 20,000
        uint256 appreciation = newSharePrice - initialSharePrice;
        uint256 feePerShare = (appreciation * INITIAL_PERFORMANCE_FEE) / BASIS_POINTS;
        uint256 expectedFee = (feePerShare * totalSupply) / 10**decimals;
        assertEq(performanceFee, expectedFee);
    }
    
    // Test calculating performance fee with multiple calls
    function test_CalculatePerformanceFeeMultipleCalls() public {
        uint256 initialSharePrice = 1 * 10**18; // $1 per share
        uint256 secondSharePrice = 1.2 * 10**18; // $1.20 per share
        uint256 thirdSharePrice = 1.5 * 10**18; // $1.50 per share
        uint256 totalSupply = 1_000_000 * 10**18; // 1M shares
        uint8 decimals = 18;
        
        // Set initial high water mark
        vm.startPrank(owner);
        feeManager.setHighWaterMark(vault, initialSharePrice);
        vm.stopPrank();
        
        // First performance fee calculation
        uint256 firstPerformanceFee = feeManager.calculatePerformanceFee(vault, secondSharePrice, totalSupply, decimals);
        
        // Expected first fee: (1.2 - 1) * 10% * 1M = 20,000
        uint256 firstAppreciation = secondSharePrice - initialSharePrice;
        uint256 firstFeePerShare = (firstAppreciation * INITIAL_PERFORMANCE_FEE) / BASIS_POINTS;
        uint256 expectedFirstFee = (firstFeePerShare * totalSupply) / 10**decimals;
        assertEq(firstPerformanceFee, expectedFirstFee);
        
        // High water mark should be updated to second share price
        assertEq(feeManager.highWaterMarks(vault), secondSharePrice);
        
        // Second performance fee calculation
        uint256 secondPerformanceFee = feeManager.calculatePerformanceFee(vault, thirdSharePrice, totalSupply, decimals);
        
        // Expected second fee: (1.5 - 1.2) * 10% * 1M = 30,000
        uint256 secondAppreciation = thirdSharePrice - secondSharePrice;
        uint256 secondFeePerShare = (secondAppreciation * INITIAL_PERFORMANCE_FEE) / BASIS_POINTS;
        uint256 expectedSecondFee = (secondFeePerShare * totalSupply) / 10**decimals;
        assertEq(secondPerformanceFee, expectedSecondFee);
        
        // High water mark should be updated to third share price
        assertEq(feeManager.highWaterMarks(vault), thirdSharePrice);
    }
    
    // Test manually setting high water mark
    function test_SetHighWaterMark() public {
        vm.startPrank(owner);
        
        uint256 newHighWaterMark = 1.5 * 10**18;
        feeManager.setHighWaterMark(vault, newHighWaterMark);
        
        assertEq(feeManager.highWaterMarks(vault), newHighWaterMark);
        
        vm.stopPrank();
    }
    
    // Test setting high water mark as non-owner
    function test_SetHighWaterMarkNonOwner() public {
        vm.startPrank(user);
        
        uint256 newHighWaterMark = 1.5 * 10**18;
        vm.expectRevert();
        feeManager.setHighWaterMark(vault, newHighWaterMark);
        
        vm.stopPrank();
    }
    
    // Test manually setting last fee collection timestamp
    function test_SetLastFeeCollectionTimestamp() public {
        vm.startPrank(owner);
        
        uint256 newTimestamp = block.timestamp + 1 days;
        feeManager.setLastFeeCollectionTimestamp(vault, newTimestamp);
        
        assertEq(feeManager.lastFeeCollectionTimestamps(vault), newTimestamp);
        
        vm.stopPrank();
    }
    
    // Test setting last fee collection timestamp as non-owner
    function test_SetLastFeeCollectionTimestampNonOwner() public {
        vm.startPrank(user);
        
        uint256 newTimestamp = block.timestamp + 1 days;
        vm.expectRevert();
        feeManager.setLastFeeCollectionTimestamp(vault, newTimestamp);
        
        vm.stopPrank();
    }
    
    // Test calculating management fee with zero asset value
    function test_CalculateManagementFeeZeroAssetValue() public {
        uint256 totalAssetsValue = 0;
        uint256 initialTimestamp = block.timestamp;
        
        // First call to set the initial timestamp
        feeManager.calculateManagementFee(vault, totalAssetsValue, initialTimestamp);
        
        // Fast forward 1 year
        uint256 oneYearLater = initialTimestamp + 365 days;
        
        // Calculate fee after 1 year
        uint256 managementFee = feeManager.calculateManagementFee(vault, totalAssetsValue, oneYearLater);
        
        // Expected fee: 0 (zero asset value)
        assertEq(managementFee, 0);
    }
    
    // Test calculating performance fee with zero total supply
    function test_CalculatePerformanceFeeZeroTotalSupply() public {
        uint256 initialSharePrice = 1 * 10**18; // $1 per share
        uint256 newSharePrice = 1.2 * 10**18; // $1.20 per share
        uint256 totalSupply = 0; // 0 shares
        uint8 decimals = 18;
        
        // Set initial high water mark
        vm.startPrank(owner);
        feeManager.setHighWaterMark(vault, initialSharePrice);
        vm.stopPrank();
        
        // Calculate performance fee
        uint256 performanceFee = feeManager.calculatePerformanceFee(vault, newSharePrice, totalSupply, decimals);
        
        // Expected fee: 0 (zero total supply)
        assertEq(performanceFee, 0);
        
        // High water mark should still be updated
        assertEq(feeManager.highWaterMarks(vault), newSharePrice);
    }
    
    // Test calculating performance fee with share price below high water mark
    function test_CalculatePerformanceFeeBelowHighWaterMark() public {
        uint256 initialSharePrice = 1.2 * 10**18; // $1.20 per share
        uint256 newSharePrice = 1.1 * 10**18; // $1.10 per share (below high water mark)
        uint256 totalSupply = 1_000_000 * 10**18; // 1M shares
        uint8 decimals = 18;
        
        // Set initial high water mark
        vm.startPrank(owner);
        feeManager.setHighWaterMark(vault, initialSharePrice);
        vm.stopPrank();
        
        // Calculate performance fee
        uint256 performanceFee = feeManager.calculatePerformanceFee(vault, newSharePrice, totalSupply, decimals);
        
        // Expected fee: 0 (below high water mark)
        assertEq(performanceFee, 0);
        
        // High water mark should remain the same
        assertEq(feeManager.highWaterMarks(vault), initialSharePrice);
    }
}
