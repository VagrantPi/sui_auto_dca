# sui_auto_dca

## Auto-DCA

自動定投合約

原本規劃是將 USDC 放進去後時間到就做 swap，但這樣資金利用率太低，因此改成設計成轉入 sUSDC(SCALLOP_USDC)，這樣在購買前還有一點點的 APR 可以賺

而預期是設定好頻率，時間一到，就會有 Keeper（路人）來幫你按按鈕，自動去 DeepBook 把 sUSDC 換成 SUI 給你。

Keeper 會獲得一些獎勵，如果都沒有人做項目方應該要寫排程自行做

本次完全 AI 實作，但跟 AI 討論功能到一半後發現 cetus 已有 DCA 功能，不過就醬吧。順便做做練習

## 使用 AI 遇到的各種坑

### cetus vs DeepBook

原本打算用 cetus 來做 swap 但如上所說，那乾脆用 sui 官方的 DeepBook

遇到了 ai 解不了的問題（這邊用的是 MiniMax M2.1 Free）

DeepBook v3 沒有在 `MystenLabs/sui` 底下，底下的 DeepBook 是舊版的

然後就進入死循環（我的 ai）

- DeepBook V3 (Testnet 版)：它是幾個月前部署的。當時它編譯時，鎖定了 當時那一版 的 Sui Framework (v1.0)。
- 我的專案 (現在)：你現在 sui move build，預設會去拉 最新版 的 Sui Framework (v2.0)。

最終還是靠 AI 強制解決依賴性問題，這邊體驗了一波 sui 生態系版本間依賴問題

```toml
[package]
name = "sui_auto_dca"
edition = "2024"

[dependencies]
# 1. 強制覆寫 Move 標準函式庫 (解決 0x1 衝突)
MoveStdlib = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/move-stdlib", rev = "framework/testnet", override = true }

# 2. 強制覆寫 Sui 框架 (解決 0x2 衝突)
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet", override = true }

# 3. DeepBook 依賴 (維持不變)
deepbook = { git = "https://github.com/MystenLabs/deepbookv3.git", subdir = "packages/deepbook", rev = "main" }
token = { git = "https://github.com/MystenLabs/deepbookv3.git", subdir = "packages/token", rev = "main" }

[addresses]
sui_auto_dca = "0x0"
```

當初串 cetus 應該會相對簡單點


### Hot Potato

依照老師的課上講的，sui move 都會盡量簡單，為了就是可以包成各式各樣的 PTB

而按造原本 spec.md 去跑，AI 會產生一個巨大的 execute_dca function，此時跟他說了上面的這段設計哲學後因此 AI 又重構了一版

- 場景 1：標準流程 (Auto-DCA)
    前端構建一個 PTB，依序呼叫：
    1. sui_auto_dca::start_dca -> 拿到 coin_a
    2. sui_auto_dca::take_fees(coin_a) -> 拿到 coin_b (淨額)
    3. sui_auto_dca::deepbook_swap(coin_b) -> 拿到 sui_coin, dust_coin
    4. sui_auto_dca::settle_proceeds(sui_coin) -> 錢進用戶口袋
    5. sui_auto_dca::restock(dust_coin) -> 零錢存回去

- 場景 2：Cetus 比較划算 (聚合路由)
    如果 DeepBook 深度不夠，Keeper 可以動態改變 PTB：
    1. sui_auto_dca::start_dca
    2. sui_auto_dca::take_fees
    3. cetus::router::swap(...) <-- 直接換成呼叫 Cetus，合約完全不用改！
    4. sui_auto_dca::settle_proceeds (只要最後是 SUI，都能用這函數給用戶)

但聰明的你一定發現了，move 都是 `public fun` 我要怎麼確保 Keeper 一定會乖乖全部跑呢？

這邊就用到了老師上課講到的 Hot Potato

不給任何能力，因此對方在做完 flash_loan 時需要去清空 receipt

因此又請 AI 進行重構了一版

1. `start_dca<T>(plan: &mut DCAPlan<T>, ...`
2. `resolve_via_deepbook<T>( request: DcaRequest<T>, ...`

未來可以隨意擴充

2. `resolve_via_cetus<T>(req: DcaRequest<T>, ...`

## 使用流程

[Guideline.md](./Guideline.md)
