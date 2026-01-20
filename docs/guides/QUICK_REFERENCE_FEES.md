# 手续费计算快速参考卡

## 基本参数

```r
FEE_RATE <- 0.00075  # 0.075%
```

## 核心公式

### 入场交易

```r
entry_fee <- capital * FEE_RATE
capital_after_fee <- capital - entry_fee
position <- capital_after_fee / entry_price
```

### 出场交易

```r
exit_value_before_fee <- position * exit_price
exit_fee <- exit_value_before_fee * FEE_RATE
final_capital <- exit_value_before_fee - exit_fee
```

### 收益率计算

```r
return_pct <- (final_capital / initial_capital - 1) * 100
```

## 快速计算表（基于10,000 USDT）

| 价格变动 | 理论收益率 | 实际收益率 | 手续费成本 | 收益侵蚀 |
|---------|-----------|-----------|-----------|---------|
| +20% | 20.00% | 19.70% | 30.79 USDT | 0.30% |
| +15% | 15.00% | 14.77% | 23.56 USDT | 0.23% |
| +10% | 10.00% | 9.84% | 15.74 USDT | 0.16% |
| +5% | 5.00% | 4.84% | 7.89 USDT | 0.16% |
| 0% | 0.00% | -0.15% | 15.00 USDT | 0.15% |
| -5% | -5.00% | -5.14% | 14.24 USDT | 0.14% |
| -10% | -10.00% | -10.13% | 13.49 USDT | 0.13% |
| -15% | -15.00% | -15.13% | 12.75 USDT | 0.13% |
| -20% | -20.00% | -20.12% | 12.00 USDT | 0.12% |

## 关键数字

- **每笔交易成本：** ~0.15%（入场0.075% + 出场0.075%）
- **10%止盈实际收益：** 9.835%
- **10%止损实际亏损：** -10.135%
- **基于10,000 USDT的单笔手续费：** ~15 USDT

## Pine Script对应关系

| Pine Script | R代码 |
|-------------|-------|
| `commission_type=strategy.commission.percent` | 百分比手续费 |
| `commission_value=0.075` | `FEE_RATE = 0.00075` |
| 开仓手续费 | `entry_fee = capital * FEE_RATE` |
| 平仓手续费 | `exit_fee = exit_value * FEE_RATE` |

## 常见错误

❌ **错误1：** `position <- capital / entry_price`（未扣入场手续费）
✅ **正确：** `position <- (capital - entry_fee) / entry_price`

❌ **错误2：** `final_capital <- position * exit_price`（未扣出场手续费）
✅ **正确：** `final_capital <- (position * exit_price) * (1 - FEE_RATE)`

❌ **错误3：** `FEE_RATE <- 0.075`（错误的费率）
✅ **正确：** `FEE_RATE <- 0.00075`（0.075%转换为小数）

## 验证检查点

- [ ] 入场时扣除手续费
- [ ] 出场时扣除手续费
- [ ] 强制平仓时扣除手续费
- [ ] 手续费率为 0.00075
- [ ] 10%止盈实际收益约 9.835%
- [ ] 10%止损实际亏损约 -10.135%
- [ ] 每笔交易成本约 0.15%

## 测试用例

```r
# 加载函数
source("backtest_with_fees.R")

# 单笔交易测试
capital <- 10000
entry_price <- 0.00000165
exit_price <- entry_price * 1.10

entry_fee <- capital * 0.00075
capital_after_entry <- capital - entry_fee
position <- capital_after_entry / entry_price
exit_value <- position * exit_price
exit_fee <- exit_value * 0.00075
final <- exit_value - exit_fee
return_pct <- (final / capital - 1) * 100

print(return_pct)  # 应该约为 9.835%
```

## 文件位置

- **验证报告：** `FEE_VALIDATION_REPORT.md`
- **验证脚本：** `fee_verification.R`
- **含手续费回测：** `backtest_with_fees.R`
- **测试脚本：** `test_fee_correctness.R`
