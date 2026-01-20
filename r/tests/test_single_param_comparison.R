# 单参数组合对比测试
# 用于与TradingView验证结果一致性
#
# 对比：
# 1. 自定义backtest_final_fixed.R
# 2. QCrypto::backtest
#
# 作者：Claude Code
# 日期：2025-10-27

cat("\n", rep("=", 80), "\n", sep="")
cat("单参数组合对比测试\n")
cat(rep("=", 80), "\n\n", sep="")

# 加载必要的库
suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
  library(QCrypto)
})

# ============================================================================
# 测试参数（请根据需要修改）
# ============================================================================

TEST_PARAMS <- list(
  symbol = "PEPEUSDT_15m",       # 时间框架
  lookback_days = 3,              # 回看天数
  drop_percent = 20,              # 跌幅阈值 (%)
  take_profit_percent = 10,       # 止盈 (%)
  stop_loss_percent = 10,         # 止损 (%)
  initial_capital = 10000,        # 初始资金
  fee_rate = 0.075               # 手续费率 (%)
)

cat("测试参数:\n")
cat(sprintf("  Symbol: %s\n", TEST_PARAMS$symbol))
cat(sprintf("  Lookback: %d天\n", TEST_PARAMS$lookback_days))
cat(sprintf("  跌幅阈值: %.0f%%\n", TEST_PARAMS$drop_percent))
cat(sprintf("  止盈: %.0f%%\n", TEST_PARAMS$take_profit_percent))
cat(sprintf("  止损: %.0f%%\n", TEST_PARAMS$stop_loss_percent))
cat(sprintf("  初始资金: %d USDT\n", TEST_PARAMS$initial_capital))
cat(sprintf("  手续费: %.3f%%\n\n", TEST_PARAMS$fee_rate))

# ============================================================================
# 加载数据
# ============================================================================

cat("加载数据...\n")
load("data/liaochu.RData")
data <- cryptodata[[TEST_PARAMS$symbol]]
cat(sprintf("OK 数据加载完成: %d 根K线\n\n", nrow(data)))

# ============================================================================
# 方法1: 使用自定义backtest_final_fixed.R
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("方法1: 自定义backtest_final_fixed.R\n")
cat(rep("=", 80), "\n\n", sep="")

source("backtest_final_fixed.R")

cat("运行回测...\n")
start_time <- Sys.time()

result_custom <- backtest_strategy_final(
  data = data,
  lookback_days = TEST_PARAMS$lookback_days,
  drop_threshold = TEST_PARAMS$drop_percent / 100,
  take_profit = TEST_PARAMS$take_profit_percent / 100,
  stop_loss = TEST_PARAMS$stop_loss_percent / 100,
  initial_capital = TEST_PARAMS$initial_capital,
  fee_rate = TEST_PARAMS$fee_rate / 100,
  next_bar_entry = FALSE,
  verbose = TRUE  # 输出详细交易记录
)

end_time <- Sys.time()
elapsed_custom <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat("\n结果摘要:\n")
cat(sprintf("  信号数: %d\n", result_custom$Signal_Count))
cat(sprintf("  交易数: %d\n", result_custom$Trade_Count))
cat(sprintf("  最终资金: %.2f USDT\n", result_custom$Final_Capital))
cat(sprintf("  收益率: %.2f%%\n", result_custom$Return_Percentage))
cat(sprintf("  胜率: %.2f%%\n", result_custom$Win_Rate))
cat(sprintf("  最大回撤: %.2f%%\n", result_custom$Max_Drawdown))
cat(sprintf("  总手续费: %.2f USDT\n", result_custom$Total_Fees))
cat(sprintf("  执行时间: %.3f秒\n\n", elapsed_custom))

# ============================================================================
# 方法2: 使用QCrypto::backtest
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("方法2: QCrypto::backtest\n")
cat(rep("=", 80), "\n\n", sep="")

# 检测时间框架
detect_timeframe <- function(data) {
  if (nrow(data) < 2) return(NA)
  time_diffs <- as.numeric(difftime(index(data)[2:min(100, nrow(data))],
                                   index(data)[1:min(99, nrow(data)-1)],
                                   units = "mins"))
  return(median(time_diffs, na.rm = TRUE))
}

tf_minutes <- detect_timeframe(data)
bars_per_day <- 1440 / tf_minutes
lookback_bars <- as.integer(TEST_PARAMS$lookback_days * bars_per_day)

