# 最终精确比对：9笔 vs 9笔
# 验证每笔交易的时间和价格
# 2025-10-27

cat("\n================================================================================\n")
cat("最终精确比对：9笔 vs 9笔\n")
cat("================================================================================\n\n")

# 读取TV数据
tv <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)
cat("TradingView交易数:", nrow(tv), "\n")

# 读取最新R数据
r <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)
cat("R回测交易数:", nrow(r), "\n\n")

# 格式化时间(去掉秒)
tv$Entry_Time_Min <- substr(tv$EntryTime, 1, 16)
tv$Exit_Time_Min <- substr(tv$ExitTime, 1, 16)

r$Entry_Time_Min <- substr(r$EntryTime, 1, 16)
r$Exit_Time_Min <- substr(r$ExitTime, 1, 16)

# 逐笔比对
cat(rep("=", 120), "\n", sep="")
cat("逐笔详细比对\n")
cat(rep("=", 120), "\n\n", sep="")

for (i in 1:9) {
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
  cat(sprintf("交易 #%d\n", i))
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))

  # 入场时间
  entry_match <- (tv$Entry_Time_Min[i] == r$Entry_Time_Min[i])
  cat(sprintf("入场时间:\n"))
  cat(sprintf("  TV: %s\n", tv$Entry_Time_Min[i]))
  cat(sprintf("  R:  %s\n", r$Entry_Time_Min[i]))
  cat(sprintf("  %s\n\n", ifelse(entry_match, "OK 完全一致", "FAIL 不一致")))

  # 入场价格
  price_diff_pct <- abs(tv$EntryPrice[i] - r$EntryPrice[i]) / tv$EntryPrice[i] * 100
  price_match <- price_diff_pct < 0.1
  cat(sprintf("入场价格:\n"))
  cat(sprintf("  TV: $%.8f\n", tv$EntryPrice[i]))
  cat(sprintf("  R:  $%.8f\n", r$EntryPrice[i]))
  cat(sprintf("  差异: %.2f%%\n", price_diff_pct))
  cat(sprintf("  %s\n\n", ifelse(price_match, "OK 基本一致", "FAIL 差异较大")))

  # 出场时间
  exit_match <- (tv$Exit_Time_Min[i] == r$Exit_Time_Min[i])
  cat(sprintf("出场时间:\n"))
  cat(sprintf("  TV: %s\n", tv$Exit_Time_Min[i]))
  cat(sprintf("  R:  %s\n", r$Exit_Time_Min[i]))
  cat(sprintf("  %s\n\n", ifelse(exit_match, "OK 完全一致", "FAIL 不一致")))

  # 出场价格
  exit_price_diff_pct <- abs(tv$ExitPrice[i] - r$ExitPrice[i]) / tv$ExitPrice[i] * 100
  exit_price_match <- exit_price_diff_pct < 0.1
  cat(sprintf("出场价格:\n"))
  cat(sprintf("  TV: $%.8f\n", tv$ExitPrice[i]))
  cat(sprintf("  R:  $%.8f\n", r$ExitPrice[i]))
  cat(sprintf("  差异: %.2f%%\n", exit_price_diff_pct))
  cat(sprintf("  %s\n\n", ifelse(exit_price_match, "OK 基本一致", "FAIL 差异较大")))

  # 盈亏
  pnl_diff <- abs(tv$PnL[i] - r$PnLPercent[i])
  pnl_match <- pnl_diff < 1
  cat(sprintf("盈亏:\n"))
  cat(sprintf("  TV: %.2f%%\n", tv$PnL[i]))
  cat(sprintf("  R:  %.2f%% (%s)\n", r$PnLPercent[i], r$ExitReason[i]))
  cat(sprintf("  差异: %.2f%%\n", pnl_diff))
  cat(sprintf("  %s\n\n", ifelse(pnl_match, "OK 基本一致", "FAIL 差异较大")))

  cat("\n")
}

