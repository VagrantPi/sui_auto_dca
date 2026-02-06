module sui_auto_dca::sui_auto_dca;

use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use deepbook::pool;
use token::deep::DEEP; 

const BASIS_POINTS_DIVISOR: u128 = 10000;
const MIN_DCA_LIMIT: u64 = 100_000_000;

// Errors
#[error]
const ETIMESTAMP_NOT_REACHED: vector<u8> = b"Time interval not yet reached";
#[error]
const EAMOUNT_BELOW_MINIMUM: vector<u8> = b"DCA amount below minimum limit";
#[error]
const EINSUFFICIENT_BALANCE: vector<u8> = b"Insufficient balance";
#[error]
const EUNAUTHORIZED: vector<u8> = b"Unauthorized";
#[error]
const EINVALID_FEE: vector<u8> = b"Fee setting allows overflow or exceeds 100%";

// --- Objects ---

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

public struct AdminCap has key, store { id: UID }

#[allow(lint(coin_field))]
/// HOT POTATO: 這個結構沒有 drop, store, key
/// 這保證了它必須在交易結束前被此模組銷毀
public struct DcaRequest<phantom T> {
    balance: Balance<T>,
    fee_coin: Coin<T>,      // 把手續費先切出來
    keeper_coin: Coin<T>,   // Keeper 的獎勵先切出來
    owner: address
}

// --- Init & Config ---

