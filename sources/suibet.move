// Allow the lint warning related to self-transfer within this module
#[allow(lint(self_transfer))]
module suibet::suibet {
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::coin::{Coin, Self as CoinSelf};
    use sui::balance::{Self as BalanceSelf, Balance};
    use sui::transfer::{transfer, share_object, public_transfer};
    use sui::object::{Self, UID};

    const FLOAT_SCALING: u64 = 1_000_000_000;

    // Define error constants for insufficient balance, denied access, and not being an owner
    const EInsufficientBalance: u64 = 0;
    const EDeniedAccess: u64 = 1;
    const ENotOwner: u64 = 2;

    // Define a struct `Admin` representing an administrator, with fields for ID, owner address, and balance
    struct Admin has key, store {
        id: UID,
        owner_address: address,
        balance: Balance<SUI>
    }

    // Define a struct `Player` representing a player, with fields for ID, player address, flagged status, balance, and date
    struct Player has key, store {
        id: UID,
        player_address: address,
        flagged: bool,
        balance: Balance<SUI>,
        date: u64
    }

    // Define a function `init` to initialize the administrator with an initial balance of zero
    fun init(ctx: &mut TxContext) {
        // Transfer ownership of an `Admin` object with zero balance to the sender of the transaction
        transfer(Admin{
            id: object::new(ctx),
            owner_address: sender(ctx),
            balance: BalanceSelf::zero()
        }, sender(ctx));
    }

    // Define an entry function `admin_address` to retrieve the address of the administrator
    public entry fun admin_address(admin: &Admin, ctx: &mut TxContext): address {
        // Ensure that the caller is the owner of the administrator
        assert!(admin.owner_address == sender(ctx), ENotOwner);
        // Return the address of the administrator
        admin.owner_address
    }

    // Define an entry function `player_address` to retrieve the address of a player
    public entry fun player_address(player: &Player): address {
        // Return the address of the player
        player.player_address
    }

    // Define an entry function `is_flagged` to check if a player is flagged
    public entry fun is_flagged(player: &Player): bool {
        // Return the flagged status of the player
        player.flagged
    }

    // Define a function `create_player` to create a new player
    public fun create_player(ctx: &mut TxContext, date: u64) {
        // Share a new `Player` object with the sender of the transaction
        share_object(
            Player{
                id: object::new(ctx),
                player_address: sender(ctx),
                flagged: false,
                balance: BalanceSelf::zero(),
                date: date
            }
        )
    }

    // Define a function `deposit` to deposit funds into a player's account
    public fun deposit(
        admin: &mut Admin,
        player: &mut Player,
        amount: &mut Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // Ensure that the caller is the player
        assert!(player.player_address == sender(ctx), ENotOwner);
        // Ensure that the deposited amount is sufficient
        assert!(CoinSelf::value(amount) >= FLOAT_SCALING*3, EInsufficientBalance);

        // Split the deposited amount
        let amount_balance_mut = CoinSelf::balance_mut(amount);
        let remaining_temp = BalanceSelf::split(amount_balance_mut, FLOAT_SCALING);
        let remaining_temp_2 = BalanceSelf::split(amount_balance_mut, FLOAT_SCALING);
        let remaining = BalanceSelf::split(amount_balance_mut, FLOAT_SCALING);
        let _amount = CoinSelf::from_balance(remaining, ctx);

        // Transfer the amount to the administrator
        public_transfer(_amount, admin.owner_address);

        // Update player and administrator balances
        BalanceSelf::join(&mut player.balance, remaining_temp);
        BalanceSelf::join(&mut admin.balance, remaining_temp_2);

    }

    // Define a function `withdraw` to withdraw funds from a player's account
    public fun withdraw (
        admin: &mut Admin,
        player: &mut Player,
        amount: Balance<SUI>,
        ctx: &mut TxContext
    ) {
        // Ensure that the withdrawal amount does not exceed the player's balance
        assert!(BalanceSelf::value(&amount) <= BalanceSelf::value(&player.balance), EInsufficientBalance);
        // Ensure that the caller is the player
        assert!(player.player_address == sender(ctx), ENotOwner);
        // Ensure that the player is not the administrator
        assert!(player.player_address != admin.owner_address, EDeniedAccess);

        // Calculate the withdrawal amount
        let amount_value = BalanceSelf::value(&amount);
        let withdraw_coin = CoinSelf::from_balance(amount, ctx);

        // Transfer the withdrawal amount to the sender's address
        public_transfer(withdraw_coin, sender(ctx));

        // Update player and administrator balances
        let remaining = BalanceSelf::split(&mut player.balance, amount_value);
        let remaining_admin = BalanceSelf::split(&mut admin.balance, amount_value);
        BalanceSelf::join(&mut player.balance, remaining);
        BalanceSelf::join(&mut admin.balance, remaining_admin);

    }

    // Define a function `place_bet` to place a bet
    public fun place_bet(
        house: &mut Admin,
        player: &mut Player,
        amount: &mut Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // Ensure that the caller is the player
        assert!(player.player_address == sender(ctx), ENotOwner);
        // Ensure that the bet amount is sufficient
        assert!(CoinSelf::value(amount) >= FLOAT_SCALING*2, EInsufficientBalance);

        // Split the bet amount
        let amount_balance = CoinSelf::balance_mut(amount);
        let remaining_temp = BalanceSelf::split(amount_balance, FLOAT_SCALING);
        let remaining = BalanceSelf::split(amount_balance, FLOAT_SCALING);
        let _amount = CoinSelf::from_balance(remaining, ctx);

        // Transfer the bet amount to the administrator (house)
        public_transfer(_amount, house.owner_address);

        // Update player balance
        BalanceSelf::join(&mut player.balance, remaining_temp);
    }

    // Define a function `flag_player` to toggle the flagged status of a player
    public fun flag_player(
        house: &Admin,
        player: &mut Player,
        ctx: &mut TxContext
    ) {
        // Ensure that the caller is the administrator (house)
        assert!(house.owner_address == sender(ctx), EDeniedAccess);
        // Toggle the flagged status of the player
        player.flagged = !player.flagged;
    }

}
