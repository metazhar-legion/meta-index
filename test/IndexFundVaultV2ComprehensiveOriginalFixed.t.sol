// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockFeeManager} from "../src/mocks/MockFeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";
import {IAssetWrapper} from "../src/interfaces/IAssetWrapper.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IDEX} from "../src/interfaces/IDEX.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Mock asset wrapper for testing
contract MockRWAAssetWrapper is IAssetWrapper {
    string public name;
    IERC20 public baseAsset;
    uint256 private _valueInBaseAsset;
    address public owner;
    
    constructor(string memory _name, address _baseAsset) {
        name = _name;
        baseAsset = IERC20(_baseAsset);
        owner = msg.sender;
    }
    
    function setValueInBaseAsset(uint256 value) external {
        _valueInBaseAsset = value;
    }
    
    function allocateCapital(uint256 amount) external override returns (bool) {
        // Transfer the base asset to this contract
        baseAsset.transferFrom(msg.sender, address(this), amount);
        _valueInBaseAsset += amount;
        return true;
    }
    
    function withdrawCapital(uint256 amount) external override returns (uint256 actualAmount) {
        require(amount <= _valueInBaseAsset, "Insufficient balance");
        _valueInBaseAsset -= amount;
        
        // Transfer the base asset back
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }
    
    function getValueInBaseAsset() external view override returns (uint256) {
        return _valueInBaseAsset;
    }
    
    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }
    
    function getName() external view override returns (string memory) {
        return name;
    }
    
    function getUnderlyingTokens() external view override returns (address[] memory tokens) {
        // Return an empty array for simplicity
        return new address[](0);
    }
    
    function harvestYield() external override returns (uint256 harvestedAmount) {
        // Mock implementation - no yield harvesting
        return 0;
    }
}

// Mock malicious asset wrapper for testing reentrancy
contract MaliciousAssetWrapper is IAssetWrapper {
    address public target;
    bool public attackOnAllocate;
    bool public attackOnWithdraw;
    bool public attackActive;
    uint256 public valueInBaseAsset;
    IERC20 public baseAsset;
    
    constructor(address _baseAsset) {
        baseAsset = IERC20(_baseAsset);
    }
    
    function setTarget(address _target) external {
        target = _target;
    }
    
    function setAttackMode(bool _onAllocate, bool _onWithdraw) external {
        attackOnAllocate = _onAllocate;
        attackOnWithdraw = _onWithdraw;
    }
    
    function activateAttack(bool _active) external {
        attackActive = _active;
    }
    
    function setValueInBaseAsset(uint256 _value) external {
        valueInBaseAsset = _value;
    }
    
    function allocateCapital(uint256 amount) external override returns (bool) {
        // Transfer the base asset to this contract
        baseAsset.transferFrom(msg.sender, address(this), amount);
        valueInBaseAsset += amount;
        
        // Attempt reentrancy if configured
        if (attackActive && attackOnAllocate && target != address(0)) {
            // Try to call rebalance on the vault
            IndexFundVaultV2(target).rebalance();
        }
        
        return true;
    }
    
    function withdrawCapital(uint256 amount) external override returns (uint256 actualAmount) {
        require(amount <= valueInBaseAsset, "Insufficient balance");
        valueInBaseAsset -= amount;
        
        // Attempt reentrancy if configured
        if (attackActive && attackOnWithdraw && target != address(0)) {
            // Try to call rebalance on the vault before transferring funds
            IndexFundVaultV2(target).rebalance();
        }
        
        // Transfer the base asset back
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }
    
    function getValueInBaseAsset() external view override returns (uint256) {
        return valueInBaseAsset;
    }
    
    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }
    
    function getName() external pure override returns (string memory) {
        return "Malicious Asset Wrapper";
    }
    
    function getUnderlyingTokens() external view override returns (address[] memory tokens) {
        // Return an empty array for simplicity
        return new address[](0);
    }
    
    function harvestYield() external override returns (uint256 harvestedAmount) {
        // Mock implementation - no yield harvesting
        return 0;
    }
}

contract IndexFundVaultV2ComprehensiveOriginalFixedTest is Test {
    // Contracts
    IndexFundVaultV2 public vault;
    MockRWAAssetWrapper public rwaWrapper;
    MockERC20 public mockUSDC;
    MockPriceOracle public mockPriceOracle;
    MockDEX public mockDEX;
    MockFeeManager public mockFeeManager;
    MaliciousAssetWrapper public maliciousWrapper;
    
    // Users
    address public owner;
    address public user1;
    address public user2;
    address public attacker;
    
    // Constants
    uint256 public constant INITIAL_PRICE = 5000 * 1e6; // $5000 in USDC decimals
    uint256 public constant DEPOSIT_AMOUNT = 10000 * 1e6; // 10000 USDC
    uint256 public constant INITIAL_BALANCE = 100000 * 1e6; // 100000 USDC initial balance for users
    
    // Events
    event AssetAdded(address indexed assetAddress, uint256 weight);
    event AssetRemoved(address indexed assetAddress);
    event AssetWeightUpdated(address indexed assetAddress, uint256 oldWeight, uint256 newWeight);
    event Rebalanced();
    event RebalanceIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event RebalanceThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event DEXUpdated(address indexed oldDEX, address indexed newDEX);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    
    function setUp() public {
        owner = address(this); // Test contract is the owner
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");
        
        // Deploy mock contracts
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockPriceOracle = new MockPriceOracle(address(mockUSDC));
        mockDEX = new MockDEX(address(mockPriceOracle));
        mockFeeManager = new MockFeeManager();
        
        // Deploy RWA wrapper (owned by this test contract)
        rwaWrapper = new MockRWAAssetWrapper(
            "S&P 500 RWA",
            address(mockUSDC)
        );
        
        // Deploy malicious wrapper for reentrancy tests
        maliciousWrapper = new MaliciousAssetWrapper(address(mockUSDC));
        
        // Deploy vault (owned by this test contract)
        vault = new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            mockPriceOracle,
            mockDEX
        );
        
        // Set rebalance interval to 0 to avoid timing issues in tests
        vault.setRebalanceInterval(0);
        
        // Ensure this test contract is the owner of the vault
        assertEq(vault.owner(), address(this));
        
        // Approve USDC for the RWA wrapper
        mockUSDC.approve(address(rwaWrapper), type(uint256).max);
        
        // Approve USDC for the vault to spend
        mockUSDC.approve(address(vault), type(uint256).max);
        
        // Approve USDC for the malicious wrapper
        mockUSDC.approve(address(maliciousWrapper), type(uint256).max);
        
        // Mint USDC to users
        mockUSDC.mint(user1, INITIAL_BALANCE);
        mockUSDC.mint(user2, INITIAL_BALANCE);
        mockUSDC.mint(attacker, INITIAL_BALANCE);
        
        // Approve USDC for the vault
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), type(uint256).max);
        mockUSDC.approve(address(maliciousWrapper), type(uint256).max);
        vm.stopPrank();
        
        // Configure malicious wrapper
        maliciousWrapper.setTarget(address(vault));
    }
