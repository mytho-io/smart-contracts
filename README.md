# MYTHO Ecosystem

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)](https://spdx.org/licenses/BUSL-1.1.html)
[![Solidity Version](https://img.shields.io/badge/Solidity-^0.8.28-brightgreen.svg)](https://soliditylang.org/)
[![Tests](https://img.shields.io/badge/Tests-Foundry-orange.svg)](https://book.getfoundry.sh/)
[![BNB Chain](https://img.shields.io/badge/Deployed%20on-BNB%20Chain-yellow.svg)](https://www.bnbchain.org/)

## Overview

The **MYTHO Ecosystem** is a comprehensive decentralized platform **deployed on BNB Smart Chain (BSC)** that combines governance tokens, community engagement, and content creation. The ecosystem centers around **totems** - community-driven tokens that users can create, trade, and engage with through various mechanisms.

### Core Concept
- **Totems**: Community tokens (BEP20/BEP721) that represent different communities or projects
- **Merit System**: Users earn merit points through engagement, which are converted to MYTHO token rewards
- **Community Posts**: Decentralized content platform where posts are NFTs that can be boosted and rewarded
- **Daily Engagement**: Streak-based boost system encouraging consistent participation with achievement badges

The platform is **natively deployed on BNB Smart Chain (BSC Mainnet, Chain ID: 56)** and leverages BNB Chain's infrastructure including:
- **Chainlink VRF on BSC** for secure randomness in premium boosts
- **Chainlink Price Feeds on BSC** for accurate token pricing
- **PancakeSwap V2** integration for liquidity pools
- **Cross-chain functionality** via Chainlink's CCIP for future expansion to other blockchains

### Latest Additions
The ecosystem has recently expanded with four major new contracts that enhance user engagement and create new reward mechanisms:
- **BoostSystem**: Daily engagement with streak rewards and VRF-powered premium boosts
- **Posts**: Community content platform with NFT posts and SHARD token rewards
- **BadgeNFT**: Achievement system with collectible milestone badges
- **Shards**: Dedicated reward token for the posts ecosystem

## Deployment on BNB Chain

**Network**: BNB Smart Chain (BSC)  
**Chain ID**: 56 (Mainnet)  
**Native Token**: BNB  
**Token Standards**: BEP20 (fungible tokens), BEP721 (NFTs)

### BNB Chain Infrastructure Integration

- **Chainlink VRF on BSC**: Used for provably fair random reward distribution in premium boosts
- **Chainlink Price Feeds on BSC**: Provides reliable BNB/USD and token price data for the ecosystem
- **PancakeSwap V2 Router**: Integrated for automated liquidity provision and token swaps
- **BNB as Native Currency**: All premium boosts, donations, and fees are paid in BNB

### Key Features

- **MYTHO Token**: BEP20 governance token with a fixed supply cap of 1 billion tokens, featuring mint-on-demand distribution with supply cap enforcement to support cross-chain burn/mint mechanisms.
- **Merit System**: Users earn merit points for their totems, which are boosted during special "Mythum" periods, and can claim MYTHO rewards based on accumulated merit.
- **Advanced Boost System**: Daily engagement mechanism with streak rewards, grace days, achievement badges, and Chainlink VRF-powered premium boosts with random reward distribution.
- **Community Posts Platform**: Decentralized content system where posts are BEP721 NFTs with boosting mechanics, SHARD token rewards, native token donations, and creator royalties.
- **Achievement Badges**: NFT-based milestone system rewarding consistent engagement with collectible badges for streak achievements (7, 14, 30, 100, 200 days).
- **SHARD Token Economy**: Dedicated BEP20 reward token for the posts ecosystem with mathematical formula-based distribution and ecosystem-wide controls.
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
| `MYTHO.sol`              | BEP20 governance token with mint-on-demand distribution and role-based access control. Features supply cap enforcement, vesting creation functionality, and ecosystem-wide pause checks. |
| `MeritManager.sol`       | Manages merit points for registered totems and distributes MYTHO tokens based on accumulated merit. Includes features for boosting, period management, and blacklisting. |
| `TotemFactory.sol`       | Creates new totems with either new or existing whitelisted tokens. Handles totem registration and fee collection. |
| `TotemTokenDistributor.sol` | Manages token sales, distribution of collected payment tokens, adding liquidity to PancakeSwap V2 pools on BSC, and closing sale periods. Uses Chainlink price feeds on BSC for token pricing. |
| `Totem.sol`              | Represents individual totems, managing token burning and MYTHO claims. |
| `TotemToken.sol`         | BEP20 token for totems with sale period restrictions on transfers. Implements burnable functionality for non-custom tokens. |
| `Treasury.sol`           | Manages and withdraws BEP20 and native tokens accumulated in the ecosystem. |
| `AddressRegistry.sol`    | Central registry for storing and retrieving contract addresses, enabling upgradable architecture and ecosystem-wide pause functionality. |

### New Ecosystem Features

| Contract                  | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `BoostSystem.sol`        | **Core boost functionality** with streak system, grace days, NFT badges, and Chainlink VRF integration on BSC. Implements daily free boosts and premium boosts (paid in BNB) with signature verification and milestone achievements. Features include streak multipliers (up to 30 days), grace day mechanics, and random reward distribution via Chainlink VRF V2.5 on BNB Chain. |
| `Posts.sol`              | **Community post management system** where posts are represented as BEP721 NFTs with royalty functionality. Supports post creation, approval workflows, boosting with totem tokens, reward distribution in SHARD tokens, and native token donations. Includes time-limited boost windows and shard reward calculations. |
| `BadgeNFT.sol`           | **Achievement badge system** that mints BEP721 NFTs for milestone achievements in the boost system. Supports milestone-based badge minting (7, 14, 30, 100, 200 day streaks) with customizable metadata URIs and user badge tracking. |
| `Shards.sol`             | **Reward token for posts ecosystem** - BEP20 token with minting, burning, and pause functionality. Minted by the Posts contract as rewards for post boosting and creator incentives. Features ecosystem-wide pause integration and role-based minting controls. |

### Cross-Chain Contracts

| Contract                  | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `BurnMintMYTHO.sol`      | Implementation of MYTHO token for non-native chains. Supports burning and minting for cross-chain transfers via CCIP's BurnMintTokenPool. |

## Detailed Functionality

### MYTHO Token Distribution

The MYTHO token has a fixed supply cap of 1 billion tokens with mint-on-demand distribution. The complete allocation plan is as follows:

#### Planned Distribution Breakdown

**MeritManager (Totem Incentives)**: **10%** = **100,000,000 MYTHO**
- Vested over 4 years (implemented at deployment):
  - Year 1: 40,000,000 MYTHO (40% of 100M)
  - Year 2: 30,000,000 MYTHO (30% of 100M)
  - Year 3: 20,000,000 MYTHO (20% of 100M)
  - Year 4: 10,000,000 MYTHO (10% of 100M)

**Ecosystem Growth & Cross-Chain Rewards**: **40%** = **400,000,000 MYTHO**
- Managed via governance system with timelock and multi-sig security
- Distributed for ecosystem growth, partnerships, and future cross-chain incentives
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
- Used for liquidity mining and PancakeSwap rewards on BSC
- Supports decentralized trading ecosystem on BNB Chain

#### Current Implementation Status

**✅ Deployed at Launch (10%):**
- **Merit Incentives**: 100 million tokens distributed through vesting wallets
- Vesting starts from deployment timestamp
- Tokens automatically released according to schedule

**🔄 On-Demand Distribution (90%):**
- **Remaining Supply**: 900 million tokens available for distribution
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
- **MANAGER Role**: Can pause/unpause token transfers and toggle transferability restrictions
- **MULTISIG Role**: Can create new vesting schedules and mint tokens (subject to supply cap)
- **TRANSFEROR Role**: Can transfer tokens even when transfers are restricted (granted to vesting wallets)
- **DEFAULT_ADMIN_ROLE**: Can manage all roles and permissions
- **Governance System**: Future implementation for managing large allocations with timelock security

### Merit System

The merit system is a core component of the MYTHO ecosystem, rewarding totem holders for their participation:

- **Merit Points**: Earned by totems through various activities and user interactions
- **Mythus Periods**: Special periods where merit points earned are multiplied (default: 1.5x)
- **Boosting**: Users holding totem tokens can boost their totems by paying a fee in native tokens during Mythus periods
- **Rewards Distribution**: MYTHO tokens are distributed to totems proportionally based on their merit points in each period
- **Blacklisting**: Totems can be blacklisted to prevent them from earning or claiming rewards

### Boost System (New Feature)

The **BoostSystem** introduces an advanced daily engagement mechanism with streak rewards and achievement badges:

#### Core Boost Mechanics
- **Free Daily Boosts**: Users can perform one free boost per day (24-hour cooldown) for any totem they hold tokens for
- **Premium Boosts**: Paid boosts using native tokens (BNB) with Chainlink VRF for random reward calculation
- **Signature Verification**: Frontend signature validation prevents unauthorized boost attempts and ensures security
- **Token Requirements**: Minimum token balance required (configurable for BEP20, any balance for BEP721)

#### Streak System & Grace Days
- **Streak Tracking**: Consecutive daily boosts build streaks with increasing reward multipliers (up to 30 days: +5% per day)
- **Grace Days**: Earned through premium boosts and 30-day streak milestones to maintain streaks during missed days
- **Grace Period**: 2x cooldown window (48 hours) before streak breaks, allowing flexibility for users
- **Streak Reset**: Automatic reset when grace days are exhausted and boost window is missed

#### Achievement Badges & Milestones
- **NFT Badges**: BEP721 tokens minted for achieving streak milestones (7, 14, 30, 100, 200 days)
- **Milestone Tracking**: Automatic detection and badge availability when milestones are reached
- **Badge Minting**: Users can mint available badges through the BadgeNFT contract
- **Customizable Metadata**: Milestone-specific URIs for different badge designs

#### VRF Integration & Premium Rewards
- **Chainlink VRF on BSC**: Secure randomness for premium boost reward calculation using Chainlink VRF V2.5 deployed on BNB Chain
- **Reward Probabilities**: 
  - 50% chance: 500 points
  - 25% chance: 700 points  
  - 15% chance: 1000 points
  - 7% chance: 2000 points
  - 3% chance: 3000 points
- **Expected Value**: ~805 base points with streak and Mythum multipliers applied
- **Payment**: Premium boosts require BNB payment

### Posts Ecosystem (New Feature)

The **Posts** system creates a decentralized content platform where community posts are tokenized as NFTs:

#### Post Creation & Management
- **NFT Posts**: Each post is an BEP721 token with royalty functionality (configurable %)
- **Approval Workflow**: Posts from non-creators/collaborators require totem owner approval
- **Metadata Storage**: Posts store content hashes for decentralized content verification
- **Creator Rights**: Automatic approval for totem creators and designated collaborators

#### Post Boosting & Rewards
- **Token Staking**: Users can boost posts by staking totem tokens (BEP20 amounts or BEP721 NFTs)
- **Boost Window**: Limited time window (default: 24 hours) for boosting after post creation
- **Shard Rewards**: Mathematical formula-based SHARD token distribution for boosters and creators
- **Reward Formula**: `S * (l/T) * sqrt(L/T)` with caps:
  - S = Base shard reward (configurable)
  - l = User's locked tokens (capped at 5% of circulating supply)
  - L = Total locked tokens for post (capped at 10% of circulating supply before sqrt)
  - T = Token circulating supply (excluding Totem and Treasury balances)

#### Donation System
- **Native Token Donations**: Direct BNB donations to post creators
- **Fee Structure**: Configurable donation fee (default: 1%) sent to treasury
- **Merit Integration**: Donations contribute to totem merit points when registered
- **Creator Rewards**: Immediate transfer of donation amount (minus fees) to post creator

#### SHARD Token Economy
- **Reward Token**: BEP20 token specifically for posts ecosystem rewards
- **Minting Control**: Only Posts contract can mint SHARD tokens
- **Burnable**: Users can burn their SHARD tokens if needed
- **Reward Formula**: `S * (l/T) * sqrt(L/T)` where:
  - S = Base shard reward (configurable)
  - l = User's locked tokens (capped at 5% of circulating supply)
  - L = Total locked tokens for post (capped at 10% of circulating supply before sqrt)
  - T = Token circulating supply
- **Ecosystem Integration**: Respects ecosystem-wide pause functionality

### Totem Creation and Token Sales

The process of creating and selling totems involves several steps:

1. **Totem Creation**: Users can create totems through the TotemFactory, either with a new token or an existing whitelisted token
2. **Sale Period**: During the sale period, users can buy and sell totem tokens through the TotemTokenDistributor
3. **Sale Closure**: When all available tokens are sold (excluding those reserved for liquidity), the sale period ends
4. **Liquidity Addition**: A portion of the collected payment tokens and totem tokens are added to PancakeSwap V2 liquidity pool on BSC
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

### Additional Security Features (New Contracts)

- **Signature Verification**: BoostSystem uses ECDSA signature verification with replay attack protection and time-based validity windows
- **VRF Integration**: Chainlink VRF provides secure randomness for premium boost rewards, preventing manipulation
- **Reentrancy Protection**: All state-changing functions use OpenZeppelin's ReentrancyGuard
- **Oracle Data Validation**: Posts contract validates TokenHoldersOracle data freshness for NFT-based calculations
- **Mathematical Safety**: Reward calculations use OpenZeppelin's Math library with overflow protection and precision handling
- **Token Staking Security**: Posts contract safely handles both BEP20 and BEP721 token staking with proper balance checks
- **Grace Day Mechanics**: BoostSystem implements secure grace day tracking to prevent streak manipulation
- **Milestone Validation**: BadgeNFT ensures only valid milestones can be achieved and prevents duplicate badge minting
- **Fee Collection Safety**: Native token handling uses Address.sendValue for secure BNB transfers
- **Access Control Inheritance**: All new contracts inherit comprehensive role-based permissions from core ecosystem

## Project Structure

```bash
mytho/
├── src/                    # Smart contracts
│   ├── AddressRegistry.sol
│   ├── BadgeNFT.sol       # 🆕 Achievement badge NFTs
│   ├── BoostSystem.sol    # 🆕 Daily boost system with streaks
│   ├── BurnMintMYTHO.sol
│   ├── MeritManager.sol
│   ├── MYTHO.sol
│   ├── Posts.sol          # 🆕 Community posts as NFTs
│   ├── Shards.sol         # 🆕 Posts reward token
│   ├── Totem.sol
│   ├── TotemFactory.sol
│   ├── TotemToken.sol
│   ├── TotemTokenDistributor.sol
│   ├── Treasury.sol
│   ├── interfaces/         # Interface definitions
│   └── utils/              # Utility contracts and libraries
├── test/                   # Test files
│   ├── Mytho.t.sol        # Core MYTHO token tests
│   ├── Posts.t.sol        # 🆕 Posts ecosystem tests
│   ├── BoostSystem.t.sol  # 🆕 BoostSystem tests
│   ├── AccessManaged.t.sol # Access control tests
│   ├── Beacon.t.sol       # Upgradability tests
│   ├── CCIPTest.t.sol     # Cross-chain functionality tests
│   ├── Complex.t.sol      # Integration tests
│   ├── OFT.t.sol          # Cross-chain token tests
│   ├── Vesting.t.sol      # Vesting functionality tests
│   ├── HoldersOracleTest.t.sol # TokenHoldersOracle tests
│   ├── NativePaymentToken.t.sol # Native payment tests
│   ├── MeritAccumulation.t.sol # Merit accumulation tests
│   ├── Do.t.sol           # Additional integration tests
│   └── util/              # Testing utilities
├── script/                 # Deployment and management scripts
│   ├── DeployBNB.s.sol    # Main deployment script for BSC
│   ├── MythoCcipSetup.s.sol # Cross-chain setup
│   ├── CrosschainTransfer.s.sol # Cross-chain transfer testing
│   └── Upgrade*.s.sol     # Various upgrade scripts
├── combined/               # Combined contracts for verification
├── foundry.toml           # Foundry configuration
└── README.md              # This file
```

### Latest Contract Additions

The following contracts represent the latest additions to the MYTHO ecosystem:

- **`BoostSystem.sol`** - Advanced daily engagement system with streak mechanics
- **`Posts.sol`** - Community content platform with NFT posts and token rewards  
- **`BadgeNFT.sol`** - Achievement badge system for milestone rewards
- **`Shards.sol`** - Dedicated reward token for the posts ecosystem

## Installation and Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (Forge for testing and deployment)

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

### Deployment on BNB Chain

To deploy the contracts to **BNB Smart Chain (BSC Mainnet)**:

```bash
forge script DeployBNB --rpc-url $BNB_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

### Environment Variables

Create a `.env` file with the following variables for **BNB Chain deployment**:

```bash
# Deployment wallet
PRIVATE_KEY=your_deployment_private_key

# BNB Chain RPC endpoint
BNB_RPC_URL=https://bsc-dataseed.binance.org/

# BNBScan API key for contract verification (optional)
BSCSCAN_API_KEY=your_bscscan_api_key_for_verification
```

### BNB Chain Network Configuration

**BSC Mainnet:**
- Chain ID: `56`
- RPC URL: `https://bsc-dataseed.binance.org/`
- Explorer: `https://bscscan.com/`
- Native Token: BNB

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
- `toggleTransferability()`: Enable/disable transfer restrictions (MANAGER role)
- `totalMinted()`: View total tokens ever minted across all operations

#### AddressRegistry Contract
- `setEcosystemPaused(bool)`: Pause entire ecosystem (MANAGER role)
- `getAddress(bytes32)`: Retrieve contract addresses by identifier

#### BoostSystem Contract (New)
- `boost(totemAddr, timestamp, signature)`: Perform daily free boost with signature verification
- `premiumBoost(totemAddr)`: Paid boost with VRF random rewards (requires BNB payment)
- `mintBadge(milestone)`: Mint achievement badge for reached milestone
- `getUserBoostData(user, totem)`: View user's streak, grace days, and boost history
- `calculateExpectedRewards(user, totem)`: Preview expected rewards for next boost

#### Posts Contract (New)
- `createPost(totemAddr, dataHash)`: Create new post (auto-approved for creators/collaborators)
- `verifyPost(pendingId, approve)`: Approve or reject pending posts (totem owners only)
- `boostPost(postId, tokenAmount)`: Boost post with totem tokens during boost window
- `unboostPost(postId)`: Unboost and claim SHARD rewards after boost window
- `donateToPost(postId)`: Send native token donations to post creator
- `getPost(postId)`: View post details including boost data and creator info

#### BadgeNFT Contract (New)
- `mintBadge(to, milestone)`: Mint badge for milestone achievement (BoostSystem only)
- `getUserBadgeCount(user, milestone)`: View user's badge count for specific milestone
- `getTokenMilestone(tokenId)`: Get milestone associated with badge token
- `setMilestoneURI(milestone, uri)`: Update metadata URI for milestone badges (MANAGER role)

#### Shards Contract (New)
- `mint(to, amount)`: Mint SHARD tokens (Posts contract only)
- `burn(amount)`: Burn own SHARD tokens
- `pause()` / `unpause()`: Emergency pause functionality (MANAGER role)
- `balanceOf(user)`: View user's SHARD token balance

## BNB Chain Ecosystem Integration

### BNB Chain Services Used

- **Chainlink VRF V2.5 on BSC**: Provides verifiable randomness for premium boost reward distribution
- **Chainlink Price Feeds on BSC**: Delivers accurate BNB/USD and token pricing for the ecosystem
- **PancakeSwap V2**: Automated market maker for totem token liquidity pools
- **BNB Token**: Native currency for all premium features, donations, and transaction fees
- **BSCScan**: Block explorer integration for transaction verification and contract interaction

### Network Details

| Parameter | Value |
|-----------|-------|
| Network Name | BNB Smart Chain |
| Chain ID | 56 |
| RPC URL | https://bsc-dataseed.binance.org/ |
| Currency Symbol | BNB |
| Block Explorer | https://bscscan.com/ |

## License

This project is licensed under the Business Source License 1.1 (BUSL-1.1) - see the [LICENSE](LICENSE) file for details.

### License Summary

- **License Type**: Business Source License 1.1 (BUSL-1.1)
- **Copyright**: © 2025 Mytho. All Rights Reserved.
- **Change Date**: May 1, 2027
- **Change License**: MIT License
- **Additional Use Grant**: None

The BUSL-1.1 license allows for non-production use of the code until the Change Date (May 1, 2027), after which the code will be available under the MIT License. For production use before the Change Date, please contact igporoshin@gmail.com to obtain a commercial license.
