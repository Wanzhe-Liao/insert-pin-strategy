# 修复方案：达到100%对齐

## 方案A: 修复信号窗口计算（推荐优先）

### 问题诊断
当前代码Line 112-120：
```r
window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)
drop_percent <- (window_high - low_vec) / window_high * 100
```

这会导致在位置i计算的window_high包含high_vec[i]本身。

但Pine Script的`ta.highest(high, n)[1]`会排除当前K线。

### 修复代码

**修改位置**: Line 112-126

**原代码**:
```r
# 使用RcppRoll计算滚动最高价（C++级别加速）
# align="right" 表示窗口包含当前位置
window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)

# 🔧 修复：移除滞后操作，直接使用当前K线的滚动窗口
# TradingView在K线收盘时计算信号，此时当前K线已完成，应该包含在窗口内
# 原来的滞后操作导致信号延迟1根K线(15分钟)

# 向量化计算跌幅
drop_percent <- (window_high - low_vec) / window_high * 100
```

**修复后**:
```r
# 使用RcppRoll计算滚动最高价（C++级别加速）
# align="right" 表示窗口包含当前位置
window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)

# 🔧 关键修复：排除当前K线，对齐Pine Script的ta.highest()[1]行为
# Pine Script: windowHigh = ta.highest(high, lookbackBars)[1]
# [1]表示向前偏移1位，即排除当前K线，只看过去lookbackBars根K线
# 这样确保信号计算时不包含当前K线的数据，避免look-ahead bias
window_high_prev <- c(NA, window_high[-n])

# 向量化计算跌幅（使用排除当前K线的窗口最高价）
drop_percent <- (window_high_prev - low_vec) / window_high_prev * 100
```

### 测试方法
```r
source("backtest_tradingview_aligned.R")
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  verbose = TRUE
)

# 检查交易数量
print(result$TradeCount)  # 应该仍然是9

# 提取交易时间
trades_df <- format_trades_df(result)
print(trades_df[, c("EntryTime", "EntryPrice")])
```

### 预期效果
- 交易数量可能仍然是9（或略有变化）
- 入场时间应该更接近TV（对齐率从77.8%提升到90%+）
- 入场价格应该更接近TV（对齐率从88.9%提升到95%+）

---

## 方案B: 修复出场价格

### 问题诊断
当前代码Line 314-326使用收盘价作为出场价格：
```r
exitPrice <- currentClose
```

但文档Line 4声称：
> 【出场价格】使用精确的TP/SL价格（而非Close价格）

### 验证步骤（优先执行）

**在修复前，先验证TV是否真的使用精确价格**:

```r
# 读取TV交易数据
tv_trades <- read.csv("outputs/tv_trades_fixed.csv")

# 对每笔交易验证
for(i in 1:nrow(tv_trades)) {
  entry <- tv_trades$EntryPrice[i]
  exit <- tv_trades$ExitPrice[i]
  pnl <- tv_trades$PnL[i]

  # 计算精确的10%止盈价格
  tp_exact <- entry * 1.10

  # 计算实际盈亏
  pnl_actual <- (exit - entry) / entry * 100

  cat(sprintf("交易#%d:\n", i))
  cat(sprintf("  入场: %.8f\n", entry))
  cat(sprintf("  出场: %.8f\n", exit))
  cat(sprintf("  10%%止盈价: %.8f\n", tp_exact))
  cat(sprintf("  价格差: %.8f (%.4f%%)\n", exit - tp_exact, (exit - tp_exact) / tp_exact * 100))
  cat(sprintf("  盈亏: %.2f%% (TV记录: %.2f%%)\n\n", pnl_actual, pnl))
}
```

### 如果验证通过，修复代码

**修改位置**: Line 314-327

**原代码**:
```r
} else if (hitTP) {
  # 仅触发止盈，使用收盘价
  exitPrice <- currentClose
  exitReason <- "TP"
  tpCount <- tpCount + 1
  exitTriggered <- TRUE

} else if (hitSL) {
  # 仅触发止损，使用收盘价
  exitPrice <- currentClose
  exitReason <- "SL"
  slCount <- slCount + 1
  exitTriggered <- TRUE
}
```

