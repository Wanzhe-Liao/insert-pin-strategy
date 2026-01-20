# 测试修复后的100%对齐
# 验证信号窗口修复是否提高对齐率
# 2025-10-27

cat("\n================================================================================\n")
cat("测试修复后的100%对齐：信号窗口排除当前K线\n")
cat("================================================================================\n\n")

library(xts)
library(data.table)
library(RcppRoll)

# 加载数据
load("data/liaochu.RData")

# 加载修复后的回测函数
source("backtest_tradingview_aligned.R")

# 获取PEPEUSDT 15分钟数据
data <- cryptodata[["PEPEUSDT_15m"]]

cat("数据行数:", nrow(data), "\n")
cat("数据范围:", as.character(index(data)[1]), "至", as.character(index(data)[nrow(data)]), "\n\n")

# 运行修复后的回测
cat("运行修复后的回测中...\n\n")

result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,  # 不输出详细日志
  logIgnoredSignals = TRUE
)

cat("\n")
cat(rep("=", 100), "\n", sep="")
cat("修复后回测结果\n")
cat(rep("=", 100), "\n\n", sep="")

cat(sprintf("交易数量: %d\n", result$TradeCount))
cat(sprintf("信号总数: %d\n", result$SignalCount))
cat(sprintf("被忽略信号: %d\n", result$IgnoredSignalCount))
cat(sprintf("胜率: %.2f%% (%d胜/%d负)\n", result$WinRate, result$WinCount, result$LossCount))
cat(sprintf("总收益率: %.2f%%\n", result$ReturnPercent))
cat(sprintf("平均盈亏: %.2f%%\n", result$AvgPnL))

