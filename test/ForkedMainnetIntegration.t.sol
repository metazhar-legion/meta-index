// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Import mock contracts
contract MockERC20 is IERC20, IERC20Metadata {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }
    
    function name() external view override returns (string memory) {
        return _name;
    }
    
    function symbol() external view override returns (string memory) {
        return _symbol;
    }
    
    function decimals() external view override returns (uint8) {
        return _decimals;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function allowance(address tokenOwner, address spender) external view override returns (uint256) {
        return _allowances[tokenOwner][spender];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
    }
    
    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        require(tokenOwner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[tokenOwner][spender] = amount;
    }
    
    function _spendAllowance(address tokenOwner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[tokenOwner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(tokenOwner, spender, currentAllowance - amount);
        }
    }
    
    function mint(address to, uint256 amount) external {
        _totalSupply += amount;
        _balances[to] += amount;
    }
}

contract MockIndexFundVault is IERC20 {
    // Constants
    uint256 constant BASIS_POINTS = 10000; // 100% in basis points
    
    address public baseAsset;
    address public feeManager;
    address public allocationManager;
    address public indexRegistry;
    uint256 private _totalSupply;
    uint256 private _totalAssets;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    address public owner;
    
    constructor(address _baseAsset, address _feeManager, address _allocationManager, address _indexRegistry) {
        baseAsset = _baseAsset;
        feeManager = _feeManager;
        allocationManager = _allocationManager;
        indexRegistry = _indexRegistry;
        owner = msg.sender;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function allowance(address tokenOwner, address spender) external view override returns (uint256) {
        return _allowances[tokenOwner][spender];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function deposit(uint256 assets, address receiver) external returns (uint256) {
        // Transfer assets from sender to vault
        IERC20(baseAsset).transferFrom(msg.sender, address(this), assets);
        
        // Calculate shares to mint (simplified for mock)
        uint256 shares = assets;
        if (_totalSupply > 0 && _totalAssets > 0) {
            shares = (assets * _totalSupply) / _totalAssets;
        }
        
        // Mint shares to receiver
        _mint(receiver, shares);
        
        // Update total assets
        _totalAssets += assets;
        
        return shares;
    }
    
    function redeem(uint256 shares, address receiver, address tokenOwner) external returns (uint256) {
        require(shares > 0, "Cannot redeem 0 shares");
        
        // If caller is not the owner, check allowance
        if (msg.sender != tokenOwner) {
            _spendAllowance(tokenOwner, msg.sender, shares);
        }
        
        // Calculate assets to withdraw (simplified for mock)
        uint256 assets = (shares * _totalAssets) / _totalSupply;
        
        // Burn shares from owner
        _burn(tokenOwner, shares);
        
        // Update total assets
        _totalAssets -= assets;
        
        // Transfer assets to receiver
        IERC20(baseAsset).transfer(receiver, assets);
        
        return assets;
    }
    
    function setFeeManager(address _feeManager) external {
        require(msg.sender == owner, "Unauthorized");
        feeManager = _feeManager;
    }
    
    function setAllocationManager(address _allocationManager) external {
        require(msg.sender == owner, "Unauthorized");
        allocationManager = _allocationManager;
    }
    
    function setIndexRegistry(address _indexRegistry) external {
        require(msg.sender == owner, "Unauthorized");
        indexRegistry = _indexRegistry;
    }
    
    function rebalance() external {
        // Mock rebalance functionality
        // In a real implementation, this would adjust the portfolio based on target allocations
    }
    
    function harvestYield() external returns (uint256) {
        // Mock yield harvesting
        // In a real implementation, this would collect yield from strategies
        return 0;
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
    }
    
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        
        _totalSupply += amount;
        _balances[account] += amount;
    }
    
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;
    }
    
    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        require(tokenOwner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[tokenOwner][spender] = amount;
    }
    
    function _spendAllowance(address tokenOwner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[tokenOwner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(tokenOwner, spender, currentAllowance - amount);
        }
    }
}

