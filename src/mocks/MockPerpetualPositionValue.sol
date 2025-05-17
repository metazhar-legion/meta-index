// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockPerpetualPositionValue
 * @dev Helper contract for testing that allows setting position values
 */
contract MockPerpetualPositionValue {
    uint256 private _positionValue;
    
    /**
     * @dev Sets the position value for testing
     * @param value The value to set
     */
    function setPositionValue(uint256 value) external {
        _positionValue = value;
    }
    
    /**
     * @dev Gets the position value
     * @return The position value
     */
    function getPositionValue() external view returns (uint256) {
        return _positionValue;
    }
}
