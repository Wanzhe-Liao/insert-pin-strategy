# 三方对比：Excel vs CSV vs R回测
# 找出时间差异的真正原因

cat("\n================================================================================\n")
cat("三方数据源对比分析\n")
cat("================================================================================\n\n")

# 读取三个数据源
tv_csv <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)
tv_excel <- read.csv("outputs/tv_trades_from_excel_detailed.csv", stringsAsFactors = FALSE)
r_backtest <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)

cat("数据源1 - tv_trades_fixed.csv (之前使用的):\n")
cat(sprintf("  交易数: %d\n", nrow(tv_csv)))
cat(sprintf("  列: %s\n\n", paste(names(tv_csv), collapse=", ")))

cat("数据源2 - tv_trades_from_excel_detailed.csv (从Excel提取):\n")
cat(sprintf("  交易数: %d\n", nrow(tv_excel)))
cat(sprintf("  列: %s\n\n", paste(names(tv_excel), collapse=", ")))

cat("数据源3 - r_backtest_trades_100percent.csv (当前R回测):\n")
cat(sprintf("  交易数: %d\n", nrow(r_backtest)))
cat(sprintf("  列: %s\n\n", paste(names(r_backtest), collapse=", ")))

cat(rep("=", 120), "\n", sep="")
cat("逐笔三方对比\n")
cat(rep("=", 120), "\n\n", sep="")

for (i in 1:9) {
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
  cat(sprintf("交易 #%d\n", i))
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))

  # 提取时间（精确到分钟）
  csv_entry <- substr(tv_csv$EntryTime[i], 1, 16)
  excel_entry <- substr(tv_excel$EntryTime[i], 1, 16)
  r_entry <- substr(r_backtest$EntryTime[i], 1, 16)

  csv_exit <- substr(tv_csv$ExitTime[i], 1, 16)
  excel_exit <- substr(tv_excel$ExitTime[i], 1, 16)
  r_exit <- substr(r_backtest$ExitTime[i], 1, 16)

  cat("入场时间:\n")
  cat(sprintf("  CSV:   %s\n", csv_entry))
  cat(sprintf("  Excel: %s\n", excel_entry))
  cat(sprintf("  R回测: %s\n", r_entry))

  # 检查一致性
  if (csv_entry == excel_entry && excel_entry == r_entry) {
    cat("  OK 三方完全一致\n\n")
  } else if (csv_entry == excel_entry) {
    cat("  WARN CSV与Excel一致，R不同\n\n")
  } else if (csv_entry == r_entry) {
    cat("  WARN CSV与R一致，Excel不同\n\n")
  } else if (excel_entry == r_entry) {
    cat("  WARN Excel与R一致，CSV不同\n\n")
  } else {
    cat("  FAIL 三方都不一致\n\n")
  }

  cat("入场价格:\n")
  cat(sprintf("  CSV:   $%.8f\n", tv_csv$EntryPrice[i]))
  cat(sprintf("  Excel: $%.8f\n", tv_excel$EntryPrice[i]))
  cat(sprintf("  R回测: $%.8f\n", r_backtest$EntryPrice[i]))

  csv_price_match <- abs(tv_csv$EntryPrice[i] - tv_excel$EntryPrice[i]) < 0.00000001
  r_price_match <- abs(tv_excel$EntryPrice[i] - r_backtest$EntryPrice[i]) < 0.00000001

  if (csv_price_match && r_price_match) {
    cat("  OK 三方完全一致\n\n")
  } else {
    cat("  FAIL 存在价格差异\n\n")
  }

  cat("出场时间:\n")
  cat(sprintf("  CSV:   %s\n", csv_exit))
  cat(sprintf("  Excel: %s\n", excel_exit))
  cat(sprintf("  R回测: %s\n\n", r_exit))

  cat("盈亏:\n")
  cat(sprintf("  CSV:   %.2f%%\n", tv_csv$PnL[i]))
  cat(sprintf("  Excel: %.2f%%\n", tv_excel$PnL[i]))
  cat(sprintf("  R回测: %.2f%%\n\n", r_backtest$PnLPercent[i]))
}