**修复后**:
```r
} else if (hitTP) {
  # 仅触发止盈，使用精确的止盈价格
  exitPrice <- tpPrice
  exitReason <- "TP"
  tpCount <- tpCount + 1
  exitTriggered <- TRUE

} else if (hitSL) {
  # 仅触发止损，使用精确的止损价格
  exitPrice <- slPrice
  exitReason <- "SL"
  slCount <- slCount + 1
  exitTriggered <- TRUE
}
```

**同时修改Line 289-312的同时触发逻辑**:
```r
if (hitTP && hitSL) {
  # 同时触发止盈和止损
  bothTriggerCount <- bothTriggerCount + 1

  # 判断K线方向来决定哪个先触发
  if (!is.na(currentOpen)) {
    if (currentClose >= currentOpen) {
      # 阳线：先触及止损（低点），后触及止盈（高点）
      # 但价格向上，最终在止盈价出场
      exitPrice <- tpPrice  # 修改：使用精确止盈价
      exitReason <- "TP_first_in_both"
      tpCount <- tpCount + 1
    } else {
      # 阴线：先触及止盈（高点），后触及止损（低点）
      # 但价格向下，最终在止损价出场
      exitPrice <- slPrice  # 修改：使用精确止损价
      exitReason <- "SL_first_in_both"
      slCount <- slCount + 1
    }
  } else {
    # 无法判断K线方向，默认止盈优先
    exitPrice <- tpPrice  # 修改：使用精确止盈价
    exitReason <- "TP_default_in_both"
    tpCount <- tpCount + 1
  }
  exitTriggered <- TRUE
}
```

### 注意事项
**关于同时触发的逻辑**:

原代码Line 295-300的逻辑可能有问题：
```r
if (currentClose >= currentOpen) {
  // 阳线：止盈优先
} else {
  // 阴线：止损优先
}
```

**更正确的逻辑应该是**:
- 阳线（价格上涨）：先触及止损（低点），后触及止盈（高点），最终出场在止盈
- 阴线（价格下跌）：先触及止盈（高点），后触及止损（低点），最终出场在止损

但这取决于开盘价与止损/止盈的相对位置。

**建议**:
```r
if (hitTP && hitSL) {
  bothTriggerCount <- bothTriggerCount + 1

  # 根据K线开盘价位置判断
  if (!is.na(currentOpen)) {
    # 如果开盘价在止损价之下，说明先上涨触及止盈
    if (currentOpen <= slPrice) {
      exitPrice <- tpPrice
      exitReason <- "TP_price_rose"
      tpCount <- tpCount + 1
    }
    # 如果开盘价在止盈价之上，说明先下跌触及止损
    else if (currentOpen >= tpPrice) {
      exitPrice <- slPrice
      exitReason <- "SL_price_fell"
      slCount <- slCount + 1
    }
    // 如果开盘价在两者之间，按收盘价判断最终方向
    else {
      if (currentClose >= currentOpen) {
        exitPrice <- tpPrice
        exitReason <- "TP_closed_higher"
        tpCount <- tpCount + 1
      } else {
        exitPrice <- slPrice
        exitReason <- "SL_closed_lower"
        slCount <- slCount + 1
      }
    }
  } else {
    // 默认止盈优先
    exitPrice <- tpPrice
    exitReason <- "TP_default"
    tpCount <- tpCount + 1
  }
  exitTriggered <- TRUE
}
```

---

## 方案C: 信号延迟入场（复杂度高）

### 问题诊断
从`analyze_tv_trade9.R`的分析：
- TV在05:44信号触发（记录的入场时间）
- 但使用05:59的收盘价入场（实际入场价格）
- 说明有1根K线的延迟

### 实现方式

**方法1: 信号队列（推荐）**

在回测主循环中添加信号队列：

