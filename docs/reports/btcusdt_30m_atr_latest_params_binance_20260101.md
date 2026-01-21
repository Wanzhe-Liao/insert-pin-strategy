# BTCUSDT_30m（ATR）更新到 2026-01-01 的最新参数（Binance 数据）

本次使用脚本在运行前从 Binance Vision API 追加 K 线（30m）到指定日期，然后做滚动 Walk-Forward + 参数优化。

## 数据更新

- 数据集：`BTCUSDT_30m`
- 追加来源：Binance Vision API（`https://data-api.binance.vision/api/v3/klines`，使用 closeTime 作为 bar 时间戳以对齐现有数据索引）
- 追加到：`2026-01-01`（UTC，按日包含至 `23:59:59.999`）

## 回测与优化设置

- signalMode：`atr`（atrLength=14）
- Walk-Forward：按月滚动，train=12 个月，test=1 个月，仅跑最后 12 个窗口
- 搜索空间：lookback ∈ [2,20]；dropATR ∈ [4,12]；TP% ∈ [0.2,8]；SL% ∈ [0.2,12]
- 优化方法：2-stage random search（phase1=200 + phase2=200），训练集硬过滤 `TradeCount>=10` 且 `Return>0`

## 结果与“最新参数”

### TradingView 出场模型（建议用于 TV 策略 `strategy.exit(limit/stop)`）

- 输出目录：`walkforward_atr_btc30m_binance_20260101/`
- 汇总：`walkforward_atr_btc30m_binance_20260101/BTCUSDT_30m_atr_wf_summary.md`
- 明细：`walkforward_atr_btc30m_binance_20260101/BTCUSDT_30m_atr_wf_details.csv`

最新窗口（test=2026-01，train=2025-01..2025-12）的参数：

- lookback=12
- dropATR=5.10
- TP=1.85%
- SL=3.20%
- exitMode=`tradingview`

> 注：由于你要求数据截止到 2026-01-01，`2026-01` 这个 test 月只有少量 bars，OOS 该月可能出现 0 信号/0 交易（属于数据不完整导致，不代表策略永远不交易）。

### Close 出场模型（用于 R/收盘触发口径）

- 输出目录：`walkforward_atr_btc30m_binance_20260101_close/`
- 汇总：`walkforward_atr_btc30m_binance_20260101_close/BTCUSDT_30m_atr_wf_summary.md`
- 明细：`walkforward_atr_btc30m_binance_20260101_close/BTCUSDT_30m_atr_wf_details.csv`

最新窗口（test=2026-01，train=2025-01..2025-12）的参数：

- lookback=14
- dropATR=5.50
- TP=0.30%
- SL=10.10%
- exitMode=`close`