# 汇总统计
cat(rep("=", 120), "\n", sep="")
cat("汇总统计\n")
cat(rep("=", 120), "\n\n", sep="")

# 计算匹配率
entry_time_matches <- sum(tv$Entry_Time_Min == r$Entry_Time_Min)
exit_time_matches <- sum(tv$Exit_Time_Min == r$Exit_Time_Min)

entry_price_matches <- sum(abs(tv$EntryPrice - r$EntryPrice) / tv$EntryPrice * 100 < 0.1)
exit_price_matches <- sum(abs(tv$ExitPrice - r$ExitPrice) / tv$ExitPrice * 100 < 0.1)

pnl_matches <- sum(abs(tv$PnL - r$PnLPercent) < 1)

cat(sprintf("入场时间完全一致: %d/9 (%.1f%%)\n", entry_time_matches, entry_time_matches/9*100))
cat(sprintf("出场时间完全一致: %d/9 (%.1f%%)\n", exit_time_matches, exit_time_matches/9*100))
cat(sprintf("入场价格基本一致(<0.1%%): %d/9 (%.1f%%)\n", entry_price_matches, entry_price_matches/9*100))
cat(sprintf("出场价格基本一致(<0.1%%): %d/9 (%.1f%%)\n", exit_price_matches, exit_price_matches/9*100))
cat(sprintf("盈亏基本一致(<1%%): %d/9 (%.1f%%)\n", pnl_matches, pnl_matches/9*100))

# 胜率
tv_winrate <- sum(tv$PnL > 0) / nrow(tv) * 100
r_winrate <- sum(r$PnLPercent > 0) / nrow(r) * 100

cat(sprintf("\nTradingView胜率: %.2f%% (%d胜/%d负)\n",
            tv_winrate, sum(tv$PnL > 0), sum(tv$PnL <= 0)))
cat(sprintf("R回测胜率: %.2f%% (%d胜/%d负)\n",
            r_winrate, sum(r$PnLPercent > 0), sum(r$PnLPercent <= 0)))
cat(sprintf("胜率差异: %.2f%%\n", abs(tv_winrate - r_winrate)))

# 最终判断
cat("\n")
cat(rep("=", 120), "\n", sep="")
cat("最终判断\n")
cat(rep("=", 120), "\n\n", sep="")

if (entry_time_matches >= 7 && exit_time_matches >= 7 && pnl_matches >= 7) {
  cat("OK 高度对齐 (>= 77.8%)\n\n")
} else {
  cat("WARN 部分对齐\n\n")
}

if (tv_winrate == r_winrate) {
  cat("OK 胜率完全一致\n")
} else {
  cat(sprintf("FAIL 胜率差异: %.2f%%\n", abs(tv_winrate - r_winrate)))
  cat("\n需要调查的交易:\n")
  for (i in 1:9) {
    if ((tv$PnL[i] > 0) != (r$PnLPercent[i] > 0)) {
      cat(sprintf("  - 交易#%d: TV=%s%.2f%% vs R=%s%.2f%%\n",
                  i,
                  ifelse(tv$PnL[i] > 0, "+", ""),
                  tv$PnL[i],
                  ifelse(r$PnLPercent[i] > 0, "+", ""),
                  r$PnLPercent[i]))
    }
  }
}

# 保存
write.csv(data.frame(
  TradeId = 1:9,
  TV_Entry = tv$Entry_Time_Min,
  R_Entry = r$Entry_Time_Min,
  TV_EntryPrice = tv$EntryPrice,
  R_EntryPrice = r$EntryPrice,
  TV_PnL = tv$PnL,
  R_PnL = r$PnLPercent,
  stringsAsFactors = FALSE
), "final_exact_comparison_100percent.csv", row.names = FALSE)

cat("\nOK 对比结果已保存: final_exact_comparison_100percent.csv\n\n")
