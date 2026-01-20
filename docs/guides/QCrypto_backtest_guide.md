# QCrypto::backtest 函数使用指南

## 完整参数优化结果摘要

### 执行统计
- **总测试数**: 380,880个
- **执行时间**: 86.1分钟
- **并行加速比**: 14.7x (32核并行)
- **平均每测试**: 0.014秒

---

## QCrypto::backtest 函数详解

### 函数签名
```r
backtest(open, buy_signal, sell_signal, initial_capital, fee = 0.001)
```

### 参数说明

| 参数 | 类型 | 描述 | 示例 |
|------|------|------|------|
| `open` | numeric vector | 入场价格向量（开盘价/收盘价） | `as.numeric(data$Close)` |
| `buy_signal` | numeric vector | 买入信号（0或1） | `c(0, 1, 0, 0, 1, ...)` |
| `sell_signal` | numeric vector | 卖出信号（0或1） | `c(0, 0, 1, 0, 0, ...)` |
| `initial_capital` | numeric | 初始资金 | `10000` |
| `fee` | numeric | 手续费率（默认0.001 = 0.1%） | `0.00075` (0.075%) |

### 函数特点

**优势：**
- ✅ 使用C++后端（`backtest_cpp`），性能极佳
- ✅ 自动处理资金复利
- ✅ 自动计算手续费
- ✅ 简洁的信号接口

**限制：**
- ⚠️ 简化的买卖逻辑，不支持复杂的盘中止盈止损
- ⚠️ 买入和卖出需要分别设置信号
- ⚠️ 需要预先生成信号向量

---

## 对比：QCrypto vs 自定义实现

### 1. QCrypto::backtest
```r
# 优点：简单、快速、C++加速
library(QCrypto)

# 生成信号
buy_signal <- c(0, 1, 0, 0, 1, 0, ...)  # 第2和第5根K线买入
sell_signal <- c(0, 0, 1, 0, 0, 1, ...) # 第3和第6根K线卖出

# 回测
result <- backtest(
  open = as.numeric(data$Close),
  buy_signal = buy_signal,
  sell_signal = sell_signal,
  initial_capital = 10000,
  fee = 0.00075
)
```

### 2. 自定义backtest_strategy_final
```r
# 优点：完全控制、支持复杂止盈止损、详细统计
source("backtest_final_fixed.R")

result <- backtest_strategy_final(
  data = data,
  lookback_days = 3,
  drop_threshold = 0.20,
  take_profit = 0.10,
  stop_loss = 0.10,
  initial_capital = 10000,
  fee_rate = 0.00075,
  next_bar_entry = FALSE,
  verbose = TRUE
)
```

---

## 最优参数结果（需谨慎！）

### ⚠️ 重要警告

优化结果显示的收益率**异常夸张**（数百亿%），这是**不现实**的！

**问题原因：**
1. **交易频率过高**：平均7,198笔交易
2. **止盈止损过小**：0.6%的TP导致极端复利
3. **过拟合**：参数在历史数据上极度优化

### 各时间框架最优参数

#### PEPEUSDT_15m
```r
lookback = 1天
minDropPercent = 2.0%
takeProfitPercent = 0.6%    # ⚠️ 过小
stopLossPercent = 4.8%

交易数 = 16,477笔           # ⚠️ 过多
胜率 = 94.3%               # ⚠️ 不现实
回撤 = 59.06%              # ⚠️ 风险高
```

#### PEPEUSDT_1h
```r
lookback = 5天
minDropPercent = 4.0%
takeProfitPercent = 0.6%    # ⚠️ 过小
stopLossPercent = 5.0%

交易数 = 9,805笔
胜率 = 94.8%
回撤 = 71.61%
```

#### PEPEUSDT_30m
```r
lookback = 1天
minDropPercent = 2.0%
takeProfitPercent = 0.7%    # ⚠️ 过小
stopLossPercent = 4.7%

交易数 = 11,923笔
胜率 = 93.1%
回撤 = 61.08%
```

