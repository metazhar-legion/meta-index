// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAssetWrapper} from "../interfaces/IAssetWrapper.sol";

/**
 * @title MockRWAAssetWrapper
 * @dev A mock implementation of IAssetWrapper for testing purposes
 */
contract MockRWAAssetWrapper is IAssetWrapper, Ownable {
    using SafeERC20 for IERC20;
    
    IERC20 public baseAsset;
    string public name;
    uint256 private valueInBaseAsset;
    
    constructor(
        string memory _name,
        address _baseAsset
    ) Ownable(msg.sender) {
        name = _name;
        baseAsset = IERC20(_baseAsset);
    }
    
    function allocateCapital(uint256 amount) external override returns (bool) {
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        valueInBaseAsset += amount;
        return true;
    }
    
    function withdrawCapital(uint256 amount) external override returns (uint256) {
        require(amount <= valueInBaseAsset, "Insufficient balance");
        valueInBaseAsset -= amount;
        baseAsset.safeTransfer(msg.sender, amount);
        return amount;
    }
    
    function getValueInBaseAsset() external view override returns (uint256) {
        return valueInBaseAsset;
    }
    
    function setValueInBaseAsset(uint256 _value) external onlyOwner {
        valueInBaseAsset = _value;
    }
    
    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }
    
    function getName() external view override returns (string memory) {
        return name;
    }
    
    function getUnderlyingTokens() external pure override returns (address[] memory) {
        address[] memory tokens = new address[](0);
        return tokens;
    }
    
    function harvestYield() external pure override returns (uint256) {
        return 0;
    }
}
