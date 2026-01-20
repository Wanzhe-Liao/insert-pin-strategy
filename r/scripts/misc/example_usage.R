# ============================================================================
# 回测函数使用示例
# ============================================================================

library(data.table)
library(lubridate)

# 加载回测函数
source("backtest_with_fee.R")

# ============================================================================
# 示例1：基本使用 - 使用默认参数
# ============================================================================

example_basic <- function() {
  cat("\n=== 示例1：基本使用 ===\n\n")

  # 加载数据
  load("data/liaochu.RData")
  data <- cryptodata[["PEPEUSDT_15m"]]

  # 转换xts为data.table
  if (inherits(data, "xts")) {
    require(xts)
    timestamps <- index(data)
    data <- as.data.table(data)
    data[, timestamp := timestamps]
    setnames(data, tolower(names(data)))
  }

  # 运行回测（使用默认参数）
  result <- run_backtest(
    data = data,
    lookback_days = 3,
    drop_threshold = 0.20,
    initial_capital = 1000,
    take_profit = 0.10,
    stop_loss = 0.10,
    fee_rate = 0.00075
  )

  # 查看统计结果
  cat("\n统计结果已自动打印\n")

  # 查看前10笔交易
  cat("\n前10笔交易:\n")
  if (nrow(result$trades) > 0) {
    print(head(result$trades[, .(
      trade_id, entry_time, exit_time,
      entry_price, exit_price, exit_type,
      profit, profit_pct, capital_after
    )], 10))
  }

  return(result)
}

# ============================================================================
# 示例2：参数优化 - 测试不同止盈止损比例
# ============================================================================

example_parameter_optimization <- function() {
  cat("\n=== 示例2：参数优化 ===\n\n")

  # 加载数据
  load("data/liaochu.RData")
  data <- cryptodata[["PEPEUSDT_15m"]]

  # 转换xts为data.table
  if (inherits(data, "xts")) {
    require(xts)
    timestamps <- index(data)
    data <- as.data.table(data)
    data[, timestamp := timestamps]
    setnames(data, tolower(names(data)))
  }

  # 测试不同的止盈止损组合
  tp_sl_combinations <- data.table(
    take_profit = c(0.05, 0.10, 0.15, 0.20),
    stop_loss = c(0.05, 0.10, 0.15, 0.20)
  )

  results_summary <- list()

  for (i in 1:nrow(tp_sl_combinations)) {
    tp <- tp_sl_combinations$take_profit[i]
    sl <- tp_sl_combinations$stop_loss[i]

    cat(sprintf("\n测试组合 %d: TP=%.0f%%, SL=%.0f%%\n", i, tp*100, sl*100))

    result <- run_backtest(
      data = data,
      lookback_days = 3,
      drop_threshold = 0.20,
      initial_capital = 1000,
      take_profit = tp,
      stop_loss = sl,
      fee_rate = 0.00075
    )

    results_summary[[i]] <- data.table(
      TP = sprintf("%.0f%%", tp*100),
      SL = sprintf("%.0f%%", sl*100),
      Total_Trades = result$stats$total_trades,
      Win_Rate = sprintf("%.2f%%", result$stats$win_rate),
      Final_Capital = sprintf("$%.2f", result$final_capital),
      Total_Return = sprintf("%.2f%%", result$stats$total_return),
      Total_Fees = sprintf("$%.2f", result$stats$total_fees)
    )
  }

  # 汇总结果
  summary_dt <- rbindlist(results_summary)

  cat("\n\n参数优化结果:\n")
  print(summary_dt)

  return(summary_dt)
}

# ============================================================================
# 示例3：无手续费回测（对比）
# ============================================================================

example_no_fee <- function() {
  cat("\n=== 示例3：无手续费回测 ===\n\n")

  # 加载数据
  load("data/liaochu.RData")
  data <- cryptodata[["PEPEUSDT_15m"]]

  # 转换xts为data.table
  if (inherits(data, "xts")) {
    require(xts)
    timestamps <- index(data)
    data <- as.data.table(data)
    data[, timestamp := timestamps]
    setnames(data, tolower(names(data)))
  }

  # 生成信号（所有版本共用）
  timeframe_minutes <- detect_timeframe(data)
  lookback_bars <- convert_days_to_bars(3, timeframe_minutes)
  data_with_signals <- generate_signals(data, lookback_bars, 0.20)

  # 无手续费回测
  result_no_fee <- backtest_with_intrabar_and_fee(
    data_with_signals,
    initial_capital = 1000,
    take_profit = 0.10,
    stop_loss = 0.10,
    fee_rate = 0  # 无手续费
  )

  # 有手续费回测
  result_with_fee <- backtest_with_intrabar_and_fee(
    data_with_signals,
    initial_capital = 1000,
    take_profit = 0.10,
    stop_loss = 0.10,
    fee_rate = 0.00075  # 0.075%手续费
  )

  # 对比
  cat("\n\n手续费影响对比:\n")
  comparison <- data.table(
    版本 = c("无手续费", "0.075%手续费"),
    总交易次数 = c(result_no_fee$stats$total_trades,
                result_with_fee$stats$total_trades),
    胜率 = sprintf("%.2f%%", c(result_no_fee$stats$win_rate,
                              result_with_fee$stats$win_rate)),
    最终资金 = sprintf("$%.2f", c(result_no_fee$final_capital,
                                 result_with_fee$final_capital)),
    总收益率 = sprintf("%.2f%%", c(result_no_fee$stats$total_return,
                                 result_with_fee$stats$total_return)),
    总手续费 = sprintf("$%.2f", c(0, result_with_fee$stats$total_fees)),
    手续费占比 = sprintf("%.2f%%", c(0,
      result_with_fee$stats$total_fees / result_no_fee$stats$total_profit * 100))
  )

  print(comparison)

  return(list(no_fee = result_no_fee, with_fee = result_with_fee))
}

