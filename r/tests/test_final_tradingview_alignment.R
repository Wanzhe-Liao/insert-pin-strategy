# 最终TradingView对齐验证测试
#
# 目标：验证所有关键修复后，R回测是否完全对齐TradingView
#
# 关键修复：
# 1. 出场条件：i >= entryBar → i > entryBar（避免同K线平仓又开仓）
# 2. 信号生成：look backDays直接当K线数（对齐Pine Script的命名混淆）
# 3. 冷却期：添加lastExitBar机制（防止快速重入场）
#
# 作者：Claude Code
# 日期：2025-10-27

cat("\n", rep("=", 80), "\n", sep="")
cat("最终TradingView对齐验证测试\n")
cat(rep("=", 80), "\n\n", sep="")

# 加载库
suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
})

# 加载修复版回测引擎
cat("加载修复版回测引擎...\n")
source("backtest_tradingview_aligned.R")

# 加载数据
cat("加载数据...\n")
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]
cat(sprintf("OK 数据加载完成: %d 根K线\n\n", nrow(data)))

# ============================================================================
# 测试参数（与TradingView完全一致）
# ============================================================================

TEST_PARAMS <- list(
  # WARN 关键：Pine Script中lookbackDays=3实际表示3根K线，不是3天
  lookbackDays = 3,              # 回看K线数（不是天数！）
  drop_percent = 20,              # 跌幅阈值 (%)
  take_profit_percent = 10,       # 止盈 (%)
  stop_loss_percent = 10,         # 止损 (%)
  initial_capital = 100,          # 初始资金（TradingView设置）
  fee_rate = 0.075               # 手续费率 (%)
)

cat("测试参数（对齐TradingView）:\n")
cat(sprintf("  回看K线数: %d根（Pine Script的lookbackDays）\n", TEST_PARAMS$lookbackDays))
cat(sprintf("  跌幅阈值: %.0f%%\n", TEST_PARAMS$drop_percent))
cat(sprintf("  止盈: %.0f%%\n", TEST_PARAMS$take_profit_percent))
cat(sprintf("  止损: %.0f%%\n", TEST_PARAMS$stop_loss_percent))
cat(sprintf("  初始资金: %d USDT\n", TEST_PARAMS$initial_capital))
cat(sprintf("  手续费: %.3f%%\n\n", TEST_PARAMS$fee_rate))

# ============================================================================
# 运行修复版回测
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("运行修复版回测\n")
cat(rep("=", 80), "\n\n", sep="")

start_time <- Sys.time()

result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = TEST_PARAMS$lookbackDays,
  minDropPercent = TEST_PARAMS$drop_percent,
  takeProfitPercent = TEST_PARAMS$take_profit_percent,
  stopLossPercent = TEST_PARAMS$stop_loss_percent,
  initialCapital = TEST_PARAMS$initial_capital,
  feeRate = TEST_PARAMS$fee_rate / 100,
  processOnClose = TRUE,  # 对齐Pine Script的process_orders_on_close=true
  verbose = FALSE,         # 不输出详细日志
  logIgnoredSignals = FALSE
)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

# ============================================================================
# 显示结果
# ============================================================================

cat("\n", rep("=", 80), "\n", sep="")
cat("修复版回测结果\n")
cat(rep("=", 80), "\n\n", sep="")

cat(sprintf("OK 执行时间: %.3f秒\n\n", elapsed))

cat("关键指标:\n")
cat(sprintf("  信号总数: %d\n", result$SignalCount))
cat(sprintf("  交易总数: %d\n", result$TradeCount))
cat(sprintf("  被忽略信号: %d (%.1f%%)\n",
            result$IgnoredSignalCount,
            result$IgnoredSignalCount / result$SignalCount * 100))
cat(sprintf("  最终资金: $%.2f\n", result$FinalCapital))
cat(sprintf("  总收益率: %.2f%%\n", result$ReturnPercent))
cat(sprintf("  胜率: %.2f%% (%d胜 / %d负)\n",
            result$WinRate, result$WinCount, result$LossCount))
