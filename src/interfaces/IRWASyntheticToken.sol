pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRWASyntheticToken
 * @dev Interface for synthetic tokens representing Real World Assets (RWAs)
 */
interface IRWASyntheticToken is IERC20 {
    /**
     * @dev Asset type enumeration
     */
    enum AssetType {
        EQUITY_INDEX,  // Stock market indices like S&P 500
        COMMODITY,     // Commodities like Gold
        FIXED_INCOME,  // Fixed income assets like Treasury bonds
        REAL_ESTATE,   // Real estate indices
        CURRENCY,      // Fiat currencies
        OTHER          // Other asset types
    }

    /**
     * @dev Asset information structure
     */
    struct AssetInfo {
        string name;           // Name of the asset (e.g., "S&P 500 Index")
        string symbol;         // Symbol of the asset (e.g., "SPX")
        AssetType assetType;   // Type of the asset
        address oracle;        // Oracle providing price data
        uint256 lastPrice;     // Last recorded price in USD (scaled by 10^18)
        uint256 lastUpdated;   // Timestamp of last price update
        bytes32 marketId;      // Identifier for the perpetual market
        bool isActive;         // Whether the asset is active
    }

    /**
     * @dev Gets information about the synthetic asset
     * @return info The asset information
     */
    function getAssetInfo() external view returns (AssetInfo memory info);

    /**
     * @dev Gets the current price of the asset in USD
     * @return price The current price (scaled by 10^18)
     */
    function getCurrentPrice() external view returns (uint256 price);

    /**
     * @dev Updates the asset price from the oracle
     * @return success Whether the update was successful
     */
    function updatePrice() external returns (bool success);

    /**
     * @dev Mints synthetic tokens
     * @param to The address to mint tokens to
     * @param amount The amount to mint
     * @return success Whether the mint was successful
     */
    function mint(address to, uint256 amount) external returns (bool success);

    /**
     * @dev Burns synthetic tokens
     * @param from The address to burn tokens from
     * @param amount The amount to burn
     * @return success Whether the burn was successful
     */
    function burn(address from, uint256 amount) external returns (bool success);
}