fun init(ctx: &mut TxContext) {
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

public fun create_config(
    total_fee_bps: u64, keeper_share_rate: u64, beneficiary: address, ctx: &mut TxContext
) {
    // [安全性修正] 確保費率邏輯合理
    assert!(total_fee_bps <= BASIS_POINTS_DIVISOR as u64, EINVALID_FEE);
    assert!(keeper_share_rate <= BASIS_POINTS_DIVISOR as u64, EINVALID_FEE);
    
    transfer::share_object(DCAConfig {
        id: object::new(ctx),
        total_fee_bps,
        keeper_share_rate,
        min_dca_limit: MIN_DCA_LIMIT,
        beneficiary,
    });
}

public fun update_config(
    config: &mut DCAConfig,
    total_fee_bps: u64, 
    keeper_share_rate: u64, 
    beneficiary: address,
    _cap: &AdminCap // 需要 Admin 權限
) {
    assert!(total_fee_bps <= 10000, EINVALID_FEE);
    assert!(keeper_share_rate <= 10000, EINVALID_FEE);
    
    config.total_fee_bps = total_fee_bps;
    config.keeper_share_rate = keeper_share_rate;
    config.beneficiary = beneficiary;
}

public fun create_dca_plan<T>(dca_amount: u64, interval: u64, ctx: &mut TxContext) {
    let plan = DCAPlan<T> {
        id: object::new(ctx),
        owner: ctx.sender(),
        balance: balance::zero(),
        dca_amount,
        last_execution: 0,
        interval,
    };
    transfer::share_object(plan);
}
public fun deposit_susdc<T>(plan: &mut DCAPlan<T>, coin: Coin<T>, ctx: &mut TxContext) {
    // 防止粉塵攻擊
    assert!(ctx.sender() == plan.owner, EUNAUTHORIZED);

    balance::join(&mut plan.balance, coin.into_balance());
}
public fun withdraw_susdc<T>(plan: &mut DCAPlan<T>, amount: u64, ctx: &mut TxContext) {
    assert!(ctx.sender() == plan.owner, EUNAUTHORIZED);
    let withdraw = plan.balance.split(amount);
    transfer::public_transfer(coin::from_balance(withdraw, ctx), plan.owner);
}

// --- 安全的 Pipeline 執行流程 ---

/// 步驟 1: 啟動 DCA
/// 這裡不做 swap，只做檢查、狀態更新、扣款，並打包成 Hot Potato
public fun start_dca<T>(
    plan: &mut DCAPlan<T>,
    config: &DCAConfig,
    clock: &Clock,
    ctx: &mut TxContext
): DcaRequest<T> {
    let current_time = clock::timestamp_ms(clock);
    
    assert!(current_time >= plan.last_execution + plan.interval, ETIMESTAMP_NOT_REACHED);
    assert!(plan.dca_amount >= config.min_dca_limit, EAMOUNT_BELOW_MINIMUM);
    assert!(plan.balance.value() >= plan.dca_amount, EINSUFFICIENT_BALANCE);

    // 更新狀態
    plan.last_execution = current_time;

    // 計算費用
    let total_fee = (plan.dca_amount as u128) * (config.total_fee_bps as u128) / BASIS_POINTS_DIVISOR;
    let keeper_share = total_fee * (config.keeper_share_rate as u128) / BASIS_POINTS_DIVISOR;
    
    let keeper_share_u64 = keeper_share as u64;
    let protocol_share_u64 = (total_fee as u64) - keeper_share_u64;

    // 資金切割
    let mut total_balance = plan.balance.split(plan.dca_amount);
    let keeper_bal = total_balance.split(keeper_share_u64);
    let protocol_bal = total_balance.split(protocol_share_u64);

    // 打包 Potato
    DcaRequest {
        balance: total_balance, // 剩下的就是 swap_amount
        fee_coin: coin::from_balance(protocol_bal, ctx),
        keeper_coin: coin::from_balance(keeper_bal, ctx),
        owner: plan.owner
    }
}

#[allow(lint(self_transfer))]
/// 步驟 2: 透過 DeepBook 執行交換 (解開 Potato)
/// 只有呼叫這個函數，start_dca 產生的 Request 才能被銷毀，交易才能成功
public fun resolve_via_deepbook<T>(
    request: DcaRequest<T>,
    config: &DCAConfig, // 為了拿 beneficiary 地址
    pool: &mut pool::Pool<T, SUI>,
    deep_coin: Coin<DEEP>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // 1. 解構 Potato
    let DcaRequest { balance, fee_coin, keeper_coin, owner } = request;

    // 2. 分發費用 (這時候給錢是安全的，因為 swap 已經「承諾」會發生)
    transfer::public_transfer(keeper_coin, ctx.sender());
    transfer::public_transfer(fee_coin, config.beneficiary);

    // 3. 執行 Swap
    let base_coin = coin::from_balance(balance, ctx);
    let (base_remaining, sui_coin, deep_remaining) = pool::swap_exact_base_for_quote<T, SUI>(
        pool,
        base_coin,
        deep_coin,
        min_out,
        clock,
        ctx
    );

    // 4. 結算給用戶
    transfer::public_transfer(sui_coin, owner);

    // 5. 處理剩餘款 (如果有)
    if (base_remaining.value() > 0) {
        transfer::public_transfer(base_remaining, owner);
    } else {
        base_remaining.destroy_zero();
    };

    transfer::public_transfer(deep_remaining, ctx.sender());
}

// === Test Helpers ===

#[test_only]
public fun config_total_fee_bps(config: &DCAConfig): u64 { config.total_fee_bps }
#[test_only]
public fun config_keeper_share_rate(config: &DCAConfig): u64 { config.keeper_share_rate }
#[test_only]
public fun config_beneficiary(config: &DCAConfig): address { config.beneficiary }
#[test_only]
public fun config_min_dca_limit(config: &DCAConfig): u64 { config.min_dca_limit }

#[test_only]
public fun plan_owner<T>(plan: &DCAPlan<T>): address { plan.owner }
#[test_only]
public fun plan_dca_amount<T>(plan: &DCAPlan<T>): u64 { plan.dca_amount }
#[test_only]
public fun plan_interval<T>(plan: &DCAPlan<T>): u64 { plan.interval }
#[test_only]
public fun plan_last_execution<T>(plan: &DCAPlan<T>): u64 { plan.last_execution }
#[test_only]
public fun plan_balance_value<T>(plan: &DCAPlan<T>): u64 { plan.balance.value() }

#[test_only]
public fun request_owner<T>(request: &DcaRequest<T>): address { request.owner }