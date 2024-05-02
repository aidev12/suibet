// Allow the lint warning related to self-transfer within this module
#[allow(lint(self_transfer))]
module suibet::suibet {
    use sui::sui::SUI;
    use sui::tx_context::{TxContext, sender};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer::{transfer, share_object,};
    use sui::object::{Self, UID, ID};

    const FLOAT_SCALING: u64 = 1_000_000_000;

    // Define error constants for insufficient balance, denied access, and not being an owner
    const EInsufficientBalance: u64 = 0;
    const EDeniedAccess: u64 = 1;
    const ENotOwner: u64 = 2;

    // Define a struct `Admin` representing an administrator, with fields for ID, owner address, and balance
    struct Admin has key {
        id: UID,
    }

    struct Protocol has key,store {
        id: UID,
        balance:Balance<SUI>,
        fee: u128
    }

    // Define a struct `Player` representing a player, with fields for ID, player address, flagged status, balance, and date
    struct Account has key, store {
        id: UID,
        player_address: address,
        flagged: bool,
        balance: Balance<SUI>,
        date: u64
    }

    struct AccountCap has key {
        id: UID,
        to: ID
    }

    // Define a function `init` to initialize the administrator with an initial balance of zero
    fun init(ctx: &mut TxContext) {
        // Transfer ownership of an `Admin` object with zero balance to the sender of the transaction
        transfer(Admin{
            id: object::new(ctx),
        }, sender(ctx));
        // share the protocol object
        share_object(Protocol{
            id: object::new(ctx),
            balance: balance::zero(),
            fee: 5
        })
    }
    
    // Define an entry function `player_address` to retrieve the address of a player
    public entry fun player_address(player: &Account): address {
        // Return the address of the player
        player.player_address
    }

    // Define an entry function `is_flagged` to check if a player is flagged
    public entry fun is_flagged(player: &Account): bool {
        // Return the flagged status of the player
        player.flagged
    }

    // Define a function `create_player` to create a new player
    public fun create_player(ctx: &mut TxContext, date: u64) {
        // Share a new `Player` object with the sender of the transaction
        let id_ = object::new(ctx);
        let inner_ = object::uid_to_inner(&id_);
        share_object(
            Account{
                id: id_,
                player_address: sender(ctx),
                flagged: false,
                balance: balance::zero(),
                date: date
            }
        );
        transfer(AccountCap{id: object::new(ctx), to: inner_}, sender(ctx));
    }

    // Define a function `deposit` to deposit funds into a player's account
    public fun deposit(
        self: &mut Protocol,
        player: &mut Account,
        cap: &AccountCap,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // Ensure that the caller is the player
        assert!(cap.to == object::id(player), ENotOwner);
        assert!(!player.flagged, EDeniedAccess);
        // Split the deposited amount
        let value = coin::value(&coin);
        let deposit_value = value - (((value as u128) * self.fee / 100) as u64);
        let admin_fee = value - deposit_value;

        let admin_coin = coin::split(&mut coin, admin_fee, ctx);
        balance::join(&mut self.balance, coin::into_balance(admin_coin));
        balance::join(&mut player.balance, coin::into_balance(coin));
    }

    // Define a function `withdraw` to withdraw funds from a player's account
    public fun withdraw (
        cap: &AccountCap,
        player: &mut Account,
        amount: u64,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        // Ensure that the withdrawal amount does not exceed the player's balance
        assert!(cap.to == object::id(player), ENotOwner);
        // Calculate the withdrawal amount
        let coin_ = coin::take(&mut player.balance, amount, ctx);
        coin_
    }

    // Define a function `flag_player` to toggle the flagged status of a player
    public fun flag_player(
        _: &Admin,
        player: &mut Account,
    ) {
        player.flagged = !player.flagged;
    }
    // change the interest
    public fun new_interest(_:&Admin, self: &mut Protocol, num: u128) {
        assert!(num > 0 && num < 50, EDeniedAccess);
        self.fee = num;
    }
}
