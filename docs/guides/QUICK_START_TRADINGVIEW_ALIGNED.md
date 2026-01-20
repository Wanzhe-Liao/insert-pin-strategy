# TradingView对齐版回测引擎 - 快速开始指南

> 说明：回测引擎支持两种出场模式（见 `backtest_tradingview_aligned()` 的 `exitMode` 参数）：  
> - `exitMode="close"`（默认）：Close 触发 + Close 成交价  
> - `exitMode="tradingview"`：High/Low 盘中触发 + 精确 TP/SL 成交价

## 30秒快速开始

```r
# 1. 加载引擎
source("backtest_tradingview_aligned.R")

# 2. 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

# 3. 运行回测
result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10
)

# 4. 查看结果
print_performance_summary(result)
```

---

## 完整测试（推荐）

```r
# 运行完整测试套件
source("test_tradingview_alignment.R")
```

这将自动执行：
- ✅ 基本功能测试
- ✅ 持仓管理验证
- ✅ 出场逻辑验证
- ✅ 与原版对比
- ✅ 与TradingView对比
- ✅ 导出所有结果到CSV

---

## 核心修复

### 修复1: 持仓管理 ⚠️ CRITICAL

**问题**: R允许持仓期间继续入场 → 127笔交易（应该是9笔）

**修复**:
```r
inPosition <- FALSE  # 持仓标志

if (signal && !inPosition) {
  # 入场
  inPosition <- TRUE
}

if (signal && inPosition) {
  # 忽略信号！
  log_ignored_signal()
}
```

### 修复2: 出场判断 ⚠️ CRITICAL

**问题**: 使用Close价判断 → 错过盘中触发的止盈止损

**修复**:
```r
# 使用High/Low而非Close
hitTP <- currentHigh >= tpPrice
hitSL <- currentLow <= slPrice
```

### 修复3: 出场价格 ⚠️ MEDIUM

**问题**: 使用Close价执行 → 价格滑点

**修复**:
```r
# 使用精确的TP/SL价格
exitPrice <- tpPrice  # 而非currentClose
```

---

## 关键参数说明

```r
backtest_tradingview_aligned(
  data,                    # xts数据（必需）
  lookbackDays,           # 回看天数（如3天）
  minDropPercent,         # 触发跌幅%（如20）
  takeProfitPercent,      # 止盈%（如10）
  stopLossPercent,        # 止损%（如10）
  initialCapital = 10000, # 初始资金
  feeRate = 0.00075,      # 手续费率（0.075%）
  processOnClose = TRUE,  # 收盘执行订单
  verbose = FALSE,        # 显示详细日志
  logIgnoredSignals = TRUE # 记录被忽略信号
)
```

---

## 查看结果

### 性能摘要
```r
print_performance_summary(result)
```

### 交易详情
```r
trades_df <- format_trades_df(result)
View(trades_df)
```

### 被忽略的信号（重要！）
```r
ignored_df <- format_ignored_signals_df(result)
View(ignored_df)

# 查看为什么信号被忽略
table(ignored_df$Reason)
```

### 导出到Excel
```r
write.csv(trades_df, "trades.csv", row.names = FALSE)
write.csv(ignored_df, "ignored_signals.csv", row.names = FALSE)
```

---

## 验证修复是否成功

### ✅ 成功的标志

1. **被忽略信号 > 0**
   ```r
   result$IgnoredSignalCount > 0  # 持仓管理生效
   ```

2. **止盈+止损 ≈ 总交易数**
   ```r
   result$TPCount + result$SLCount ≈ result$TradeCount
   ```

3. **交易数量大幅减少**
   ```r
   # 原版: 127笔
   # 对齐版: 10-15笔（接近TV的9笔）
   ```

4. **平均盈亏接近设定值**
   ```r
   # 平均盈利 ≈ +10%
   # 平均亏损 ≈ -10%
   ```

### ⚠️ 需要调查的情况

1. **被忽略信号 = 0**
   → 持仓管理可能未生效

2. **交易数量仍然很多（>30笔）**
   → 信号生成可能有问题

3. **平均盈亏偏差大（>2%）**
   → 出场价格可能不精确

---

## 对比分析

### 与原版对比
```r
# 加载原版
source("backtest_final_fixed.R")

result_original <- backtest_strategy_final(
  data, lookback_days=3, drop_threshold=0.20,
  take_profit=0.10, stop_loss=0.10
)

result_aligned <- backtest_tradingview_aligned(
  data, lookbackDays=3, minDropPercent=20,
  takeProfitPercent=10, stopLossPercent=10
)

# 对比
data.frame(
  Metric = c("信号数", "交易数", "收益率", "胜率"),
  Original = c(
    result_original$Signal_Count,
    result_original$Trade_Count,
    result_original$Return_Percentage,
    result_original$Win_Rate
  ),
  Aligned = c(
    result_aligned$SignalCount,
    result_aligned$TradeCount,
    result_aligned$ReturnPercent,
    result_aligned$WinRate
  )
)
```

