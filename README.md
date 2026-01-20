# 插针策略研究工作区

这个目录是一个“研究型脚本仓库”：围绕加密货币策略（如“三日暴跌接针”）的 **R 回测引擎（TradingView 对齐）**、参数优化、Walk-Forward，以及若干对比/验证/可视化脚本与报告。

## 从哪里开始

- 项目总览与入口：`docs/PROJECT_MAP.md`
- 已整理的策略交付包（含引擎/优化脚本/TV 代码）：`策略回测汇总_2025-10-27/README.md`

## 快速运行（R）

```r
# 1) 加载回测引擎
source("backtest_tradingview_aligned.R")

# 2) 加载数据（本仓库默认使用 data/liaochu.RData）
load("data/liaochu.RData")
data <- cryptodata[["ETHUSDT_30m"]]

# 3) 运行回测
result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 2,
  minDropPercent = 6.2,
  takeProfitPercent = 0.0,
  stopLossPercent = 7.4
)
print_performance_summary(result)
```

## 快速运行（Python）

```bash
python run_full_analysis.py
```
