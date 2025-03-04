# Contributing to Web3 Index Fund

Thank you for your interest in contributing to the Web3 Index Fund project! This document provides guidelines and instructions for contributing to both the smart contracts and frontend components of the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Smart Contract Development](#smart-contract-development)
- [Frontend Development](#frontend-development)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally
3. Set up the development environment as described in the README.md
4. Create a new branch for your feature or bugfix
5. Make your changes
6. Submit a pull request

## Development Workflow

We follow a feature branch workflow:

1. Create a new branch for each feature or bugfix
2. Use descriptive branch names (e.g., `feature/add-token-support`, `fix/deposit-bug`)
3. Make regular commits with clear, concise messages
4. Keep pull requests focused on a single feature or bugfix
5. Rebase your branch on the latest main branch before submitting a PR

## Smart Contract Development

### Environment Setup

1. Install Foundry as described in the README.md
2. Run `forge install` to install dependencies
3. Run `forge build` to compile contracts
4. Run `forge test` to run the test suite

### Guidelines

- Follow the Solidity style guide
- Add comprehensive test coverage for new features
- Document functions and contracts using NatSpec comments
- Optimize for gas efficiency where possible
- Consider security implications of all changes

### Testing

- Write unit tests for all new functions
- Include integration tests for complex interactions
- Test edge cases and failure modes
- Run the full test suite before submitting a PR

## Frontend Development

### Environment Setup

1. Navigate to the `frontend` directory
2. Run `npm install` to install dependencies
3. Copy `.env.example` to `.env.local` and configure as needed
4. Run `npm start` to start the development server

### Guidelines

- Follow the React/TypeScript best practices
- Use the existing component structure and styling patterns
- Add appropriate error handling
- Make the UI responsive for different screen sizes
- Document complex components and functions

### Testing

- Write unit tests for components and hooks
- Test different user roles and workflows
- Ensure compatibility with major browsers
- Verify wallet connection and transaction handling

## Pull Request Process

1. Update the README.md with details of changes if applicable
2. Update documentation as needed
3. The PR should work in all supported environments
4. Ensure all tests pass
5. Request review from at least one maintainer
6. Address all review comments and requested changes
7. Once approved, a maintainer will merge your PR

## Coding Standards

### Solidity

- Use Solidity version ^0.8.20
- Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/v0.8.20/style-guide.html)
- Use descriptive variable and function names
- Add NatSpec comments for all public and external functions
- Use SafeMath or Solidity 0.8+ built-in overflow protection
- Follow the checks-effects-interactions pattern

### TypeScript/React

- Use TypeScript for type safety
- Follow the [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
- Use functional components with hooks
- Use descriptive variable and function names
- Add JSDoc comments for complex functions
- Follow the React component composition pattern

## Testing Guidelines

- Aim for high test coverage (>90% for smart contracts)
- Test both success and failure cases
- Mock external dependencies when appropriate
- Use descriptive test names that explain what is being tested
- Organize tests logically by feature or component

## Documentation

- Keep README.md up to date
- Document all public interfaces
- Add inline comments for complex logic
- Create or update diagrams for architecture changes
- Document environment variables and configuration options

Thank you for contributing to the Web3 Index Fund project!