cat(sprintf("  最大回撤: %.2f%%\n", result$MaxDrawdown))
cat(sprintf("  总手续费: $%.2f\n\n", result$TotalFees))

cat("出场原因统计:\n")
cat(sprintf("  止盈: %d (%.1f%%)\n", result$TPCount,
            result$TPCount / result$TradeCount * 100))
cat(sprintf("  止损: %d (%.1f%%)\n", result$SLCount,
            result$SLCount / result$TradeCount * 100))
cat(sprintf("  同时触发: %d (%.1f%%)\n\n", result$BothTriggerCount,
            result$BothTriggerCount / result$TradeCount * 100))

# ============================================================================
# 关键验证检查
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("关键验证检查\n")
cat(rep("=", 80), "\n\n", sep="")

# 检查1：HoldingBars=0的交易（同K线平仓又开仓）
trades_df <- result$Trades

# 安全检查：确保trades_df是data.frame
if (is.list(trades_df) && !is.data.frame(trades_df)) {
  trades_df <- as.data.frame(do.call(rbind, trades_df), stringsAsFactors = FALSE)
}

if ("HoldingBars" %in% names(trades_df) && nrow(trades_df) > 0) {
  zero_holding_trades <- trades_df[trades_df$HoldingBars == 0, ]

  cat(sprintf("[检查1] 同K线交易数量: %d\n", nrow(zero_holding_trades)))
  if (nrow(zero_holding_trades) == 0) {
    cat("  OK 通过！没有同K线交易\n")
  } else {
    cat("  FAIL 失败！仍存在同K线交易\n")
    cat("\n异常交易:\n")
    print(head(zero_holding_trades[, c("TradeId", "EntryTime", "ExitTime", "ExitReason", "PnLPercent")], 5))
  }
} else {
  cat("[检查1] 跳过（trades_df格式问题）\n")
}

# 检查2：交易数量是否接近TradingView（9笔）
cat(sprintf("\n[检查2] 交易数量对比: R=%d vs TV=9\n", result$TradeCount))
trade_diff <- abs(result$TradeCount - 9)
if (trade_diff <= 5) {
  cat(sprintf("  OK 通过！差异仅%d笔\n", trade_diff))
} else {
  cat(sprintf("  WARN 警告！差异%d笔，仍较大\n", trade_diff))
}

# 检查3：首笔交易时间
if (nrow(trades_df) > 0) {
  first_trade <- trades_df[1, ]
  tv_first_time <- as.POSIXct("2023-05-06 02:44:59", tz="UTC")
  r_first_time <- as.POSIXct(first_trade$EntryTime)
  time_diff_hours <- as.numeric(difftime(r_first_time, tv_first_time, units="hours"))

  cat(sprintf("\n[检查3] 首笔交易时间:\n"))
  cat(sprintf("  TradingView: 2023-05-06 02:44:59\n"))
  cat(sprintf("  R修复版: %s\n", first_trade$EntryTime))
  cat(sprintf("  时间差: %.1f小时\n", abs(time_diff_hours)))
  if (abs(time_diff_hours) < 24) {
    cat("  OK 通过！时间差<24小时\n")
  } else {
    cat("  FAIL 失败！时间差>24小时\n")
  }
} else {
  cat("\n[检查3] 跳过（无交易数据）\n")
}

# 检查4：胜率合理性
cat(sprintf("\n[检查4] 胜率检查: %.2f%%\n", result$WinRate))
if (result$WinRate >= 70 && result$WinRate <= 100) {
  cat("  OK 通过！胜率在合理范围\n")
} else if (result$WinRate < 70) {
  cat("  WARN 警告！胜率偏低，可能仍有逻辑问题\n")
}

