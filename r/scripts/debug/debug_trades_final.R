# 最终调试：提取正确的交易数据

library(xts)

load('data/liaochu.RData')
source('backtest_tradingview_aligned.R')

data <- cryptodata[["PEPEUSDT_15m"]]

# 运行回测
result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 50,
  stopLossPercent = 50
)

cat("========================================\n")
cat("交易数据提取（正确的字段名）\n")
cat("========================================\n\n")

# 使用大写的Trades
cat("Trades检查:\n")
cat("Trades是否为NULL:", is.null(result$Trades), "\n")

if (!is.null(result$Trades) && length(result$Trades) > 0) {
  cat("总交易数:", length(result$Trades), "\n\n")

  cat("所有交易的入场时间:\n")
  for (i in 1:length(result$Trades)) {
    trade <- result$Trades[[i]]
    cat(sprintf("交易 #%d: %s (%.8f)\n",
                i,
                as.character(trade$entry_time),
                trade$entry_price))
  }

  cat("\n第一笔交易详情:\n")
  first_trade <- result$Trades[[1]]
  cat("入场时间:", as.character(first_trade$entry_time), "\n")
  cat("入场日期:", format(first_trade$entry_time, "%Y-%m-%d"), "\n")
  cat("入场价格:", first_trade$entry_price, "\n")
  cat("出场时间:", as.character(first_trade$exit_time), "\n")
  cat("出场价格:", first_trade$exit_price, "\n")
  cat("收益率:", sprintf("%.2f%%", first_trade$pnl_pct), "\n")
  cat("出场原因:", first_trade$exit_type, "\n")
}

cat("\n========================================\n")
cat("被忽略信号提取\n")
cat("========================================\n\n")

cat("IgnoredSignals检查:\n")
cat("IgnoredSignals是否为NULL:", is.null(result$IgnoredSignals), "\n")

if (!is.null(result$IgnoredSignals) && length(result$IgnoredSignals) > 0) {
  cat("总被忽略信号数:", length(result$IgnoredSignals), "\n\n")

  cat("所有被忽略信号:\n")
  for (i in 1:length(result$IgnoredSignals)) {
    sig <- result$IgnoredSignals[[i]]
    cat(sprintf("信号 #%d: %s - %s\n",
                i,
                as.character(sig$time),
                sig$reason))
  }

  # 检查2023-05-06的被忽略信号
  cat("\n2023-05-06的被忽略信号:\n")
  may6_ignored <- sapply(result$IgnoredSignals, function(sig) {
    format(sig$time, "%Y-%m-%d") == "2023-05-06"
  })

  if (any(may6_ignored)) {
    may6_sigs <- result$IgnoredSignals[may6_ignored]
    for (sig in may6_sigs) {
      cat("  时间:", as.character(sig$time), "\n")
      cat("  原因:", sig$reason, "\n")
    }
  } else {
    cat("  无2023-05-06的被忽略信号\n")
  }
}

cat("\n========================================\n")
cat("关键分析：为什么第一笔是2023-05-09？\n")
cat("========================================\n\n")

# 生成所有信号
signals <- generate_drop_signals(data, lookbackDays=3, minDropPercent=20)
all_signal_indices <- which(signals)

cat("所有信号索引（前20个）:\n")
for (i in 1:min(20, length(all_signal_indices))) {
  idx <- all_signal_indices[i]
  sig_time <- index(data)[idx]
  cat(sprintf("信号 #%d: 索引%d - %s\n", i, idx, as.character(sig_time)))
}

# 对比第一个信号和第一笔交易
cat("\n对比分析:\n")
first_signal_idx <- all_signal_indices[1]
first_signal_time <- index(data)[first_signal_idx]

cat("第一个信号:\n")
cat("  索引:", first_signal_idx, "\n")
cat("  时间:", as.character(first_signal_time), "\n")
cat("  日期:", format(first_signal_time, "%Y-%m-%d"), "\n")

if (!is.null(result$Trades) && length(result$Trades) > 0) {
  first_trade <- result$Trades[[1]]
  cat("\n第一笔交易:\n")
  cat("  时间:", as.character(first_trade$entry_time), "\n")
  cat("  日期:", format(first_trade$entry_time, "%Y-%m-%d"), "\n")

  time_diff <- as.numeric(difftime(first_trade$entry_time, first_signal_time, units="days"))
  cat("\n时间差:", sprintf("%.2f天", time_diff), "\n")
}

# 检查2023-05-06到2023-05-09之间的所有信号
cat("\n2023-05-06到2023-05-09的信号分布:\n")
for (date_str in c("2023-05-06", "2023-05-07", "2023-05-08", "2023-05-09")) {
  day_indices <- which(format(index(data), "%Y-%m-%d") == date_str)
  day_signals <- signals[day_indices]
  signal_count <- sum(day_signals)

  cat(sprintf("%s: %d个信号\n", date_str, signal_count))

  if (signal_count > 0) {
    signal_times <- index(data)[day_indices[day_signals]]
    for (st in signal_times) {
      cat(sprintf("  - %s\n", as.character(st)))
    }
  }
}