```r
# 初始化（Line 228之后添加）
pendingSignals <- list()  # 待处理的信号队列

# 主循环中（Line 255之后修改）
for (i in 1:n) {

  # ===== 阶段0: 处理待处理的信号 =====
  if (length(pendingSignals) > 0 && !inPosition) {
    # 取出最早的待处理信号
    signal <- pendingSignals[[1]]
    pendingSignals <- pendingSignals[-1]

    # 在当前K线收盘价入场
    entryPrice <- close_vec[i]
    entryBar <- i
    signalBar <- signal$bar  # 记录信号触发的K线

    # 验证价格有效性
    if (!is.na(entryPrice) && entryPrice > 0) {
      # 计算手续费
      entryFee <- capital * feeRate
      entryCapital <- capital - entryFee

      # 入场
      position <- entryCapital / entryPrice
      capital <- 0
      inPosition <- TRUE
      totalFees <- totalFees + entryFee

      if (verbose) {
        cat(sprintf("[入场] 信号K线=%d, 入场K线=%d, 时间=%s, 价格=%.8f\n",
                    signalBar, entryBar, as.character(timestamps[entryBar]), entryPrice))
      }
    }
  }

  # ===== 阶段1: 检查出场条件 =====
  # ... 保持原有逻辑 ...

  # ===== 阶段2: 检查入场信号 =====
  if (signals[i] && !inPosition && i != lastExitBar) {
    # 信号触发，但不立即入场，加入待处理队列
    pendingSignals[[length(pendingSignals) + 1]] <- list(
      bar = i,
      timestamp = timestamps[i]
    )

    if (verbose) {
      cat(sprintf("[信号] K线=%d, 时间=%s, 加入待处理队列\n",
                  i, as.character(timestamps[i])))
    }
  }

  # ===== 阶段3: 记录净值曲线 =====
  # ... 保持原有逻辑 ...
}
```

**方法2: 简化版（直接延迟1根K线）**

```r
# 修改Line 384-411

if (signals[i] && !inPosition && i != lastExitBar) {
  # 信号触发，延迟到下一根K线入场
  if (i < n) {
    # 使用下一根K线的收盘价入场
    entryPrice <- close_vec[i + 1]
    entryBar <- i + 1

    # 记录信号触发的K线（用于日志）
    signalBar <- i
  } else {
    # 最后一根K线，无法延迟入场
    if (logIgnoredSignals) {
      ignoredCount <- ignoredCount + 1
      ignoredSignals[[ignoredCount]] <- list(
        Bar = i,
        Timestamp = as.character(timestamps[i]),
        Reason = "最后一根K线，无法延迟入场"
      )
    }
    next
  }

  # 验证入场价格有效性
  if (is.na(entryPrice) || entryPrice <= 0) {
    if (logIgnoredSignals) {
      ignoredCount <- ignoredCount + 1
      ignoredSignals[[ignoredCount]] <- list(
        Bar = i,
        Timestamp = as.character(timestamps[i]),
        Reason = sprintf("延迟入场价格无效: %.8f", entryPrice)
      )
    }
    next
  }

  # 计算手续费
  entryFee <- capital * feeRate
  entryCapital <- capital - entryFee

  # 入场
  position <- entryCapital / entryPrice
  capital <- 0
  inPosition <- TRUE
  totalFees <- totalFees + entryFee

  if (verbose) {
    cat(sprintf("[入场] 信号K线=%d, 入场K线=%d, 时间=%s, 价格=%.8f\n",
                signalBar, entryBar, as.character(timestamps[entryBar]), entryPrice))
  }
}
```

**问题**: 这种方法会破坏for循环的逻辑，因为在i循环中访问了i+1的数据。

**更好的实现**: 使用方法1的信号队列。

---

## 方案D: 组合修复（最终方案）

结合方案A和方案B：

1. 修复信号窗口（排除当前K线）
2. 修复出场价格（使用精确TP/SL）
3. 保持入场逻辑不变（在信号K线收盘价入场）

### 完整修复代码

**修改1: Line 112-126**
```r
# 计算滚动最高价
window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)

# 关键修复：排除当前K线
window_high_prev <- c(NA, window_high[-n])

# 计算跌幅
drop_percent <- (window_high_prev - low_vec) / window_high_prev * 100

# 生成信号
signals <- !is.na(drop_percent) & (drop_percent >= minDropPercent)
```