# 统计分析
cat(rep("=", 120), "\n", sep="")
cat("统计分析\n")
cat(rep("=", 120), "\n\n", sep="")

# 入场时间对齐率
csv_excel_entry_match <- sum(substr(tv_csv$EntryTime, 1, 16) == substr(tv_excel$EntryTime, 1, 16))
excel_r_entry_match <- sum(substr(tv_excel$EntryTime, 1, 16) == substr(r_backtest$EntryTime, 1, 16))
csv_r_entry_match <- sum(substr(tv_csv$EntryTime, 1, 16) == substr(r_backtest$EntryTime, 1, 16))

cat("入场时间对齐率:\n")
cat(sprintf("  CSV vs Excel: %d/9 (%.1f%%)\n", csv_excel_entry_match, csv_excel_entry_match/9*100))
cat(sprintf("  Excel vs R:   %d/9 (%.1f%%)\n", excel_r_entry_match, excel_r_entry_match/9*100))
cat(sprintf("  CSV vs R:     %d/9 (%.1f%%)\n\n", csv_r_entry_match, csv_r_entry_match/9*100))

# 入场价格对齐率
csv_excel_price_match <- sum(abs(tv_csv$EntryPrice - tv_excel$EntryPrice) < 0.00000001)
excel_r_price_match <- sum(abs(tv_excel$EntryPrice - r_backtest$EntryPrice) < 0.00000001)
csv_r_price_match <- sum(abs(tv_csv$EntryPrice - r_backtest$EntryPrice) < 0.00000001)

cat("入场价格对齐率:\n")
cat(sprintf("  CSV vs Excel: %d/9 (%.1f%%)\n", csv_excel_price_match, csv_excel_price_match/9*100))
cat(sprintf("  Excel vs R:   %d/9 (%.1f%%)\n", excel_r_price_match, excel_r_price_match/9*100))
cat(sprintf("  CSV vs R:     %d/9 (%.1f%%)\n\n", csv_r_price_match, csv_r_price_match/9*100))

# 分析时间差异模式
cat(rep("=", 120), "\n", sep="")
cat("时间差异模式分析\n")
cat(rep("=", 120), "\n\n", sep="")

for (i in 1:9) {
  csv_time <- as.POSIXct(tv_csv$EntryTime[i], format="%Y-%m-%d %H:%M:%S", tz="UTC")
  excel_time <- as.POSIXct(tv_excel$EntryTime[i], format="%Y-%m-%d %H:%M:%S", tz="UTC")
  r_time <- as.POSIXct(r_backtest$EntryTime[i], format="%Y-%m-%d %H:%M:%S", tz="UTC")

  csv_excel_diff <- as.numeric(difftime(csv_time, excel_time, units="mins"))
  excel_r_diff <- as.numeric(difftime(r_time, excel_time, units="mins"))

  if (abs(csv_excel_diff) > 0.1 || abs(excel_r_diff) > 0.1) {
    cat(sprintf("交易#%d:\n", i))
    cat(sprintf("  CSV vs Excel: %+.0f分钟\n", csv_excel_diff))
    cat(sprintf("  R vs Excel:   %+.0f分钟\n\n", excel_r_diff))
  }
}

cat("\n结论:\n")
if (csv_excel_entry_match == 9) {
  cat("OK CSV与Excel时间完全一致 - Excel转换正确\n")
} else {
  cat("WARN CSV与Excel时间有差异 - 可能是时区或格式问题\n")
}

if (excel_r_entry_match > csv_r_entry_match) {
  cat("OK R回测更接近Excel数据 - 应以Excel为准\n")
} else {
  cat("WARN R回测更接近CSV数据 - 需要分析Excel数据的准确性\n")
}

cat("\n完成！\n\n")