cat(sprintf("时间框架: %d分钟\n", tf_minutes))
cat(sprintf("回看K线数: %d根\n\n", lookback_bars))

# 生成买入信号（QCrypto修正版）
cat("生成买入信号...\n")

n <- nrow(data)
high_vec <- as.numeric(data[, "High"])
low_vec <- as.numeric(data[, "Low"])

# 计算回看窗口内的最高价
window_high <- RcppRoll::roll_max(high_vec, n = lookback_bars,
                                  align = "right", fill = NA)

# 关键修正：不包括当前K线
window_high_prev <- c(NA, window_high[1:(n-1)])

# 计算跌幅
drop_percent <- (window_high_prev - low_vec) / window_high_prev

# 生成买入信号
buy_signal <- ifelse(!is.na(drop_percent) &
                     (drop_percent >= TEST_PARAMS$drop_percent / 100), 1, 0)

cat(sprintf("买入信号数: %d\n\n", sum(buy_signal, na.rm = TRUE)))

# 生成卖出信号
cat("生成卖出信号...\n")

close_vec <- as.numeric(data[, "Close"])
open_vec <- as.numeric(data[, "Open"])

sell_signal <- rep(0, n)
in_position <- FALSE
entry_price <- 0

for (i in 1:n) {
  if (!in_position && buy_signal[i] == 1) {
    # 买入
    in_position <- TRUE
    entry_price <- close_vec[i]
  } else if (in_position && i > 1) {
    # 检查止盈/止损
    tp_price <- entry_price * (1 + TEST_PARAMS$take_profit_percent / 100)
    sl_price <- entry_price * (1 - TEST_PARAMS$stop_loss_percent / 100)

    hit_tp <- !is.na(high_vec[i]) && high_vec[i] >= tp_price
    hit_sl <- !is.na(low_vec[i]) && low_vec[i] <= sl_price

    if (hit_tp || hit_sl) {
      sell_signal[i] <- 1
      in_position <- FALSE
    }
  }
}

cat(sprintf("卖出信号数: %d\n\n", sum(sell_signal, na.rm = TRUE)))

# 调用QCrypto::backtest
cat("运行QCrypto::backtest...\n")
start_time <- Sys.time()

backtest_result <- QCrypto::backtest(
  open = close_vec,
  buy_signal = buy_signal,
  sell_signal = sell_signal,
  initial_capital = TEST_PARAMS$initial_capital,
  fee = TEST_PARAMS$fee_rate / 100
)

end_time <- Sys.time()
elapsed_qcrypto <- as.numeric(difftime(end_time, start_time, units = "secs"))

# 计算统计指标
buy_count <- sum(buy_signal, na.rm = TRUE)
sell_count <- sum(sell_signal, na.rm = TRUE)

if ("capital" %in% names(backtest_result)) {
  final_capital <- tail(backtest_result$capital, 1)
  return_pct <- ((final_capital - TEST_PARAMS$initial_capital) / TEST_PARAMS$initial_capital) * 100

  # 计算胜率
  trades <- backtest_result[backtest_result$sell_signal == 1, ]
  if (nrow(trades) > 0 && "profit" %in% names(trades)) {
    win_rate <- sum(trades$profit > 0, na.rm = TRUE) / nrow(trades) * 100
  } else {
    win_rate <- NA
  }

  # 计算最大回撤
  capital_series <- backtest_result$capital
  cummax_capital <- cummax(capital_series)
  drawdown <- (cummax_capital - capital_series) / cummax_capital * 100
  max_drawdown <- max(drawdown, na.rm = TRUE)

  total_fees <- (buy_count + sell_count) * TEST_PARAMS$initial_capital * (TEST_PARAMS$fee_rate / 100)

} else {
  final_capital <- NA
  return_pct <- NA
  win_rate <- NA
  max_drawdown <- NA
  total_fees <- 0
}

cat("\n结果摘要:\n")
cat(sprintf("  信号数: %d\n", buy_count))
cat(sprintf("  交易数: %d\n", sell_count))
cat(sprintf("  最终资金: %.2f USDT\n", final_capital))
cat(sprintf("  收益率: %.2f%%\n", return_pct))
cat(sprintf("  胜率: %.2f%%\n", win_rate))
cat(sprintf("  最大回撤: %.2f%%\n", max_drawdown))
cat(sprintf("  总手续费: %.2f USDT\n", total_fees))
cat(sprintf("  执行时间: %.3f秒\n\n", elapsed_qcrypto))

