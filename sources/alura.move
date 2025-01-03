module alura::agent {
    use std::signer;
    use std::string::{Self, String};
    use aptos_framework::coin::{Self, CoinInfo, register, withdraw, deposit, mint, initialize};
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use alura::events;
    use aptos_std::debug;
    
    // Constants
    const MAX_TICK: u64 = 887272; // Example max tick value (Uniswap-style)
    const MIN_TICK: u64 = 0;      // Example min tick value
    const GROWTH_PARAMETER: u64 = 500;  // Growth parameter for bonding curve
    const AUCTION_DURATION: u64 = 3600; // 1 hour in seconds
    const TOTAL_SUPPLY: u64 = 100000000000000000; // 1 billion tokens
    const INITIAL_MARKET_CAP: u64 = 2000 * 100000000; // 2000 APT in base units (1 APT = 100M base units)

    /// Error: Invalid parameter 
    const EINVALID_PARAMETER: u64 = 0;

    /// Error: Invalid signer
    const EINVALID_SIGNER: u64 = 1;

    /// Error: Not enough tokens in the bonding curve
    const ENOT_ENOUGH_TOKENS: u64 = 2;

    /// Error: Slippage exceeded the acceptable threshold
    const ESLIPPAGE_EXCEEDED: u64 = 3;

    /// Error: Insufficient APT balance
    const EINSUFFICIENT_APT_BALANCE: u64 = 4;

    /// Error: Dutch auction is still active
    const EAUCTION_STILL_ACTIVE: u64 = 5;

    // Struct to store resource account information
    struct ResourceInfo has key {
        resource_cap: account::SignerCapability,
        source: address, // Address of the creator
    }

    // Struct to store agent information
    struct Agent has key {
        name: string::String,
        ticker: string::String,
        description: string::String,
        tg: string::String,
        website: string::String,
        theme: string::String,
        image: string::String,
        remaining_supply: u64,
        creator: address,
        reserve_balance: u64,
        start_time: u64,
        end_time: u64,
        initial_price: u64, // Initial price in base units
    }

    // Struct to store auction state
    struct DutchAuction has key {
        current_tick: u64,        // Current tick (price)
        sold_tokens: u64,         // Tokens sold so far
        bonding_curve_active: bool, // Whether bonding curve is active
    }

    // Struct to store bonding curve state
    struct BondingCurve has key {
        origin_tick: u64,         // Origin tick for bonding curve
        growth_parameter: u64,    // Growth parameter (y)
        max_time: u64,            // Max time for bonding curve
    }

    /// Create a new agent with a resource account
    public entry fun create_agent<CoinType>(
        account: &signer,
        name: String,
        ticker: String,
        description: String,
        tg: String,
        website: String,
        theme: String,
        image: String,
        seeds: vector<u8>
    ) {
        // Create the resource account for the bonding curve
        let (_resource, resource_cap) = account::create_resource_account(account, seeds);
        let resource_signer = account::create_signer_with_capability(&resource_cap);

        // Save resource account information
        move_to<ResourceInfo>(
            &resource_signer,
            ResourceInfo { resource_cap, source: signer::address_of(account) }
        );

        // Calculate the initial price based on the desired market cap
        let initial_price = INITIAL_MARKET_CAP / TOTAL_SUPPLY; // Price per token in base units

        let start_time = timestamp::now_seconds();
        // Initialize the Agent struct
        let agent = Agent {
            name,
            ticker,
            description,
            tg,
            website,
            theme,
            image,
            remaining_supply: TOTAL_SUPPLY,
            creator: signer::address_of(account),
            reserve_balance: 0,
            start_time,
            end_time: start_time + AUCTION_DURATION,
            initial_price
        };

        // Store the Agent in the resource account
        move_to(&resource_signer, agent);
        // Initialize the Dutch auction
        let auction = DutchAuction {
            current_tick: MAX_TICK,
            sold_tokens: 0,
            bonding_curve_active: false,
        };
        move_to(&resource_signer, auction);
        // Initialize the bonding curve
        let bonding_curve = BondingCurve {
            origin_tick: MIN_TICK,
            growth_parameter: GROWTH_PARAMETER,
            max_time: AUCTION_DURATION,
        };
        move_to(&resource_signer, bonding_curve);
        
        // Initialize and mint the token
        let (burn_cap, freeze_cap, mint_cap) = initialize<CoinType>(
            account, name, ticker, 8, true
        );
        register<CoinType>(&resource_signer);
        register<AptosCoin>(&resource_signer);
        let minted_tokens = mint<CoinType>(TOTAL_SUPPLY, &mint_cap);
        deposit<CoinType>(signer::address_of(&resource_signer), minted_tokens);

        // Destroy unused capabilities
        coin::destroy_freeze_cap(freeze_cap);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);

        // Emit an event for agent creation
        events::emit_create_event(
            name, ticker, description, tg, website, theme, image, TOTAL_SUPPLY, signer::address_of(account), 0
        );
    }

    /// Buy tokens during the Dutch auction or bonding curve phase
    public entry fun buy_tokens<CoinType>(
        account: &signer,
        apt_amount: u64, // Amount of APT to spend
        agent_address: address,
        max_slippage: u64, // Maximum acceptable slippage
    ) acquires Agent, ResourceInfo, DutchAuction, BondingCurve {
        let resource_account_info = borrow_global<ResourceInfo>(agent_address);
        let resource_signer = account::create_signer_with_capability(&resource_account_info.resource_cap);
        let agent = borrow_global_mut<Agent>(agent_address);
        let auction = borrow_global_mut<DutchAuction>(signer::address_of(&resource_signer));
        let bonding_curve = borrow_global_mut<BondingCurve>(signer::address_of(&resource_signer));
        let current_time = timestamp::now_seconds();

        // Calculate the expected price
        let expected_price = if (!auction.bonding_curve_active && current_time < agent.end_time) {
            calculate_dutch_price(auction, agent.start_time, agent.end_time)
        } else {
            let time_elapsed = current_time - agent.start_time;
            calculate_bonding_price(bonding_curve, time_elapsed)
        };

        // Check slippage
        let actual_price = auction.current_tick;
        // assert!(actual_price <= expected_price + max_slippage, ESLIPPAGE_EXCEEDED); //uncomment in future

        // Calculate the number of tokens to transfer based on the APT amount and current price
        let tokens_to_transfer = apt_amount * 100000000 / expected_price; // Convert APT to base units and calculate tokens

        // Ensure there are enough tokens remaining in the resource account
        assert!(agent.remaining_supply >= tokens_to_transfer, ENOT_ENOUGH_TOKENS);

        // Transfer APT from the user to the resource account
        let apt_coins = coin::withdraw<AptosCoin>(account, apt_amount);
        coin::deposit<AptosCoin>(signer::address_of(&resource_signer), apt_coins);
        register<CoinType>(account);

        // Transfer tokens from the resource account to the user's account
        let tokens = coin::withdraw<CoinType>(&resource_signer, tokens_to_transfer);
        coin::deposit<CoinType>(signer::address_of(account), tokens);

        // Update auction state
        auction.current_tick = expected_price;
        auction.sold_tokens = auction.sold_tokens + tokens_to_transfer;
        agent.remaining_supply = agent.remaining_supply - tokens_to_transfer;

        // Emit an event for the token purchase
        events::emit_buy_event(signer::address_of(account), apt_amount);

    }

    /// Sell tokens after the Dutch auction has ended
    public entry fun sell_tokens<CoinType>(
        account: &signer,
        token_amount: u64, // Amount of tokens to sell
        agent_address: address,
        max_slippage: u64, // Maximum acceptable slippage
    ) acquires Agent, ResourceInfo, DutchAuction, BondingCurve {
        let resource_account_info = borrow_global<ResourceInfo>(agent_address);
        let resource_signer = account::create_signer_with_capability(&resource_account_info.resource_cap);
        let agent = borrow_global<Agent>(agent_address);
        let auction = borrow_global<DutchAuction>(signer::address_of(&resource_signer));
        let current_time = timestamp::now_seconds();

        // Ensure the Dutch auction has ended
        assert!(current_time >= agent.end_time, EAUCTION_STILL_ACTIVE);

        // Calculate the current price based on the bonding curve
        let bonding_curve = borrow_global<BondingCurve>(signer::address_of(&resource_signer));
        let time_elapsed = current_time - agent.start_time;
        let current_price = calculate_bonding_price(bonding_curve, time_elapsed);

        // Calculate the amount of APT to send to the user
        let apt_to_send = token_amount * current_price / 100000000; // Convert base units to APT

        // Ensure the resource account has enough APT to send
        let apt_balance = coin::balance<AptosCoin>(signer::address_of(&resource_signer));
        assert!(apt_balance >= apt_to_send, EINSUFFICIENT_APT_BALANCE);

        // Transfer tokens from the user to the resource account
        let tokens = coin::withdraw<CoinType>(account, token_amount);
        coin::deposit<CoinType>(signer::address_of(&resource_signer), tokens);

        // Transfer APT from the resource account to the user
        let apt_coins = coin::withdraw<AptosCoin>(&resource_signer, apt_to_send);
        coin::deposit<AptosCoin>(signer::address_of(account), apt_coins);

        // Emit an event for the token sale
        events::emit_sell_event(signer::address_of(account), token_amount);

    }

    // Calculate the current price based on the Dutch auction
    fun calculate_dutch_price(
        auction: &DutchAuction,
        start_time: u64,
        end_time: u64,
    ): u64 {
        let current_time = timestamp::now_seconds();
        if (current_time >= end_time) {
            return MIN_TICK // Auction ended, price is at min tick
        };
        let time_elapsed = current_time - start_time;
        let total_time = end_time - start_time;
        let price_delta = (MAX_TICK - MIN_TICK) * time_elapsed / total_time;
        MAX_TICK - price_delta
    }

    // Calculate the price based on the bonding curve
    fun calculate_bonding_price(
        bonding_curve: &BondingCurve,
        time_elapsed: u64,
    ): u64 {
        let current_tick = bonding_curve.origin_tick + (bonding_curve.growth_parameter * time_elapsed / bonding_curve.max_time);
        current_tick
    }

    #[view]
    public fun get_bonding_curve_status(agent_address: address): (u64, u64, u64) acquires Agent, ResourceInfo,DutchAuction, BondingCurve {
        let resource_account_info = borrow_global<ResourceInfo>(agent_address);
        let resource_signer = account::create_signer_with_capability(&resource_account_info.resource_cap);
        let agent = borrow_global<Agent>(agent_address);
        let auction = borrow_global<DutchAuction>(signer::address_of(&resource_signer));
        let bonding_curve = borrow_global<BondingCurve>(signer::address_of(&resource_signer));
        let current_time = timestamp::now_seconds();

        // Calculate the current price
        let current_price = if (!auction.bonding_curve_active && current_time < agent.end_time) {
            calculate_dutch_price(auction, agent.start_time, agent.end_time)
        } else {
            let time_elapsed = current_time - agent.start_time;
            calculate_bonding_price(bonding_curve, time_elapsed)
        };

        // Get the reserve balance (APT balance in the resource account)
        let reserve_balance = coin::balance<AptosCoin>(signer::address_of(&resource_signer));

        // Return the bonding curve status
        (agent.remaining_supply, current_price, reserve_balance)
    }

    #[test(account = @0x1)]
    public fun initialize_for_test() {
        debug::print(&calculate_price(TOTAL_SUPPLY, 200000000000));
    }
}