# 最终精确比对:使用修复后的TV时间戳
# TV 9笔 vs R 9笔
# 2025-10-27

cat("\n================================================================================\n")
cat("最终精确比对:使用修复后的TV时间戳 (9笔 vs 9笔)\n")
cat("================================================================================\n\n")

# 读取修复后的TV数据
tv <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)
cat("TradingView交易数:", nrow(tv), "\n")

# 读取R数据
r <- read.csv("outputs/r_backtest_trades_no_lag.csv", stringsAsFactors = FALSE)
cat("R回测交易数:", nrow(r), "\n\n")

# 格式化时间(去掉秒)
tv$Entry_Time_Min <- substr(tv$EntryTime, 1, 16)
tv$Exit_Time_Min <- substr(tv$ExitTime, 1, 16)

r$Entry_Time_Min <- substr(r$EntryTime, 1, 16)
r$Exit_Time_Min <- substr(r$ExitTime, 1, 16)

# 创建比对表
comparison <- data.frame(
  TradeId = 1:9,
  TV_Entry = tv$Entry_Time_Min,
  R_Entry = r$Entry_Time_Min,
  Entry_Match = (tv$Entry_Time_Min == r$Entry_Time_Min),
  TV_Exit = tv$Exit_Time_Min,
  R_Exit = r$Exit_Time_Min,
  Exit_Match = (tv$Exit_Time_Min == r$Exit_Time_Min),
  TV_PnL = tv$PnL,
  R_PnL = r$PnLPercent,
  R_ExitReason = r$ExitReason,
  stringsAsFactors = FALSE
)

# 逐笔显示
cat(rep("=", 100), "\n", sep="")
cat("逐笔时间比对(精确到分钟)\n")
cat(rep("=", 100), "\n\n", sep="")

for (i in 1:nrow(comparison)) {
  entry_icon <- ifelse(comparison$Entry_Match[i], "OK", "FAIL")
  exit_icon <- ifelse(comparison$Exit_Match[i], "OK", "FAIL")
  pnl_match <- abs(comparison$TV_PnL[i] - comparison$R_PnL[i]) < 1
  pnl_icon <- ifelse(pnl_match, "OK", "FAIL")

  cat(sprintf("交易 #%d:\n", i))
  cat(sprintf("  入场: TV=%s | R=%s | %s\n",
              comparison$TV_Entry[i],
              comparison$R_Entry[i],
              entry_icon))
  cat(sprintf("  出场: TV=%s | R=%s | %s\n",
              comparison$TV_Exit[i],
              comparison$R_Exit[i],
              exit_icon))
  cat(sprintf("  盈亏: TV=%.2f%% | R=%.2f%% (%s) | %s\n",
              comparison$TV_PnL[i],
              comparison$R_PnL[i],
              comparison$R_ExitReason[i],
              pnl_icon))
  cat("\n")
}

# 汇总
cat(rep("=", 100), "\n", sep="")
cat("汇总统计\n")
cat(rep("=", 100), "\n\n", sep="")

entry_match_count <- sum(comparison$Entry_Match)
exit_match_count <- sum(comparison$Exit_Match)
pnl_match_count <- sum(abs(comparison$TV_PnL - comparison$R_PnL) < 1)

cat(sprintf("入场时间完全一致: %d/9 (%.1f%%)\n", entry_match_count, entry_match_count/9*100))
cat(sprintf("出场时间完全一致: %d/9 (%.1f%%)\n", exit_match_count, exit_match_count/9*100))
cat(sprintf("盈亏完全一致: %d/9 (%.1f%%)\n", pnl_match_count, pnl_match_count/9*100))

# 胜率
tv_winrate <- sum(tv$PnL > 0) / nrow(tv) * 100
r_winrate <- sum(r$PnLPercent > 0) / nrow(r) * 100

cat(sprintf("\nTradingView胜率: %.2f%% (%d胜/%d负)\n",
            tv_winrate, sum(tv$PnL > 0), sum(tv$PnL <= 0)))
cat(sprintf("R回测胜率: %.2f%% (%d胜/%d负)\n",
            r_winrate, sum(r$PnLPercent > 0), sum(r$PnLPercent <= 0)))
cat(sprintf("胜率差异: %.2f%%\n", tv_winrate - r_winrate))

# 保存
write.csv(comparison, "final_comparison_after_fix.csv", row.names = FALSE)
cat("\nOK 比对结果已保存: final_comparison_after_fix.csv\n\n")

# 最终判断
cat(rep("=", 100), "\n", sep="")
cat("最终判断\n")
cat(rep("=", 100), "\n\n", sep="")

if (entry_match_count == 9 && exit_match_count == 9 && pnl_match_count == 9) {
  cat("🎉 完全对齐！\n")
  cat("   所有交易的入场时间、出场时间和盈亏完全一致\n")
  cat("   OK 入场时间: 100%一致\n")
  cat("   OK 出场时间: 100%一致\n")
  cat("   OK 盈亏: 100%一致\n")
  cat("   OK 胜率: 100%一致\n\n")
} else {
  if (entry_match_count == 9) {
    cat("OK 入场时间100%对齐 (%d/9)\n", entry_match_count)
  } else {
    cat(sprintf("WARN 入场时间: %d/9对齐 (%.1f%%)\n", entry_match_count, entry_match_count/9*100))
  }

  if (exit_match_count == 9) {
    cat("OK 出场时间100%对齐 (%d/9)\n", exit_match_count)
  } else {
    cat(sprintf("FAIL 出场时间: %d/9对齐 (%.1f%%) - 需要修复\n", exit_match_count, exit_match_count/9*100))
  }

  if (pnl_match_count == 9) {
    cat("OK 盈亏100%对齐 (%d/9)\n", pnl_match_count)
  } else {
    cat(sprintf("WARN 盈亏: %d/9对齐 (%.1f%%)\n", pnl_match_count, pnl_match_count/9*100))
  }

  if (tv_winrate == r_winrate) {
    cat("OK 胜率完全一致\n")
  } else {
    cat(sprintf("WARN 胜率差异: %.2f%%\n", abs(tv_winrate - r_winrate)))
  }

  cat("\n需要修复的问题:\n")
  mismatches <- which(!comparison$Entry_Match | !comparison$Exit_Match |
                      abs(comparison$TV_PnL - comparison$R_PnL) >= 1)

  if (length(mismatches) > 0) {
    for (idx in mismatches) {
      issues <- c()
      if (!comparison$Entry_Match[idx]) issues <- c(issues, "入场时间")
      if (!comparison$Exit_Match[idx]) issues <- c(issues, "出场时间")
      if (abs(comparison$TV_PnL[idx] - comparison$R_PnL[idx]) >= 1) issues <- c(issues, "盈亏")

      cat(sprintf("   - 交易#%d: %s\n", idx, paste(issues, collapse=", ")))
    }
  }
}

cat("\n")