# 保存交易结果
if (length(result$Trades) > 0) {
  trades_list <- result$Trades

  trades_df <- data.frame(
    TradeId = sapply(trades_list, function(x) x$TradeId),
    EntryTime = sapply(trades_list, function(x) x$EntryTime),
    EntryPrice = sapply(trades_list, function(x) x$EntryPrice),
    ExitTime = sapply(trades_list, function(x) x$ExitTime),
    ExitPrice = sapply(trades_list, function(x) x$ExitPrice),
    ExitReason = sapply(trades_list, function(x) x$ExitReason),
    PnLPercent = sapply(trades_list, function(x) x$PnLPercent),
    HoldingBars = sapply(trades_list, function(x) x$HoldingBars),
    stringsAsFactors = FALSE
  )

  write.csv(trades_df, "r_backtest_trades_FIXED.csv", row.names = FALSE)
  cat("\nOK 修复后结果已保存: r_backtest_trades_FIXED.csv\n\n")

  # 读取TradingView数据进行对比
  tv <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)

  cat(rep("=", 100), "\n", sep="")
  cat("逐笔详细对比（修复后 vs TradingView）\n")
  cat(rep("=", 100), "\n\n", sep="")

  for (i in 1:min(nrow(trades_df), nrow(tv))) {
    cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
    cat(sprintf("交易 #%d\n", i))
    cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))

    # 入场时间
    tv_entry <- substr(tv$EntryTime[i], 1, 16)
    r_entry <- substr(trades_df$EntryTime[i], 1, 16)
    entry_match <- (tv_entry == r_entry)

    cat(sprintf("入场时间:\n"))
    cat(sprintf("  TV:    %s\n", tv_entry))
    cat(sprintf("  R修复: %s\n", r_entry))
    cat(sprintf("  %s\n\n", ifelse(entry_match, "OK 完全一致", "FAIL 不一致")))

    # 入场价格
    price_diff_pct <- abs(tv$EntryPrice[i] - trades_df$EntryPrice[i]) / tv$EntryPrice[i] * 100
    price_match <- price_diff_pct < 0.1

    cat(sprintf("入场价格:\n"))
    cat(sprintf("  TV:    $%.8f\n", tv$EntryPrice[i]))
    cat(sprintf("  R修复: $%.8f\n", trades_df$EntryPrice[i]))
    cat(sprintf("  差异: %.2f%%\n", price_diff_pct))
    cat(sprintf("  %s\n\n", ifelse(price_match, "OK 基本一致", "FAIL 差异较大")))

    # 出场时间
    tv_exit <- substr(tv$ExitTime[i], 1, 16)
    r_exit <- substr(trades_df$ExitTime[i], 1, 16)
    exit_match <- (tv_exit == r_exit)

    cat(sprintf("出场时间:\n"))
    cat(sprintf("  TV:    %s\n", tv_exit))
    cat(sprintf("  R修复: %s\n", r_exit))
    cat(sprintf("  %s\n\n", ifelse(exit_match, "OK 完全一致", "FAIL 不一致")))

    # 盈亏
    pnl_diff <- abs(tv$PnL[i] - trades_df$PnLPercent[i])
    pnl_match <- pnl_diff < 1

    cat(sprintf("盈亏:\n"))
    cat(sprintf("  TV:    %.2f%%\n", tv$PnL[i]))
    cat(sprintf("  R修复: %.2f%% (%s)\n", trades_df$PnLPercent[i], trades_df$ExitReason[i]))
    cat(sprintf("  差异: %.2f%%\n", pnl_diff))
    cat(sprintf("  %s\n\n", ifelse(pnl_match, "OK 基本一致", "FAIL 差异较大")))
  }

  # 计算对齐率
  cat(rep("=", 100), "\n", sep="")
  cat("最终对齐率统计\n")
  cat(rep("=", 100), "\n\n", sep="")

  entry_time_matches <- sum(substr(tv$EntryTime, 1, 16) == substr(trades_df$EntryTime, 1, 16))
  exit_time_matches <- sum(substr(tv$ExitTime, 1, 16) == substr(trades_df$ExitTime, 1, 16))
  entry_price_matches <- sum(abs(tv$EntryPrice - trades_df$EntryPrice) / tv$EntryPrice * 100 < 0.1)
  exit_price_matches <- sum(abs(tv$ExitPrice - trades_df$ExitPrice) / tv$ExitPrice * 100 < 0.1)
  pnl_matches <- sum(abs(tv$PnL - trades_df$PnLPercent) < 1)

  cat(sprintf("交易数量对齐: %d vs %d %s\n",
              nrow(trades_df), nrow(tv),
              ifelse(nrow(trades_df) == nrow(tv), "OK 完全一致", "FAIL 不一致")))
  cat(sprintf("入场时间完全一致: %d/%d (%.1f%%) %s\n",
              entry_time_matches, nrow(tv), entry_time_matches/nrow(tv)*100,
              ifelse(entry_time_matches >= 8, "OK", "WARN")))
  cat(sprintf("出场时间完全一致: %d/%d (%.1f%%) %s\n",
              exit_time_matches, nrow(tv), exit_time_matches/nrow(tv)*100,
              ifelse(exit_time_matches >= 7, "OK", "WARN")))
  cat(sprintf("入场价格基本一致(<0.1%%): %d/%d (%.1f%%) %s\n",
              entry_price_matches, nrow(tv), entry_price_matches/nrow(tv)*100,
              ifelse(entry_price_matches >= 8, "OK", "WARN")))
  cat(sprintf("出场价格基本一致(<0.1%%): %d/%d (%.1f%%) %s\n",
              exit_price_matches, nrow(tv), exit_price_matches/nrow(tv)*100,
              ifelse(exit_price_matches >= 7, "OK", "WARN")))
  cat(sprintf("盈亏基本一致(<1%%): %d/%d (%.1f%%) %s\n",
              pnl_matches, nrow(tv), pnl_matches/nrow(tv)*100,
              ifelse(pnl_matches >= 8, "OK", "WARN")))

  # 胜率对比
  tv_winrate <- sum(tv$PnL > 0) / nrow(tv) * 100
  r_winrate <- sum(trades_df$PnLPercent > 0) / nrow(trades_df) * 100

  cat(sprintf("\nTradingView胜率: %.2f%% (%d胜/%d负)\n",
              tv_winrate, sum(tv$PnL > 0), sum(tv$PnL <= 0)))
  cat(sprintf("R修复后胜率: %.2f%% (%d胜/%d负)\n",
              r_winrate, sum(trades_df$PnLPercent > 0), sum(trades_df$PnLPercent <= 0)))
  cat(sprintf("胜率差异: %.2f%% %s\n",
              abs(tv_winrate - r_winrate),
              ifelse(abs(tv_winrate - r_winrate) < 0.01, "OK 完全一致", "WARN")))

  # 对比修复前后的改进
  cat("\n")
  cat(rep("=", 100), "\n", sep="")
  cat("修复前后对比\n")
  cat(rep("=", 100), "\n\n", sep="")

  # 读取修复前的结果（如果存在）
  if (file.exists("outputs/r_backtest_trades_100percent.csv")) {
    r_old <- read.csv("outputs/r_backtest_trades_100percent.csv")

    old_entry_time_matches <- sum(substr(tv$EntryTime, 1, 16) == substr(r_old$EntryTime, 1, 16))
    old_entry_price_matches <- sum(abs(tv$EntryPrice - r_old$EntryPrice) / tv$EntryPrice * 100 < 0.1)

    cat("入场时间对齐率:\n")
    cat(sprintf("  修复前: %d/9 (%.1f%%)\n", old_entry_time_matches, old_entry_time_matches/9*100))
    cat(sprintf("  修复后: %d/9 (%.1f%%)\n", entry_time_matches, entry_time_matches/9*100))
    cat(sprintf("  提升: %+d (%.1f%%)\n\n",
                entry_time_matches - old_entry_time_matches,
                (entry_time_matches - old_entry_time_matches)/9*100))

    cat("入场价格对齐率:\n")
    cat(sprintf("  修复前: %d/9 (%.1f%%)\n", old_entry_price_matches, old_entry_price_matches/9*100))
    cat(sprintf("  修复后: %d/9 (%.1f%%)\n", entry_price_matches, entry_price_matches/9*100))
    cat(sprintf("  提升: %+d (%.1f%%)\n\n",
                entry_price_matches - old_entry_price_matches,
                (entry_price_matches - old_entry_price_matches)/9*100))
  }

  # 最终判断
  cat("\n")
  cat(rep("=", 100), "\n", sep="")
  cat("最终评估\n")
  cat(rep("=", 100), "\n\n", sep="")

  if (entry_time_matches == 9 && entry_price_matches == 9 && nrow(trades_df) == 9) {
    cat("🎉🎉🎉 完美！达到100%完全对齐！🎉🎉🎉\n\n")
    cat("OK 交易数量: 9笔 (100%)\n")
    cat("OK 入场时间: 9/9 (100%)\n")
    cat("OK 入场价格: 9/9 (100%)\n")
    cat("OK 胜率: 100% vs 100%\n")
  } else if (entry_time_matches >= 8 && entry_price_matches >= 8 && nrow(trades_df) == 9) {
    cat("OK 高度对齐！已达到90%+对齐率\n\n")
    cat(sprintf("OK 交易数量: %d笔 (100%%)\n", nrow(trades_df)))
    cat(sprintf("OK 入场时间: %d/9 (%.1f%%)\n", entry_time_matches, entry_time_matches/9*100))
    cat(sprintf("OK 入场价格: %d/9 (%.1f%%)\n", entry_price_matches, entry_price_matches/9*100))
    cat(sprintf("OK 胜率: %.2f%% vs %.2f%%\n", r_winrate, tv_winrate))
    cat("\n仍有%d笔交易需要进一步分析\n", 9 - min(entry_time_matches, entry_price_matches))
  } else {
    cat("WARN 部分对齐，需要进一步调查\n\n")
    cat(sprintf("交易数量: %d笔 (预期9笔)\n", nrow(trades_df)))
    cat(sprintf("入场时间: %d/9 (%.1f%%)\n", entry_time_matches, entry_time_matches/9*100))
    cat(sprintf("入场价格: %d/9 (%.1f%%)\n", entry_price_matches, entry_price_matches/9*100))
  }

} else {
  cat("FAIL 没有交易记录\n")
}

cat("\n完成！\n\n")
