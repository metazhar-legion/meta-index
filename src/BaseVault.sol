// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {CommonErrors} from "./errors/CommonErrors.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/**
 * @title BaseVault
 * @dev A base ERC4626-compliant vault that provides core functionality for all vaults
 * including fee management, pausing, and basic vault operations.
 */
abstract contract BaseVault is ERC4626, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
    // Target share price in base asset units
    // Setting this to 100 means 1 share will be worth ~100 base asset units initially
    uint256 private constant TARGET_SHARE_PRICE = 100;
    
    // Fee manager
    IFeeManager public feeManager;
    
    // Last time fees were collected
    uint256 public lastFeeCollection;
    
    // Events
    event FeesCollected(uint256 managementFee, uint256 performanceFee);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);
    
    /**
     * @dev Constructor that initializes the vault with the asset token and a name
     * @param asset_ The underlying asset token (typically a stablecoin)
     * @param feeManager_ The fee manager contract address
     */
    constructor(
        IERC20 asset_,
        IFeeManager feeManager_
    ) 
        ERC4626(asset_)
        ERC20(
            string(abi.encodePacked("Index Fund Vault ", ERC20(address(asset_)).name())),
            string(abi.encodePacked("ifv", ERC20(address(asset_)).symbol()))
        )
        Ownable(msg.sender)
    {
        if (address(feeManager_) == address(0)) revert CommonErrors.ZeroAddress();
        
        feeManager = feeManager_;
        lastFeeCollection = block.timestamp;
    }
    
    /**
     * @dev Collect management and performance fees
     * @return managementFee The management fee collected
     * @return performanceFee The performance fee collected
     */
    function collectFees() public virtual returns (uint256 managementFee, uint256 performanceFee) {
        if (paused()) revert CommonErrors.OperationPaused();
        
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return (0, 0);
        
        // Calculate time elapsed since last fee collection
        uint256 timeElapsed = block.timestamp - lastFeeCollection;
        
        // Collect fees using the fee manager
        (managementFee, performanceFee) = feeManager.collectFees(
            totalValue,
            timeElapsed
        );
        
        uint256 totalFee = managementFee + performanceFee;
        if (totalFee > 0) {
            // Mint new shares to the fee recipient
            address feeRecipient = feeManager.getFeeRecipient();
            _mint(feeRecipient, convertToShares(totalFee));
        }
        
        lastFeeCollection = block.timestamp;
        
        emit FeesCollected(managementFee, performanceFee);
        return (managementFee, performanceFee);
    }
    
    /**
     * @dev Update the fee manager
     * @param newFeeManager The new fee manager address
     */
    function updateFeeManager(IFeeManager newFeeManager) external onlyOwner {
        if (address(newFeeManager) == address(0)) revert CommonErrors.ZeroAddress();
        
        address oldFeeManager = address(feeManager);
        feeManager = newFeeManager;
        
        emit FeeManagerUpdated(oldFeeManager, address(newFeeManager));
    }
    
    /**
     * @dev Pause the vault
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Override of _deposit to add fee collection and pausing
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (paused()) revert CommonErrors.OperationPaused();
        
        // Collect fees before deposit to ensure accurate share price
        collectFees();
        
        super._deposit(caller, receiver, assets, shares);
    }
    
    /**
     * @dev Override of _withdraw to add fee collection and pausing
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (paused()) revert CommonErrors.OperationPaused();
        
        // Collect fees before withdrawal to ensure accurate share price
        collectFees();
        
        super._withdraw(caller, receiver, owner, assets, shares);
    }
    
    /**
     * @dev Calculate the total assets in the vault
     * This should be overridden by derived contracts to include all assets
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }
}
