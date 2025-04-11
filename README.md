# MYTHO Ecosystem

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Solidity Version](https://img.shields.io/badge/Solidity-^0.8.28-brightgreen.svg)](https://soliditylang.org/)
[![Tests](https://img.shields.io/badge/Tests-Foundry-orange.svg)](https://book.getfoundry.sh/)

## Overview

The **MYTHO Ecosystem** is a decentralized platform built on Soneium that integrates a governance token (MYTHO) with a totem-based merit system. It enables the creation, sale, and management of totems, rewarding participants with MYTHO tokens based on merit points. The ecosystem is designed with upgradable smart contracts to ensure flexibility, security, and scalability.

The platform features cross-chain functionality via Chainlink's CCIP (Cross-Chain Interoperability Protocol), allowing the MYTHO token to operate seamlessly across multiple blockchains, including Ethereum, Soneium, and Astar networks.

### Key Features

- **MYTHO Token**: ERC20 governance token with a fixed supply of 1 billion tokens, distributed via vesting schedules for totems, team, treasury, AMM incentives, and airdrops.
- **Merit System**: Users earn merit points for their totems, which are boosted during special "Mythus" periods, and can claim MYTHO rewards based on accumulated merit.
- **Totem Creation**: Supports creation of totems with either new tokens or existing whitelisted tokens, with registration after full sale for non-custom tokens.
- **Token Sales**: Users can buy and sell `TotemToken` during the sale period, with liquidity automatically added to UniswapV2-type pool after the sale concludes.
- **Cross-Chain Functionality**: MYTHO tokens can be transferred between supported blockchains using Chainlink's CCIP, with specialized implementations for each chain (standard MYTHO on native chain, BurnMintMYTHO on non-native chains).
- **Security**: Leverages OpenZeppelin libraries for access control, safe transfers, reentrancy protection, and upgradability patterns.

## Architecture

The MYTHO ecosystem consists of several interconnected smart contracts that work together to provide a comprehensive platform for totem creation, token sales, merit management, and cross-chain operations.

### Core Contracts

| Contract                  | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `MYTHO.sol`              | ERC20 governance token with vesting schedules for various allocations. Implements pausable functionality and ecosystem-wide pause checks. |
| `MeritManager.sol`       | Manages merit points for registered totems and distributes MYTHO tokens based on accumulated merit. Includes features for boosting, period management, and blacklisting. |
| `TotemFactory.sol`       | Creates new totems with either new or existing whitelisted tokens. Handles totem registration and fee collection. |
| `TotemTokenDistributor.sol` | Manages token sales, distribution of collected payment tokens, adding liquidity to AMM pools, and closing sale periods. Uses Chainlink price feeds for token pricing. |
| `Totem.sol`              | Represents individual totems, managing token burning and MYTHO claims.
| `TotemToken.sol`         | ERC20 token for totems with sale period restrictions on transfers. Implements burnable functionality for non-custom tokens. |
| `Treasury.sol`           | Manages and withdraws ERC20 and native tokens accumulated in the ecosystem. |
| `AddressRegistry.sol`    | Central registry for storing and retrieving contract addresses, enabling upgradable architecture and ecosystem-wide pause functionality. |

### Cross-Chain Contracts

| Contract                  | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `BurnMintMYTHO.sol`      | Implementation of MYTHO token for non-native chains. Supports burning and minting for cross-chain transfers via CCIP's BurnMintTokenPool. |

## Detailed Functionality

### MYTHO Token Distribution

The MYTHO token has a fixed supply of 1 billion tokens, distributed as follows:

- **Totem Incentives (50%)**: 500 million tokens distributed over 4 years
  - Year 1: 200 million tokens (40% of incentives)
  - Year 2: 150 million tokens (30% of incentives)
  - Year 3: 100 million tokens (20% of incentives)
  - Year 4: 50 million tokens (10% of incentives)
- **Team Allocation (20%)**: 200 million tokens with 2-year vesting
- **Treasury (23%)**: 230 million tokens for ecosystem development and operations
- **AMM Incentives (7%)**: 70 million tokens with 2-year vesting for liquidity incentives

### Merit System

The merit system is a core component of the MYTHO ecosystem, rewarding totem holders for their participation:

- **Merit Points**: Earned by totems through various activities and user interactions
- **Mythus Periods**: Special periods where merit points earned are multiplied (default: 1.5x)
- **Boosting**: Users holding totem tokens can boost their totems by paying a fee in native tokens during Mythus periods
- **Rewards Distribution**: MYTHO tokens are distributed to totems proportionally based on their merit points in each period
- **Blacklisting**: Totems can be blacklisted to prevent them from earning or claiming rewards

### Totem Creation and Token Sales

The process of creating and selling totems involves several steps:

1. **Totem Creation**: Users can create totems through the TotemFactory, either with a new token or an existing whitelisted token
2. **Sale Period**: During the sale period, users can buy and sell totem tokens through the TotemTokenDistributor
3. **Sale Closure**: When all available tokens are sold (excluding those reserved for liquidity), the sale period ends
4. **Liquidity Addition**: A portion of the collected payment tokens and totem tokens are added to a UniswapV2-type liquidity pool
5. **Distribution**: Collected payment tokens are distributed according to predefined shares:
   - Revenue share (treasury): 2.5%
   - Creator share: 0.5%
   - Pool share (liquidity): 28.57%
   - Vault share (totem contract): 68.43%
6. **Token Burning**: After the sale period, totem token holders can burn their tokens to receive proportional shares of payment tokens, MYTHO tokens, and LP tokens

### Cross-Chain Functionality

The MYTHO ecosystem supports cross-chain operations using Chainlink's CCIP:

- **Native Chain**: Uses the standard MYTHO token with LockReleaseTokenPool for CCIP integration
- **Non-Native Chains**: Uses BurnMintMYTHO with BurnMintTokenPool for CCIP integration
- **Token Transfer**: Users can transfer MYTHO tokens between supported chains by:
  1. Approving the token for the source chain's token pool
  2. Initiating a transfer through the CCIP router
  3. Receiving tokens on the destination chain through minting (for non-native chains) or release (for native chain)
- **Security**: Implements access control for minting and burning operations, with only authorized CCIP pools able to mint or burn tokens

## Security Features

The MYTHO ecosystem implements several security features:

- **Access Control**: Uses OpenZeppelin's AccessControl for role-based permissions
- **Reentrancy Protection**: Implements ReentrancyGuard to prevent reentrancy attacks
- **Pausable Functionality**: All contracts can be paused in emergency situations
- **Ecosystem-Wide Pause**: AddressRegistry provides a central mechanism to pause the entire ecosystem
- **Safe Transfers**: Uses SafeERC20 for token transfers to prevent common vulnerabilities
- **Upgradability**: Implements the upgradable pattern for all core contracts to allow for future improvements
- **Rate Limiting**: Cross-chain transfers can be rate-limited to prevent abuse
- **Slippage Protection**: Implements slippage protection for liquidity addition

## Project Structure

```bash
mytho/
├── src/                    # Smart contracts
│   ├── AddressRegistry.sol
│   ├── BurnMintMYTHO.sol
│   ├── MeritManager.sol
│   ├── MYTHO.sol
│   ├── Totem.sol
│   ├── TotemFactory.sol
│   ├── TotemToken.sol
│   ├── TotemTokenDistributor.sol
│   ├── Treasury.sol
│   └── interfaces/         # Interface definitions
├── test/                   # Test files
│   ├── AccessManaged.t.sol
│   ├── Beacon.t.sol
│   ├── CCIPTest.t.sol
│   ├── Complex.t.sol
│   ├── Mytho.t.sol
│   ├── OFT.t.sol
│   ├── Vesting.t.sol
│   ├── mocks/              # Mock contracts for testing
│   └── util/               # Testing utilities
├── script/                 # Deployment scripts
│   ├── CombineContracts.s.sol
│   ├── CrosschainTransfer.s.sol
│   ├── Deploy.s.sol
│   ├── Do.s.sol
│   ├── DoOftSending.s.sol
│   ├── MythoCcipSetup.s.sol
│   ├── UpgradeMeritManager.s.sol
│   ├── UpgradeTotem.s.sol
│   ├── UpgradeTotemFactory.s.sol
│   └── UpgradeTotemTokenDistributor.s.sol
├── combined/               # Combined contracts for verification
├── flattened/              # Flattened contracts for verification
├── foundry.toml            # Foundry configuration
└── README.md               # This file
```

## Installation and Setup

### Prerequisites

- [Node.js](https://nodejs.org/) (v16+ recommended)
- [Foundry](https://book.getfoundry.sh/) (Forge for testing and deployment)
- [Git](https://git-scm.com/)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/mytho-io/smart-contracts.git
   cd mytho
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Compile the contracts:
   ```bash
   forge build
   ```

### Testing

Run the test suite:
```bash
forge test
```

For more verbose output:
```bash
forge test -vvv
```

### Deployment

The project includes several deployment scripts in the `script/` directory:

- `Deploy.s.sol`: Deploys the core contracts
- `MythoCcipSetup.s.sol`: Sets up cross-chain functionality with CCIP
- `CrosschainTransfer.s.sol`: Script for testing cross-chain transfers
- Various upgrade scripts for upgrading individual contracts

To deploy the contracts:
```bash
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

## Cross-Chain Configuration

To set up cross-chain functionality:

1. Deploy MYTHO on the native chain and BurnMintMYTHO on non-native chains
2. Set up token pools (LockReleaseTokenPool for native chain, BurnMintTokenPool for non-native chains)
3. Configure CCIP routers and chain selectors
4. Grant minting and burning permissions to the token pools
5. Set up remote pool configurations

For detailed steps, refer to the `MythoCcipSetup.s.sol` script.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
