# Alura: A Liquidity Bootstrapping Ecosystem

Alura is a **liquidity bootstrapping ecosystem** built on the Aptos blockchain. It introduces a novel mechanism called **Dutch-auction Dynamic Bonding Curves** to facilitate initial price discovery and liquidity provision for arbitrary assets. This project is designed to help token projects bootstrap liquidity in a decentralized and automated manner.

---

## Features

- **Dutch-auction Dynamic Bonding Curves**:
  - Automated price discovery through a descending price auction.
  - Dynamic bonding curve to ensure fair price adjustments over time.

- **Token Factory**:
  - Deploys ERC20 tokens with known bytecode to prevent malicious implementations.
  - Supports customizable token features like fee-on-transfer, buy/sell taxes, and airdrops.

- **Liquidity Provision**:
  - Streams liquidity into the pool at a configurable rate.
  - Directly deposits funds into a generalized AMM (e.g., Uniswap v4) without user intervention.

- **Time-locked Liquidity**:
  - Liquidity tokens are initially time-locked but can be withdrawn later.

- **Sell Functionality**:
  - Allows users to sell tokens back to the pool after the Dutch auction has ended.

---

## How It Works

### 1. **Dutch Auction Phase**:
   - The price starts high and decreases over time until it reaches a market-clearing price.
   - Buyers can purchase tokens at the current price during the auction.

### 2. **Bonding Curve Phase**:
   - After the auction ends, the price is determined by a dynamic bonding curve.
   - The price increases gradually based on the bonding curve formula.

### 3. **Sell Phase**:
   - After the auction ends, users can sell their tokens back to the pool at the current price.


