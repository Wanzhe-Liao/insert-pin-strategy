# 深度分析交易#8和#9的价格差异
# 找出为什么R和Excel选择了不同的入场点

library(xts)
library(RcppRoll)

cat("\n================================================================================\n")
cat("交易#8和#9深度分析 - 价格差异根源\n")
cat("================================================================================\n\n")

# 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

tv_excel <- read.csv("outputs/tv_trades_latest_b2b3d.csv", stringsAsFactors = FALSE)
r_backtest <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)

# 提取关键时间点
cat("Excel数据:\n")
cat(sprintf("  交易#8: 入场 %s @ $%.8f\n", tv_excel$EntryTime[8], tv_excel$EntryPrice[8]))
cat(sprintf("  交易#8: 出场 %s @ $%.8f\n", tv_excel$ExitTime[8], tv_excel$ExitPrice[8]))
cat(sprintf("  交易#9: 入场 %s @ $%.8f\n", tv_excel$EntryTime[9], tv_excel$EntryPrice[9]))
cat(sprintf("  交易#9: 出场 %s @ $%.8f\n\n", tv_excel$ExitTime[9], tv_excel$ExitPrice[9]))

cat("R回测数据:\n")
cat(sprintf("  交易#8: 入场 %s @ $%.8f\n", r_backtest$EntryTime[8], r_backtest$EntryPrice[8]))
cat(sprintf("  交易#8: 出场 %s @ $%.8f\n", r_backtest$ExitTime[8], r_backtest$ExitPrice[8]))
cat(sprintf("  交易#9: 入场 %s @ $%.8f\n", r_backtest$EntryTime[9], r_backtest$EntryPrice[9]))
cat(sprintf("  交易#9: 出场 %s @ $%.8f\n\n", r_backtest$ExitTime[9], r_backtest$ExitPrice[9]))

# 计算信号
high_vec <- as.numeric(data[, "High"])
low_vec <- as.numeric(data[, "Low"])
close_vec <- as.numeric(data[, "Close"])

lookbackBars <- 3
window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)
drop_percent <- (window_high - low_vec) / window_high * 100
signals <- !is.na(drop_percent) & (drop_percent >= 20)

# 分析2025-10-11当天的所有K线和信号
target_date <- as.Date("2025-10-11")
day_indices <- which(as.Date(index(data)) == target_date)

cat(rep("=", 120), "\n", sep="")
cat("2025-10-11当天的所有K线数据和信号\n")
cat(rep("=", 120), "\n\n")

cat(sprintf("%-25s %12s %12s %12s %12s %10s %10s\n",
            "时间", "Open", "High", "Low", "Close", "跌幅%", "信号"))
cat(rep("-", 120), "\n", sep="")

for (idx in day_indices) {
  time_str <- as.character(index(data)[idx])
  open_val <- as.numeric(data$Open[idx])
  high_val <- as.numeric(data$High[idx])
  low_val <- as.numeric(data$Low[idx])
  close_val <- as.numeric(data$Close[idx])
  drop_val <- drop_percent[idx]
  signal_val <- signals[idx]

  signal_str <- if (signal_val) "OK 信号" else ""

  cat(sprintf("%-25s %12.8f %12.8f %12.8f %12.8f %10.2f %10s\n",
              time_str, open_val, high_val, low_val, close_val, drop_val, signal_str))
}

cat("\n")

# 找出当天的所有信号
signal_times <- index(data)[day_indices[signals[day_indices]]]
signal_prices <- close_vec[day_indices[signals[day_indices]]]
signal_drops <- drop_percent[day_indices[signals[day_indices]]]

cat(rep("=", 120), "\n", sep="")
cat(sprintf("当天信号汇总（共%d个）\n", length(signal_times)))
cat(rep("=", 120), "\n\n")

for (i in seq_along(signal_times)) {
  cat(sprintf("信号#%d: %s, 收盘价=$%.8f, 跌幅=%.2f%%\n",
              i, as.character(signal_times[i]), signal_prices[i], signal_drops[i]))
}

cat("\n")

# 检查交易#8的出场时间和交易#9的入场时间的关系
r_trade8_exit_time <- as.POSIXct(r_backtest$ExitTime[8], format="%Y-%m-%d %H:%M:%S", tz="UTC")
r_trade9_entry_time <- as.POSIXct(r_backtest$EntryTime[9], format="%Y-%m-%d %H:%M:%S", tz="UTC")

