# SafiSwap Core Protocol

This repository hosts the core smart contracts for the SafiSwap Ecosystem, a custom Decentralized Exchange (DEX) engineered with gamification layers and automated yield mechanics.

Unlike standard AMM forks, this protocol implements dynamic fee separation, optimized on-chain storage for lottery systems, and incentivized maintenance vaults.

## 🏗 Key Technical Features

### 1. Dynamic Fee AMM (`Factory.sol` & `Router.sol`)
The Market Maker logic was upgraded to support a granular fee structure, allowing the protocol to split fees dynamically between Liquidity Providers and the Treasury.
- **Custom Fee Architecture:** Fees are not hardcoded. The `Factory` manages `swapFeeBps`, `lpFeeBps`, and `protocolFeeBps` individually.
- **Pair-Specific Overrides:** Logic to set specific fee tiers for stablecoin pairs or promotional tokens via `pairFeeOverride`.

### 2. Gas-Optimized Lottery (`SafiLuck.sol`)
A decentralized lottery system designed to handle high-volume ticket sales without hitting block gas limits.
- **Span Management:** Instead of storing every ticket ID individually, the contract uses `Span` structs to group sequential ticket purchases.
- **Binary Search Verification:** Winner verification uses a binary search algorithm (`_ownerOfTicket`) to locate the owner within Spans in O(log n) time, significantly reducing gas costs compared to linear iteration.

### 3. Permissionless Keeper Vaults (`EmissionsVault.sol`)
The staking reward mechanism solves the "stale state" problem by incentivizing public actors to trigger updates.
- **Incentivized Upkeep:** The `distributeStakeRewards` function is public. Any user (or bot) can execute the daily distribution and potential upkeep tasks, ensuring the protocol remains alive and decentralized without manual admin intervention.
- **Emission Control:** Strict daily caps on minting to prevent inflation exploits.

## 🛠 Tech Stack
- **Language:** Solidity ^0.8.24
- **Security:** OpenZeppelin (ReentrancyGuard, SafeERC20) & Checks-Effects-Interactions pattern.
- **Architecture:** Modular implementation separating Token logic (`SAFIToken`), Farming (`SAFIStake`), and Trading Engine (`Router/Factory`).
