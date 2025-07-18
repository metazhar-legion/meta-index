// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITRSProvider
 * @dev Interface for Total Return Swap providers
 * @notice Enables integration with various TRS counterparties and platforms
 */
interface ITRSProvider {
    /**
     * @dev Enum for TRS contract status
     */
    enum TRSStatus {
        PENDING,    // Contract created but not yet active
        ACTIVE,     // Contract is active and accruing returns
        MATURED,    // Contract has reached maturity
        TERMINATED, // Contract terminated early
        DEFAULTED   // Counterparty defaulted
    }

    /**
     * @dev Information about a TRS contract
     */
    struct TRSContract {
        bytes32 contractId;         // Unique identifier for the contract
        address counterparty;       // Address of the counterparty
        bytes32 underlyingAssetId;  // Identifier for the underlying asset (e.g., "SP500")
        uint256 notionalAmount;     // Notional amount of the exposure
        uint256 leverage;           // Leverage ratio (100 = 1x)
        uint256 collateralPosted;   // Amount of collateral posted
        uint256 borrowRate;         // Annual borrow rate in basis points
        uint256 startTime;          // Contract start timestamp
        uint256 maturityTime;       // Contract maturity timestamp
        TRSStatus status;           // Current status of the contract
        int256 unrealizedPnL;       // Current unrealized P&L
        uint256 lastMarkToMarket;   // Last mark-to-market timestamp
    }

    /**
     * @dev Counterparty information and risk metrics
     */
    struct CounterpartyInfo {
        address counterpartyAddress;
        string name;
        uint256 creditRating;       // Credit rating from 1-10 (10 = highest)
        uint256 maxExposure;        // Maximum exposure allowed with this counterparty
        uint256 currentExposure;    // Current exposure with this counterparty
        uint256 defaultProbability; // Estimated default probability (basis points)
        bool isActive;              // Whether counterparty is currently active
        uint256 collateralRequirement; // Required collateral ratio (basis points)
    }

    /**
     * @dev Quote for a TRS contract
     */
    struct TRSQuote {
        address counterparty;
        uint256 borrowRate;         // Annual rate in basis points
        uint256 collateralRequirement; // Required collateral (basis points)
        uint256 maxNotional;        // Maximum notional amount available
        uint256 maxMaturity;        // Maximum maturity available (seconds)
        uint256 quotedAt;          // Timestamp when quote was generated
        uint256 validUntil;        // Quote expiration timestamp
        bytes32 quoteId;           // Unique quote identifier
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets information about a specific TRS contract
     * @param contractId The TRS contract identifier
     * @return contract_ The TRS contract information
     */
    function getTRSContract(bytes32 contractId) external view returns (TRSContract memory contract_);

    /**
     * @dev Gets information about a counterparty
     * @param counterparty The counterparty address
     * @return info The counterparty information
     */
    function getCounterpartyInfo(address counterparty) external view returns (CounterpartyInfo memory info);

    /**
     * @dev Gets all available counterparties
     * @return counterparties Array of counterparty addresses
     */
    function getAvailableCounterparties() external view returns (address[] memory counterparties);

    /**
     * @dev Requests quotes from multiple counterparties
     * @param underlyingAssetId The underlying asset identifier
     * @param notionalAmount The desired notional amount
     * @param maturityDuration The desired maturity duration in seconds
     * @param leverage The desired leverage
     * @return quotes Array of quotes from different counterparties
     */
    function requestQuotes(
        bytes32 underlyingAssetId,
        uint256 notionalAmount,
        uint256 maturityDuration,
        uint256 leverage
    ) external view returns (TRSQuote[] memory quotes);

    /**
     * @dev Gets the current mark-to-market value of a TRS contract
     * @param contractId The TRS contract identifier
     * @return currentValue The current value in base asset terms
     * @return unrealizedPnL The unrealized P&L
     */
    function getMarkToMarketValue(bytes32 contractId) external view returns (uint256 currentValue, int256 unrealizedPnL);

