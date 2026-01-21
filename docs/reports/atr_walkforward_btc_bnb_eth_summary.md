# ATR 标化滚动 Walk-Forward 结果（BTC / BNB / ETH × 5m/15m/30m/1h）

统一设置（与对应明细一致）：

- signalMode: `atr`（atrLength=14）
- Walk-Forward：按月滚动，`train=12` 个月，`test=1` 个月，仅统计最后 `12` 个窗口（OOS）
- 参数搜索空间：lookback ∈ [2,20]；dropATR ∈ [4,12]；TP% ∈ [0.2,8]；SL% ∈ [0.2,12]
- 费用：feeRate=0.00075；回测引擎：`backtest_tradingview_aligned()`（TV 对齐，`exitMode="close"`）
- 汇总 CSV：`docs/reports/atr_walkforward_btc_bnb_eth_all_timeframes_summary.csv`

## 结论

- 最佳：`BTCUSDT_30m`（Sharpe 1.44，OOS +75.00%，maxDD -15.21%，OOS 交易 101）
- BNB：`BNBUSDT_15m` / `BNBUSDT_1h` 为正且相对更稳（Sharpe 0.75 / 0.73）
- ETH：4 个分时在最近 12 个 OOS 月整体为负（最接近持平的是 `ETHUSDT_15m`：OOS -2.94%）

## 汇总（OOS，按 Sharpe 排序）

| dataset | OOS累计收益 | OOS最大回撤 | Sharpe | 月均收益 | 月波动 | OOS月份(+/-/0) | OOS交易数 | 月均交易 | OOS信号数 | 月均信号 | summary |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| BTCUSDT_30m | +75.00% | -15.21% | 1.44 | +5.48% | 13.21% | 10 / 2 / 0 | 101 | 8.42 | 1345 | 112.08 | `walkforward_atr_drop4_full/BTCUSDT_30m_atr_wf_summary.md` |
| BNBUSDT_15m | +24.40% | -25.13% | 0.75 | +2.37% | 10.97% | 6 / 6 / 0 | 126 | 10.50 | 2542 | 211.83 | `walkforward_atr_drop4_full/BNBUSDT_15m_atr_wf_summary.md` |
| BNBUSDT_1h | +16.50% | -18.07% | 0.73 | +1.51% | 7.23% | 7 / 5 / 0 | 116 | 9.67 | 532 | 44.33 | `walkforward_atr_drop4_full/BNBUSDT_1h_atr_wf_summary.md` |
| BNBUSDT_30m | +12.08% | -31.83% | 0.43 | +2.00% | 15.97% | 5 / 7 / 0 | 157 | 13.08 | 1361 | 113.42 | `walkforward_atr_drop4_full/BNBUSDT_30m_atr_wf_summary.md` |
| BTCUSDT_5m | -0.28% | -28.19% | 0.20 | +0.68% | 12.11% | 7 / 5 / 0 | 172 | 14.33 | 6014 | 501.17 | `walkforward_atr_drop4_full/BTCUSDT_5m_atr_wf_summary.md` |
| ETHUSDT_15m | -2.94% | -33.33% | 0.13 | +0.45% | 12.58% | 6 / 6 / 0 | 150 | 12.50 | 641 | 53.42 | `walkforward_atr_drop4_full/ETHUSDT_15m_atr_wf_summary.md` |
| BNBUSDT_5m | -6.65% | -32.31% | 0.08 | +0.32% | 13.83% | 7 / 5 / 0 | 178 | 14.83 | 2060 | 171.67 | `walkforward_atr_drop4_full/BNBUSDT_5m_atr_wf_summary.md` |
| BTCUSDT_15m | -15.81% | -32.41% | -0.30 | -0.91% | 10.47% | 6 / 6 / 0 | 145 | 12.08 | 3211 | 267.58 | `walkforward_atr_drop4_full/BTCUSDT_15m_atr_wf_summary.md` |
| ETHUSDT_30m | -26.87% | -41.49% | -0.76 | -2.12% | 9.66% | 3 / 7 / 2 | 88 | 7.33 | 396 | 33.00 | `walkforward_atr_drop4_full/ETHUSDT_30m_atr_wf_summary.md` |
| BTCUSDT_1h | -19.72% | -23.43% | -0.98 | -1.65% | 5.81% | 7 / 5 / 0 | 110 | 9.17 | 1000 | 83.33 | `walkforward_atr_drop4_full/BTCUSDT_1h_atr_wf_summary.md` |
| ETHUSDT_5m | -26.60% | -30.85% | -1.03 | -2.25% | 7.58% | 6 / 6 / 0 | 207 | 17.25 | 449 | 37.42 | `walkforward_atr_drop4_full/ETHUSDT_5m_atr_wf_summary.md` |
| ETHUSDT_1h | -46.13% | -46.13% | -2.05 | -4.70% | 7.93% | 2 / 7 / 3 | 52 | 4.33 | 279 | 23.25 | `walkforward_atr_drop4_full/ETHUSDT_1h_atr_wf_summary.md` |

## 参数优化方法（每个 WF 窗口）

实现见：`r/scripts/walkforward/walk_forward_atr_quick.R`

1. Phase1：在给定范围内随机采样 200 组参数（lookback/minDrop(TP/SL) 以 0.05 为步长离散化）。
2. Phase2：取 Phase1 得分最高的一小批参数为中心，用高斯扰动做局部细化采样 200 组。
3. 评分与过滤（训练集）：
   - 硬过滤：`TradeCount < 10` 或 `ReturnPercent <= 0` 直接记为 0 分（避免极小样本/负收益参数在训练集“侥幸上榜”）。
   - 加权评分（0~1）：Return(0.45) + Drawdown 控制(0.30) + Trades(0.20) + WinRate(0.05)，其中 Return 做上限截断（cap=500%），Trades 用 `sqrt` 压缩。
4. 取训练集得分最高的一组参数，应用到下一月（test month）做 OOS 评估并记录到明细 CSV。
