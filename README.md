# MYTHO Ecosystem

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)](https://spdx.org/licenses/BUSL-1.1.html)
[![Solidity Version](https://img.shields.io/badge/Solidity-^0.8.28-brightgreen.svg)](https://soliditylang.org/)
[![Tests](https://img.shields.io/badge/Tests-Foundry-orange.svg)](https://book.getfoundry.sh/)

## Overview

The **MYTHO Ecosystem** is a decentralized platform built on Soneium that integrates a governance token (MYTHO) with a totem-based merit system. It enables the creation, sale, and management of totems, rewarding participants with MYTHO tokens based on merit points. The ecosystem is designed with upgradable smart contracts to ensure flexibility, security, and scalability.

The platform features cross-chain functionality via Chainlink's CCIP (Cross-Chain Interoperability Protocol), allowing the MYTHO token to operate seamlessly across multiple blockchains, including Ethereum, Soneium, and Astar networks.

### Key Features

- **MYTHO Token**: ERC20 governance token with a fixed supply cap of 1 billion tokens, featuring mint-on-demand distribution with supply cap enforcement to support cross-chain burn/mint mechanisms.
- **Merit System**: Users earn merit points for their totems, which are boosted during special "Mythus" periods, and can claim MYTHO rewards based on accumulated merit.
- **Totem Creation**: Supports creation of totems with either new tokens or existing whitelisted tokens, with registration after full sale for non-custom tokens.
- **Token Sales**: Users can buy and sell `TotemToken` during the sale period, with liquidity automatically added to UniswapV2-type pool after the sale concludes.
- **Cross-Chain Functionality**: MYTHO tokens can be transferred between supported blockchains using Chainlink's CCIP, with specialized implementations for each chain (standard MYTHO on native chain, BurnMintMYTHO on non-native chains).
- **Role-Based Access Control**: Implements comprehensive role-based permissions using OpenZeppelin's AccessControl for secure operations.
- **Security**: Leverages OpenZeppelin libraries for access control, safe transfers, reentrancy protection, and upgradability patterns.

## Architecture

The MYTHO ecosystem consists of several interconnected smart contracts that work together to provide a comprehensive platform for totem creation, token sales, merit management, and cross-chain operations.

### Core Contracts

| Contract                  | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `MYTHO.sol`              | ERC20 governance token with mint-on-demand distribution and role-based access control. Features supply cap enforcement, vesting creation functionality, and ecosystem-wide pause checks. |
| `MeritManager.sol`       | Manages merit points for registered totems and distributes MYTHO tokens based on accumulated merit. Includes features for boosting, period management, and blacklisting. |
| `TotemFactory.sol`       | Creates new totems with either new or existing whitelisted tokens. Handles totem registration and fee collection. |
| `TotemTokenDistributor.sol` | Manages token sales, distribution of collected payment tokens, adding liquidity to AMM pools, and closing sale periods. Uses Chainlink price feeds for token pricing. |
| `Totem.sol`              | Represents individual totems, managing token burning and MYTHO claims. |
| `TotemToken.sol`         | ERC20 token for totems with sale period restrictions on transfers. Implements burnable functionality for non-custom tokens. |
| `Treasury.sol`           | Manages and withdraws ERC20 and native tokens accumulated in the ecosystem. |
| `AddressRegistry.sol`    | Central registry for storing and retrieving contract addresses, enabling upgradable architecture and ecosystem-wide pause functionality. |

### Cross-Chain Contracts

| Contract                  | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `BurnMintMYTHO.sol`      | Implementation of MYTHO token for non-native chains. Supports burning and minting for cross-chain transfers via CCIP's BurnMintTokenPool. |

## Detailed Functionality

### MYTHO Token Distribution

The MYTHO token has a fixed supply cap of 1 billion tokens with mint-on-demand distribution. The complete allocation plan is as follows:

#### Planned Distribution Breakdown

**MeritManager (Totem Incentives)**: **2%** = **20,000,000 MYTHO**
- Vested over 4 years (implemented at deployment):
  - Year 1: 8,000,000 MYTHO (40% of 20M)
  - Year 2: 6,000,000 MYTHO (30% of 20M)
  - Year 3: 4,000,000 MYTHO (20% of 20M)
  - Year 4: 2,000,000 MYTHO (10% of 20M)

**Soneium & Cross-Chain Rewards**: **48%** = **480,000,000 MYTHO**
- Managed via governance system with timelock and multi-sig security
- Distributed for ecosystem growth and cross-chain incentives
- Released through governance-approved vesting schedules

**Team Allocation**: **20%** = **200,000,000 MYTHO**
- Vested over 2 years
- Distributed to core team members and advisors
- Created via `createVesting` function by MULTISIG role

**Treasury Allocation**: **23%** = **230,000,000 MYTHO**
- Used for ecosystem development and operations
- Managed by treasury governance
- Flexible distribution based on ecosystem needs

**AMM Incentives**: **7%** = **70,000,000 MYTHO**
- Vested over 2 years
- Used for liquidity mining and AMM rewards
- Supports decentralized trading ecosystem

#### Current Implementation Status

**✅ Deployed at Launch (2%):**
- **Merit Incentives**: 20 million tokens distributed through vesting wallets
- Vesting starts from deployment timestamp
- Tokens automatically released according to schedule

**🔄 On-Demand Distribution (98%):**
- **Remaining Supply**: 980 million tokens available for distribution
- Created through `createVesting` function by MULTISIG role
- Subject to governance approval and timelock mechanisms
- Supply cap protection ensures global 1 billion token limit

#### Distribution Mechanism

**Mint-on-Demand Architecture:**
- **Supply Cap Protection**: Total minted amount tracked to ensure 1B token cap across all chains
- **Cross-Chain Safe**: Accounts for burn/mint bridging mechanisms while maintaining supply cap
- **Governance Security**: Large allocations managed via timelock and multi-sig for security
- **Flexible Vesting**: Custom vesting schedules can be created for different allocation purposes

#### Role-Based Access Control
- **MANAGER Role**: Can pause/unpause token transfers
- **MULTISIG Role**: Can create new vesting schedules and mint tokens (subject to supply cap)
- **DEFAULT_ADMIN_ROLE**: Can manage all roles and permissions
- **Governance System**: Future implementation for managing large allocations with timelock security

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
- **Supply Cap Management**: The native chain tracks total minted amount to maintain global supply cap across all chains
- **Token Transfer**: Users can transfer MYTHO tokens between supported chains by:
  1. Approving the token for the source chain's token pool
  2. Initiating a transfer through the CCIP router
  3. Receiving tokens on the destination chain through minting (for non-native chains) or release (for native chain)
- **Security**: Implements access control for minting and burning operations, with only authorized CCIP pools able to mint or burn tokens

## Security Features

The MYTHO ecosystem implements several security features:

- **Role-Based Access Control**: Uses OpenZeppelin's AccessControl for granular role-based permissions
- **Supply Cap Enforcement**: Tracks total minted amount to prevent exceeding 1 billion token global cap
- **Pausable Functionality**: MANAGER role can pause contracts in emergency situations
- **Ecosystem-Wide Pause**: AddressRegistry provides a central mechanism to pause the entire ecosystem
- **Safe Transfers**: Uses SafeERC20 for token transfers to prevent common vulnerabilities
- **Upgradability**: Implements the upgradable pattern for all core contracts to allow for future improvements
- **Cross-Chain Safety**: Mint-on-demand design prevents supply inflation during cross-chain operations

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
│   ├── interfaces/         # Interface definitions
│   └── utils/              # Utility contracts and libraries
├── test/                   # Test files
│   ├── Mytho.t.sol        # Core MYTHO token tests
│   ├── AccessManaged.t.sol # Access control tests
│   ├── Beacon.t.sol       # Upgradability tests
│   ├── CCIPTest.t.sol     # Cross-chain functionality tests
│   ├── Complex.t.sol      # Integration tests
│   ├── OFT.t.sol          # Cross-chain token tests
│   ├── Vesting.t.sol      # Vesting functionality tests
│   └── util/              # Testing utilities
├── script/                 # Deployment and management scripts
│   ├── Deploy.s.sol       # Main deployment script
│   ├── MythoCcipSetup.s.sol # Cross-chain setup
│   ├── CrosschainTransfer.s.sol # Cross-chain transfer testing
│   └── Upgrade*.s.sol     # Various upgrade scripts
├── combined/               # Combined contracts for verification
├── foundry.toml           # Foundry configuration
└── README.md              # This file
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

Run specific tests:
```bash
forge test --match-contract MythoTest
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

### Environment Variables

Create a `.env` file with the following variables:
```bash
PRIVATE_KEY=your_deployment_private_key
RPC_URL=your_rpc_endpoint
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## Cross-Chain Configuration

To set up cross-chain functionality:

1. Deploy MYTHO on the native chain and BurnMintMYTHO on non-native chains
2. Set up token pools (LockReleaseTokenPool for native chain, BurnMintTokenPool for non-native chains)
3. Configure CCIP routers and chain selectors
4. Grant minting and burning permissions to the token pools
5. Set up remote pool configurations

For detailed steps, refer to the `MythoCcipSetup.s.sol` script.

## Smart Contract Interactions

### Key Functions

#### MYTHO Contract
- `createVesting(beneficiary, amount, startTime, duration)`: Create new vesting schedule (MULTISIG role)
- `pause()` / `unpause()`: Emergency pause functionality (MANAGER role)
- `totalMinted()`: View total tokens ever minted across all operations

#### AddressRegistry Contract
- `setEcosystemPaused(bool)`: Pause entire ecosystem (MANAGER role)
- `getAddress(bytes32)`: Retrieve contract addresses by identifier

### Role Management
```solidity
// Grant roles (DEFAULT_ADMIN_ROLE required)
mytho.grantRole(MANAGER, managerAddress);
mytho.grantRole(MULTISIG, multisigAddress);

// Check roles
bool isManager = mytho.hasRole(MANAGER, address);
```

## License

This project is licensed under the Business Source License 1.1 (BUSL-1.1) - see the [LICENSE](LICENSE) file for details.

### License Summary

- **License Type**: Business Source License 1.1 (BUSL-1.1)
- **Copyright**: © 2025 Mytho. All Rights Reserved.
- **Change Date**: May 1, 2027
- **Change License**: MIT License
- **Additional Use Grant**: None

The BUSL-1.1 license allows for non-production use of the code until the Change Date (May 1, 2027), after which the code will be available under the MIT License. For production use before the Change Date, please contact igporoshin@gmail.com to obtain a commercial license.

## Support

For technical support, questions, or commercial licensing inquiries, please contact:
- Email: igporoshin@gmail.com
- GitHub: [Create an issue](https://github.com/mytho-io/smart-contracts/issues)

## Security

If you discover a security vulnerability, please send an email to igporoshin@gmail.com. All security vulnerabilities will be promptly addressed.