    /**
     * @dev Calculates the required collateral for a TRS contract
     * @param counterparty The counterparty address
     * @param notionalAmount The notional amount
     * @param leverage The leverage ratio
     * @return collateralRequired The required collateral amount
     */
    function calculateCollateralRequirement(
        address counterparty,
        uint256 notionalAmount,
        uint256 leverage
    ) external view returns (uint256 collateralRequired);

    // ============ STATE-CHANGING FUNCTIONS ============

    /**
     * @dev Creates a new TRS contract
     * @param quoteId The quote identifier to accept
     * @param collateralAmount The collateral amount to post
     * @return contractId The new TRS contract identifier
     */
    function createTRSContract(
        bytes32 quoteId,
        uint256 collateralAmount
    ) external returns (bytes32 contractId);

    /**
     * @dev Posts additional collateral to a TRS contract
     * @param contractId The TRS contract identifier
     * @param additionalCollateral The additional collateral amount
     */
    function postCollateral(bytes32 contractId, uint256 additionalCollateral) external;

    /**
     * @dev Withdraws excess collateral from a TRS contract
     * @param contractId The TRS contract identifier
     * @param collateralAmount The collateral amount to withdraw
     */
    function withdrawCollateral(bytes32 contractId, uint256 collateralAmount) external;

    /**
     * @dev Terminates a TRS contract before maturity
     * @param contractId The TRS contract identifier
     * @return finalValue The final settlement value
     * @return collateralReturned The collateral returned
     */
    function terminateContract(bytes32 contractId) external returns (uint256 finalValue, uint256 collateralReturned);

    /**
     * @dev Settles a matured TRS contract
     * @param contractId The TRS contract identifier
     * @return finalValue The final settlement value
     * @return collateralReturned The collateral returned
     */
    function settleContract(bytes32 contractId) external returns (uint256 finalValue, uint256 collateralReturned);

    /**
     * @dev Rolls over a TRS contract to a new maturity
     * @param contractId The existing TRS contract identifier
     * @param newQuoteId The quote for the new contract
     * @return newContractId The new TRS contract identifier
     */
    function rolloverContract(bytes32 contractId, bytes32 newQuoteId) external returns (bytes32 newContractId);

    /**
     * @dev Marks a TRS contract to market (updates P&L)
     * @param contractId The TRS contract identifier
     * @return newValue The updated contract value
     * @return pnlChange The change in P&L
     */
    function markToMarket(bytes32 contractId) external returns (uint256 newValue, int256 pnlChange);

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Adds a new counterparty (admin only)
     * @param counterparty The counterparty address
     * @param info The counterparty information
     */
    function addCounterparty(address counterparty, CounterpartyInfo calldata info) external;

    /**
     * @dev Updates counterparty information (admin only)
     * @param counterparty The counterparty address
     * @param info The updated counterparty information
     */
    function updateCounterparty(address counterparty, CounterpartyInfo calldata info) external;

    /**
     * @dev Removes a counterparty (admin only)
     * @param counterparty The counterparty address
     */
    function removeCounterparty(address counterparty) external;

    // ============ EVENTS ============

    event TRSContractCreated(
        bytes32 indexed contractId,
        address indexed counterparty,
        bytes32 indexed underlyingAssetId,
        uint256 notionalAmount,
        uint256 borrowRate
    );

    event TRSContractTerminated(
        bytes32 indexed contractId,
        uint256 finalValue,
        int256 finalPnL,
        uint256 collateralReturned
    );

    event TRSContractSettled(
        bytes32 indexed contractId,
        uint256 finalValue,
        int256 finalPnL,
        uint256 collateralReturned
    );

    event CollateralPosted(bytes32 indexed contractId, uint256 amount);
    event CollateralWithdrawn(bytes32 indexed contractId, uint256 amount);

    event CounterpartyAdded(address indexed counterparty, string name, uint256 creditRating);
    event CounterpartyUpdated(address indexed counterparty, uint256 newCreditRating);
    event CounterpartyRemoved(address indexed counterparty);

    event MarkedToMarket(bytes32 indexed contractId, uint256 newValue, int256 pnlChange);
    event QuoteRequested(bytes32 indexed underlyingAssetId, uint256 notionalAmount, uint256 maturityDuration);
}