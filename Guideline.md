### 0. 環境變數設定 (請先在終端機執行)

為了讓後面的指令好複製貼上，請先設定這些變數。

```bash
# 你的合約 Package ID (從你的部署結果貼上)
export PACKAGE_ID=

# 你的錢包地址 (Admin & User & Keeper 假設都先用同一個)
export MY_ADDR=$(sui client active-address)

# DeepBook V3 相關設定 (Sui Testnet)
# Native USDC (Testnet)
export SUSDC_TYPE="0x854950aa624b1df59fe64e630b2ba7c550642e9342267a33061d59fb31582da5::scallop_usdc::SCALLOP_USDC"
# DEEP Token (Testnet) - 手續費需要
export DEEP_TYPE="0xdeeb7a4662eec9f2f3def03fb937a663dddaa2e215b8078a284d026b7946c270::deep::DEEP"
# SUI/USDC Pool ID (DeepBook V3 Testnet) - 需確認目前流動性池 ID，這是一個常見的 Testnet Pool ID
export POOL_ID=""

# 你的模組名稱
export MODULE="sui_auto_dca"
```

---

### 1. 取得測試代幣 (USDC & DEEP)

* **領取 Testnet SUI**: 在 Discord `#testnet-faucet` 輸入 `!faucet <YOUR_ADDRESS>`.
* **領取 Testnet USDC**: https://faucet.circle.com/

* **領取/購買 Testnet DEEP**:
* DeepBook 交易需要 DEEP 代幣支付手續費。請在 Cetus 或 DeepBook UI 上用 SUI 換一點 DEEP (例如 10 顆就夠用很久)。

> **注意**: 確保你的錢包裡有至少一個 `USDC` Object 和一個 `DEEP` Object。你可以用 `sui client gas --coin $SUSDC_TYPE` 查看。

---

### 2. 初始化 Config (Admin 操作)

首先，你需要建立全域設定檔 `DCAConfig`。

* **參數**:
* `total_fee_bps`: 100 (代表 1%)
* `keeper_share_rate`: 3000 (代表 Keeper 拿手續費的 30%)
* `beneficiary`: `$MY_ADDR` (剩下的錢給誰)

```bash
sui client call \
  --package $PACKAGE_ID \
  --module $MODULE \
  --function create_config \
  --args 100 3000 $MY_ADDR \
  --gas-budget 50000000

```

🛑 **重要**: 執行成功後，在輸出結果的 `Created Objects` 中找到 `DCAConfig` 的 **Object ID**。

```bash
export CONFIG_ID=<貼上你的 Config ID>

```

---

### 3. 用戶建立 DCA 計畫 (User 操作)

建立一個每隔 1 分鐘 (60000 ms) 定投 1 USDC 的計畫。

* **參數**:
* `dca_amount`: 1000000 (USDC 精度為 6，所以這是 1 USDC)
* `interval`: 60000 (毫秒)



```bash
sui client call \
  --package $PACKAGE_ID \
  --module $MODULE \
  --function create_dca_plan \
  --type-args $SUSDC_TYPE \
  --args 1000000 60000 \
  --gas-budget 50000000

```

🛑 **重要**: 找到 `Created Objects` 中的 `DCAPlan` ID。

```bash
export PLAN_ID=<貼上你的 Plan ID>

```

---

### 4. 用戶存入資金 (User 操作)

把你的 USDC 存入 Plan。

1. 先找出你的 USDC Coin ID：
```bash
sui client gas --coin $SUSDC_TYPE

```


複製其中一個餘額足夠的 **Coin ID**。
2. 執行存款 (假設存入整顆 Coin)：
```bash
export MY_USDC_COIN=<貼上你的 USDC Coin ID>

sui client call \
  --package $PACKAGE_ID \
  --module $MODULE \
  --function deposit_susdc \
  --type-args $SUSDC_TYPE \
  --args $PLAN_ID $MY_USDC_COIN \
  --gas-budget 50000000

```



---

### 5. 執行 DCA (Keeper 操作 - 核心 PTB)

這是最關鍵的一步。因為我們將邏輯拆成了 `start_dca` 和 `resolve_via_deepbook`，且中間傳遞的是 **Hot Potato**，我們**必須**用 `sui client ptb` 在同一筆交易完成。

1. 先找出你的 DEEP Coin ID (付手續費用的)：
```bash
sui client gas --coin $DEEP_TYPE

```


```bash
export MY_DEEP_COIN=<貼上你的 DEEP Coin ID>

```


2. **執行 PTB 指令**:
這串指令做了以下事情：
1. 呼叫 `start_dca`，將結果存入變數 `req` (這就是 Hot Potato)。
2. 呼叫 `resolve_via_deepbook`，傳入 `req`、Config、Pool、Deep代幣、滑點(設為0)、Clock。



```bash
sui client ptb \
  --move-call $PACKAGE_ID::$MODULE::start_dca \
    <$SUSDC_TYPE> \
    @$PLAN_ID @$CONFIG_ID @0x6 \
  --assign req \
  --move-call $PACKAGE_ID::$MODULE::resolve_via_deepbook \
    <$SUSDC_TYPE> \
    req @$CONFIG_ID @$POOL_ID @$MY_DEEP_COIN 0 @0x6 \
  --gas-budget 100000000

```

**如果執行成功：**

* 你會看到 `Status: Success`。
* 你的錢包會收到 Swap 換回來的 SUI。
* 你的錢包會收到 Keeper Reward (USDC)。
* Beneficiary 錢包會收到 Protocol Fee (USDC)。
* Plan 的 `last_execution` 時間會更新。

**如果失敗 (例如 `ETIMESTAMP_NOT_REACHED`)**:

* 這代表距離上次執行的時間還不到 60 秒。請稍等一下再執行。

---

### 常見問題排除

1. **找不到 Pool ID?**
DeepBook V3 的 Pool ID 在 Testnet 可能會變動。你可以到 [Suiscan Testnet](https://www.google.com/search?q=https://suiscan.xyz/testnet/objects) 搜尋 DeepBook 相關的物件，或者直接使用 Explorer 觀察別人在 DeepBook 交易的紀錄來抓 Pool ID。
* 如果上面的 `0x18d...` 不能用，請嘗試在 DeepBook 官方文件或 Discord 找最新的 Testnet USDC/SUI Pool。


2. **餘額不足 (EAMOUNT_BELOW_MINIMUM)**
確認你存入 Plan 的錢 (`balance`) 是否大於你設定的 `dca_amount` (例如 1000000)。
3. **Coin 類型錯誤**
確保 `$SUSDC_TYPE` 字串完全正確，包含 `::coin::COIN` 後綴。

這個 CLI 流程能讓你完整驗證合約的每個功能。祝測試順利！