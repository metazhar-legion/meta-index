// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";

/**
 * @title IndexRegistry
 * @dev Registry for managing index compositions
 * The registry maintains the list of tokens and their weights in the index
 * Initially managed by the owner, but can be transitioned to DAO governance
 */
contract IndexRegistry is IIndexRegistry, Ownable {
    // Index composition
    address[] public indexTokens;
    mapping(address => uint256) public tokenWeights;
    mapping(address => bool) public isTokenInIndex;
    
    // Total weight must equal BASIS_POINTS
    uint256 public constant BASIS_POINTS = 10000;
    
    // DAO governance
    address public daoGovernance;
    bool public isGovernanceEnabled;
    
    // Proposal system
    struct IndexProposal {
        address[] tokens;
        uint256[] weights;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        bool canceled;
    }
    
    IndexProposal[] public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    // Events
    event TokenAdded(address indexed token, uint256 weight);
    event TokenRemoved(address indexed token);
    event TokenWeightUpdated(address indexed token, uint256 newWeight);
    event IndexRebalanced();
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer);
    event ProposalVote(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event GovernanceEnabled(address indexed daoAddress);
    event GovernanceDisabled();

    /**
     * @dev Constructor that initializes the registry
     */
    constructor() Ownable(msg.sender) {
        isGovernanceEnabled = false;
    }

    /**
     * @dev Adds a token to the index with a specified weight
     * @param token The token address
     * @param weight The token weight in basis points
     */
    function addToken(address token, uint256 weight) external onlyOwnerOrGovernance {
        require(token != address(0), "Invalid token address");
        require(!isTokenInIndex[token], "Token already in index");
        require(weight > 0, "Weight must be positive");
        
        // Check that total weight doesn't exceed BASIS_POINTS
        uint256 totalWeight = getTotalWeight();
        require(totalWeight + weight <= BASIS_POINTS, "Total weight exceeds 100%");
        
        indexTokens.push(token);
        tokenWeights[token] = weight;
        isTokenInIndex[token] = true;
        
        emit TokenAdded(token, weight);
    }

    /**
     * @dev Removes a token from the index
     * @param token The token address
     */
    function removeToken(address token) external onlyOwnerOrGovernance {
        require(isTokenInIndex[token], "Token not in index");
        
        // Find and remove the token from the array
        for (uint256 i = 0; i < indexTokens.length; i++) {
            if (indexTokens[i] == token) {
                // Move the last element to the position of the removed token
                indexTokens[i] = indexTokens[indexTokens.length - 1];
                // Remove the last element
                indexTokens.pop();
                break;
            }
        }
        
        // Clear the weight and flag
        delete tokenWeights[token];
        isTokenInIndex[token] = false;
        
        emit TokenRemoved(token);
    }

    /**
     * @dev Updates the weight of a token in the index
     * @param token The token address
     * @param newWeight The new weight in basis points
     */
    function updateTokenWeight(address token, uint256 newWeight) external onlyOwnerOrGovernance {
        require(isTokenInIndex[token], "Token not in index");
        require(newWeight > 0, "Weight must be positive");
        
        // Calculate the total weight without this token
        uint256 totalWeight = getTotalWeight() - tokenWeights[token];
        require(totalWeight + newWeight <= BASIS_POINTS, "Total weight exceeds 100%");
        
        tokenWeights[token] = newWeight;
        
        emit TokenWeightUpdated(token, newWeight);
    }

    /**
     * @dev Rebalances the index by normalizing all weights to sum up to BASIS_POINTS
     */
    function rebalanceIndex() external onlyOwnerOrGovernance {
        uint256 totalWeight = getTotalWeight();
        require(totalWeight > 0, "No tokens in index");
        
        if (totalWeight != BASIS_POINTS) {
            // Normalize weights
            for (uint256 i = 0; i < indexTokens.length; i++) {
                address token = indexTokens[i];
                uint256 normalizedWeight = (tokenWeights[token] * BASIS_POINTS) / totalWeight;
                tokenWeights[token] = normalizedWeight;
            }
        }
        
        emit IndexRebalanced();
    }

    /**
     * @dev Gets the total weight of all tokens in the index
     * @return The total weight in basis points
     */
    function getTotalWeight() public view returns (uint256) {
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < indexTokens.length; i++) {
            totalWeight += tokenWeights[indexTokens[i]];
        }
        return totalWeight;
    }

    /**
     * @dev Gets the current index composition
     * @return tokens Array of token addresses
     * @return weights Array of token weights in basis points
     */
    function getCurrentIndex() external view override returns (address[] memory tokens, uint256[] memory weights) {
        tokens = new address[](indexTokens.length);
        weights = new uint256[](indexTokens.length);
        
        for (uint256 i = 0; i < indexTokens.length; i++) {
            tokens[i] = indexTokens[i];
            weights[i] = tokenWeights[indexTokens[i]];
        }
        
        return (tokens, weights);
    }

    /**
     * @dev Gets the number of tokens in the index
     * @return The number of tokens
     */
    function getIndexSize() external view returns (uint256) {
        return indexTokens.length;
    }

    /**
     * @dev Enables DAO governance
     * @param daoAddress The address of the DAO governance contract
     */
    function enableGovernance(address daoAddress) external onlyOwner {
        require(daoAddress != address(0), "Invalid DAO address");
        daoGovernance = daoAddress;
        isGovernanceEnabled = true;
        
        emit GovernanceEnabled(daoAddress);
    }

    /**
     * @dev Disables DAO governance
     */
    function disableGovernance() external onlyOwner {
        isGovernanceEnabled = false;
        
        emit GovernanceDisabled();
    }

    /**
     * @dev Creates a new index proposal
     * @param tokens The proposed token addresses
     * @param weights The proposed token weights
     * @param votingPeriod The voting period in seconds
     */
    function createProposal(
        address[] calldata tokens,
        uint256[] calldata weights,
        uint256 votingPeriod
    ) external {
        require(isGovernanceEnabled, "Governance not enabled");
        require(tokens.length > 0, "Empty proposal");
        require(tokens.length == weights.length, "Mismatched arrays");
        require(votingPeriod >= 1 days, "Voting period too short");
        
        // Check that weights sum up to BASIS_POINTS
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            require(weights[i] > 0, "Weight must be positive");
            totalWeight += weights[i];
        }
        require(totalWeight == BASIS_POINTS, "Weights must sum to 100%");
        
        // Create the proposal
        proposals.push(IndexProposal({
            tokens: tokens,
            weights: weights,
            votesFor: 0,
            votesAgainst: 0,
            endTime: block.timestamp + votingPeriod,
            executed: false,
            canceled: false
        }));
        
        emit ProposalCreated(proposals.length - 1, msg.sender);
    }

    /**
     * @dev Votes on a proposal
     * @param proposalId The ID of the proposal
     * @param support Whether to support the proposal
     */
    function vote(uint256 proposalId, bool support) external {
        require(isGovernanceEnabled, "Governance not enabled");
        require(proposalId < proposals.length, "Invalid proposal ID");
        
        IndexProposal storage proposal = proposals[proposalId];
        
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal canceled");
        require(block.timestamp < proposal.endTime, "Voting period ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        
        // In a real implementation, this would check the voter's voting power
        // based on their token holdings or other governance mechanism
        uint256 votingPower = 1; // Placeholder
        
        if (support) {
            proposal.votesFor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }
        
        hasVoted[proposalId][msg.sender] = true;
        
        emit ProposalVote(proposalId, msg.sender, support);
    }

    /**
     * @dev Executes a proposal if it has passed
     * @param proposalId The ID of the proposal
     */
    function executeProposal(uint256 proposalId) external {
        require(isGovernanceEnabled, "Governance not enabled");
        require(proposalId < proposals.length, "Invalid proposal ID");
        
        IndexProposal storage proposal = proposals[proposalId];
        
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal canceled");
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal did not pass");
        
        // Clear the current index
        for (uint256 i = 0; i < indexTokens.length; i++) {
            isTokenInIndex[indexTokens[i]] = false;
            delete tokenWeights[indexTokens[i]];
        }
        delete indexTokens;
        
        // Set the new index
        for (uint256 i = 0; i < proposal.tokens.length; i++) {
            address token = proposal.tokens[i];
            uint256 weight = proposal.weights[i];
            
            indexTokens.push(token);
            tokenWeights[token] = weight;
            isTokenInIndex[token] = true;
        }
        
        proposal.executed = true;
        
        emit ProposalExecuted(proposalId);
        emit IndexRebalanced();
    }

    /**
     * @dev Cancels a proposal
     * @param proposalId The ID of the proposal
     */
    function cancelProposal(uint256 proposalId) external onlyOwner {
        require(proposalId < proposals.length, "Invalid proposal ID");
        
        IndexProposal storage proposal = proposals[proposalId];
        
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal already canceled");
        
        proposal.canceled = true;
        
        emit ProposalCanceled(proposalId);
    }

    /**
     * @dev Modifier that allows only the owner or the DAO governance to call a function
     */
    modifier onlyOwnerOrGovernance() {
        require(
            msg.sender == owner() || 
            (isGovernanceEnabled && msg.sender == daoGovernance),
            "Not authorized"
        );
        _;
    }
}
