module suibet::exchange {
    // === Imports ===

    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Supply, Balance};
    use sui::transfer;
    use sui::math;
    use sui::tx_context::{Self, TxContext};

    // === Errors ===

    const E_ZERO_BET: u64 = 0;
    const E_WRONG_FEE: u64 = 1;
    const E_RESERVES_EMPTY: u64 = 2;
    const E_POOL_FULL: u64 = 3;

    // === Constants ===

    const FEE_SCALING: u128 = 10000;
    const MAX_POOL_VALUE: u64 = 184467440737095516; // U64 MAX / FEE_SCALING

    // === Structs ===

    struct BetShare<phantom X, phantom Y> {}

    struct BetPool<phantom X, phantom Y> {
        id: UID,
        reserve_x: Balance<X>,
        reserve_y: Balance<Y>,
        bet_share_supply: Supply<BetShare<X, Y>>,
        fee_percent: u64,
    }

    impl<phantom X, phantom Y> drop for BetShare<X, Y> {}

    // === Init Function ===

    fun init(_: &mut TxContext) {}

    // === Public-Mutative Functions ===

    entry fun create_pool<X, Y>(
        fee_percent: u64,
        ctx: &mut TxContext
    ) {
        ensure!(fee_percent < 10000, E_WRONG_FEE);

        let bet_share_supply = balance::create_supply(BetShare<X, Y> {});
        transfer::share_object(BetPool {
            id: object::new(ctx),
            reserve_x: balance::zero<X>(),
            reserve_y: balance::zero<Y>(),
            bet_share_supply,
            fee_percent,
        });
    }

    public fun create_pool_direct<X, Y>(
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        fee_percent: u64,
        ctx: &mut TxContext
    ): Coin<BetShare<X, Y>> {
        let coin_amount_x = coin::value(&coin_x);
        let coin_amount_y = coin::value(&coin_y);

        ensure!(coin_amount_x > 0 && coin_amount_y > 0, E_ZERO_BET);
        ensure!(coin_amount_x < MAX_POOL_VALUE && coin_amount_y < MAX_POOL_VALUE, E_POOL_FULL);
        ensure!(fee_percent < 10000, E_WRONG_FEE);

        let share = math::sqrt(coin_amount_x) * math::sqrt(coin_amount_y);
        let bet_share_supply = balance::create_supply(BetShare<X, Y> {});
        let bet_share = balance::increase_supply(&mut bet_share_supply, share);

        transfer::share_object(BetPool {
            id: object::new(ctx),
            reserve_x: coin::into_balance(coin_x),
            reserve_y: coin::into_balance(coin_y),
            bet_share_supply,
            fee_percent,
        });

        coin::from_balance(bet_share, ctx)
    }

    entry fun add_liquidity<X, Y>(
        pool: &mut BetPool<X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        ctx: &mut TxContext
    ) {
        let (coin_share_x, coin_share_y) = add_liquidity_direct(pool, coin_x, coin_y, ctx);
        transfer::public_transfer(coin_share_x, tx_context::sender(ctx));
        transfer::public_transfer(coin_share_y, tx_context::sender(ctx));
    }

    public fun add_liquidity_direct<X, Y>(
        pool: &mut BetPool<X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        ctx: &mut TxContext
    ) -> (Coin<X>, Coin<Y>) {
        ensure!(coin::value(&coin_x) > 0, E_ZERO_BET);
        ensure!(coin::value(&coin_y) > 0, E_ZERO_BET);

        let balance_x = coin::into_balance(coin_x);
        let balance_y = coin::into_balance(coin_y);

        let (reserve_x, reserve_y, bet_share_supply) = get_amounts(pool);

        let x_added = balance::value(&balance_x);
        let y_added = balance::value(&balance_y);
        let share_minted = if (reserve_x * reserve_y > 0) {
            math::min(
                (x_added * bet_share_supply) / reserve_x,
                (y_added * bet_share_supply) / reserve_y,
            )
        } else {
            math::sqrt(x_added) * math::sqrt(y_added)
        };

        let coin_amount_x = balance::join(&mut pool.reserve_x, balance_x);
        let coin_amount_y = balance::join(&mut pool.reserve_y, balance_y);

        ensure!(coin_amount_x < MAX_POOL_VALUE, E_POOL_FULL);
        ensure!(coin_amount_y < MAX_POOL_VALUE, E_POOL_FULL);

        let balance = balance::increase_supply(&mut pool.bet_share_supply, share_minted);
        (
            coin::from_balance(balance, ctx),
            coin::from_balance(coin_amount_y, ctx),
        )
    }

    entry fun remove_liquidity_<X, Y>(
        pool: &mut BetPool<X, Y>,
        bet_share: Coin<BetShare<X, Y>>,
        ctx: &mut TxContext
    ) {
        let (coin_x, coin_y) = remove_liquidity(pool, bet_share, ctx);
        let sender = tx_context::sender(ctx);

        transfer::public_transfer(coin_x, sender);
        transfer::public_transfer(coin_y, sender);
    }

    public fun remove_liquidity<X, Y>(
        pool: &mut BetPool<X, Y>,
        bet_share: Coin<BetShare<X, Y>>,
        ctx: &mut TxContext
    ) -> (Coin<X>, Coin<Y>) {
        let bet_share_amount = coin::value(&bet_share);

        ensure!(bet_share_amount > 0, E_ZERO_BET);

        let (reserve_x, reserve_y, bet_share_supply) = get_amounts(pool);
        let x_removed = (reserve_x * bet_share_amount) / bet_share_supply;
        let y_removed = (reserve_y * bet_share_amount) / bet_share_supply;

        balance::decrease_supply(&mut pool.bet_share_supply, coin::into_balance(bet_share));

        (
            coin::from_balance(coin::take(&mut pool.reserve_x, x_removed, ctx), ctx),
            coin::from_balance(coin::take(&mut pool.reserve_y, y_removed, ctx), ctx),
        )
    }

    // === Public-View Functions ===

    public fun price_x_to_y<X, Y>(pool: &BetPool<X, Y>, delta_y: u64) -> u64 {
        let (reserve_x, reserve_y, _) = get_amounts(pool);
        get_input_price(delta_y, reserve_y, reserve_x, pool.fee_percent)
    }

    public fun price_y_to_x<X, Y>(pool: &BetPool<X, Y>, delta_x: u64) -> u64 {
        let (reserve_x, reserve_y, _) = get_amounts(pool);
        get_input_price(delta_x, reserve_x, reserve_y, pool.fee_percent)
    }

    // === Helper Functions ===

    public fun get_amounts<X, Y>(pool: &BetPool<X, Y>) -> (u64, u64, u64) {
        (
            balance::value(&pool.reserve_x),
            balance::value(&pool.reserve_y),
            balance::supply_value(&pool.bet_share_supply),
        )
    }

    public fun get_input_price(
        input_amount: u64,
        input_reserve: u64,
        output_reserve: u64,
        fee_percent: u64
    ) -> u64 {
        let (
            input_amount,
            input_reserve,
            output_reserve,
            fee_percent,
        ) = (
            (input_amount as u128),
            (input_reserve as u128),
            (output_reserve as u128),
            (fee_percent as u128),
        );

        let input_amount_with_fee = input_amount * (FEE_SCALING - fee_percent);
        let numerator = input_amount_with_fee * output_reserve;
        let denominator = (input_reserve * FEE_SCALING) + input_amount_with_fee;

        (numerator / denominator as u64)
    }
}