cat("\n\n最终报告保存中...\n")

# 保存最终报告
sink("time_diff_final_report.txt")

cat("========================================\n")
cat("R vs TradingView 时间差异根因分析报告\n")
cat("生成时间:", as.character(Sys.time()), "\n")
cat("========================================\n\n")

cat("【问题】\n")
cat("TradingView第一笔交易: 2023-05-06 (Excel序列号45052)\n")
cat("R第一笔交易: 2023-05-09 02:14:59\n")
cat("差异: 约3天\n\n")

cat("【根本原因】lookbackBars参数定义错误\n\n")

cat("1. 代码实现（backtest_tradingview_aligned.R 第100行）:\n")
cat("   lookbackBars <- lookbackDays  # 直接使用，不转换\n\n")

cat("2. 实际效果:\n")
cat("   - 输入: lookbackDays = 3\n")
cat("   - 结果: lookbackBars = 3（3根K线，约45分钟）\n")
cat("   - 期望: lookbackBars = 288（3天 × 96根K线/天）\n\n")

cat("3. 代码注释声称:\n")
cat('   "虽然变量名叫lookbackDays，但Pine Script实际将其当作K线数量使用！"\n\n')

cat("4. 这导致:\n")
cat("   - 只看前3根K线（45分钟）而非3天\n")
cat("   - 信号生成逻辑与TradingView不一致\n")
cat("   - 第一个信号出现过早（索引4，2023-05-06 02:59:59）\n\n")

cat("【信号vs交易分析】\n\n")

cat("R第一个信号:\n")
cat("  索引:", first_signal_idx, "\n")
cat("  时间:", as.character(first_signal_time), "\n")
cat("  日期:", format(first_signal_time, "%Y-%m-%d"), "\n\n")

if (!is.null(result$Trades) && length(result$Trades) > 0) {
  first_trade <- result$Trades[[1]]
  cat("R第一笔交易:\n")
  cat("  时间:", as.character(first_trade$entry_time), "\n")
  cat("  日期:", format(first_trade$entry_time, "%Y-%m-%d"), "\n")
  cat("  入场价:", first_trade$entry_price, "\n")
  cat("  出场价:", first_trade$exit_price, "\n")
  cat("  收益率:", sprintf("%.2f%%", first_trade$pnl_pct), "\n\n")

  time_diff <- as.numeric(difftime(first_trade$entry_time, first_signal_time, units="days"))
  cat("第一个信号到第一笔交易的时间差:", sprintf("%.2f天", time_diff), "\n\n")
}

cat("信号分布（2023-05-06到2023-05-09）:\n")
for (date_str in c("2023-05-06", "2023-05-07", "2023-05-08", "2023-05-09")) {
  day_indices <- which(format(index(data), "%Y-%m-%d") == date_str)
  day_signals <- signals[day_indices]
  signal_count <- sum(day_signals)
  cat(sprintf("  %s: %d个信号\n", date_str, signal_count))
}
cat("\n")

if (!is.null(result$IgnoredSignals) && length(result$IgnoredSignals) > 0) {
  cat("被忽略的信号:\n")
  cat("  总数:", length(result$IgnoredSignals), "\n")

  may6_ignored <- sapply(result$IgnoredSignals, function(sig) {
    format(sig$time, "%Y-%m-%d") == "2023-05-06"
  })

  if (any(may6_ignored)) {
    cat("  2023-05-06被忽略:", sum(may6_ignored), "个\n")
    may6_sigs <- result$IgnoredSignals[may6_ignored]
    for (sig in may6_sigs) {
      cat("    -", as.character(sig$time), "-", sig$reason, "\n")
    }
  }
  cat("\n")
}

cat("【结论】\n\n")

cat("主要问题:\n")
cat("1. lookbackBars计算错误，使用3根K线而非3天（288根K线）\n")
cat("2. 这导致信号生成逻辑与TradingView完全不同\n")
cat("3. 需要验证Pine Script中lookbackDays的真实含义\n\n")

cat("次要问题（需进一步调查）:\n")
cat("1. 为什么2023-05-06的信号没有产生交易？\n")
cat("2. 被忽略信号的原因是什么？\n")
cat("3. 第一笔交易为何延迟到2023-05-09？\n\n")

cat("建议修复:\n")
cat("1. 检查TradingView Pine Script源码，确认lookbackDays含义\n")
cat("2. 如果确实应该是天数，修改第100行:\n")
cat("     lookbackBars <- lookbackDays * 96  # 15分钟K线\n")
cat("3. 重新运行回测，验证第一笔交易时间是否对齐\n")

sink()

cat("最终报告已保存: time_diff_final_report.txt\n")
