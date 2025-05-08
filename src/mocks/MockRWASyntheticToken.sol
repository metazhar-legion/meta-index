// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRWASyntheticToken} from "../interfaces/IRWASyntheticToken.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title MockRWASyntheticToken
 * @dev Mock implementation of IRWASyntheticToken for testing
 */
contract MockRWASyntheticToken is ERC20, IRWASyntheticToken, Ownable {
    AssetInfo private _assetInfo;
    address private _minter;

    /**
     * @dev Constructor
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param assetType The type of asset
     * @param oracle The oracle address
     */
    constructor(string memory name_, string memory symbol_, AssetType assetType, address oracle)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        _assetInfo = AssetInfo({
            name: name_,
            symbol: symbol_,
            assetType: assetType,
            oracle: oracle,
            lastPrice: 1e18, // Default price of 1 USD
            lastUpdated: block.timestamp,
            marketId: bytes32(0),
            isActive: true
        });
    }

    /**
     * @dev Set the minter address
     * @param minter The address allowed to mint/burn tokens
     */
    function setMinter(address minter) external onlyOwner {
        _minter = minter;
    }

    /**
     * @dev Gets information about the synthetic asset
     * @return info The asset information
     */
    function getAssetInfo() external view override returns (AssetInfo memory info) {
        return _assetInfo;
    }

    /**
     * @dev Gets the current price of the asset in USD
     * @return price The current price (scaled by 10^18)
     */
    function getCurrentPrice() external view override returns (uint256 price) {
        return _assetInfo.lastPrice;
    }

    /**
     * @dev Updates the asset price
     * @return success Whether the update was successful
     */
    function updatePrice() external override returns (bool success) {
        _assetInfo.lastUpdated = block.timestamp;
        return true;
    }

    /**
     * @dev Set a new price for the asset
     * @param newPrice The new price (scaled by 10^18)
     */
    function setPrice(uint256 newPrice) external onlyOwner {
        _assetInfo.lastPrice = newPrice;
        _assetInfo.lastUpdated = block.timestamp;
    }

    /**
     * @dev Mints synthetic tokens
     * @param to The address to mint tokens to
     * @param amount The amount to mint
     * @return success Whether the mint was successful
     */
    function mint(address to, uint256 amount) external override returns (bool success) {
        if (msg.sender != _minter && msg.sender != owner()) revert CommonErrors.Unauthorized();
        _mint(to, amount);
        return true;
    }

    /**
     * @dev Burns synthetic tokens
     * @param from The address to burn tokens from
     * @param amount The amount to burn
     * @return success Whether the burn was successful
     */
    function burn(address from, uint256 amount) external override returns (bool success) {
        if (msg.sender != _minter && msg.sender != owner()) revert CommonErrors.Unauthorized();
        _burn(from, amount);
        return true;
    }
}
