# MYTHO: Decentralized Content Creation & Engagement Ecosystem

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)](https://spdx.org/licenses/BUSL-1.1.html)
[![Solidity Version](https://img.shields.io/badge/Solidity-^0.8.28-brightgreen.svg)](https://soliditylang.org/)
[![Tests](https://img.shields.io/badge/Tests-Foundry-orange.svg)](https://book.getfoundry.sh/)
[![Forge Version](https://img.shields.io/badge/Forge-0.2.0-blue.svg)](https://book.getfoundry.sh/)

## Overview

MYTHO is a comprehensive decentralized platform that revolutionizes content creation through **Totems** (content collections), **Layers** (individual content pieces as NFTs), and a sophisticated reward system powered by **SHARD** tokens. The ecosystem incentivizes quality content creation, community engagement, and long-term participation through gamified mechanics including streak systems, NFT badges, and merit-based rewards.

## Core Architecture

### Smart Contracts

#### Core Tokens
- **MYTHO Token** (`MYTHO.sol`) - Main governance token with 1B total supply and vesting schedules
- **SHARD Token** (`Shards.sol`) - Reward token for engagement activities (mintable, burnable, pausable)
- **Totem Tokens** (`TotemToken.sol`) - Individual ERC20 tokens for each content collection
- **Badge NFTs** (`BadgeNFT.sol`) - Achievement NFTs for milestone rewards

#### Content & Engagement
- **Totems** (`Totem.sol`) - Content collections with token economics and merit tracking
- **Layers** (`Layers.sol`) - Individual content pieces as ERC721 NFTs with royalties
- **Boost System** (`BoostSystem.sol`) - Gamified engagement with streaks, grace days, and VRF integration
- **Merit Manager** (`MeritManager.sol`) - Merit point distribution and period management

#### Infrastructure
- **Totem Factory** (`TotemFactory.sol`) - Factory for creating new Totems
- **Address Registry** (`AddressRegistry.sol`) - Centralized contract address management
- **Treasury** (`Treasury.sol`) - Protocol treasury management
- **Token Distributor** (`TotemTokenDistributor.sol`) - Token distribution and pricing logic

## Key Features

### 🎨 Content Creation System
- **Totems**: Content collections that can use standard or custom ERC20/ERC721 tokens
- **Layers**: Individual content pieces minted as NFTs with built-in royalty system
- **Verification**: Multi-tier approval system for content quality control
- **Metadata**: IPFS-based content storage with hash validation

### 💎 SHARD Reward Economy
- **Earning Mechanisms**: Layer creation, boosting activities, and engagement rewards
- **Distribution Formula**: Dynamic reward calculation based on participation and token holdings
- **Utility**: Used for badges, staking boosts, and ecosystem privileges
- **Tokenomics**: Transferable, burnable ERC20 with controlled minting

### 🚀 Boost & Streak System
- **Daily Boosts**: Free daily engagement with streak multipliers
- **Premium Boosts**: Paid boosts with signature verification
- **Grace Days**: Streak protection system (3-7 days based on streak length)
- **NFT Badges**: Milestone achievements (7, 30, 60, 365+ day streaks)
- **VRF Integration**: Chainlink VRF for randomized rewards

### 📊 Merit & Ranking System
- **Merit Points**: Earned through layer publication and engagement
- **Period-based**: Time-bounded competition periods with rewards
- **Totem Rankings**: Merit-based ecosystem positioning
- **Reward Distribution**: Automated MYTHO token distribution to top performers

### 🔧 Advanced Features
- **Cross-chain Support**: LayerZero v2 integration for multi-chain operations
- **Upgradeable Contracts**: OpenZeppelin proxy pattern for future improvements
- **Pause Mechanisms**: Emergency controls and ecosystem-wide pause functionality
- **Access Control**: Role-based permissions with multi-signature support
- **Oracle Integration**: Token holder verification and price feeds

## Token Economics

### MYTHO Token Distribution (1B Total Supply)
- **Merit Rewards (50%)**: 500M tokens distributed over 4 years
  - Year 1: 200M (40% of incentives)
  - Year 2: 150M (30% of incentives)  
  - Year 3: 100M (20% of incentives)
  - Year 4: 50M (10% of incentives)
- **Treasury (23%)**: 230M tokens for ecosystem development
- **Team (20%)**: 200M tokens with vesting schedules
- **AMM Incentives (7%)**: 70M tokens for liquidity rewards

### SHARD Token Mechanics
- **Minting**: Controlled by authorized contracts (Layers, BoostSystem)
- **Burning**: Users can burn tokens for deflationary pressure
- **Distribution**: Formula-based rewards considering user participation and token holdings
- **Utility**: Badge purchases, boost multipliers, governance participation

## Development Setup

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (v0.2.0+)
- [Git](https://git-scm.com/) with submodule support
- Node.js (for additional tooling)

### Installation
```bash
# Clone repository with submodules
git clone --recursive https://github.com/mytho-labs/mytho-contracts.git
cd mytho-contracts

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Run specific test file
forge test --match-path test/BoostSystem.t.sol

# Generate gas report
forge test --gas-report
```

### Environment Setup
```bash
# Copy environment template
cp .env.example .env

# Configure RPC endpoints in .env
SEPOLIA_RPC_URL=your_sepolia_rpc
MAINNET_RPC_URL=your_mainnet_rpc
# ... other networks
```

## Testing

The project includes comprehensive test coverage across all major components:

- **Unit Tests**: Individual contract functionality
- **Integration Tests**: Cross-contract interactions  
- **Complex Scenarios**: Multi-user, multi-period edge cases
- **Access Control**: Permission and role-based security
- **Economic Models**: Token distribution and reward calculations

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Test specific functionality
forge test --match-test test_boost
forge test --match-test test_LayerCreation
forge test --match-test test_MeritManager
```

## Deployment

### Supported Networks
- Ethereum Mainnet
- Arbitrum
- Astar
- Soneium  
- Minato (Testnet)
- Sepolia (Testnet)
- Shibuya (Testnet)

### Deployment Scripts
```bash
# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast

# Upgrade contracts
forge script script/UpgradeLayers.s.sol --rpc-url mainnet --broadcast

# Verify contracts
forge verify-contract <contract_address> <contract_name> --chain-id 1
```

## Security

### Audit Status
- Smart contracts implement OpenZeppelin security standards
- Comprehensive access control with role-based permissions
- Reentrancy protection on all external calls
- Pause mechanisms for emergency situations

### Key Security Features
- **Upgradeable Proxies**: Secure upgrade patterns with timelock controls
- **Multi-signature**: Critical operations require multiple approvals
- **Rate Limiting**: Boost cooldowns and streak validation
- **Input Validation**: Comprehensive parameter checking and bounds validation

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for new functionality
4. Ensure all tests pass (`forge test`)
5. Commit changes (`git commit -m 'Add amazing feature'`)
6. Push to branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the Business Source License 1.1 (BUSL-1.1). See [LICENSE](LICENSE) file for details.

## Links

- **Documentation**: [Coming Soon]
- **Website**: [mytho.xyz](https://mytho.xyz)
- **Discord**: [Join Community](https://discord.gg/mytho)
- **Twitter**: [@MythoLabs](https://twitter.com/MythoLabs)