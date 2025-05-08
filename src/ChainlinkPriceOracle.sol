// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title ChainlinkPriceOracle
 * @dev Implementation of IPriceOracle using Chainlink price feeds
 */
contract ChainlinkPriceOracle is IPriceOracle, Ownable {
    // Mapping from token address to price feed address
    mapping(address => address) public priceFeeds;

    // Base asset address (e.g., USDC)
    address public immutable baseAsset;

    // Base asset decimals
    uint8 public immutable baseAssetDecimals;

    // Events
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);

    /**
     * @dev Constructor
     * @param _baseAsset The base asset address (e.g., USDC)
     */
    constructor(address _baseAsset) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        baseAsset = _baseAsset;
        baseAssetDecimals = IERC20Metadata(_baseAsset).decimals();
    }

    /**
     * @dev Sets a price feed for a token
     * @param token The token address
     * @param priceFeed The Chainlink price feed address
     */
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        if (token == address(0)) revert CommonErrors.ZeroAddress();
        if (priceFeed == address(0)) revert CommonErrors.ZeroAddress();

        // Verify that the price feed is valid by calling latestRoundData
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        (, int256 price,,,) = feed.latestRoundData();
        if (price <= 0) revert CommonErrors.InvalidValue();

        priceFeeds[token] = priceFeed;
        emit PriceFeedUpdated(token, priceFeed);
    }

    /**
     * @dev Gets the price of a token from Chainlink
     * @param token The token address
     * @return The price in base asset terms (with 18 decimals)
     */
    function getPrice(address token) external view override returns (uint256) {
        // If token is the base asset, return 1
        if (token == baseAsset) return 1e18;

        address priceFeed = priceFeeds[token];
        if (priceFeed == address(0)) revert CommonErrors.PriceNotAvailable();

        // Get the latest price from Chainlink
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        (, int256 price,,,) = feed.latestRoundData();

        // Ensure the price is positive
        if (price <= 0) revert CommonErrors.PriceNotAvailable();

        // Convert to uint256
        uint256 priceUint = uint256(price);

        // Get the number of decimals in the price feed
        uint8 feedDecimals = feed.decimals();

        // Convert to 18 decimals for our standard representation
        if (feedDecimals < 18) {
            priceUint = priceUint * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            priceUint = priceUint / (10 ** (feedDecimals - 18));
        }

        return priceUint;
    }

    /**
     * @dev Converts an amount of a token to the base asset
     * @param token The token address
     * @param amount The token amount
     * @return The equivalent amount in base asset terms
     */
    function convertToBaseAsset(address token, uint256 amount) external view override returns (uint256) {
        // If token is the base asset, return the amount adjusted for decimals
        if (token == baseAsset) {
            if (baseAssetDecimals < 18) {
                return amount * (10 ** (18 - baseAssetDecimals));
            } else if (baseAssetDecimals > 18) {
                return amount / (10 ** (baseAssetDecimals - 18));
            }
            return amount;
        }

        // Get the token price and decimals
        uint256 price = this.getPrice(token);
        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        // Calculate the value in base asset
        uint256 valueInBaseAsset;
        if (tokenDecimals < 18) {
            valueInBaseAsset = (amount * price * (10 ** (18 - tokenDecimals))) / 1e18;
        } else if (tokenDecimals > 18) {
            valueInBaseAsset = (amount * price) / (10 ** (tokenDecimals - 18)) / 1e18;
        } else {
            valueInBaseAsset = (amount * price) / 1e18;
        }

        // Convert to base asset decimals
        if (baseAssetDecimals < 18) {
            return valueInBaseAsset / (10 ** (18 - baseAssetDecimals));
        } else if (baseAssetDecimals > 18) {
            return valueInBaseAsset * (10 ** (baseAssetDecimals - 18));
        }

        return valueInBaseAsset;
    }

    /**
     * @dev Converts an amount of the base asset to a token
     * @param token The token address
     * @param amount The base asset amount
     * @return The equivalent amount in token terms
     */
    function convertFromBaseAsset(address token, uint256 amount) external view override returns (uint256) {
        // If token is the base asset, return the amount adjusted for decimals
        if (token == baseAsset) {
            if (baseAssetDecimals < 18) {
                return amount / (10 ** (18 - baseAssetDecimals));
            } else if (baseAssetDecimals > 18) {
                return amount * (10 ** (baseAssetDecimals - 18));
            }
            return amount;
        }

        // Get the token price and decimals
        uint256 price = this.getPrice(token);
        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        // Adjust base asset amount to 18 decimals
        uint256 adjustedAmount;
        if (baseAssetDecimals < 18) {
            adjustedAmount = amount * (10 ** (18 - baseAssetDecimals));
        } else if (baseAssetDecimals > 18) {
            adjustedAmount = amount / (10 ** (baseAssetDecimals - 18));
        } else {
            adjustedAmount = amount;
        }

        // Calculate the equivalent token amount
        uint256 tokenAmount = (adjustedAmount * 1e18) / price;

        // Adjust for token decimals
        if (tokenDecimals < 18) {
            return tokenAmount / (10 ** (18 - tokenDecimals));
        } else if (tokenDecimals > 18) {
            return tokenAmount * (10 ** (tokenDecimals - 18));
        }

        return tokenAmount;
    }
}