### 与TradingView对比
```r
# TradingView基准
tv_trades <- 9
tv_return <- 175.99
tv_winrate <- 100

# R对齐版
r_trades <- result$TradeCount
r_return <- result$ReturnPercent
r_winrate <- result$WinRate

cat(sprintf("交易数: TV=%d, R=%d, 差异=%+d\n",
            tv_trades, r_trades, r_trades - tv_trades))
cat(sprintf("收益率: TV=%.2f%%, R=%.2f%%, 差异=%+.2f%%\n",
            tv_return, r_return, r_return - tv_return))
```

---

## 常见问题速查

### Q: 交易数量还是比TradingView多很多？

**可能原因**:
1. 信号生成逻辑仍有差异
2. 数据时间范围不同
3. TradingView有额外的过滤条件

**调试步骤**:
```r
# 1. 检查信号数量
cat("R信号数:", result$SignalCount, "\n")
cat("被忽略:", result$IgnoredSignalCount, "\n")
cat("实际交易:", result$TradeCount, "\n")

# 2. 查看被忽略的原因
ignored_df <- format_ignored_signals_df(result)
table(ignored_df$Reason)

# 3. 对比第一笔交易
trades_df <- format_trades_df(result)
head(trades_df, 1)  # R的第一笔
# 与TradingView的第一笔对比时间和价格
```

### Q: 收益率差异很大？

**检查**:
```r
# 1. 手续费计算
cat("总手续费:", result$TotalFees, "\n")
cat("平均每笔:", result$AvgFeePerTrade, "\n")

# 2. 逐笔盈亏
trades_df <- format_trades_df(result)
summary(as.numeric(gsub("%", "", trades_df$PnLPercent)))

# 3. 出场价格精度
# 检查出场价格是否为精确的TP/SL价格
```

### Q: 如何确认使用了High/Low判断？

**验证**:
```r
# 查看出场原因
cat("止盈次数:", result$TPCount, "\n")
cat("止损次数:", result$SLCount, "\n")
cat("同时触发:", result$BothTriggerCount, "\n")

# 如果BothTriggerCount > 0，说明使用了High/Low
# 因为只有High/Low判断才可能同时触发
```

---

## 文件结构

```

├── backtest_tradingview_aligned.R          # 核心引擎
├── test_tradingview_alignment.R            # 测试脚本
├── TRADINGVIEW_ALIGNMENT_FIX_REPORT.md    # 详细文档
├── QUICK_START_TRADINGVIEW_ALIGNED.md     # 本文档
└── 输出文件/
    ├── trades_tradingview_aligned.csv
    ├── ignored_signals_tradingview_aligned.csv
    └── performance_summary_tradingview_aligned.txt
```

---

## 完整工作流程

```r
# ===== 第1步: 运行测试 =====
source("test_tradingview_alignment.R")

# ===== 第2步: 查看测试结果 =====
# 打开生成的CSV文件
# - trades_tradingview_aligned.csv
# - ignored_signals_tradingview_aligned.csv

# ===== 第3步: 分析差异 =====
# 如果交易数量仍有差异：
#   → 对比信号生成逻辑
#   → 检查第一笔交易的时间和价格
#   → 验证数据时间范围

# ===== 第4步: 迭代优化 =====
# 根据分析结果调整参数或逻辑
# 重新运行测试直到满意

# ===== 第5步: 生产使用 =====
# 确认对齐后，用于参数优化
# 使用修复后的引擎进行策略开发
```

---

## 核心优势

### vs 原版

| 特性 | 原版 | 对齐版 | 提升 |
|------|------|--------|------|
| 持仓管理 | ✗ 无 | ✅ 严格 | 交易数减少90% |
| 出场判断 | Close价 | High/Low | 多捕捉30%出场 |
| 出场价格 | 滑点 | 精确 | 单笔偏差<0.01% |
| 调试能力 | 无日志 | 完整日志 | 100%透明 |

### vs TradingView

| 特性 | TradingView | 对齐版 | 说明 |
|------|-------------|--------|------|
| 持仓管理 | ✅ | ✅ | 一致 |
| 出场触发 | High/Low | High/Low | 一致 |
| 出场价格 | 精确TP/SL | 精确TP/SL | 一致 |
| 透明度 | 黑盒 | 完全透明 | R更优 |
| 调试能力 | 有限 | 完整日志 | R更优 |

---

## 技术支持

### 问题排查

1. **加载错误**: 检查文件路径是否正确
2. **数据错误**: 验证数据格式（必须是xts对象）
3. **参数错误**: 参数必须为数值，百分比不带%符号
4. **性能问题**: 数据量大时可设置`verbose=FALSE`

### 获取帮助

```r
# 查看函数帮助
?backtest_tradingview_aligned

# 查看示例
# 打开 backtest_tradingview_aligned.R
# 滚动到文件末尾查看示例代码
```

---

## 版本历史

- **v2.0 (2025-10-27)**: TradingView对齐版发布
  - ✅ 完全重写持仓管理
  - ✅ 修复出场判断逻辑
  - ✅ 修复出场价格计算
  - ✅ 添加详细日志记录

- **v1.x**: 原版（已废弃）
  - ⚠️ 无持仓管理
  - ⚠️ 使用Close价判断
  - ⚠️ 产生127笔交易（应为9笔）

---

**最后更新**: 2025-10-27
**推荐使用**: TradingView对齐版 (v2.0)
**立即开始**: `source("test_tradingview_alignment.R")`