#### PEPEUSDT_5m
```r
lookback = 1天
minDropPercent = 2.0%
takeProfitPercent = 0.6%    # ⚠️ 过小
stopLossPercent = 3.4%

交易数 = 24,400笔          # ⚠️ 过多
胜率 = 90.6%
回撤 = 85.97%              # ⚠️ 风险极高
```

---

## 建议的实战参数

基于常识和风险控制，建议使用更保守的参数：

### 推荐参数范围

```r
lookbackDays = 3-5天        # 足够的观察周期
minDropPercent = 10-20%     # 真正的"暴跌"
takeProfitPercent = 5-15%   # 合理的止盈
stopLossPercent = 8-12%     # 合理的止损
```

### 过滤优化结果的方法

```r
# 读取完整结果
results <- read.csv("pepe_complete_optimization_results.csv")

# 过滤合理的参数
filtered <- results[
  results$takeProfitPercent >= 5 &      # TP ≥ 5%
  results$stopLossPercent >= 8 &        # SL ≥ 8%
  results$Trade_Count <= 1000 &         # 交易数 ≤ 1000
  results$Max_Drawdown <= 50 &          # 回撤 ≤ 50%
  results$Return_Percentage > 0,        # 盈利
]

# 按收益率排序
best_filtered <- filtered[order(-filtered$Return_Percentage), ]

# 查看前10名
head(best_filtered, 10)
```

---

## 如何使用QCrypto::backtest适配您的策略

### 示例代码

```r
library(QCrypto)
library(xts)
source("backtest_qcrypto_adapter.R")  # 我为您创建的适配器

# 加载数据
load("liaochu.RData")
data <- cryptodata$PEPEUSDT_15m

# 使用QCrypto回测（通过适配器）
result <- test_qcrypto_strategy(
  data = data,
  lookback_days = 3,
  drop_pct = 20,    # 20%跌幅
  tp_pct = 10,      # 10%止盈
  sl_pct = 10       # 10%止损
)

# 查看结果
print(result)
```

### 直接使用QCrypto::backtest

```r
library(QCrypto)

# 1. 准备数据
close_vec <- as.numeric(data$Close)
n <- length(close_vec)

# 2. 生成买入信号（简化示例）
buy_signal <- rep(0, n)
buy_signal[c(100, 200, 300)] <- 1  # 第100, 200, 300根K线买入

# 3. 生成卖出信号（买入后10根K线卖出）
sell_signal <- rep(0, n)
sell_signal[c(110, 210, 310)] <- 1

# 4. 执行回测
result <- QCrypto::backtest(
  open = close_vec,
  buy_signal = buy_signal,
  sell_signal = sell_signal,
  initial_capital = 10000,
  fee = 0.00075
)

# 5. 查看结果
print(head(result, 20))
```

---

## 结论

### QCrypto::backtest 适用场景

✅ **适合：**
- 简单的买卖信号策略
- 需要快速验证信号效果
- 已有明确的入场/出场规则

❌ **不适合：**
- 复杂的盘中止盈止损逻辑
- 需要详细交易统计
- 动态调整止盈止损

### 建议

1. **继续使用自定义backtest_strategy_final**：因为您的策略有复杂的止盈止损逻辑
2. **QCrypto::backtest作为辅助验证**：用于快速测试信号质量
3. **优化结果需要实盘验证**：不要直接使用极端参数
4. **关注合理性指标**：
   - 交易数：每年50-200笔较合理
   - 胜率：55-70%较现实
   - 回撤：≤30%为佳
   - 止盈止损比：1:1到2:1

---

## 下一步

1. ✅ **查看完整结果**：
   ```r
   results <- read.csv("pepe_complete_optimization_results.csv")
   ```

2. ✅ **过滤合理参数**：使用上述过滤方法

3. ✅ **TradingView验证**：
   - 选择3-5组合理参数
   - 在TradingView上手动验证
   - 对比实盘可行性

4. ✅ **小资金实盘测试**：
   - 使用最保守的参数组合
   - 小额资金验证
   - 记录实际表现

---

**创建时间**: 2025-10-26
**作者**: Claude Code
**版本**: 1.0
