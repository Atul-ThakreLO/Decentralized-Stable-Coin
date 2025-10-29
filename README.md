# Decentralized Stablecoin (DSC)

A decentralized, algorithmic stablecoin system pegged to USD, built with Solidity and Foundry. This project implements a fully collateralized stablecoin protocol with exogenous crypto assets as collateral.

## 📋 Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [System Design](#system-design)
- [Smart Contracts](#smart-contracts)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [License](#license)

## 🎯 Overview

The Decentralized Stablecoin (DSC) is an **exogenous, decentralized, anchored (pegged), crypto-collateralized** low-volatility coin designed to maintain a 1:1 peg with the US Dollar.

### Core Parameters

1. **Relative Stability**: Pegged/Anchored → $1.00 USD
   - Uses Chainlink Price Feeds for accurate price data
2. **Stability Mechanism**: Algorithmic (Decentralized)

   - Over-collateralization ratio: **200%**
   - Liquidation threshold: **50%**
   - Liquidation bonus: **10%**

3. **Collateral Type**: Exogenous (Crypto)
   - Supported collateral: **wETH** and **wBTC**
   - Multi-collateral system for diversification

## ✨ Key Features

- **Over-Collateralized**: Users must maintain 200% collateralization ratio
- **Liquidation Mechanism**: Protects protocol solvency through liquidations
- **Oracle Integration**: Chainlink price feeds with staleness checks
- **Multi-Collateral**: Accepts wETH and wBTC as collateral
- **Health Factor System**: Real-time monitoring of user positions
- **Reentrancy Protection**: Built with OpenZeppelin's ReentrancyGuard
- **Burnable & Mintable**: ERC20 token with controlled minting/burning

## 🏗 System Design

### Architecture

```
┌─────────────────────────────────────────────────┐
│                   Users                          │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              DSCEngine                           │
│  - Deposit/Redeem Collateral                    │
│  - Mint/Burn DSC                                │
│  - Liquidation Logic                            │
│  - Health Factor Calculations                   │
└─────────┬───────────────────┬───────────────────┘
          │                   │
          ▼                   ▼
┌──────────────────┐  ┌──────────────────┐
│ DecentralizedStablecoin  Chainlink Oracles│
│  - ERC20 Token   │  │  - wETH/USD      │
│  - Mint/Burn     │  │  - wBTC/USD      │
└──────────────────┘  └──────────────────┘
```

### How It Works

1. **Deposit Collateral**: Users deposit wETH or wBTC as collateral
2. **Mint DSC**: Users can mint DSC up to 50% of their collateral value
3. **Health Factor**: System monitors user's collateralization ratio
4. **Liquidation**: If health factor < 1, position can be liquidated by anyone
5. **Incentives**: Liquidators receive 10% bonus for maintaining protocol health

## 📜 Smart Contracts

### Core Contracts

#### `DecentralizedStablecoin.sol`

- ERC20 token implementation
- Burnable and mintable
- Ownable (controlled by DSCEngine)
- Symbol: **DSC**
- Name: **DecentralizedStablecoin**

#### `DSCEngine.sol`

- Main engine for the stablecoin system
- Handles collateral deposits and redemptions
- Manages DSC minting and burning
- Implements liquidation mechanism
- Integrates with Chainlink price feeds

#### `OracleLib.sol`

- Library for Chainlink oracle interactions
- Implements staleness checks for price feeds
- Ensures data reliability

### Key Functions

**User Operations:**

- `depositCollateral()` - Deposit wETH/wBTC as collateral
- `depositCollateralAndMintDSC()` - Deposit and mint in one transaction
- `mintDSC()` - Mint DSC against deposited collateral
- `burnDSC()` - Burn DSC to reduce debt
- `redeemCollateral()` - Withdraw collateral (if health factor allows)
- `redeemCollateralForDSC()` - Burn DSC and redeem collateral

**Liquidation:**

- `liquidate()` - Liquidate undercollateralized positions

**View Functions:**

- `getHealthFactor()` - Check user's health factor
- `getAccountInformation()` - Get user's DSC debt and collateral value
- `getAccountCollateralValue()` - Get total collateral value in USD
- `getTokenAmountFromUSD()` - Convert USD amount to token amount

## 🚀 Getting Started

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation

1. Clone the repository:

```bash
git clone https://github.com/Atul-ThakreLO/Decentralized-Stable-Coin.git
cd Decentralized-Stable-Coin
```

2. Install dependencies:

```bash
forge install
```

3. Build the project:

```bash
forge build
```

## 💻 Usage

### Build

Compile the smart contracts:

```bash
forge build
```

### Test

Run the test suite:

```bash
forge test
```

Run tests with verbosity:

```bash
forge test -vvv
```

Run specific test file:

```bash
forge test --match-path test/Unit/DSCEngineTests.t.sol
```

### Format

Format code according to Solidity style guide:

```bash
forge fmt
```

### Gas Snapshots

Generate gas usage reports:

```bash
forge snapshot
```

### Coverage

Check test coverage:

```bash
forge coverage
```

## 🧪 Testing

The project includes comprehensive test suites:

### Test Structure

```
test/
├── Unit/
│   └── DSCEngineTests.t.sol        # Unit tests for DSCEngine
├── Fuzz/
│   ├── Handler.t.sol                # Handler for invariant testing
│   └── Invariants.t.sol             # Invariant/fuzz tests
└── Mocks/
    └── MockV3Aggregator.sol         # Mock Chainlink price feed
```

### Invariant Testing

The project uses advanced fuzzing with invariant tests (128 runs, 128 depth):

- Protocol must always be over-collateralized
- Users can't create unbacked DSC
- Getters should never revert

Run invariant tests:

```bash
forge test --match-test invariant
```

## 🚢 Deployment

### Local Deployment (Anvil)

1. Start local Ethereum node:

```bash
anvil
```

2. Deploy contracts:

```bash
forge script script/DeployDSC.s.sol:DeployDSC --rpc-url http://localhost:8545 --private-key <PRIVATE_KEY> --broadcast
```

### Testnet/Mainnet Deployment

Deploy to Sepolia testnet:

```bash
forge script script/DeployDSC.s.sol:DeployDSC --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

### Environment Variables

Create a `.env` file:

```env
SEPOLIA_RPC_URL=your_rpc_url
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## 🔒 Security

### Security Features

- ✅ Reentrancy protection on critical functions
- ✅ Oracle staleness checks
- ✅ Integer overflow protection (Solidity ^0.8.19)
- ✅ Access control with OpenZeppelin's Ownable
- ✅ CEI pattern (Checks-Effects-Interactions)
- ✅ Comprehensive test coverage including invariant tests

### Known Considerations

- The protocol assumes >100% collateralization for liquidations to work effectively
- Oracle price feed failures could affect system stability
- Users are responsible for maintaining their health factors

### Audit Status

⚠️ This project is for educational purposes. It has not been audited. Do not use in production without a professional security audit.

## 📚 Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Chainlink Price Feeds](https://docs.chain.link/data-feeds/price-feeds)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Solidity Documentation](https://docs.soliditylang.org/)

## 🛠 Built With

- **Solidity ^0.8.19** - Smart contract language
- **Foundry** - Development framework
- **OpenZeppelin** - Secure contract libraries
- **Chainlink** - Decentralized oracle network

## 👨‍💻 Author

**Atul Thakre**

## 📄 License

This project is licensed under the MIT License.

## 🙏 Acknowledgments

- Foundry team for the excellent development toolkit
- OpenZeppelin for secure contract implementations
- Chainlink for reliable price feeds

---

### Foundry Commands Quick Reference

```bash
forge build                          # Compile contracts
forge test                           # Run tests
forge test -vvv                      # Run tests with detailed output
forge coverage                       # Generate coverage report
forge snapshot                       # Create gas snapshots
forge fmt                            # Format code
anvil                                # Start local node
cast <subcommand>                    # Interact with contracts
forge --help                         # Show help
```
