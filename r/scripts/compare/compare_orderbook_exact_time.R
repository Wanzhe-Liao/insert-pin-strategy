# 精确比对R和TradingView订单簿
# 目标：逐笔比对时间（精确到分钟）和出场原因
# 2025-10-27

cat("\n================================================================================\n")
cat("R vs TradingView 订单簿精确比对\n")
cat("================================================================================\n\n")

# Excel时间转换函数
excel_to_datetime <- function(excel_serial) {
  # Excel日期基准: 1899-12-30 (考虑1900年闰年bug)
  origin <- as.POSIXct("1899-12-30 00:00:00", tz="UTC")
  datetime <- origin + (excel_serial * 86400)  # 86400秒/天
  return(datetime)
}

# 读取TradingView数据
tv_raw <- read.csv("data/tradingview_trades.csv",
                    stringsAsFactors = FALSE)

# 查看数据结构
cat("TradingView原始数据行数:", nrow(tv_raw), "\n")
cat("类型列唯一值:", unique(tv_raw$类型), "\n\n")

# 提取入场和出场行（每笔交易2行）
# 注意：出场在前，入场在后（从CSV看到的顺序）
tv_exits <- tv_raw[seq(1, nrow(tv_raw), by=2), ]   # 奇数行是出场
tv_entries <- tv_raw[seq(2, nrow(tv_raw), by=2), ]  # 偶数行是入场

# 转换时间
tv_entries$DateTime <- excel_to_datetime(tv_entries$日期.时间)
tv_exits$DateTime <- excel_to_datetime(tv_exits$日期.时间)

# 创建TradingView交易表
tv_trades <- data.frame(
  TV_TradeId = tv_entries$交易...,
  TV_EntryTime = format(tv_entries$DateTime, "%Y-%m-%d %H:%M"),
  TV_EntryPrice = tv_entries$价格.USDT,
  TV_ExitTime = format(tv_exits$DateTime, "%Y-%m-%d %H:%M"),
  TV_ExitPrice = tv_exits$价格.USDT,
  TV_PnL = tv_exits$净损益...,
  stringsAsFactors = FALSE
)

# 读取R回测结果
r_trades <- read.csv("outputs/r_backtest_trades_latest.csv",
                      stringsAsFactors = FALSE)

# 格式化R时间（去掉秒）
r_trades$R_EntryTime <- format(as.POSIXct(r_trades$EntryTime), "%Y-%m-%d %H:%M")
r_trades$R_ExitTime <- format(as.POSIXct(r_trades$ExitTime), "%Y-%m-%d %H:%M")

# 创建对比表
comparison <- data.frame(
  TradeId = 1:9,
  TV_Entry = tv_trades$TV_EntryTime,
  R_Entry = r_trades$R_EntryTime,
  EntryMatch = tv_trades$TV_EntryTime == r_trades$R_EntryTime,
  TV_Exit = tv_trades$TV_ExitTime,
  R_Exit = r_trades$R_ExitTime,
  ExitMatch = tv_trades$TV_ExitTime == r_trades$R_ExitTime,
  TV_PnL = tv_trades$TV_PnL,
  R_PnL = r_trades$PnLPercent,
  R_ExitReason = r_trades$ExitReason,
  stringsAsFactors = FALSE
)

# 输出对比结果
cat("\n逐笔时间对比（精确到分钟）:\n")
cat(rep("=", 80), "\n\n", sep="")