excel_trade8_exit_time <- as.POSIXct(tv_excel$ExitTime[8], format="%Y-%m-%d %H:%M:%S", tz="UTC")
excel_trade9_entry_time <- as.POSIXct(tv_excel$EntryTime[9], format="%Y-%m-%d %H:%M:%S", tz="UTC")

cat(rep("=", 120), "\n", sep="")
cat("交易#8出场 vs 交易#9入场的时间关系\n")
cat(rep("=", 120), "\n\n")

cat("R回测:\n")
cat(sprintf("  交易#8出场: %s\n", r_backtest$ExitTime[8]))
cat(sprintf("  交易#9入场: %s\n", r_backtest$EntryTime[9]))
if (r_trade9_entry_time == r_trade8_exit_time) {
  cat("  WARN 同一根K线出场和入场！\n")
} else {
  time_gap <- as.numeric(difftime(r_trade9_entry_time, r_trade8_exit_time, units="mins"))
  cat(sprintf("  时间间隔: %.0f分钟\n", time_gap))
}

cat("\nExcel:\n")
cat(sprintf("  交易#8出场: %s\n", tv_excel$ExitTime[8]))
cat(sprintf("  交易#9入场: %s\n", tv_excel$EntryTime[9]))
time_gap_excel <- as.numeric(difftime(excel_trade9_entry_time, excel_trade8_exit_time, units="mins"))
cat(sprintf("  时间间隔: %.0f分钟\n\n", time_gap_excel))

# 检查R的交易#8和#9是否对应Excel的交易#8和#9
cat(rep("=", 120), "\n", sep="")
cat("价格匹配分析\n")
cat(rep("=", 120), "\n\n")

cat("交易#8:\n")
cat(sprintf("  Excel入场价: $%.8f\n", tv_excel$EntryPrice[8]))
cat(sprintf("  R回测入场价: $%.8f\n", r_backtest$EntryPrice[8]))
cat(sprintf("  差异: %.4f%%\n\n", abs(tv_excel$EntryPrice[8] - r_backtest$EntryPrice[8])/tv_excel$EntryPrice[8]*100))

cat("交易#9:\n")
cat(sprintf("  Excel入场价: $%.8f\n", tv_excel$EntryPrice[9]))
cat(sprintf("  R回测入场价: $%.8f\n", r_backtest$EntryPrice[9]))
cat(sprintf("  差异: %.4f%%\n\n", abs(tv_excel$EntryPrice[9] - r_backtest$EntryPrice[9])/tv_excel$EntryPrice[9]*100))

# 检查Excel的价格对应哪个信号
cat(rep("=", 120), "\n", sep="")
cat("Excel价格与实际信号的匹配\n")
cat(rep("=", 120), "\n\n")

cat("Excel交易#9入场价 $%.8f 最接近哪个信号？\n", tv_excel$EntryPrice[9])
for (i in seq_along(signal_times)) {
  price_diff_pct <- abs(signal_prices[i] - tv_excel$EntryPrice[9])/tv_excel$EntryPrice[9]*100
  cat(sprintf("  信号#%d ($%.8f): 差异 %.2f%%\n", i, signal_prices[i], price_diff_pct))
}

cat("\n")

# 分析可能的原因
cat(rep("=", 120), "\n", sep="")
cat("问题诊断\n")
cat(rep("=", 120), "\n\n")

cat("可能的原因：\n\n")

cat("1. 信号选择逻辑不同\n")
cat("   - R选择了05:29的第一个信号（67.67%跌幅）\n")
cat("   - Excel可能选择了05:44的第二个信号（40.95%跌幅）\n")
cat("   - 或者Excel选择了06:14的第三个信号（23.51%跌幅）\n\n")

cat("2. 持仓管理逻辑不同\n")
cat("   - 检查R的交易#8是否在05:29之前就已经出场\n")
cat("   - 如果R在05:15入场，05:29还持仓中，则应该忽略05:29的信号\n\n")

cat("3. 同一K线出场再入场的处理\n")
cat("   - R的代码中有 i != lastExitBar 的限制\n")
cat("   - 这防止在同一根K线先出场再入场\n")
cat("   - 需要检查这个逻辑是否导致信号被错误忽略\n\n")

cat("完成！\n\n")
