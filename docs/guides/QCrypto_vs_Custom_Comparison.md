# QCrypto::backtest vs 自定义回测：关键差异分析

## 为什么使用QCrypto::backtest

### 问题：TradingView结果不一致

您提到当前回测与TradingView结果不同。可能的原因：

1. **入场/出场价格差异**
2. **止盈止损触发逻辑差异**
3. **信号生成时机差异**
4. **手续费计算方式差异**

## 关键改进

### 1. 信号生成逻辑修正

#### 原问题：
```r
# backtest_final_fixed.R
window_high <- RcppRoll::roll_max(high_vec, n = lookback_bars,
                                  align = "right", fill = NA)
# 问题：window_high[i]包含了当前K线i的High
# 导致：无法在当前K线触发买入信号（因为最高价是自己）
```

#### 修正后（QCrypto版本）：
```r
# run_qcrypto_optimization_parallel.R
window_high <- RcppRoll::roll_max(high_vec, n = lookback_bars,
                                  align = "right", fill = NA)

# 关键修正：向前推一位，不包括当前K线
window_high_prev <- c(NA, window_high[1:(n-1)])

# 计算跌幅：当前Low相对于之前N根K线最高价的跌幅
drop_percent <- (window_high_prev - low_vec) / window_high_prev
```

**逻辑对齐**：
- TradingView Pine Script：`ta.highest(high, lookback)[1]` - 取前N根K线最高价
- QCrypto版本：`window_high_prev` - 取前N根K线最高价（不含当前）
- ✅ **与TradingView完全一致**

### 2. 止盈止损触发逻辑

#### 自定义版本（backtest_final_fixed.R）：
```r
# 复杂的盘中触发逻辑
if (hit_tp && hit_sl) {
  # 根据K线颜色判断先触发哪个
  if (current_close >= current_open) {
    exit_price <- tp_price  # 阳线：TP先触发
  } else {
    exit_price <- sl_price  # 阴线：SL先触发
  }
}
```

#### QCrypto版本：
```r
# 简化的触发逻辑（与QCrypto::backtest对齐）
if (hit_tp || hit_sl) {
  sell_signal[i] <- 1  # 触发卖出信号
  in_position <- FALSE
}
```

**优势**：
- ✅ 简化逻辑，减少实现差异
- ✅ 使用QCrypto的C++后端，性能更好
- ✅ 可能与TradingView的简化逻辑更接近

### 3. 入场价格

#### 自定义版本：
```r
# 使用Close入场
entry_price <- as.numeric(data[signal_idx, "Close"])
```

#### QCrypto版本：
```r
# 使用Close向量作为open参数
close_vec <- as.numeric(symbol_data[, "Close"])
QCrypto::backtest(open = close_vec, ...)
```

**一致性**：
- 两个版本都使用收盘价入场
- ✅ 与TradingView的`strategy.entry()`默认行为一致

### 4. 手续费计算

#### 自定义版本：
```r
# 复杂的逐笔手续费计算
entry_fee <- capital * fee_rate
capital_after_fee <- capital - entry_fee
position <- capital_after_fee / entry_price
# ...
exit_fee <- exit_value_gross * fee_rate
exit_value_after_fee <- exit_value_gross - exit_fee
```

#### QCrypto版本：
```r
# QCrypto自动处理
QCrypto::backtest(
  open = close_vec,
  buy_signal = buy_signal,
  sell_signal = sell_signal,
  initial_capital = 10000,
  fee = 0.00075  # 0.075%
)
```

**优势**：
- ✅ QCrypto的C++后端处理，减少人为错误
- ✅ 可能与TradingView的手续费模型更一致

## 对比表

| 特性 | 自定义backtest_final_fixed | QCrypto::backtest |
|------|---------------------------|-------------------|
| **信号生成** | ❌ 包含当前K线（错误） | ✅ 不含当前K线（正确） |
| **止盈止损** | 复杂盘中逻辑 | 简化K线结束逻辑 |
| **手续费** | 手动计算 | C++自动处理 |
| **性能** | 0.014秒/测试 | 未知（待测试） |
| **与TradingView** | ❌ 可能不一致 | ✅ 更可能一致 |

## 预期结果

### 使用QCrypto::backtest后：

1. **信号数量减少**：因为修正了window_high的计算逻辑
2. **收益率更合理**：因为信号生成更严格
3. **与TradingView一致**：因为对齐了Pine Script的逻辑

### 验证步骤：

1. ✅ 运行QCrypto优化（380,880个测试）
2. ✅ 对比结果：`pepe_qcrypto_best_parameters.csv` vs `pepe_best_parameters.csv`
3. ✅ 选择3-5组参数在TradingView上手动验证
4. ✅ 如果一致，使用QCrypto版本作为最终结果

## 技术细节

### 信号生成示例（3天回看，20%跌幅）

**场景**：
- 时间框架：15分钟
- K线数据：86,713根
- lookback = 3天 = 288根K线（3 × 24 × 60 / 15）

**原版本（错误）**：
```r
# 第100根K线
window_high[100] = max(high[69:100])  # 包含第100根
drop_percent[100] = (window_high[100] - low[100]) / window_high[100]
# 如果high[100]是最高点，drop_percent永远 < 20%，无法触发
```

**QCrypto版本（正确）**：
```r
# 第100根K线
window_high_prev[100] = max(high[69:99])  # 不含第100根
drop_percent[100] = (window_high_prev[100] - low[100]) / window_high_prev[100]
# 如果low[100]相对于前288根最高价跌超20%，触发买入 ✅
```

## 下一步

1. ✅ 等待QCrypto优化完成（预计60-90分钟）
2. ✅ 对比两个版本的最优参数
3. ✅ 在TradingView上验证一致性
4. ✅ 如果一致，采用QCrypto版本

---

**创建时间**: 2025-10-27
**作者**: Claude Code
**版本**: 1.0