for (i in 1:nrow(comparison)) {
  cat(sprintf("交易 #%d:\n", i))
  cat(sprintf("  入场时间:\n"))
  cat(sprintf("    TV: %s\n", comparison$TV_Entry[i]))
  cat(sprintf("    R:  %s\n", comparison$R_Entry[i]))
  cat(sprintf("    匹配: %s\n", ifelse(comparison$EntryMatch[i], "OK", "FAIL")))

  cat(sprintf("  出场时间:\n"))
  cat(sprintf("    TV: %s\n", comparison$TV_Exit[i]))
  cat(sprintf("    R:  %s\n", comparison$R_Exit[i]))
  cat(sprintf("    匹配: %s\n", ifelse(comparison$ExitMatch[i], "OK", "FAIL")))

  cat(sprintf("  盈亏:\n"))
  cat(sprintf("    TV: %.2f%%\n", comparison$TV_PnL[i]))
  cat(sprintf("    R:  %.2f%% (%s)\n", comparison$R_PnL[i], comparison$R_ExitReason[i]))
  cat(sprintf("    匹配: %s\n", ifelse(abs(comparison$TV_PnL[i] - comparison$R_PnL[i]) < 0.5, "OK", "FAIL")))
  cat("\n")
}

# 汇总统计
cat(rep("=", 80), "\n", sep="")
cat("汇总统计:\n")
cat(rep("=", 80), "\n\n", sep="")

entry_match_rate <- sum(comparison$EntryMatch) / nrow(comparison) * 100
exit_match_rate <- sum(comparison$ExitMatch) / nrow(comparison) * 100
pnl_match <- abs(comparison$TV_PnL - comparison$R_PnL) < 0.5
pnl_match_rate <- sum(pnl_match) / nrow(comparison) * 100

cat(sprintf("入场时间匹配率: %.1f%% (%d/9)\n", entry_match_rate, sum(comparison$EntryMatch)))
cat(sprintf("出场时间匹配率: %.1f%% (%d/9)\n", exit_match_rate, sum(comparison$ExitMatch)))
cat(sprintf("盈亏匹配率: %.1f%% (%d/9)\n", pnl_match_rate, sum(pnl_match)))

# 找出不匹配的交易
cat("\n不匹配的交易:\n")
mismatches <- which(!comparison$EntryMatch | !comparison$ExitMatch | !pnl_match)
if (length(mismatches) > 0) {
  for (i in mismatches) {
    cat(sprintf("\n交易 #%d 不匹配:\n", i))
    if (!comparison$EntryMatch[i]) {
      cat(sprintf("  FAIL 入场时间: TV=%s, R=%s\n",
                  comparison$TV_Entry[i], comparison$R_Entry[i]))
    }
    if (!comparison$ExitMatch[i]) {
      cat(sprintf("  FAIL 出场时间: TV=%s, R=%s\n",
                  comparison$TV_Exit[i], comparison$R_Exit[i]))
    }
    if (!pnl_match[i]) {
      cat(sprintf("  FAIL 盈亏: TV=%.2f%%, R=%.2f%% (%s)\n",
                  comparison$TV_PnL[i], comparison$R_PnL[i], comparison$R_ExitReason[i]))
    }
  }
} else {
  cat("  OK 所有交易完全匹配!\n")
}

# 保存对比结果
write.csv(comparison, "orderbook_exact_comparison.csv", row.names = FALSE)
cat("\nOK 对比结果已保存: orderbook_exact_comparison.csv\n\n")

# 最终判断
cat(rep("=", 80), "\n", sep="")
cat("最终判断:\n")
cat(rep("=", 80), "\n\n", sep="")

if (entry_match_rate == 100 && exit_match_rate == 100 && pnl_match_rate == 100) {
  cat("OK 完全对齐！R回测与TradingView完全一致\n")
  cat("   - 所有入场时间一致\n")
  cat("   - 所有出场时间一致\n")
  cat("   - 所有盈亏一致\n")
} else {
  cat("FAIL 未完全对齐\n")
  cat(sprintf("   - 入场时间匹配率: %.1f%%\n", entry_match_rate))
  cat(sprintf("   - 出场时间匹配率: %.1f%%\n", exit_match_rate))
  cat(sprintf("   - 盈亏匹配率: %.1f%%\n", pnl_match_rate))
  cat("\n需要进一步调查不匹配的原因\n")
}

cat("\n")
