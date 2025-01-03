module alura::events {
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::object::{Self, Object};
    use std::string::{Self, String};

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AluraEvents has key{
        buy_event: EventHandle<BuyEvent>,
        sell_event: EventHandle<SellEvent>,
        create_event: EventHandle<CreateEvent>,
    }
    struct BuyEvent has store, drop {
        buyer: address,
        amount: u64,
    }

    struct SellEvent has store, drop {
        seller: address,
        amount: u64,
    }

    struct CreateEvent has store, drop {
        name: String,
        ticker: String,
        description: String,
        tg: String,
        website: String,
        theme: String,
        image: String,
        remaining_supply: u64,
        creator: address,
        reserve_balance: u64,
    }

    /// Initialize the event store
    public entry fun init_events(account: &signer) {
        let constructor_ref = object::create_object_from_account(account);
        let object_signer = object::generate_signer(&constructor_ref);

        let event_handle = AluraEvents{
            buy_event: object::new_event_handle(&object_signer),
            sell_event: object::new_event_handle(&object_signer),
            create_event: object::new_event_handle(&object_signer),
        };
        move_to(account, event_handle);
    }

    public fun emit_create_event(
        name: String,
        ticker: String,
        description: String,
        tg: String,
        website: String,
        theme: String,
        image: String,
        remaining_supply: u64,
        creator: address,
        reserve_balance: u64
    ) acquires AluraEvents{
        let event_handle = borrow_global_mut<AluraEvents>(@alura);
        let create_event = CreateEvent {
            name,
            ticker,
            description,
            tg,
            website,
            theme,
            image,
            remaining_supply,
            creator,
            reserve_balance
        };
        event::emit_event(&mut event_handle.create_event,create_event);
    }

    public fun emit_buy_event(buyer: address, amount: u64) acquires AluraEvents{
        let event_handle = borrow_global_mut<AluraEvents>(@alura);
        let buy_event = BuyEvent {
            buyer,
            amount,
        };
        event::emit_event(&mut event_handle.buy_event,buy_event);

    }

    public fun emit_sell_event(seller: address, amount: u64) acquires AluraEvents{
        let event_handle = borrow_global_mut<AluraEvents>(@alura);
        let sell_event = SellEvent {
            seller,
            amount,
        };        
        event::emit_event(&mut event_handle.sell_event,sell_event);
    }
}