# Sui Move Project Spec: sUSDC-to-SUI Auto-DCA Vault (DeepBook V3)

## 1. Project Goal
Implement a decentralized, yield-bearing Auto-DCA vault where users store **sUSDC** (Scallop interest-bearing coin). The vault utilizes **DeepBook V3** to swap sUSDC for **SUI** at fixed intervals using a secure **Hot Potato** pattern.

## 2. Core Business Rules
* **Yield Generation**: Principal remains in `sUSDC` (or any generic `T`) to earn lending interest until the moment of swap.
* **Minimum Threshold**: `dca_amount` must be **>= 100 sUSD** (100,000,000 units) to ensure the execution reward covers Keeper's gas fees.
* **Hot Potato Security**: The execution flow is split into `start` and `resolve` phases. Keepers must complete the swap to claim rewards; they cannot steal funds.
* **Dust Protection**: Only the `owner` can deposit funds into their plan to prevent malicious dust attacks.
* **Fee Structure**:
    * Total Fee = `dca_amount` * `admin_fee_bps`.
    * **Keeper Reward**: A configured percentage of the Total Fee, paid to `tx_context::sender`.
    * **Protocol Fee**: The remainder, paid to the `beneficiary`.

## 3. Object Definitions

### A. `DCAConfig` (Shared Object)
* `total_fee_bps`: `u64` (Max 10000).
* `keeper_share_rate`: `u64` (Max 10000).
* `min_dca_limit`: `u64` (Fixed at 100,000,000).
* `beneficiary`: `address`.

### B. `DCAPlan<T>` (Shared Object)
* `id`: `UID`.
* `owner`: `address`.
* `balance`: `Balance<T>`.
* `dca_amount`: `u64`.
* `last_execution`: `u64` (ms timestamp).
* `interval`: `u64` (ms duration).

### C. `DcaRequest<T>` (Hot Potato / Transient Struct)
* **Capabilities**: No abilities (`drop`, `store`, `key`, `copy` are all absent).
* **Purpose**: Ensures atomic execution. Must be consumed by `resolve_via_deepbook` within the same transaction block.
* **Fields**: Contains `balance` (for swap), `fee_coin`, `keeper_coin`, and `owner` address.

## 4. Execution Logic (Pipeline)

### Phase 1: `start_dca` (State & Validation)
1.  **Validation**:
    * Check `clock::timestamp_ms >= last_execution + interval`.
    * Check `dca_amount >= min_dca_limit`.
    * Check `balance >= dca_amount`.
2.  **State Update**: Set `last_execution` to current timestamp.
3.  **Accounting**:
    * Calculate fees using `u128` to prevent overflow.
    * Split balance into `swap_amount`, `keeper_fee`, and `protocol_fee`.
4.  **Output**: Return a **`DcaRequest<T>`** (Hot Potato) containing the assets.

### Phase 2: `resolve_via_deepbook` (Swap & Settlement)
1.  **Unpack Potato**: Destructure `DcaRequest`.
2.  **Distribute Fees**: Transfer `keeper_fee` to sender and `protocol_fee` to beneficiary.
3.  **DeepBook Swap**:
    * Call `deepbook::pool::swap_exact_base_for_quote`.
    * **Slippage Control**: Accept `min_out` parameter from Keeper.
4.  **Settlement**:
    * Transfer acquired `SUI` to `plan.owner`.
    * Refund any remaining `base_coin` (dust) to `plan.owner`.
    * Refund unused `DEEP` fee (if any) to Keeper.

## 5. Technical Requirements
* **Edition**: Sui Move 2024.
* **Design Pattern**: **Hot Potato (Linear Types)** for mandatory execution flow.
* **Composability**: Use `public` functions designed for **Programmable Transaction Blocks (PTBs)**, allowing Keepers to chain `start` -> `swap` calls.
* **Safety**:
    * Use `u128` for fee calculations.
    * Assert fee configurations do not exceed 100%.
    * Restrict deposits to owner only.