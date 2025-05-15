// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RWAAssetWrapper} from "./RWAAssetWrapper.sol";
import {RWASyntheticSP500} from "./RWASyntheticSP500.sol";
import {StablecoinLendingStrategy} from "./StablecoinLendingStrategy.sol";
import {PerpetualPositionWrapper} from "./PerpetualPositionWrapper.sol";
import {PerpetualPositionAdapter} from "./adapters/PerpetualPositionAdapter.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IPerpetualRouter} from "./interfaces/IPerpetualRouter.sol";
import {IRWASyntheticToken} from "./interfaces/IRWASyntheticToken.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title RWAWrapperFactory
 * @dev Factory contract for creating different types of RWA wrappers
 * This factory creates standardized RWA bundles with consistent interfaces
 */
contract RWAWrapperFactory is Ownable {
    // Wrapper type enum
    enum WrapperType {
        Standard,      // Standard RWA wrapper with synthetic token
        Perpetual,     // Perpetual position wrapper
        Hybrid         // Hybrid wrapper with both synthetic and perpetual
    }
    
    // Core components
    IPriceOracle public priceOracle;
    address public baseAsset; // e.g., USDC
    
    // Registry of created wrappers
    address[] public wrappers;
    mapping(address => bool) public isRegisteredWrapper;
    
    // Events
    event WrapperCreated(address wrapper, WrapperType wrapperType, string name);
    event PerpetualPositionWrapperCreated(address wrapper, bytes32 marketId, string assetSymbol);
    
    // Custom errors
    error UnsupportedWrapperType();
    error InvalidParameters();
    
    /**
     * @dev Constructor
     * @param _priceOracle Address of the price oracle
     * @param _baseAsset Address of the base asset (e.g., USDC)
     */
    constructor(address _priceOracle, address _baseAsset) Ownable(msg.sender) {
        if (_priceOracle == address(0) || _baseAsset == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        priceOracle = IPriceOracle(_priceOracle);
        baseAsset = _baseAsset;
    }
    
    /**
     * @dev Creates a standard RWA wrapper with synthetic token
     * @param name Name of the wrapper
     * @param perpetualTrading Address of the perpetual trading contract
     * @param yieldStrategyName Name of the yield strategy
     * @param lendingProtocol Address of the lending protocol
     * @param yieldToken Address of the yield token
     * @param feeRecipient Address of the fee recipient
     * @return wrapperAddress Address of the created wrapper
     */
    function createStandardWrapper(
        string memory name,
        string memory /* syntheticTokenName */,
        string memory /* syntheticTokenSymbol */,
        address perpetualTrading,
        string memory yieldStrategyName,
        address lendingProtocol,
        address yieldToken,
        address feeRecipient
    ) external onlyOwner returns (address wrapperAddress) {
        // Create synthetic token
        RWASyntheticSP500 syntheticToken = new RWASyntheticSP500(
            baseAsset,
            perpetualTrading,
            address(priceOracle)
        );
        
        // Create yield strategy
        StablecoinLendingStrategy yieldStrategy = new StablecoinLendingStrategy(
            yieldStrategyName,
            baseAsset,
            lendingProtocol,
            yieldToken,
            feeRecipient
        );
        
        // Create RWA wrapper
        RWAAssetWrapper wrapper = new RWAAssetWrapper(
            name,
            IERC20(baseAsset),
            syntheticToken,
            yieldStrategy,
            priceOracle
        );
        
        // Transfer ownership of synthetic token and yield strategy to wrapper
        syntheticToken.transferOwnership(address(wrapper));
        yieldStrategy.transferOwnership(address(wrapper));
        
        // Register wrapper
        wrappers.push(address(wrapper));
        isRegisteredWrapper[address(wrapper)] = true;
        
        emit WrapperCreated(address(wrapper), WrapperType.Standard, name);
        
        return address(wrapper);
    }
    
    /**
     * @dev Creates a perpetual position wrapper
     * @param name Name of the wrapper
     * @param perpetualRouter Address of the perpetual router
     * @param marketId Market identifier for the perpetual position
     * @param leverage Initial leverage for positions
     * @param isLong Whether positions should be long (true) or short (false)
     * @param assetSymbol Symbol of the asset being tracked
     * @return wrapperAddress Address of the created wrapper
     */
    function createPerpetualPositionWrapper(
        string memory name,
        address perpetualRouter,
        bytes32 marketId,
        uint256 leverage,
        bool isLong,
        string memory assetSymbol
    ) external onlyOwner returns (address wrapperAddress) {
        // Create perpetual position wrapper
        PerpetualPositionWrapper wrapper = new PerpetualPositionWrapper(
            perpetualRouter,
            baseAsset,
            address(priceOracle),
            marketId,
            leverage,
            isLong,
            assetSymbol
        );
        
        // Register wrapper
        wrappers.push(address(wrapper));
        isRegisteredWrapper[address(wrapper)] = true;
        
        emit WrapperCreated(address(wrapper), WrapperType.Perpetual, name);
        emit PerpetualPositionWrapperCreated(address(wrapper), marketId, assetSymbol);
        
        return address(wrapper);
    }
    
    // Structs to group parameters and avoid stack too deep errors
    struct PerpetualParams {
        address router;
        bytes32 marketId;
        uint256 leverage;
        bool isLong;
        string tokenName;
        string tokenSymbol;
    }
    
    struct YieldParams {
        string strategyName;
        address lendingProtocol;
        address yieldToken;
        address feeRecipient;
    }
    
    /**
     * @dev Creates a hybrid wrapper with both synthetic token and perpetual position
     * @param name Name of the wrapper
     * @param perpParams Parameters for the perpetual position
     * @param yieldParams Parameters for the yield strategy
     * @return wrapperAddress Address of the created wrapper
     */
    function createHybridWrapper(
        string memory name,
        PerpetualParams memory perpParams,
        YieldParams memory yieldParams
    ) external onlyOwner returns (address wrapperAddress) {
        // Validate parameters
        if (perpParams.router == address(0) || yieldParams.lendingProtocol == address(0) || 
            yieldParams.yieldToken == address(0) || yieldParams.feeRecipient == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        // Create perpetual position wrapper
        PerpetualPositionWrapper perpWrapper = new PerpetualPositionWrapper(
            perpParams.router,
            baseAsset,
            address(priceOracle),
            perpParams.marketId,
            perpParams.leverage,
            perpParams.isLong,
            perpParams.tokenSymbol
        );
        
        // Create adapter to make the perpetual wrapper compatible with IRWASyntheticToken
        PerpetualPositionAdapter perpAdapter = new PerpetualPositionAdapter(
            address(perpWrapper),
            perpParams.tokenName,
            IRWASyntheticToken.AssetType.EQUITY_INDEX // Default type, can be parameterized if needed
        );
        
        // Create yield strategy
        StablecoinLendingStrategy yieldStrategy = new StablecoinLendingStrategy(
            yieldParams.strategyName,
            baseAsset,
            yieldParams.lendingProtocol,
            yieldParams.yieldToken,
            yieldParams.feeRecipient
        );
        
        // Create RWA wrapper to manage both components
        RWAAssetWrapper wrapper = new RWAAssetWrapper(
            name,
            IERC20(baseAsset),
            perpAdapter,
            yieldStrategy,
            priceOracle
        );
        
        // Transfer ownership of components to the wrapper
        perpWrapper.transferOwnership(address(perpAdapter));
        perpAdapter.transferOwnership(address(wrapper));
        yieldStrategy.transferOwnership(address(wrapper));
        
        // Register wrapper
        wrappers.push(address(wrapper));
        isRegisteredWrapper[address(wrapper)] = true;
        
        emit WrapperCreated(address(wrapper), WrapperType.Hybrid, name);
        emit PerpetualPositionWrapperCreated(address(perpWrapper), perpParams.marketId, perpParams.tokenSymbol);
        
        return address(wrapper);
    }
    
    /**
     * @dev Gets all created wrappers
     * @return Array of wrapper addresses
     */
    function getAllWrappers() external view returns (address[] memory) {
        return wrappers;
    }
    
    /**
     * @dev Sets the price oracle
     * @param _priceOracle New price oracle address
     */
    function setPriceOracle(address _priceOracle) external onlyOwner {
        if (_priceOracle == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        priceOracle = IPriceOracle(_priceOracle);
    }
    
    /**
     * @dev Sets the base asset
     * @param _baseAsset New base asset address
     */
    function setBaseAsset(address _baseAsset) external onlyOwner {
        if (_baseAsset == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        baseAsset = _baseAsset;
    }
}