# 检查5：平均盈亏接近±10%
if (nrow(trades_df) > 0 && "PnLPercent" %in% names(trades_df)) {
  avg_profit <- mean(trades_df[trades_df$PnLPercent > 0, "PnLPercent"], na.rm = TRUE)
  avg_loss <- mean(trades_df[trades_df$PnLPercent < 0, "PnLPercent"], na.rm = TRUE)

  cat(sprintf("\n[检查5] 平均盈亏:\n"))
  cat(sprintf("  平均盈利: %.2f%% (预期~10%%)\n", avg_profit))
  cat(sprintf("  平均亏损: %.2f%% (预期~-10%%)\n", avg_loss))
  if (!is.na(avg_profit) && abs(avg_profit - 10) < 1 && (!is.na(avg_loss) && abs(avg_loss + 10) < 1 || is.nan(avg_loss))) {
    cat("  OK 通过！盈亏接近预期\n")
  } else {
    cat("  WARN 注意！盈亏与预期有偏差\n")
  }
} else {
  cat("\n[检查5] 跳过（无交易数据）\n")
}

# ============================================================================
# 与TradingView详细对比
# ============================================================================

cat("\n", rep("=", 80), "\n", sep="")
cat("与TradingView详细对比\n")
cat(rep("=", 80), "\n\n", sep="")

tv_results <- data.frame(
  指标 = c("交易数量", "胜率(%)", "收益率(%)", "最大回撤(%)", "总手续费"),
  TradingView = c("9", "100.00", "175.99", "13.95", "2.23 USDT"),
  R修复版 = c(
    as.character(result$TradeCount),
    sprintf("%.2f", result$WinRate),
    sprintf("%.2f", result$ReturnPercent),
    sprintf("%.2f", result$MaxDrawdown),
    sprintf("%.2f USDT", result$TotalFees)
  ),
  stringsAsFactors = FALSE
)

print(tv_results)

# ============================================================================
# 导出结果
# ============================================================================

cat("\n", rep("=", 80), "\n", sep="")
cat("导出结果文件\n")
cat(rep("=", 80), "\n\n", sep="")

# 导出交易详情
write.csv(trades_df, "final_trades_aligned.csv", row.names = FALSE)
cat(sprintf("OK 交易详情已导出: final_trades_aligned.csv (%d行)\n", nrow(trades_df)))

# 导出前10笔交易对比
if (nrow(trades_df) >= 10) {
  first_10 <- trades_df[1:10, c("TradeId", "EntryTime", "EntryPrice", "ExitTime",
                                 "ExitPrice", "ExitReason", "PnLPercent", "HoldingBars")]
  cat("\n前10笔交易:\n")
  print(first_10)
}

# ============================================================================
# 最终判断
# ============================================================================

cat("\n", rep("=", 80), "\n", sep="")
cat("最终判断\n")
cat(rep("=", 80), "\n\n", sep="")

# 计算对齐分数
alignment_score <- 0
if (nrow(zero_holding_trades) == 0) alignment_score <- alignment_score + 30
if (trade_diff <= 5) alignment_score <- alignment_score + 30
if (abs(time_diff_hours) < 24) alignment_score <- alignment_score + 20
if (result$WinRate >= 70) alignment_score <- alignment_score + 10
if (abs(avg_profit - 10) < 1) alignment_score <- alignment_score + 10

cat(sprintf("对齐分数: %d/100\n\n", alignment_score))

if (alignment_score >= 80) {
  cat("OK 优秀！R回测已基本对齐TradingView\n")
  cat("   建议：可以进行大规模参数优化\n\n")
} else if (alignment_score >= 60) {
  cat("WARN 良好！R回测接近TradingView，但仍有改进空间\n")
  cat("   建议：检查剩余差异，进一步优化\n\n")
} else {
  cat("FAIL 需要改进！R回测与TradingView仍有较大差异\n")
  cat("   建议：仔细检查Pine Script代码和R实现的每个细节\n\n")
}

cat(rep("=", 80), "\n", sep="")
cat("测试完成！\n")
cat(rep("=", 80), "\n\n", sep="")

cat("生成的文件:\n")
cat("  1. final_trades_aligned.csv - 修复版交易详情\n\n")

cat("下一步:\n")
cat("  1. 如果对齐分数>=80：运行大规模参数优化\n")
cat("  2. 如果对齐分数<80：继续调查差异原因\n")
cat("  3. 对比前10笔交易的时间和价格，确认一致性\n\n")
