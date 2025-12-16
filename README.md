###YOU CAN FIND FULL BACKEND AND FRONTEND AND DOCUMENTATION FOR SAFIDOSWAP ON MY GITHUB REPOSITORIES###
# SafiSwap Ecosystem

The **SafiSwap Ecosystem** is a full-stack Decentralized Exchange (DEX) solution engineered with gamification layers, automated yield mechanics, and a proprietary high-performance indexing infrastructure.

Unlike standard AMM forks, this protocol implements dynamic fee separation, optimized on-chain storage for lottery systems, and a custom event-driven backend to bypass RPC bottlenecks.

---

## 🏗 Key Technical Features (Smart Contracts)

### 1. Dynamic Fee AMM (`Factory.sol` & `Router.sol`)
The Market Maker logic was upgraded to support a granular fee structure, allowing the protocol to split fees dynamically between Liquidity Providers and the Treasury.
* **Custom Fee Architecture:** Fees are not hardcoded. The Factory manages `swapFeeBps`, `lpFeeBps`, and `protocolFeeBps` individually.
* **Pair-Specific Overrides:** Logic to set specific fee tiers for stablecoin pairs or promotional tokens via `pairFeeOverride`.

### 2. Gas-Optimized Lottery (`SafiLuck.sol`)
A decentralized lottery system designed to handle high-volume ticket sales without hitting block gas limits.
* **Span Management:** Instead of storing every ticket ID individually, the contract uses `Span` structs to group sequential ticket purchases.
* **Binary Search Verification:** Winner verification uses a binary search algorithm (`_ownerOfTicket`) to locate the owner within Spans in **O(log n)** time, significantly reducing gas costs compared to linear iteration.

### 3. Permissionless Keeper Vaults (`EmissionsVault.sol`)
The staking reward mechanism solves the "stale state" problem by incentivizing public actors to trigger updates.
* **Incentivized Upkeep:** The `distributeStakeRewards` function is public. Any user (or bot) can execute the daily distribution and potential upkeep tasks.
* **Emission Control:** Strict daily caps on minting to prevent inflation exploits.

---

## 🖥️ Frontend Architecture (React + Wagmi)

The user interface was built to handle complex blockchain state management without compromising UX/UI performance.

### 1. Client-Side Smart Routing (`swap.tsx`)
Instead of relying on external APIs for routing, the frontend implements a **BFS (Breadth-First Search) algorithm** locally.
* **Graph Traversal:** Automatically finds the best swap path (e.g., Token A -> WPHRS -> Token B) using cached pair data.
* **Stale Price Protection:** Implements a double-check mechanism that re-fetches reserves immediately before transaction signing to prevent slippage failures.

### 2. Reactive Data Hooks (`useVaultReward.ts`)
Custom hooks designed to abstract complex contract interactions.
* **Optimistic UI:** Simulates contract calls (`simulateContract`) to predict transaction success and update the UI instantly before the block is mined.
* **Latency Sync:** Intelligent polling that adjusts refresh rates based on round phases (e.g., accelerates polling as lottery deadlines approach).

---

## ⚙️ Backend & Infrastructure (Node.js + Ethers.js)

A robust off-chain infrastructure ensures data availability and protocol automation.

### 1. Event-Driven Indexer (`aprWatcher.ts` & `indexer.ts`)
A custom ETL (Extract, Transform, Load) pipeline that listens to blockchain events in real-time.
* **Log Parsing:** Listens for `Swap` and `Sync` events to calculate APY and Volume metrics off-chain, saving frontend resources.
* **Database Flush:** Batches updates to PostgreSQL to persist historical data for analytics charts.

### 2. Secure Automation Keepers (`luckWatcher.ts`)
Python/TypeScript bots responsible for protocol maintenance.
* **Round Finalization:** Monitors the `SafiLuck` contract and automatically executes the VRF/Randomness callback when rounds end.
* **Security:** Uses secure environment variable injection for signing transactions without exposing private keys.

---

## 🛠 Tech Stack

**Smart Contracts:**
* Language: Solidity ^0.8.24
* Security: OpenZeppelin (ReentrancyGuard, SafeERC20)
* Testing: Hardhat & Foundry

**Frontend:**
* Framework: React (Vite) + TypeScript
* Web3: Wagmi v2 + Viem (Type-safe interactions)
* Styling: TailwindCSS

**Backend:**
* Runtime: Node.js
* Database: PostgreSQL
* Libraries: Ethers.js v6 (Event Listening)

---

*Engineered with precision for the Pharos Ecosystem.*
