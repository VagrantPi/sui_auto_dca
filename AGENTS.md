# AGENTS.md - Sui Auto-DCA Development Guide

## Build, Lint, and Test Commands

### Core Commands
```bash
# Build the project
sui move build

# Build with linting enabled
sui move build --lint

# Update dependencies
sui move update-deps

# Run tests
sui move test

# Run a single test
sui move test --filter <test_name>
```

### Project Structure
```
sui_auto_dca/
├── sources/           # Main Move modules
│   └── sui_auto_dca.move
├── tests/            # Test modules
│   └── sui_auto_dca_tests.move
├── Move.toml         # Package manifest
└── Move.lock         # Dependency lockfile
```

## Code Style Guidelines

### Imports
- Use shorthand module access where possible (e.g., `ctx.sender()` instead of `tx_context::sender(ctx)`)
- Group imports by category: Sui framework, DeepBook, other dependencies
- Use `{Self}` sparingly; prefer direct function calls
- Use module method syntax when available

**Example:**
```move
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use deepbook::pool;
use token::deep::DEEP;
```

### Error Handling
- Use `#[error]` attribute with descriptive error messages
- Prefer `vector<u8>` error type with clear messages
- Define errors at module level with descriptive constant names
- Use assertion functions with clear error messages

**Example:**
```move
#[error]
const EINVALID_AMOUNT: vector<u8> = b"Amount must be greater than 0";

assert!(amount > 0, EINVALID_AMOUNT);
```

### Type Conventions
- Use `u64` for amounts, timestamps, and most values
- Use `u128` for intermediate fee calculations to prevent overflow
- Use `address` for wallet addresses
- Use `Coin<T>` for coin inputs/outputs
- Use `Balance<T>` for internal token tracking
- Use `phantom T` for generic type parameters that don't require storage
- Use `&mut` for mutable references to shared objects
- Use `&` for read-only references

### Naming Conventions
- **Constants**: SCREAMING_SNAKE_CASE (e.g., `BASIS_POINTS_DIVISOR`)
- **Error codes**: E prefix + descriptive name (e.g., `EINVALID_AMOUNT`)
- **Structs**: PascalCase (e.g., `DCAConfig`, `DCAPlan`)
- **Functions**: snake_case (e.g., `create_dca_plan`, `execute_dca`)
- **Variables**: snake_case (e.g., `dca_amount`, `keeper_share`)
- **Type parameters**: Single uppercase letter (e.g., `T`)

### Struct Definitions
- Use `has key` for shared objects
- Use `has store` for transferable objects
- Use `has key, store` for objects that are both shared and transferable
- Use `phantom` modifier for type parameters that don't require stored values

**Example:**
```move
public struct DCAConfig has key {
    id: UID,
    total_fee_bps: u64,
    keeper_share_rate: u64,
    min_dca_limit: u64,
    beneficiary: address,
}

public struct DCAPlan<phantom T> has key {
    id: UID,
    owner: address,
    balance: Balance<T>,
    dca_amount: u64,
    last_execution: u64,
    interval: u64,
}
```

### Function Design
- Use `public` for entry points and library functions
- Use `entry` modifier for transaction entry points
- Pass `ctx: &mut TxContext` as the last parameter
- Pass shared objects (`&mut Pool<T, SUI>`) explicitly rather than fetching them internally
- Use method syntax where natural (e.g., `plan.balance.value()`)

### DeepBook Integration
- Pool must be passed as a mutable reference: `pool: &mut pool::Pool<T, SUI>`
- DEEP coin is required for swap fees: `deep_coin: Coin<DEEP>`
- Swap functions return 3 values: `(base_remaining, sui_coin, deep_remaining)`
- Handle remaining coins properly (return to user or destroy_zero)
- Use `min_out` parameter for slippage protection

### Fee Calculations
- Always use `u128` for intermediate calculations
- Divide by `BASIS_POINTS_DIVISOR` (10000) for bps conversions
- Example: `total_fee = (amount as u128) * (bps as u128) / BASIS_POINTS_DIVISOR`

### Transfer Patterns
- Shared objects: `transfer::share_object(obj)`
- Ownership transfer: `transfer::public_transfer(coin, recipient)`
- Balance joining: `balance::join(&mut target, source)`

### Testing
- Place tests in `tests/` directory
- Use `#[test_only]` module attribute
- Use `#[test]` for unit tests
- Use `#[test, expected_failure]` for negative tests

### Important Addresses
- DeepBook package: `0xdee9`
- DEEP token: `token::deep::DEEP` from DeepBook package
- All addresses are defined in `Move.toml` and managed by dependencies
