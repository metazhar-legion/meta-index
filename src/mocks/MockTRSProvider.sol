// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITRSProvider} from "../interfaces/ITRSProvider.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title MockTRSProvider
 * @dev Mock implementation of a TRS provider for testing
 * @notice Simulates real TRS counterparties and contract lifecycle
 */
contract MockTRSProvider is ITRSProvider, Ownable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_LEVERAGE = 500; // 5x
    uint256 public constant MIN_MATURITY = 7 days;
    uint256 public constant MAX_MATURITY = 365 days;

    // State variables
    IERC20 public immutable baseAsset;
    
    // Storage
    mapping(bytes32 => TRSContract) private trsContracts;
    mapping(address => CounterpartyInfo) private counterparties;
    mapping(bytes32 => TRSQuote) private quotes;
    
    address[] private counterpartyList;
    bytes32[] private activeContractIds;
    
    // Counters for ID generation
    uint256 private contractCounter;
    uint256 private quoteCounter;
    
    // Mock market data
    mapping(bytes32 => uint256) private assetPrices;
    mapping(bytes32 => uint256) private assetPriceTimestamps;
    
    // Testing configuration
    bool public shouldFailCreation;
    bool public shouldFailSettlement;
    uint256 public mockVolatility = 500; // 5% daily volatility

    /**
     * @dev Constructor
     * @param _baseAsset The base asset for collateral (e.g., USDC)
     */
    constructor(address _baseAsset) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        baseAsset = IERC20(_baseAsset);
        
        // Initialize mock asset prices
        assetPrices[bytes32("SP500")] = 5000e18; // $5000
        assetPrices[bytes32("NASDAQ")] = 15000e18; // $15000
        assetPrices[bytes32("GOLD")] = 2000e18; // $2000
        assetPrices[bytes32("CRUDE")] = 80e18; // $80
        
        // Set timestamps
        assetPriceTimestamps[bytes32("SP500")] = block.timestamp;
        assetPriceTimestamps[bytes32("NASDAQ")] = block.timestamp;
        assetPriceTimestamps[bytes32("GOLD")] = block.timestamp;
        assetPriceTimestamps[bytes32("CRUDE")] = block.timestamp;
        
        // Add default mock counterparties
        _addMockCounterparties();
    }

    // ============ VIEW FUNCTIONS ============

    function getTRSContract(bytes32 contractId) external view override returns (TRSContract memory contract_) {
        contract_ = trsContracts[contractId];
        if (contract_.contractId == bytes32(0)) revert CommonErrors.NotFound();
        
        // Update unrealized P&L for active contracts
        if (contract_.status == TRSStatus.ACTIVE) {
            (, int256 unrealizedPnL) = _calculateMarkToMarket(contractId);
            contract_.unrealizedPnL = unrealizedPnL;
        }
        
        return contract_;
    }

    function getCounterpartyInfo(address counterparty) external view override returns (CounterpartyInfo memory info) {
        info = counterparties[counterparty];
        if (bytes(info.name).length == 0) revert CommonErrors.NotFound();
        return info;
    }

    function getAvailableCounterparties() external view override returns (address[] memory) {
        return counterpartyList;
    }

    function requestQuotes(
        bytes32 underlyingAssetId,
        uint256 notionalAmount,
        uint256 maturityDuration,
        uint256 leverage
    ) external override returns (TRSQuote[] memory quotes_) {
        if (notionalAmount == 0) revert CommonErrors.ValueTooLow();
        if (maturityDuration < MIN_MATURITY || maturityDuration > MAX_MATURITY) revert CommonErrors.ValueOutOfRange(maturityDuration, MIN_MATURITY, MAX_MATURITY);
        if (leverage > MAX_LEVERAGE) revert CommonErrors.ValueTooHigh();
        if (assetPrices[underlyingAssetId] == 0) revert CommonErrors.InvalidValue();

        // Generate quotes from available counterparties
        uint256 activeCounterparties = 0;
        for (uint256 i = 0; i < counterpartyList.length; i++) {
            if (counterparties[counterpartyList[i]].isActive) {
                activeCounterparties++;
            }
        }

        quotes_ = new TRSQuote[](activeCounterparties);
        uint256 quoteIndex = 0;

        for (uint256 i = 0; i < counterpartyList.length; i++) {
            address counterparty = counterpartyList[i];
            CounterpartyInfo memory info = counterparties[counterparty];
            
            if (!info.isActive) continue;
            if (info.currentExposure + notionalAmount > info.maxExposure) continue;

            // Generate realistic quote based on counterparty risk
            uint256 borrowRate = _calculateBorrowRate(info.creditRating, leverage, maturityDuration);
            uint256 collateralReq = _calculateCollateralRequirement(info.collateralRequirement, leverage);

            quotes_[quoteIndex] = TRSQuote({
                counterparty: counterparty,
                borrowRate: borrowRate,
                collateralRequirement: collateralReq,
                maxNotional: info.maxExposure - info.currentExposure,
                maxMaturity: MAX_MATURITY,
                quotedAt: block.timestamp,
                validUntil: block.timestamp + 10 minutes,
                quoteId: keccak256(abi.encodePacked(counterparty, block.timestamp, quoteCounter++))
            });
            
            quoteIndex++;
        }

        emit QuoteRequested(underlyingAssetId, notionalAmount, maturityDuration);
        return quotes_;
    }

    /**
     * @dev Internal view function to get quotes without state modification (for cost estimation)
     */
    function _getQuotesView(
        bytes32 underlyingAssetId,
        uint256 notionalAmount,
        uint256 maturityDuration,
        uint256 leverage
    ) internal view returns (TRSQuote[] memory quotes_) {
        if (notionalAmount == 0) return new TRSQuote[](0);
        if (maturityDuration < MIN_MATURITY || maturityDuration > MAX_MATURITY) return new TRSQuote[](0);
        if (leverage > MAX_LEVERAGE) return new TRSQuote[](0);
        if (assetPrices[underlyingAssetId] == 0) return new TRSQuote[](0);

        // Generate quotes from available counterparties
        uint256 activeCounterparties = 0;
        for (uint256 i = 0; i < counterpartyList.length; i++) {
            if (counterparties[counterpartyList[i]].isActive) {
                activeCounterparties++;
            }
        }

        quotes_ = new TRSQuote[](activeCounterparties);
        uint256 quoteIndex = 0;

        for (uint256 i = 0; i < counterpartyList.length; i++) {
            address counterparty = counterpartyList[i];
            CounterpartyInfo memory info = counterparties[counterparty];
            
            if (!info.isActive) continue;
            if (info.currentExposure + notionalAmount > info.maxExposure) continue;

            // Generate realistic quote based on counterparty risk
            uint256 borrowRate = _calculateBorrowRate(info.creditRating, leverage, maturityDuration);
            uint256 collateralReq = _calculateCollateralRequirement(info.collateralRequirement, leverage);

            quotes_[quoteIndex] = TRSQuote({
                counterparty: counterparty,
                borrowRate: borrowRate,
                collateralRequirement: collateralReq,
                maxNotional: info.maxExposure - info.currentExposure,
                maxMaturity: MAX_MATURITY,
                quotedAt: block.timestamp,
                validUntil: block.timestamp + 10 minutes,
                quoteId: keccak256(abi.encodePacked(counterparty, block.timestamp, i)) // Use i instead of counter
            });
            
            quoteIndex++;
        }

        return quotes_;
    }

    function getQuotesForEstimation(
        bytes32 underlyingAssetId,
        uint256 notionalAmount,
        uint256 maturityDuration,
        uint256 leverage
    ) external view override returns (TRSQuote[] memory quotes_) {
        return _getQuotesView(underlyingAssetId, notionalAmount, maturityDuration, leverage);
    }

    function getMarkToMarketValue(bytes32 contractId) external view override returns (uint256 currentValue, int256 unrealizedPnL) {
        return _calculateMarkToMarket(contractId);
    }

    function calculateCollateralRequirement(
        address counterparty,
        uint256 notionalAmount,
        uint256 leverage
    ) external view override returns (uint256 collateralRequired) {
        CounterpartyInfo memory info = counterparties[counterparty];
        if (bytes(info.name).length == 0) revert CommonErrors.NotFound();
        
        uint256 baseCollateral = (notionalAmount * 100) / leverage;
        return (baseCollateral * info.collateralRequirement) / BASIS_POINTS;
    }

    // ============ STATE-CHANGING FUNCTIONS ============

    function createTRSContract(
        bytes32 quoteId,
        uint256 collateralAmount
    ) external override returns (bytes32 contractId) {
        if (shouldFailCreation) revert CommonErrors.OperationFailed();
        
        TRSQuote memory quote = quotes[quoteId];
        if (quote.quoteId == bytes32(0)) revert CommonErrors.NotFound();
        if (block.timestamp > quote.validUntil) revert CommonErrors.Expired();

        // Calculate required collateral
        uint256 notionalAmount = (collateralAmount * BASIS_POINTS) / quote.collateralRequirement;
        uint256 leverage = (notionalAmount * 100) / collateralAmount;
        
        if (collateralAmount == 0) revert CommonErrors.ValueTooLow();

        // Transfer collateral from user
        baseAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Generate contract ID
        contractId = keccak256(abi.encodePacked(msg.sender, quote.counterparty, block.timestamp, contractCounter++));

        // Create contract
        trsContracts[contractId] = TRSContract({
            contractId: contractId,
            counterparty: quote.counterparty,
            underlyingAssetId: bytes32("SP500"), // Default for testing
            notionalAmount: notionalAmount,
            leverage: leverage,
            collateralPosted: collateralAmount,
            borrowRate: quote.borrowRate,
            startTime: block.timestamp,
            maturityTime: block.timestamp + 30 days, // Default 30 days
            status: TRSStatus.ACTIVE,
            unrealizedPnL: 0,
            lastMarkToMarket: block.timestamp
        });

        // Update counterparty exposure
        counterparties[quote.counterparty].currentExposure += notionalAmount;
        
        // Add to active contracts
        activeContractIds.push(contractId);

        emit TRSContractCreated(contractId, quote.counterparty, bytes32("SP500"), notionalAmount, quote.borrowRate);
        return contractId;
    }

    function postCollateral(bytes32 contractId, uint256 additionalCollateral) external override {
        TRSContract storage contract_ = trsContracts[contractId];
        if (contract_.contractId == bytes32(0)) revert CommonErrors.NotFound();
        if (contract_.status != TRSStatus.ACTIVE) revert CommonErrors.InvalidState();

        baseAsset.safeTransferFrom(msg.sender, address(this), additionalCollateral);
        contract_.collateralPosted += additionalCollateral;

        emit CollateralPosted(contractId, additionalCollateral);
    }

    function withdrawCollateral(bytes32 contractId, uint256 collateralAmount) external override {
        TRSContract storage contract_ = trsContracts[contractId];
        if (contract_.contractId == bytes32(0)) revert CommonErrors.NotFound();
        if (contract_.status != TRSStatus.ACTIVE) revert CommonErrors.InvalidState();

        // Check minimum collateral requirement
        uint256 minCollateral = this.calculateCollateralRequirement(
            contract_.counterparty,
            contract_.notionalAmount,
            contract_.leverage
        );
        
        if (contract_.collateralPosted - collateralAmount < minCollateral) {
            revert CommonErrors.InsufficientBalance();
        }

        contract_.collateralPosted -= collateralAmount;
        baseAsset.safeTransfer(msg.sender, collateralAmount);

        emit CollateralWithdrawn(contractId, collateralAmount);
    }

    function terminateContract(bytes32 contractId) external override returns (uint256 finalValue, uint256 collateralReturned) {
        TRSContract storage contract_ = trsContracts[contractId];
        if (contract_.contractId == bytes32(0)) revert CommonErrors.NotFound();
        if (contract_.status != TRSStatus.ACTIVE) revert CommonErrors.InvalidState();

        // Calculate final settlement
        int256 finalPnL;
        (finalValue, finalPnL) = _calculateMarkToMarket(contractId);
        
        // Update contract status
        contract_.status = TRSStatus.TERMINATED;
        contract_.unrealizedPnL = finalPnL;

        // Calculate amount to return
        if (finalPnL >= 0) {
            collateralReturned = contract_.collateralPosted + uint256(finalPnL);
        } else {
            uint256 loss = uint256(-finalPnL);
            collateralReturned = loss < contract_.collateralPosted ? 
                contract_.collateralPosted - loss : 0;
        }

        // Update counterparty exposure
        counterparties[contract_.counterparty].currentExposure -= contract_.notionalAmount;

        // Transfer final amount to user
        if (collateralReturned > 0) {
            baseAsset.safeTransfer(msg.sender, collateralReturned);
        }

        emit TRSContractTerminated(contractId, finalValue, finalPnL, collateralReturned);
        return (finalValue, collateralReturned);
    }

    function settleContract(bytes32 contractId) external override returns (uint256 finalValue, uint256 collateralReturned) {
        if (shouldFailSettlement) revert CommonErrors.OperationFailed();
        
        TRSContract storage contract_ = trsContracts[contractId];
        if (contract_.contractId == bytes32(0)) revert CommonErrors.NotFound();
        if (contract_.status != TRSStatus.ACTIVE) revert CommonErrors.InvalidState();
        if (block.timestamp < contract_.maturityTime) revert CommonErrors.TooSoon();

        // Calculate final settlement
        int256 finalPnL;
        (finalValue, finalPnL) = _calculateMarkToMarket(contractId);
        
        // Update contract status
        contract_.status = TRSStatus.MATURED;
        contract_.unrealizedPnL = finalPnL;

        // Calculate amount to return (same logic as terminate)
        if (finalPnL >= 0) {
            collateralReturned = contract_.collateralPosted + uint256(finalPnL);
        } else {
            uint256 loss = uint256(-finalPnL);
            collateralReturned = loss < contract_.collateralPosted ? 
                contract_.collateralPosted - loss : 0;
        }

        // Update counterparty exposure
        counterparties[contract_.counterparty].currentExposure -= contract_.notionalAmount;

        // Transfer final amount to user
        if (collateralReturned > 0) {
            baseAsset.safeTransfer(msg.sender, collateralReturned);
        }

        emit TRSContractSettled(contractId, finalValue, finalPnL, collateralReturned);
        return (finalValue, collateralReturned);
    }

    function rolloverContract(bytes32 contractId, bytes32 newQuoteId) external override returns (bytes32 newContractId) {
        // Terminate old contract
        (uint256 finalValue, uint256 collateralReturned) = this.terminateContract(contractId);
        
        // Create new contract with returned collateral
        newContractId = this.createTRSContract(newQuoteId, collateralReturned);
        
        return newContractId;
    }

    function markToMarket(bytes32 contractId) external override returns (uint256 newValue, int256 pnlChange) {
        TRSContract storage contract_ = trsContracts[contractId];
        if (contract_.contractId == bytes32(0)) revert CommonErrors.NotFound();
        if (contract_.status != TRSStatus.ACTIVE) revert CommonErrors.InvalidState();

        int256 oldPnL = contract_.unrealizedPnL;
        int256 newPnL;
        (newValue, newPnL) = _calculateMarkToMarket(contractId);
        
        pnlChange = newPnL - oldPnL;
        contract_.unrealizedPnL = newPnL;
        contract_.lastMarkToMarket = block.timestamp;

        emit MarkedToMarket(contractId, newValue, pnlChange);
        return (newValue, pnlChange);
    }

    // ============ ADMIN FUNCTIONS ============

    function addCounterparty(address counterparty, CounterpartyInfo calldata info) external override onlyOwner {
        if (counterparty == address(0)) revert CommonErrors.ZeroAddress();
        if (bytes(counterparties[counterparty].name).length > 0) revert CommonErrors.AlreadyExists();

        counterparties[counterparty] = info;
        counterpartyList.push(counterparty);

        emit CounterpartyAdded(counterparty, info.name, info.creditRating);
    }

    function updateCounterparty(address counterparty, CounterpartyInfo calldata info) external override onlyOwner {
        if (bytes(counterparties[counterparty].name).length == 0) revert CommonErrors.NotFound();

        uint256 oldRating = counterparties[counterparty].creditRating;
        counterparties[counterparty] = info;

        emit CounterpartyUpdated(counterparty, info.creditRating);
    }

    function removeCounterparty(address counterparty) external override onlyOwner {
        if (bytes(counterparties[counterparty].name).length == 0) revert CommonErrors.NotFound();
        if (counterparties[counterparty].currentExposure > 0) revert CommonErrors.InvalidState();

        delete counterparties[counterparty];
        
        // Remove from list
        for (uint256 i = 0; i < counterpartyList.length; i++) {
            if (counterpartyList[i] == counterparty) {
                counterpartyList[i] = counterpartyList[counterpartyList.length - 1];
                counterpartyList.pop();
                break;
            }
        }

        emit CounterpartyRemoved(counterparty);
    }

    // ============ TESTING FUNCTIONS ============

    function setAssetPrice(bytes32 assetId, uint256 price) external onlyOwner {
        assetPrices[assetId] = price;
        assetPriceTimestamps[assetId] = block.timestamp;
    }

    function setMockVolatility(uint256 volatility) external onlyOwner {
        mockVolatility = volatility;
    }

    function setShouldFailCreation(bool shouldFail) external onlyOwner {
        shouldFailCreation = shouldFail;
    }

    function setShouldFailSettlement(bool shouldFail) external onlyOwner {
        shouldFailSettlement = shouldFail;
    }

    function getActiveContractIds() external view returns (bytes32[] memory) {
        return activeContractIds;
    }

    // ============ INTERNAL FUNCTIONS ============

    function _calculateMarkToMarket(bytes32 contractId) internal view returns (uint256 currentValue, int256 unrealizedPnL) {
        TRSContract memory contract_ = trsContracts[contractId];
        if (contract_.contractId == bytes32(0)) return (0, 0);

        bytes32 assetId = contract_.underlyingAssetId;
        uint256 currentPrice = assetPrices[assetId];
        
        // Simulate price movement based on time elapsed and volatility
        uint256 timeElapsed = block.timestamp - contract_.startTime;
        if (timeElapsed > 0) {
            // Simple random price movement simulation
            uint256 priceMultiplier = uint256(keccak256(abi.encodePacked(contractId, block.timestamp / 3600))) % 200;
            int256 priceChange = int256(priceMultiplier) - 100; // -100 to +100
            
            // Apply volatility scaling
            priceChange = (priceChange * int256(mockVolatility) * int256(timeElapsed)) / (int256(BASIS_POINTS) * 86400);
            
            if (priceChange >= 0) {
                currentPrice = currentPrice + (currentPrice * uint256(priceChange)) / BASIS_POINTS;
            } else {
                uint256 decrease = (currentPrice * uint256(-priceChange)) / BASIS_POINTS;
                currentPrice = currentPrice > decrease ? currentPrice - decrease : currentPrice / 2;
            }
        }

        // Calculate current value of the position
        currentValue = (contract_.notionalAmount * currentPrice) / assetPrices[assetId];
        
        // Calculate unrealized P&L
        int256 positionPnL = int256(currentValue) - int256(contract_.notionalAmount);
        
        // Account for borrow costs
        uint256 borrowCosts = (contract_.notionalAmount * contract_.borrowRate * timeElapsed) / (BASIS_POINTS * 365 days);
        unrealizedPnL = positionPnL - int256(borrowCosts);

        return (currentValue, unrealizedPnL);
    }

    function _calculateBorrowRate(uint256 creditRating, uint256 leverage, uint256 maturity) internal pure returns (uint256) {
        // Base rate starts at 300 bps (3%) for highest credit rating
        uint256 baseRate = 300 + (1000 - creditRating * 100); // 300-1200 bps based on rating
        
        // Add leverage premium
        uint256 leveragePremium = (leverage - 100) * 10; // 10 bps per 0.1x leverage above 1x
        
        // Add maturity premium
        uint256 maturityPremium = maturity / (30 days) * 25; // 25 bps per month
        
        return baseRate + leveragePremium + maturityPremium;
    }

    function _calculateCollateralRequirement(uint256 baseRequirement, uint256 leverage) internal pure returns (uint256) {
        // Increase collateral requirement with leverage
        uint256 leverageMultiplier = leverage > 100 ? leverage : 100;
        return (baseRequirement * leverageMultiplier) / 100;
    }

    function _addMockCounterparties() internal {
        // High-grade institutional counterparty
        counterparties[address(0x1111)] = CounterpartyInfo({
            counterpartyAddress: address(0x1111),
            name: "MockBank AAA",
            creditRating: 9,
            maxExposure: 10000000e6, // $10M
            currentExposure: 0,
            defaultProbability: 5, // 0.05%
            isActive: true,
            collateralRequirement: 1200 // 12%
        });
        counterpartyList.push(address(0x1111));

        // Medium-grade counterparty
        counterparties[address(0x2222)] = CounterpartyInfo({
            counterpartyAddress: address(0x2222),
            name: "MockFund BBB",
            creditRating: 7,
            maxExposure: 5000000e6, // $5M
            currentExposure: 0,
            defaultProbability: 25, // 0.25%
            isActive: true,
            collateralRequirement: 1500 // 15%
        });
        counterpartyList.push(address(0x2222));

        // Lower-grade but higher capacity counterparty
        counterparties[address(0x3333)] = CounterpartyInfo({
            counterpartyAddress: address(0x3333),
            name: "MockPrime BB",
            creditRating: 5,
            maxExposure: 20000000e6, // $20M
            currentExposure: 0,
            defaultProbability: 100, // 1%
            isActive: true,
            collateralRequirement: 2000 // 20%
        });
        counterpartyList.push(address(0x3333));
    }
}