contract MockRWAAssetWrapper {
    string public name;
    string public symbol;
    address public underlyingAsset;
    address public vault;
    address public yieldStrategy;
    uint256 public allocationPercentage; // Percentage in basis points (e.g., 5000 = 50%)
    
    constructor(string memory _name, string memory _symbol, address _underlyingAsset) {
        name = _name;
        symbol = _symbol;
        underlyingAsset = _underlyingAsset;
    }
    
    function setVault(address _vault) external {
        vault = _vault;
    }
    
    function setYieldStrategy(address _yieldStrategy) external {
        yieldStrategy = _yieldStrategy;
    }
    
    function setAllocationPercentage(uint256 _allocationPercentage) external {
        allocationPercentage = _allocationPercentage;
    }
    
    function allocateToStrategy(uint256 amount) external {
        // Mock allocation to strategy
        // In a real implementation, this would transfer tokens to the strategy
    }
    
    function withdrawFromStrategy(uint256 amount) external {
        // Mock withdrawal from strategy
        // In a real implementation, this would withdraw tokens from the strategy
    }
    
    function harvestYield() external returns (uint256) {
        // Mock yield harvesting
        // In a real implementation, this would collect yield from the strategy
        return 0;
    }
}

contract ForkedMainnetIntegrationTest is Test {
    // Constants
    uint256 constant BASIS_POINTS = 10000; // 100% in basis points
    uint256 constant DEPOSIT_AMOUNT = 100_000 * 10**6; // 100,000 USDC
    
    // Mainnet contract addresses
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // Test accounts
    address owner;
    address user1;
    address user2;
    
    // Contract instances
    IERC20 usdc;
    IERC20Metadata usdcMetadata;
    MockIndexFundVault vault;
    MockRWAAssetWrapper spWrapper;
    MockRWAAssetWrapper goldWrapper;
    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("mainnet");
        
        // Set up test accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Fund accounts with ETH
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        // Connect to USDC contract
        usdc = IERC20(USDC_ADDRESS);
        usdcMetadata = IERC20Metadata(USDC_ADDRESS);
    }
    
    function _setupVaultEnvironment() internal {
        // Create mock contracts
        MockERC20 mockFeeManager = new MockERC20("Fee Manager", "FM", 18);
        MockERC20 mockAllocationManager = new MockERC20("Allocation Manager", "AM", 18);
        MockERC20 mockIndexRegistry = new MockERC20("Index Registry", "IR", 18);
        
        // Set up owner as the deployer of all contracts
        vm.startPrank(owner);
        
        // Create vault
        vault = new MockIndexFundVault(
            USDC_ADDRESS,
            address(mockFeeManager),
            address(mockAllocationManager),
            address(mockIndexRegistry)
        );
        
        // Create asset wrappers
        spWrapper = new MockRWAAssetWrapper("S&P 500 Wrapper", "SPW", address(0));
        goldWrapper = new MockRWAAssetWrapper("Gold Wrapper", "GOLDW", address(0));
        
        // Configure asset wrappers
        spWrapper.setVault(address(vault));
        goldWrapper.setVault(address(vault));
        
        // Mint USDC to users for testing
        // Since we can't mint real USDC, we'll use vm.prank to transfer from a whale account
        address usdcWhale = 0x55FE002aefF02F77364de339a1292923A15844B8; // Known USDC whale
        vm.startPrank(usdcWhale);
        usdc.transfer(user1, DEPOSIT_AMOUNT * 2);
        usdc.transfer(user2, DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        
        vm.stopPrank();
    }
    
    // Test basic USDC functionality
    function test_USDCBasicFunctionality() public {
        // Check that we can access USDC
        assertEq(usdcMetadata.decimals(), 6, "USDC should have 6 decimals");
        assertEq(usdcMetadata.symbol(), "USDC", "Symbol should be USDC");
        
        // Check USDC balance of whale account
        address usdcWhale = 0x55FE002aefF02F77364de339a1292923A15844B8;
        uint256 whaleBalance = usdc.balanceOf(usdcWhale);
        assertGt(whaleBalance, DEPOSIT_AMOUNT * 4, "Whale should have enough USDC");
        
        // Transfer USDC from whale to user1
        vm.prank(usdcWhale);
        usdc.transfer(user1, DEPOSIT_AMOUNT);
        
        // Check user1 balance
        assertEq(usdc.balanceOf(user1), DEPOSIT_AMOUNT, "User1 should have received USDC");
        
        // Test approval and transferFrom
        vm.startPrank(user1);
        usdc.approve(user2, DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check allowance
        assertEq(usdc.allowance(user1, user2), DEPOSIT_AMOUNT, "Allowance should be set correctly");
        
        // Transfer using allowance
        vm.startPrank(user2);
        usdc.transferFrom(user1, user2, DEPOSIT_AMOUNT / 4);
        vm.stopPrank();
        
        // Check balances after transfer
        assertEq(usdc.balanceOf(user1), DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT / 4), "User1 balance should be reduced");
        assertEq(usdc.balanceOf(user2), DEPOSIT_AMOUNT / 4, "User2 should have received USDC");
        
        // Check remaining allowance
        assertEq(usdc.allowance(user1, user2), DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT / 4), "Allowance should be reduced");
    }
    
    // Test vault deposit and withdrawal
    function test_VaultDepositWithdraw() public {
        // Set up vault environment
        _setupVaultEnvironment();
        
        // User1 deposits into the vault
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Check user1 shares
        assertEq(vault.balanceOf(user1), shares, "User1 should have received shares");
        
        // User1 withdraws from the vault
        vm.startPrank(user1);
        uint256 assets = vault.redeem(shares, user1, user1);
        vm.stopPrank();
        
        // Check user1 USDC balance after withdrawal
        assertEq(usdc.balanceOf(user1), DEPOSIT_AMOUNT, "User1 should have received USDC back");
        assertEq(assets, DEPOSIT_AMOUNT, "Assets withdrawn should equal deposit");
    }
    
    // Test vault rebalance
    function test_VaultRebalance() public {
        // Set up vault environment
        _setupVaultEnvironment();
        
        // User1 deposits into the vault
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Owner performs rebalance
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        
        // In a real test, we would check the new allocations
        // For this mock test, we just ensure the function doesn't revert
    }
    
    // Test yield harvesting
    function test_YieldHarvesting() public {
        // Set up vault environment
        _setupVaultEnvironment();
        
        // User1 deposits into the vault
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Owner harvests yield
        vm.startPrank(owner);
        uint256 yieldHarvested = vault.harvestYield();
        vm.stopPrank();
        
        // In a real test, we would check the yield amount
        // For this mock test, we just ensure the function doesn't revert
        assertEq(yieldHarvested, 0, "Mock yield should be 0");
    }
    
    // Test edge cases
    function test_VaultEdgeCases() public {
        // Set up vault environment
        _setupVaultEnvironment();
        
        // Test zero deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), 0);
        uint256 shares = vault.deposit(0, user1);
        vm.stopPrank();
        
        // Zero deposit should result in zero shares
        assertEq(shares, 0, "Zero deposit should result in zero shares");
        
        // Verify owner can call these functions
        vm.startPrank(owner);
        vault.setFeeManager(address(0x123));
        vault.setAllocationManager(address(0x456));
        vault.setIndexRegistry(address(0x789));
        vm.stopPrank();
        
        // Check that the changes took effect
        assertEq(vault.feeManager(), address(0x123), "Fee manager should be updated");
        assertEq(vault.allocationManager(), address(0x456), "Allocation manager should be updated");
        assertEq(vault.indexRegistry(), address(0x789), "Index registry should be updated");
    }
}
