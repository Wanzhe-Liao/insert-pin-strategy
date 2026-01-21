# ATR 标化滚动 Walk-Forward 结果（BTC / BNB / ETH）

统一设置（与对应明细一致）：

- signalMode: `atr`（atrLength=14）
- Walk-Forward：按月滚动，`train=12` 个月，`test=1` 个月，仅统计最后 `12` 个窗口（OOS）
- 参数搜索空间：lookback ∈ [2,20]；dropATR ∈ [4,12]；TP% ∈ [0.2,8]；SL% ∈ [0.2,12]
- 费用：feeRate=0.00075；回测引擎：`backtest_tradingview_aligned()`（TV 对齐，`exitMode="close"`）

## 汇总（OOS）

| dataset | OOS累计收益 | OOS最大回撤 | 月均收益 | 月波动 | Sharpe(年化) | OOS月份(+/-/0) | 明细 |
|---|---:|---:|---:|---:|---:|---:|---|
| BTCUSDT_30m | +75.00% | -15.21% | +5.48% | 13.21% | 1.44 | 10 / 2 / 0 | `walkforward_atr_drop4_full/BTCUSDT_30m_atr_wf_details.csv` |
| BNBUSDT_15m | +24.40% | -25.13% | +2.37% | 10.97% | 0.75 | 6 / 6 / 0 | `walkforward_atr_drop4_full/BNBUSDT_15m_atr_wf_details.csv` |
| ETHUSDT_30m | -26.87% | -41.49% | -2.12% | 9.66% | -0.76 | 3 / 7 / 2 | `walkforward_atr_drop4_full/ETHUSDT_30m_atr_wf_details.csv` |

对应 summary：

- `walkforward_atr_drop4_full/BTCUSDT_30m_atr_wf_summary.md`
- `walkforward_atr_drop4_full/BNBUSDT_15m_atr_wf_summary.md`
- `walkforward_atr_drop4_full/ETHUSDT_30m_atr_wf_summary.md`

## 参数优化方法（每个 WF 窗口）

实现见：`r/scripts/walkforward/walk_forward_atr_quick.R`

1. Phase1：在给定范围内随机采样 200 组参数（lookback/minDrop(TP/SL) 以 0.05 为步长离散化）。
2. Phase2：取 Phase1 得分最高的一小批参数为中心，用高斯扰动做局部细化采样 200 组。
3. 评分与过滤（训练集）：
   - 硬过滤：`TradeCount < 10` 或 `ReturnPercent <= 0` 直接记为 0 分（避免极小样本/负收益参数在训练集“侥幸上榜”）。
   - 加权评分（0~1）：Return(0.45) + Drawdown 控制(0.30) + Trades(0.20) + WinRate(0.05)，其中 Return 做上限截断（cap=500%），Trades 用 `sqrt` 压缩。
4. 取训练集得分最高的一组参数，应用到下一月（test month）做 OOS 评估并记录到明细 CSV。
