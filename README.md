# MYTHO

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Solidity Version](https://img.shields.io/badge/Solidity-^0.8.28-brightgreen.svg)](https://soliditylang.org/)
[![Tests](https://img.shields.io/badge/Tests-Foundry-orange.svg)](https://book.getfoundry.sh/)

## Overview

The **MYTHO Ecosystem** is a decentralized platform on Ethereum that integrates a governance token (MYTHO) with a totem-based merit system. It enables the creation, sale, and management of totems, rewarding participants with MYTHO tokens based on merit points. Built with upgradable smart contracts, it ensures flexibility, security, and scalability.

### Key Features

- **MYTHO Token**: 1 billion fixed supply, distributed via vesting for totems, team, treasury, AMM, and airdrops.
- **Merit System**: Earn merit points for totems, boosted during "Mythus" periods, and claim MYTHO rewards.
- **Totem Creation**: Supports new or existing tokens, with registration after full sale for non-custom tokens.
- **Token Sales**: Buy/sell `TotemToken` during sale, with liquidity added to Uniswap V2 post-sale.
- **Security**: Leverages OpenZeppelin for access control, safe transfers, and reentrancy protection.

## Contracts

| Contract                  | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `MYTHO.sol`              | ERC20 governance token with vesting schedules.                              |
| `MeritManager.sol`       | Manages merit points and MYTHO distribution.                                |
| `TotemFactory.sol`       | Creates totems with new or existing tokens.                                 |
| `TotemTokenDistributor.sol` | Handles token sales and liquidity provision.                              |
| `Totem.sol`              | Manages individual totems, burning, and MYTHO claims.                       |
| `TotemToken.sol`         | ERC20 token for totems with sale restrictions.                              |
| `Treasury.sol`           | Manages and withdraws ERC20 and native tokens.                              |
| `AddressRegistry.sol`    | Central registry for storing and retrieving contract addresses.             |

## Structure

```bash
mytho/
├── src/                    # Smart contracts
│   ├── AddressRegistry.sol
│   ├── MeritManager.sol
│   ├── MYTHO.sol
│   ├── Totem.sol
│   ├── TotemFactory.sol
│   ├── TotemToken.sol
│   ├── TotemTokenDistributor.sol
│   ├── Treasury.sol
│   └── interfaces/         # Interface definitions
├── test/                   # Test files
│   ├── Complex.t.sol
│   ├── mocks/              # Mock contracts for testing
│   └── util/               # Testing utilities
├── script/                 # Deployment scripts
│   ├── Deploy.s.sol
│   └── Do.s.sol
├── combined/               # Combined contracts for verification
├── foundry.toml            # Foundry configuration
└── README.md               # This file
```

## Installation

### Prerequisites

- [Node.js](https://nodejs.org/) (v16+ recommended)
- [Foundry](https://book.getfoundry.sh/) (Forge for testing and deployment)
- [Git](https://git-scm.com/)