# ============================================================================
# 对比结果
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("结果对比\n")
cat(rep("=", 80), "\n\n", sep="")

comparison <- data.frame(
  指标 = c("信号数", "交易数", "最终资金", "收益率(%)", "胜率(%)",
          "最大回撤(%)", "总手续费", "执行时间(秒)"),
  自定义版本 = c(
    result_custom$Signal_Count,
    result_custom$Trade_Count,
    sprintf("%.2f", result_custom$Final_Capital),
    sprintf("%.2f", result_custom$Return_Percentage),
    sprintf("%.2f", result_custom$Win_Rate),
    sprintf("%.2f", result_custom$Max_Drawdown),
    sprintf("%.2f", result_custom$Total_Fees),
    sprintf("%.3f", elapsed_custom)
  ),
  QCrypto版本 = c(
    buy_count,
    sell_count,
    sprintf("%.2f", final_capital),
    sprintf("%.2f", return_pct),
    sprintf("%.2f", win_rate),
    sprintf("%.2f", max_drawdown),
    sprintf("%.2f", total_fees),
    sprintf("%.3f", elapsed_qcrypto)
  ),
  stringsAsFactors = FALSE
)

print(comparison)

cat("\n")
cat(rep("=", 80), "\n", sep="")
cat("对比说明\n")
cat(rep("=", 80), "\n\n", sep="")

cat("关键差异:\n")
cat("1. 信号生成逻辑:\n")
cat("   - 自定义版本: 使用完整的信号生成函数\n")
cat("   - QCrypto版本: 修正了window_high计算（不含当前K线）\n\n")

cat("2. 止盈止损触发:\n")
cat("   - 自定义版本: 复杂的盘中触发逻辑（根据K线颜色判断优先级）\n")
cat("   - QCrypto版本: 简化的触发逻辑（K线结束时检查）\n\n")

cat("3. 手续费计算:\n")
cat("   - 自定义版本: 手动计算每笔交易的手续费\n")
cat("   - QCrypto版本: C++后端自动处理\n\n")

cat("请将以上结果与TradingView对比，看哪个版本更接近！\n\n")

# ============================================================================
# 导出详细交易记录（用于TradingView对比）
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("导出详细交易记录\n")
cat(rep("=", 80), "\n\n", sep="")

# 提取买入信号的时间和价格
buy_indices <- which(buy_signal == 1)
if (length(buy_indices) > 0) {
  buy_records <- data.frame(
    Index = buy_indices,
    Timestamp = index(data)[buy_indices],
    Close = as.numeric(data[buy_indices, "Close"]),
    High = as.numeric(data[buy_indices, "High"]),
    Low = as.numeric(data[buy_indices, "Low"]),
    stringsAsFactors = FALSE
  )

  cat("前10个买入信号:\n")
  print(head(buy_records, 10))

  # 保存到CSV
  write.csv(buy_records, "buy_signals_detail.csv", row.names = FALSE)
  cat(sprintf("\nOK 完整买入信号已保存: buy_signals_detail.csv (%d行)\n", nrow(buy_records)))
}

# 提取卖出信号的时间和价格
sell_indices <- which(sell_signal == 1)
if (length(sell_indices) > 0) {
  sell_records <- data.frame(
    Index = sell_indices,
    Timestamp = index(data)[sell_indices],
    Close = as.numeric(data[sell_indices, "Close"]),
    High = as.numeric(data[sell_indices, "High"]),
    Low = as.numeric(data[sell_indices, "Low"]),
    stringsAsFactors = FALSE
  )

  cat("\n前10个卖出信号:\n")
  print(head(sell_records, 10))

  # 保存到CSV
  write.csv(sell_records, "sell_signals_detail.csv", row.names = FALSE)
  cat(sprintf("\nOK 完整卖出信号已保存: sell_signals_detail.csv (%d行)\n", nrow(sell_records)))
}

cat("\n", rep("=", 80), "\n", sep="")
cat("测试完成！\n")
cat(rep("=", 80), "\n\n", sep="")

cat("生成的文件:\n")
cat("  1. buy_signals_detail.csv - 买入信号详细记录\n")
cat("  2. sell_signals_detail.csv - 卖出信号详细记录\n\n")

cat("下一步:\n")
cat("  1. 在TradingView中使用相同参数运行Pine Script\n")
cat("  2. 对比信号数量和时间点\n")
cat("  3. 对比最终收益率\n")
cat("  4. 确定哪个版本与TradingView一致\n\n")