**修改2: Line 289-327**
```r
if (hitTP && hitSL) {
  bothTriggerCount <- bothTriggerCount + 1

  # 根据开盘价位置判断
  if (!is.na(currentOpen)) {
    if (currentOpen <= slPrice) {
      exitPrice <- tpPrice
      exitReason <- "TP_price_rose"
      tpCount <- tpCount + 1
    } else if (currentOpen >= tpPrice) {
      exitPrice <- slPrice
      exitReason <- "SL_price_fell"
      slCount <- slCount + 1
    } else {
      if (currentClose >= currentOpen) {
        exitPrice <- tpPrice
        exitReason <- "TP_closed_higher"
        tpCount <- tpCount + 1
      } else {
        exitPrice <- slPrice
        exitReason <- "SL_closed_lower"
        slCount <- slCount + 1
      }
    }
  } else {
    exitPrice <- tpPrice
    exitReason <- "TP_default"
    tpCount <- tpCount + 1
  }
  exitTriggered <- TRUE

} else if (hitTP) {
  exitPrice <- tpPrice  # 使用精确止盈价
  exitReason <- "TP"
  tpCount <- tpCount + 1
  exitTriggered <- TRUE

} else if (hitSL) {
  exitPrice <- slPrice  # 使用精确止损价
  exitReason <- "SL"
  slCount <- slCount + 1
  exitTriggered <- TRUE
}
```

---

## 测试和验证流程

### 步骤1: 备份当前版本
```r
file.copy("backtest_tradingview_aligned.R",
          "backtest_tradingview_aligned_backup.R")
```

### 步骤2: 应用方案A（信号窗口修复）
修改Line 112-126，重新运行回测：
```r
source("backtest_tradingview_aligned.R")
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

result_fix_a <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  verbose = TRUE
)

trades_fix_a <- format_trades_df(result_fix_a)
write.csv(trades_fix_a, "r_trades_fix_a.csv", row.names = FALSE)
```

### 步骤3: 对比结果
```r
# 读取TV和R的交易数据
tv_trades <- read.csv("outputs/tv_trades_fixed.csv")
r_trades_fix_a <- read.csv("r_trades_fix_a.csv")

# 计算对齐率
entry_time_match <- 0
entry_price_match <- 0
exit_time_match <- 0

for(i in 1:min(nrow(tv_trades), nrow(r_trades_fix_a))) {
  tv_entry <- as.POSIXct(tv_trades$EntryTime[i], format="%Y-%m-%d %H:%M:%S")
  r_entry <- as.POSIXct(r_trades_fix_a$EntryTime[i], format="%Y-%m-%d %H:%M:%S")

  if(abs(as.numeric(difftime(tv_entry, r_entry, units="mins"))) < 1) {
    entry_time_match <- entry_time_match + 1
  }

  if(abs(tv_trades$EntryPrice[i] - r_trades_fix_a$EntryPrice[i]) / tv_trades$EntryPrice[i] < 0.01) {
    entry_price_match <- entry_price_match + 1
  }

  tv_exit <- as.POSIXct(tv_trades$ExitTime[i], format="%Y-%m-%d %H:%M:%S")
  r_exit <- as.POSIXct(r_trades_fix_a$ExitTime[i], format="%Y-%m-%d %H:%M:%S")

  if(abs(as.numeric(difftime(tv_exit, r_exit, units="mins"))) < 1) {
    exit_time_match <- exit_time_match + 1
  }
}

cat(sprintf("方案A修复后对齐率:\n"))
cat(sprintf("  交易数量: %d vs %d\n", nrow(tv_trades), nrow(r_trades_fix_a)))
cat(sprintf("  入场时间: %d/%d (%.1f%%)\n", entry_time_match, nrow(tv_trades), entry_time_match/nrow(tv_trades)*100))
cat(sprintf("  入场价格: %d/%d (%.1f%%)\n", entry_price_match, nrow(tv_trades), entry_price_match/nrow(tv_trades)*100))
cat(sprintf("  出场时间: %d/%d (%.1f%%)\n", exit_time_match, nrow(tv_trades), exit_time_match/nrow(tv_trades)*100))
```

### 步骤4: 如果方案A有效，继续应用方案B
修改出场价格逻辑，重新测试。

### 步骤5: 如果方案A+B仍未达到100%
需要深入分析Pine Script源代码，或使用方案C（信号延迟入场）。

---

## 总结

**推荐执行顺序**:
1. 方案A（信号窗口修复）- 最可能的根本原因
2. 验证TV出场价格 - 确定是否需要方案B
3. 如果仍未100%，深入分析不对齐案例
4. 如果确认需要延迟入场，实现方案C

**预期效果**:
- 方案A应该能将入场时间对齐率提升到90%+
- 方案A+B应该能将出场时间对齐率提升到80%+
- 如果需要100%，可能需要方案C

**关键**: 需要Pine Script源代码才能做出最准确的判断。
