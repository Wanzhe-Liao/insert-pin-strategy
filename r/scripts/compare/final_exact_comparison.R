# 最终精确比对：9笔 vs 9笔
# 使用data-analyst代理已转换的TV数据 + 最新R数据

cat("\n================================================================================\n")
cat("最终精确比对：TradingView vs R（9笔 vs 9笔）\n")
cat("================================================================================\n\n")

# 读取已转换的TV数据
tv <- read.csv("outputs/tv_trades_detailed.csv", stringsAsFactors = FALSE)
cat("TradingView交易数:", nrow(tv), "\n")

# 读取最新R数据
r <- read.csv("outputs/r_backtest_trades_latest.csv", stringsAsFactors = FALSE)
cat("R回测交易数:", nrow(r), "\n\n")

# 格式化时间（去掉秒）
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
cat("逐笔时间比对（精确到分钟）\n")
cat(rep("=", 100), "\n\n", sep="")

for (i in 1:nrow(comparison)) {
  cat(sprintf("交易 #%d:\n", i))
  cat(sprintf("  入场: TV=%s | R=%s | %s\n",
              comparison$TV_Entry[i],
              comparison$R_Entry[i],
              ifelse(comparison$Entry_Match[i], "OK", "FAIL")))
  cat(sprintf("  出场: TV=%s | R=%s | %s\n",
              comparison$TV_Exit[i],
              comparison$R_Exit[i],
              ifelse(comparison$Exit_Match[i], "OK", "FAIL")))
  cat(sprintf("  盈亏: TV=%.2f%% | R=%.2f%% (%s) | %s\n",
              comparison$TV_PnL[i],
              comparison$R_PnL[i],
              comparison$R_ExitReason[i],
              ifelse(abs(comparison$TV_PnL[i] - comparison$R_PnL[i]) < 1, "OK", "FAIL")))
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

# TV胜率
tv_winrate <- sum(tv$PnL > 0) / nrow(tv) * 100
r_winrate <- sum(r$PnLPercent > 0) / nrow(r) * 100

cat(sprintf("\nTradingView胜率: %.2f%% (%d胜/%d负)\n",
            tv_winrate, sum(tv$PnL > 0), sum(tv$PnL <= 0)))
cat(sprintf("R回测胜率: %.2f%% (%d胜/%d负)\n",
            r_winrate, sum(r$PnLPercent > 0), sum(r$PnLPercent <= 0)))
cat(sprintf("胜率差异: %.2f%%\n", tv_winrate - r_winrate))

# 保存
write.csv(comparison, "final_exact_comparison.csv", row.names = FALSE)
cat("\nOK 比对结果已保存: final_exact_comparison.csv\n\n")

# 最终判断
cat(rep("=", 100), "\n", sep="")
cat("最终判断\n")
cat(rep("=", 100), "\n\n", sep="")

if (entry_match_count == 9 && exit_match_count == 9 && pnl_match_count == 9) {
  cat("OK 完全对齐！\n")
  cat("   所有交易的时间和盈亏完全一致\n\n")
} else {
  cat("FAIL 未完全对齐\n\n")

  if (entry_match_count < 9) {
    cat(sprintf("   入场时间差异: %d笔不匹配\n", 9 - entry_match_count))
  }
  if (exit_match_count < 9) {
    cat(sprintf("   出场时间差异: %d笔不匹配\n", 9 - exit_match_count))
  }
  if (pnl_match_count < 9) {
    cat(sprintf("   盈亏差异: %d笔不匹配\n", 9 - pnl_match_count))
  }
  if (tv_winrate != r_winrate) {
    cat(sprintf("   胜率差异: %.2f%%\n", abs(tv_winrate - r_winrate)))
  }

  cat("\n需要修复的问题:\n")
  mismatches <- which(!comparison$Entry_Match | !comparison$Exit_Match |
                      abs(comparison$TV_PnL - comparison$R_PnL) >= 1)

  for (idx in mismatches) {
    cat(sprintf("   - 交易#%d\n", idx))
  }
}

cat("\n")
