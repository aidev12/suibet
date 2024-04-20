module suibet::exchange {
    // === Imports ===

    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Supply, Balance};
    use sui::transfer;
    use sui::math;
    use sui::tx_context::{Self, TxContext};

    // === Errors ===

    /// For when supplied Coin is zero.
    const E_ZERO_BET: u64 = 0;

    /// For when pool fee is set incorrectly.
    /// Allowed values are: [0-10000).
    const E_WRONG_FEE: u64 = 1;

    /// For when someone tries to swap in an empty pool.
    const E_RESERVES_EMPTY: u64 = 2;

    /// For when initial Bet Share amount is zero.
    // const E_SHARE_FULL: u64 = 3;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const E_POOL_FULL: u64 = 4;

    // === Constants ===

    /// The integer scaling setting for fees calculation.
    const FEE_SCALING: u128 = 10000;

    /// The max value that can be held in one of the Balances of
    /// a Pool. U64 MAX / FEE_SCALING
    const MAX_POOL_VALUE: u64 = {
        18446744073709551615 / 10000
    };

    // === Structs ===

    /// The Pool token that will be used to mark the pool share
    /// of a liquidity provider. The first type parameter stands
    /// for the witness type of a pool. The seconds is for the
    /// coin held in the pool.
    struct BetShare<phantom X, phantom Y> has drop {}

    /// The pool with exchange.
    ///
    /// - `fee_percent` should be in the range: [0-10000), meaning
    /// that 1000 is 100% and 1 is 0.1%
    struct BetPool<phantom X, phantom Y> has key {
        id: UID,
        reserve_x: Balance<X>,
        reserve_y: Balance<Y>,
        bet_share_supply: Supply<BetShare<X, Y>>,
        /// Fee Percent is denominated in basis points.
        fee_percent: u64
    }

    // === Init Function ===

    fun init(_: &mut TxContext) {}

    // === Public-Mutative Functions ===

    /// Create new `Pool` for token `T`. Each Pool holds a `Coin<T>`
    /// and a `Coin<SUI>`. Swaps are available in both directions.
    ///
    /// Share is calculated based on Uniswap's constant product formula:
    ///  liquidity = sqrt( X * Y )
    public entry fun create_pool<X, Y>(
        fee_percent: u64,
        ctx: &mut TxContext
    ) {
        assert!(fee_percent >= 0 && fee_percent < 10000, E_WRONG_FEE);

        let bet_share_supply = balance::create_supply(BetShare<X, Y> {});
        transfer::share_object(BetPool {
            id: object::new(ctx),
            reserve_x: balance::zero<X>(),
            reserve_y: balance::zero<Y>(),
            bet_share_supply,
            fee_percent
        });
    }

    /// Create new `Pool` for token `T`. Each Pool holds a `Coin<T>`
    /// and a `Coin<SUI>`. Swaps are available in both directions.
    /// - `coin_x` - the amount of token T to add.
    /// - `coin_y` - the amount of SUI to add.
    /// - `fee_percent` - the fee percent to be charged on swaps.
    /// - `ctx` - the transaction context.
    public fun create_pool_direct<X, Y>(
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        fee_percent: u64,
        ctx: &mut TxContext
    ): Coin<BetShare<X, Y>> {
        let coin_amount_x = coin::value(&coin_x);
        let coin_amount_y = coin::value(&coin_y);

        assert!(coin_amount_x > 0 && coin_amount_y > 0, E_ZERO_BET);
        assert!(coin_amount_x < MAX_POOL_VALUE && coin_amount_y < MAX_POOL_VALUE, E_POOL_FULL);
        assert!(fee_percent >= 0 && fee_percent < 10000, E_WRONG_FEE);

        // Initial share of BetShare is the sqrt(a) * sqrt(b)
        let share = math::sqrt(coin_amount_x) * math::sqrt(coin_amount_y);
        let bet_share_supply = balance::create_supply(BetShare<X, Y> {});
        let bet_share = balance::increase_supply(&mut bet_share_supply, share);

        transfer::share_object(BetPool {
            id: object::new(ctx),
            reserve_x: coin::into_balance(coin_x),
            reserve_y: coin::into_balance(coin_y),
            bet_share_supply,
            fee_percent
        });

        coin::from_balance(bet_share, ctx)
    }

    /// Swaps token T for SUI.
    /// - `coin_x` - the amount of token T to swap.
    /// - `ctx` - the transaction context.
    /// - Returns the amount of SUI received.
    /// - The sender of the transaction will receive the SUI.
    public entry fun swap<X, Y>(pool: &mut BetPool<X, Y>, coin_x: Coin<X>, ctx: &mut TxContext) {
        transfer::public_transfer(
            swap_x_to_y_direct(pool, coin_x, ctx),
            tx_context::sender(ctx)
        );
    }

    /// Swaps SUI for token T.
    /// - `coin_y` - the amount of SUI to swap.
    /// - `ctx` - the transaction context.
    /// - Returns the amount of token T received.
    public fun swap_x_to_y_direct<X, Y>(
        pool: &mut BetPool<X, Y>, coin_x: Coin<X>, ctx: &mut TxContext
    ): Coin<Y> {
        assert!(coin::value(&coin_x) > 0, E_ZERO_BET);

        let balance_x = coin::into_balance(coin_x);

        // Calculate the output amount - fee
        let (reserve_x, reserve_y, _) = get_amounts(pool);

        assert!(reserve_x > 0 && reserve_y > 0, E_RESERVES_EMPTY);

        let output_amount = get_input_price(
            balance::value(&balance_x),
            reserve_x,
            reserve_y,
            pool.fee_percent
        );

        balance::join(&mut pool.reserve_x, balance_x);
        coin::take(&mut pool.reserve_y, output_amount, ctx)
    }

    /// Swaps T for SUI.
    /// - `coin_y` - the amount of T to swap.
    /// - `ctx` - the transaction context.
    /// - Returns the amount of token SUI received.
    public fun swap_y_to_x_direct<X, Y>(
        pool: &mut BetPool<X, Y>, coin_y: Coin<Y>, ctx: &mut TxContext
    ): Coin<X> {
        assert!(coin::value(&coin_y) > 0, E_ZERO_BET);

        let balance_y = coin::into_balance(coin_y);

        // Calculate the output amount - fee
        let (reserve_x, reserve_y, _) = get_amounts(pool);

        assert!(reserve_x > 0 && reserve_y > 0, E_RESERVES_EMPTY);

        let output_amount = get_input_price(
            balance::value(&balance_y),
            reserve_y,
            reserve_x,
            pool.fee_percent
        );

        balance::join(&mut pool.reserve_y, balance_y);
        coin::take(&mut pool.reserve_x, output_amount, ctx)
    }

    /// Add liquidity to the pool.
    /// - `coin_x` - the amount of token T to add.
    /// - `coin_y` - the amount of SUI to add.
    /// - `ctx` - the transaction context.
    /// - The sender of the transaction will receive the pool share.
    entry fun add_liquidity<X, Y>(
        pool: &mut BetPool<X, Y>, coin_x: Coin<X>, coin_y: Coin<Y>, ctx: &mut TxContext
    )
    {
        transfer::public_transfer(
            add_liquidity_direct(pool, coin_x, coin_y, ctx),
            tx_context::sender(ctx)
        );
    }

    /// Add liquidity to the pool and return the pool share.
    /// - `coin_x` - the amount of token T to add.
    /// - `coin_y` - the amount of SUI to add.
    /// - `ctx` - the transaction context.
    /// - Returns the pool share.
    public fun add_liquidity_direct<X, Y>(
        pool: &mut BetPool<X, Y>, coin_x: Coin<X>, coin_y: Coin<Y>, ctx: &mut TxContext
    ): Coin<BetShare<X, Y>>
    {
        assert!(coin::value(&coin_x) > 0, E_ZERO_BET);
        assert!(coin::value(&coin_y) > 0, E_ZERO_BET);

        let balance_x = coin::into_balance(coin_x);
        let balance_y = coin::into_balance(coin_y);

        let (reserve_x, reserve_y, bet_share_supply) = get_amounts(pool);

        let x_added = balance::value(&balance_x);
        let y_added = balance::value(&balance_y);
        let share_minted = if (reserve_x * reserve_y > 0) {
            math::min(
                (x_added * bet_share_supply) / reserve_x,
                (y_added * bet_share_supply) / reserve_y
            )
        } else {
            math::sqrt(x_added) * math::sqrt(y_added)
        };

        let coin_amount_x = balance::join(&mut pool.reserve_x, balance_x);
        let coin_amount_y = balance::join(&mut pool.reserve_y, balance_y);

        assert!(coin_amount_x < MAX_POOL_VALUE, E_POOL_FULL);
        assert!(coin_amount_y < MAX_POOL_VALUE, E_POOL_FULL);

        let balance = balance::increase_supply(&mut pool.bet_share_supply, share_minted);
        coin::from_balance(balance, ctx)
    }

    /// Entrypoint for the `remove_liquidity` method. Transfers
    /// withdrawn assets to the sender.
    entry fun remove_liquidity_<X, Y>(
        pool: &mut BetPool<X, Y>,
        bet_share: Coin<BetShare<X, Y>>,
        ctx: &mut TxContext
    )
    {
        let (coin_x, coin_y) = remove_liquidity(pool, bet_share, ctx);
        let sender = tx_context::sender(ctx);

        transfer::public_transfer(coin_x, sender);
        transfer::public_transfer(coin_y, sender);
    }

    /// Remove liquidity from the `Pool` by burning `Coin<BetShare>`.
    /// Returns `Coin<T>` and `Coin<SUI>`.
    public fun remove_liquidity<X, Y>(
        pool: &mut BetPool<X, Y>,
        bet_share: Coin<BetShare<X, Y>>,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>)
    {
        let bet_share_amount = coin::value(&bet_share);

        // If there's a non-empty BetShare, we can
        assert!(bet_share_amount > 0, E_ZERO_BET);

        let (reserve_x, reserve_y, bet_share_supply) = get_amounts(pool);
        let x_removed = (reserve_x * bet_share_amount) / bet_share_supply;
        let y_removed = (reserve_y * bet_share_amount) / bet_share_supply;

        balance::decrease_supply(&mut pool.bet_share_supply, coin::into_balance(bet_share));

        (
            coin::take(&mut pool.reserve_x, x_removed, ctx),
            coin::take(&mut pool.reserve_y, y_removed, ctx)
        )
    }

    // === Public-View Functions ===

    /// Public getter for the price of SUI in token T.
    /// - How much SUI one will get if they send `to_sell` amount of T;
    public fun price_x_to_y<X, Y>(pool: &BetPool<X, Y>, delta_y: u64): u64
    {
        let (reserve_x, reserve_y, _) = get_amounts(pool);
        get_input_price(delta_y, reserve_y, reserve_x, pool.fee_percent)
    }

    /// Public getter for the price of token T in SUI.
    /// - How much T one will get if they send `to_sell` amount of SUI;
    public fun price_y_to_x<X, Y>(pool: &BetPool<X, Y>, delta_x: u64): u64
    {
        let (reserve_x, reserve_y, _) = get_amounts(pool);
        get_input_price(delta_x, reserve_x, reserve_y, pool.fee_percent)
    }


    /// Get most used values in a handy way:
    /// - amount of CoinX
    /// - amount of CoinY
    /// - total supply of BetShare
    public fun get_amounts<X, Y>(pool: &BetPool<X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.reserve_x),
            balance::value(&pool.reserve_y),
            balance::supply_value(&pool.bet_share_supply)
        )
    }

    /// Calculate the output amount minus the fee - 0.3%
    public fun get_input_price(
        input_amount: u64, input_reserve: u64, output_reserve: u64, fee_percent: u64
    ): u64 {
        // up casts
        let (
            input_amount,
            input_reserve,
            output_reserve,
            fee_percent
        ) = (
            (input_amount as u128),
            (input_reserve as u128),
            (output_reserve as u128),
            (fee_percent as u128)
        );

        let input_amount_with_fee = input_amount * (FEE_SCALING - fee_percent);
        let numerator = input_amount_with_fee * output_reserve;
        let denominator = (input_reserve * FEE_SCALING) + input_amount_with_fee;

        (numerator / denominator as u64)
    }
}
