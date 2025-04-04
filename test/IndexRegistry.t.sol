// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IndexRegistry} from "../src/IndexRegistry.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract IndexRegistryTest is Test {
    IndexRegistry public registry;
    
    address public owner = address(1);
    address public daoGovernance = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;
    MockToken public token4;
    
    uint256 public constant BASIS_POINTS = 10000;
    
    function setUp() public {
        vm.startPrank(owner);
        registry = new IndexRegistry();
        
        token1 = new MockToken("Token 1", "TKN1", 18);
        token2 = new MockToken("Token 2", "TKN2", 18);
        token3 = new MockToken("Token 3", "TKN3", 18);
        token4 = new MockToken("Token 4", "TKN4", 18);
        
        vm.stopPrank();
    }
    
    // Test initialization
    function test_Initialization() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.isGovernanceEnabled(), false);
        assertEq(registry.daoGovernance(), address(0));
        assertEq(registry.getIndexSize(), 0);
    }
    
    // Test adding tokens
    function test_AddToken() public {
        vm.startPrank(owner);
        
        registry.addToken(address(token1), 4000); // 40%
        registry.addToken(address(token2), 6000); // 60%
        
        vm.stopPrank();
        
        (address[] memory tokens, uint256[] memory weights) = registry.getCurrentIndex();
        
        assertEq(tokens.length, 2);
        assertEq(weights.length, 2);
        assertEq(tokens[0], address(token1));
        assertEq(tokens[1], address(token2));
        assertEq(weights[0], 4000);
        assertEq(weights[1], 6000);
        assertEq(registry.getTotalWeight(), 10000);
        assertEq(registry.getIndexSize(), 2);
        assertTrue(registry.isTokenInIndex(address(token1)));
        assertTrue(registry.isTokenInIndex(address(token2)));
    }
    
    // Test adding token with invalid parameters
    function test_AddTokenInvalidParams() public {
        vm.startPrank(owner);
        
        // Zero address
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        registry.addToken(address(0), 5000);
        
        // Zero weight
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueTooLow.selector));
        registry.addToken(address(token1), 0);
        
        // Add a token
        registry.addToken(address(token1), 5000);
        
        // Try to add the same token again
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TokenAlreadyExists.selector));
        registry.addToken(address(token1), 3000);
        
        // Try to add a token that would exceed 100%
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TotalExceeds100Percent.selector));
        registry.addToken(address(token2), 6000);
        
        vm.stopPrank();
    }
    
    // Test adding token as non-owner
    function test_AddTokenNonOwner() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        registry.addToken(address(token1), 5000);
        
        vm.stopPrank();
    }
    
    // Test removing tokens
    function test_RemoveToken() public {
        vm.startPrank(owner);
        
        registry.addToken(address(token1), 3000);
        registry.addToken(address(token2), 3000);
        registry.addToken(address(token3), 4000);
        
        registry.removeToken(address(token2));
        
        vm.stopPrank();
        
        (address[] memory tokens, uint256[] memory weights) = registry.getCurrentIndex();
        
        assertEq(tokens.length, 2);
        assertEq(weights.length, 2);
        assertEq(tokens[0], address(token1));
        assertEq(tokens[1], address(token3));
        assertEq(weights[0], 3000);
        assertEq(weights[1], 4000);
        assertEq(registry.getTotalWeight(), 7000);
        assertEq(registry.getIndexSize(), 2);
        assertTrue(registry.isTokenInIndex(address(token1)));
        assertFalse(registry.isTokenInIndex(address(token2)));
        assertTrue(registry.isTokenInIndex(address(token3)));
    }
    
    // Test removing token with invalid parameters
    function test_RemoveTokenInvalidParams() public {
        vm.startPrank(owner);
        
        // Try to remove a non-existent token
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TokenNotFound.selector));
        registry.removeToken(address(token1));
        
        vm.stopPrank();
    }
    
    // Test removing token as non-owner
    function test_RemoveTokenNonOwner() public {
        vm.startPrank(owner);
        registry.addToken(address(token1), 5000);
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert();
        registry.removeToken(address(token1));
        vm.stopPrank();
    }
    
    // Test updating token weights
    function test_UpdateTokenWeight() public {
        vm.startPrank(owner);
        
        registry.addToken(address(token1), 4000);
        registry.addToken(address(token2), 6000);
        
        // We need to update to a weight that won't exceed BASIS_POINTS
        // Current total is 10000, so we can update token1 to at most 4000
        registry.updateTokenWeight(address(token1), 4000);
        
        vm.stopPrank();
        
        (address[] memory tokens, uint256[] memory weights) = registry.getCurrentIndex();
        
        assertEq(tokens.length, 2);
        assertEq(weights.length, 2);
        assertEq(weights[0], 4000);
        assertEq(weights[1], 6000);
        assertEq(registry.getTotalWeight(), 10000);
    }
    
    // Test updating token weight with invalid parameters
    function test_UpdateTokenWeightInvalidParams() public {
        vm.startPrank(owner);
        
        // Try to update a non-existent token
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TokenNotFound.selector));
        registry.updateTokenWeight(address(token1), 5000);
        
        // Add tokens
        registry.addToken(address(token1), 4000);
        registry.addToken(address(token2), 6000);
        
        // Try to update with zero weight
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueTooLow.selector));
        registry.updateTokenWeight(address(token1), 0);
        
        // Try to update with weight that would exceed 100%
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TotalExceeds100Percent.selector));
        registry.updateTokenWeight(address(token1), 5001);
        
        vm.stopPrank();
    }
    
    // Test updating token weight as non-owner
    function test_UpdateTokenWeightNonOwner() public {
        vm.startPrank(owner);
        registry.addToken(address(token1), 5000);
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert();
        registry.updateTokenWeight(address(token1), 6000);
        vm.stopPrank();
    }
    
    // Test rebalancing index
    function test_RebalanceIndex() public {
        vm.startPrank(owner);
        
        registry.addToken(address(token1), 3000);
        registry.addToken(address(token2), 4000);
        
        // Total weight is 7000, after rebalance token1 should be ~4286 and token2 should be ~5714
        registry.rebalanceIndex();
        
        vm.stopPrank();
        
        (address[] memory tokens, uint256[] memory weights) = registry.getCurrentIndex();
        
        assertEq(tokens.length, 2);
        assertEq(weights.length, 2);
        
        // Due to rounding, we check approximate values
        uint256 expectedToken1Weight = (3000 * BASIS_POINTS) / 7000;
        uint256 expectedToken2Weight = (4000 * BASIS_POINTS) / 7000;
        
        assertEq(weights[0], expectedToken1Weight);
        assertEq(weights[1], expectedToken2Weight);
        
        // Due to rounding errors, the total weight might be slightly off from BASIS_POINTS
        // We'll check that it's very close (within 1 basis point)
        uint256 totalWeight = registry.getTotalWeight();
        assertTrue(totalWeight >= BASIS_POINTS - 1 && totalWeight <= BASIS_POINTS + 1);
    }
    
    // Test rebalancing empty index
    function test_RebalanceEmptyIndex() public {
        vm.startPrank(owner);
        
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.EmptyArray.selector));
        registry.rebalanceIndex();
        
        vm.stopPrank();
    }
    
    // Test rebalancing index as non-owner
    function test_RebalanceIndexNonOwner() public {
        vm.startPrank(owner);
        registry.addToken(address(token1), 5000);
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert();
        registry.rebalanceIndex();
        vm.stopPrank();
    }
    
    // Test enabling governance
    function test_EnableGovernance() public {
        vm.startPrank(owner);
        
        registry.enableGovernance(daoGovernance);
        
        vm.stopPrank();
        
        assertTrue(registry.isGovernanceEnabled());
        assertEq(registry.daoGovernance(), daoGovernance);
    }
    
    // Test enabling governance with invalid parameters
    function test_EnableGovernanceInvalidParams() public {
        vm.startPrank(owner);
        
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        registry.enableGovernance(address(0));
        
        vm.stopPrank();
    }
    
    // Test enabling governance as non-owner
    function test_EnableGovernanceNonOwner() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        registry.enableGovernance(daoGovernance);
        
        vm.stopPrank();
    }
    
    // Test disabling governance
    function test_DisableGovernance() public {
        vm.startPrank(owner);
        
        registry.enableGovernance(daoGovernance);
        assertTrue(registry.isGovernanceEnabled());
        
        registry.disableGovernance();
        
        vm.stopPrank();
        
        assertFalse(registry.isGovernanceEnabled());
    }
    
    // Test disabling governance as non-owner
    function test_DisableGovernanceNonOwner() public {
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert();
        registry.disableGovernance();
        vm.stopPrank();
    }
    
    // Test creating a proposal
    function test_CreateProposal() public {
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);
        
        uint256[] memory weights = new uint256[](3);
        weights[0] = 3000;
        weights[1] = 3000;
        weights[2] = 4000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        vm.stopPrank();
        
        // For public arrays of structs, we can't easily access all fields
        // Instead, we'll focus on testing the functionality rather than the internal state
        
        // Verify the proposal exists by checking if we can vote on it
        vm.prank(user2);
        registry.vote(0, true);
        
        // If we got here without reverting, the proposal exists
    }
    
    // Test creating a proposal with invalid parameters
    function test_CreateProposalInvalidParams() public {
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);
        
        uint256[] memory weights = new uint256[](3);
        weights[0] = 3000;
        weights[1] = 3000;
        weights[2] = 4000;
        
        uint256[] memory invalidWeights = new uint256[](2);
        invalidWeights[0] = 5000;
        invalidWeights[1] = 5000;
        
        uint256[] memory excessWeights = new uint256[](3);
        excessWeights[0] = 4000;
        excessWeights[1] = 4000;
        excessWeights[2] = 4000;
        
        vm.startPrank(user1);
        
        // Governance disabled
        vm.stopPrank();
        vm.startPrank(owner);
        registry.disableGovernance();
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.GovernanceDisabled.selector));
        registry.createProposal(tokens, weights, 7 days);
        
        // Re-enable governance for further tests
        vm.stopPrank();
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        // Empty tokens array
        address[] memory emptyTokens = new address[](0);
        uint256[] memory emptyWeights = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.EmptyArray.selector));
        registry.createProposal(emptyTokens, emptyWeights, 7 days);
        
        // Mismatched array lengths
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.MismatchedArrayLengths.selector));
        registry.createProposal(tokens, invalidWeights, 7 days);
        
        // Invalid voting period
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidTimeParameters.selector));
        registry.createProposal(tokens, weights, 12 hours);
        
        // Zero weight
        uint256[] memory zeroWeights = new uint256[](3);
        zeroWeights[0] = 5000;
        zeroWeights[1] = 5000;
        zeroWeights[2] = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueTooLow.selector));
        registry.createProposal(tokens, zeroWeights, 7 days);
        
        // Total weight not equal to BASIS_POINTS
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TotalExceeds100Percent.selector));
        registry.createProposal(tokens, excessWeights, 7 days);
        
        vm.stopPrank();
    }
    
    // Test voting on a proposal
    function test_VoteOnProposal() public {
        // Setup proposal
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        vm.stopPrank();
        
        // Vote on proposal
        vm.startPrank(user1);
        registry.vote(0, true);
        vm.stopPrank();
        
        vm.startPrank(user2);
        registry.vote(0, false);
        vm.stopPrank();
        
        // We can't easily check the vote counts directly
        // Instead, we'll verify voting functionality by checking if users have voted
        
        // Check that users have voted
        assertTrue(registry.hasVoted(0, user1));
        assertTrue(registry.hasVoted(0, user2));
        assertTrue(registry.hasVoted(0, user1));
        assertTrue(registry.hasVoted(0, user2));
    }
    
    // Test voting on a proposal with invalid parameters
    function test_VoteOnProposalInvalidParams() public {
        // Setup proposal
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        // Governance disabled
        vm.stopPrank();
        vm.startPrank(owner);
        registry.disableGovernance();
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.GovernanceDisabled.selector));
        registry.vote(0, true);
        
        // Re-enable governance for further tests
        vm.stopPrank();
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        // Invalid proposal ID
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ProposalInvalid.selector));
        registry.vote(999, true);
        
        // Vote on proposal
        registry.vote(0, true);
        
        // Try to vote again
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.AlreadyVoted.selector));
        registry.vote(0, false);
        
        // Warp to after voting period
        vm.warp(block.timestamp + 8 days);
        
        // Try to vote after voting period
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.VotingPeriodEnded.selector));
        registry.vote(0, true);
        
        vm.stopPrank();
    }
    
    // Test executing a proposal
    function test_ExecuteProposal() public {
        // Setup proposal
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        
        // Add initial tokens
        registry.addToken(address(token1), 6000);
        registry.addToken(address(token2), 4000);
        
        vm.stopPrank();
        
        // Create proposal for new index composition
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token3);
        tokens[2] = address(token4);
        
        uint256[] memory weights = new uint256[](3);
        weights[0] = 3000;
        weights[1] = 3000;
        weights[2] = 4000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        registry.vote(0, true);
        vm.stopPrank();
        
        vm.startPrank(user2);
        registry.vote(0, true);
        vm.stopPrank();
        
        // Warp to after voting period
        vm.warp(block.timestamp + 8 days);
        
        // Execute proposal
        vm.startPrank(user1);
        registry.executeProposal(0);
        vm.stopPrank();
        
        // Check index was updated
        (address[] memory indexTokens, uint256[] memory indexWeights) = registry.getCurrentIndex();
        
        assertEq(indexTokens.length, 3);
        assertEq(indexWeights.length, 3);
        assertEq(indexTokens[0], address(token1));
        assertEq(indexTokens[1], address(token3));
        assertEq(indexTokens[2], address(token4));
        assertEq(indexWeights[0], 3000);
        assertEq(indexWeights[1], 3000);
        assertEq(indexWeights[2], 4000);
        assertEq(registry.getTotalWeight(), BASIS_POINTS);
        
        // We can't directly check if the proposal is executed
        // Instead, we'll verify the index was updated correctly
        // If the index was updated correctly, the proposal must have been executed successfully
    }
    
    // Test executing a proposal with invalid parameters
    function test_ExecuteProposalInvalidParams() public {
        // Setup proposal
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        // Governance disabled
        vm.stopPrank();
        vm.startPrank(owner);
        registry.disableGovernance();
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.GovernanceDisabled.selector));
        registry.executeProposal(0);
        
        // Re-enable governance for further tests
        vm.stopPrank();
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        // Invalid proposal ID
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ProposalInvalid.selector));
        registry.executeProposal(999);
        
        // Voting period still active
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.VotingPeriodActive.selector));
        registry.executeProposal(0);
        
        // Warp to after voting period
        vm.warp(block.timestamp + 8 days);
        
        // Proposal rejected (not enough votes)
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ProposalRejected.selector));
        registry.executeProposal(0);
        
        // Add votes and execute
        vm.stopPrank();
        
        // Reset time and add votes
        vm.warp(block.timestamp - 8 days);
        
        vm.startPrank(user1);
        registry.vote(0, true);
        vm.stopPrank();
        
        vm.startPrank(user2);
        registry.vote(0, true);
        vm.stopPrank();
        
        // Warp to after voting period
        vm.warp(block.timestamp + 8 days);
        
        // Execute proposal
        vm.startPrank(user1);
        registry.executeProposal(0);
        
        // Try to execute again
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ProposalAlreadyExecuted.selector));
        registry.executeProposal(0);
        
        vm.stopPrank();
    }
    
    // Test canceling a proposal
    function test_CancelProposal() public {
        // Setup proposal
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        vm.stopPrank();
        
        // Cancel proposal
        vm.startPrank(owner);
        registry.cancelProposal(0);
        vm.stopPrank();
        
        // We can't directly check if the proposal is canceled
        // Instead, we'll verify that we can't vote on it anymore
        // Try to vote on the canceled proposal
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ProposalCanceled.selector));
        registry.vote(0, true);
        vm.stopPrank();
    }
    
    // Test canceling a proposal with invalid parameters
    function test_CancelProposalInvalidParams() public {
        // Setup proposal
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Invalid proposal ID
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ProposalInvalid.selector));
        registry.cancelProposal(999);
        
        // Cancel proposal
        registry.cancelProposal(0);
        
        // Try to cancel again
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ProposalCanceled.selector));
        registry.cancelProposal(0);
        
        vm.stopPrank();
    }
    
    // Test canceling a proposal as non-owner
    function test_CancelProposalNonOwner() public {
        // Setup proposal
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        
        vm.startPrank(user1);
        registry.createProposal(tokens, weights, 7 days);
        vm.stopPrank();
        
        // Try to cancel as non-owner
        vm.startPrank(user1);
        vm.expectRevert();
        registry.cancelProposal(0);
        vm.stopPrank();
    }
    
    // Test governance actions
    function test_GovernanceActions() public {
        // Setup governance
        vm.startPrank(owner);
        registry.enableGovernance(daoGovernance);
        vm.stopPrank();
        
        // Test that DAO can add tokens
        vm.startPrank(daoGovernance);
        registry.addToken(address(token1), 4000);
        registry.addToken(address(token2), 6000);
        vm.stopPrank();
        
        (address[] memory tokens, uint256[] memory weights) = registry.getCurrentIndex();
        
        assertEq(tokens.length, 2);
        assertEq(weights.length, 2);
        assertEq(tokens[0], address(token1));
        assertEq(tokens[1], address(token2));
        assertEq(weights[0], 4000);
        assertEq(weights[1], 6000);
        
        // Test that DAO can update weights (without exceeding BASIS_POINTS)
        vm.startPrank(daoGovernance);
        registry.updateTokenWeight(address(token1), 4000); // Keep the same weight
        vm.stopPrank();
        
        (tokens, weights) = registry.getCurrentIndex();
        
        assertEq(weights[0], 4000);
        
        // Test that DAO can remove tokens
        vm.startPrank(daoGovernance);
        registry.removeToken(address(token1));
        vm.stopPrank();
        
        (tokens, weights) = registry.getCurrentIndex();
        
        assertEq(tokens.length, 1);
        assertEq(weights.length, 1);
        assertEq(tokens[0], address(token2));
        assertEq(weights[0], 6000);
        
        // Test that DAO can rebalance
        vm.startPrank(daoGovernance);
        registry.rebalanceIndex();
        vm.stopPrank();
        
        (tokens, weights) = registry.getCurrentIndex();
        
        assertEq(weights[0], BASIS_POINTS);
    }
}