# ============================================================================
# 示例4：导出交易记录到CSV
# ============================================================================

example_export_trades <- function() {
  cat("\n=== 示例4：导出交易记录 ===\n\n")

  # 加载数据
  load("data/liaochu.RData")
  data <- cryptodata[["PEPEUSDT_15m"]]

  # 转换xts为data.table
  if (inherits(data, "xts")) {
    require(xts)
    timestamps <- index(data)
    data <- as.data.table(data)
    data[, timestamp := timestamps]
    setnames(data, tolower(names(data)))
  }

  # 运行回测
  result <- run_backtest(
    data = data,
    lookback_days = 3,
    drop_threshold = 0.20,
    initial_capital = 1000,
    take_profit = 0.10,
    stop_loss = 0.10,
    fee_rate = 0.00075
  )

  # 导出交易记录
  if (nrow(result$trades) > 0) {
    output_file <- "backtest_trades_export.csv"
    fwrite(result$trades, output_file)
    cat(sprintf("\n交易记录已导出到: %s\n", output_file))
    cat(sprintf("总计 %d 笔交易\n", nrow(result$trades)))
  }

  return(result)
}

# ============================================================================
# 示例5：自定义分析 - 计算夏普比率等指标
# ============================================================================

example_advanced_analysis <- function() {
  cat("\n=== 示例5：高级分析 ===\n\n")

  # 加载数据
  load("data/liaochu.RData")
  data <- cryptodata[["PEPEUSDT_15m"]]

  # 转换xts为data.table
  if (inherits(data, "xts")) {
    require(xts)
    timestamps <- index(data)
    data <- as.data.table(data)
    data[, timestamp := timestamps]
    setnames(data, tolower(names(data)))
  }

  # 运行回测
  result <- run_backtest(
    data = data,
    lookback_days = 3,
    drop_threshold = 0.20,
    initial_capital = 1000,
    take_profit = 0.10,
    stop_loss = 0.10,
    fee_rate = 0.00075
  )

  if (nrow(result$trades) > 0) {
    # 计算额外指标
    trades <- result$trades

    # 1. 夏普比率（假设无风险利率为0）
    returns <- trades$profit_pct
    sharpe_ratio <- mean(returns) / sd(returns) * sqrt(252)  # 年化

    # 2. 最大回撤
    equity_curve <- cumsum(trades$profit)
    running_max <- cummax(equity_curve)
    drawdown <- equity_curve - running_max
    max_drawdown <- min(drawdown)
    max_drawdown_pct <- max_drawdown / result$stats$total_profit * 100

    # 3. 盈亏比
    winning_trades <- trades[profit > 0]
    losing_trades <- trades[profit < 0]
    avg_win <- mean(winning_trades$profit)
    avg_loss <- abs(mean(losing_trades$profit))
    profit_factor <- avg_win / avg_loss

    # 4. 连续盈利/亏损
    win_streak <- max(rle(trades$profit > 0)$lengths[rle(trades$profit > 0)$values])
    loss_streak <- max(rle(trades$profit < 0)$lengths[rle(trades$profit < 0)$values])

    # 打印高级指标
    cat("\n高级分析指标:\n")
    cat(rep("=", 60), "\n", sep = "")
    cat(sprintf("夏普比率（年化）: %.2f\n", sharpe_ratio))
    cat(sprintf("最大回撤: $%.2f (%.2f%%)\n", max_drawdown, max_drawdown_pct))
    cat(sprintf("盈亏比: %.2f\n", profit_factor))
    cat(sprintf("最长连续盈利: %d 笔\n", win_streak))
    cat(sprintf("最长连续亏损: %d 笔\n", loss_streak))
    cat(sprintf("平均持仓时间: %.1f 根K线\n",
                mean(trades$exit_index - trades$entry_index)))
    cat(rep("=", 60), "\n", sep = "")
  }

  return(result)
}

# ============================================================================
# 运行示例（取消注释以执行）
# ============================================================================

# 示例1：基本使用
# result1 <- example_basic()

# 示例2：参数优化
# result2 <- example_parameter_optimization()

# 示例3：手续费对比
# result3 <- example_no_fee()

# 示例4：导出交易记录
# result4 <- example_export_trades()

# 示例5：高级分析
# result5 <- example_advanced_analysis()

cat("\n示例脚本加载完成！\n")
cat("取消注释上面的代码以运行相应示例\n")
cat("\n可用示例:\n")
cat("  - example_basic(): 基本使用\n")
cat("  - example_parameter_optimization(): 参数优化\n")
cat("  - example_no_fee(): 手续费对比\n")
cat("  - example_export_trades(): 导出交易记录\n")
cat("  - example_advanced_analysis(): 高级分析\n")
