
# SUI Bet Module

The SUI Bet module is a decentralized betting platform implemented on the SUI blockchain. It allows users to create pools, add liquidity, swap between different types of bets, and remove liquidity. The module ensures secure and efficient betting operations while incentivizing liquidity providers through fee mechanisms.

## Installation

To use the SUI Bet module, follow these steps:

1. Ensure you have the SUI blockchain platform set up and running.


```rust
use suibet::exchange;
```

To build:

```bash
sui move build
```

To publish:

```bash
sui client publish --gas-budget 100000000 --json
```

## Usage

### How to Use

This guide assumes you have a key, already have faucet coins in testnet or devnet, and two coins pre-deployed.

You can interact with the SUI Bet module using the SUI explorer or with the SUI CLI.

#### To create a new pool:

```bash
sui client call --package $PACKAGE_ID --module dex --function create_pool --type-args $BASE_COIN_TYPE $QUOTE_COIN_TYPE --args $FEE_PERCENTAGE --gas-budget 10000000000 --json
```

#### To swap tokens:

```bash
sui client call --package $PACKAGE_ID --module dex --function swap --type-args $BASE_COIN_TYPE $QUOTE_COIN_TYPE --args $POOL_ID $BASE_COIN_ID --gas-budget 10000000000 --json
```

### Example

Here's an example of how to use the SUI Bet module in your SUI smart contract:

```rust
// Create a new pool
exchange::create_pool_direct(...);

// Swap tokens
exchange::swap(...);
```

Certainly! Below is a README-style documentation for the SUI Bet module:

---

```


The SUI Bet module provides various functions for betting operations. These include creating pools, adding liquidity, swapping between bets, and removing liquidity.

## Functions

- **create_pool:** Creates a new betting pool with a specified fee percentage.
- **create_pool_direct:** Creates a new pool with specified amounts of bets and fee percentage.
- **swap:** Swaps one type of bet for another within a pool.
- **swap_x_to_y_direct:** Swaps one type of bet for another directly.
- **swap_y_to_x_direct:** Swaps one type of bet for another directly.
- **add_liquidity:** Adds liquidity to the pool by providing bets of both types.
- **add_liquidity_direct:** Adds liquidity to the pool directly with specified amounts of bets.
- **remove_liquidity_:** Removes liquidity from the pool.
- **price_x_to_y:** Calculates the price of one type of bet in terms of the other.
- **price_y_to_x:** Calculates the price of one type of bet in terms of the other.
- **get_amounts:** Retrieves the amounts of bets and the total supply of pool shares.
- **get_input_price:** Calculates the output amount minus the fee for a given input amount and reserves.

## Example

```rust
use suibet::exchange;

// Create a pool with a fee percentage
exchange::create_pool(100, &mut ctx);

// Add liquidity to the pool
let coin_x = Coin::new(100);
let coin_y = Coin::new(200);
exchange::add_liquidity(&mut pool, coin_x, coin_y, &mut ctx);

// Swap one type of bet for another
let bet_x = Coin::new(50);
exchange::swap(&mut pool, bet_x, &mut ctx);

// Remove liquidity from the pool
let lsp = Coin::new(100);
exchange::remove_liquidity_(&mut pool, lsp, &mut ctx);
```

## License

This project is licensed under the [MIT License](LICENSE).

---

Save the above content in a file named `README.md` in the root directory of your SUI Bet module project. This README provides users with clear instructions on how to install, use, and understand the functionalities of the SUI Bet module.

---

This README provides an overview of the SUI Bet module, installation instructions, usage guidelines, an example, and licensing information.
