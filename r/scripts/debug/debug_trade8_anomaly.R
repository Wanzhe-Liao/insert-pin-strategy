# 调试交易#8的盈亏异常
# 时间完全一致,但盈亏差异巨大: TV=28.09% vs R=10%
# 2025-10-27

cat("\n================================================================================\n")
cat("调试交易#8盈亏异常\n")
cat("================================================================================\n\n")

library(xts)

# 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

# 读取交易数据
tv <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)
r <- read.csv("outputs/r_backtest_trades_no_lag.csv", stringsAsFactors = FALSE)

cat("交易#8详细信息:\n")
cat(rep("=", 100), "\n\n", sep="")

cat("TradingView:\n")
cat(sprintf("  入场: %s @ $%.8f\n", tv$EntryTime[8], tv$EntryPrice[8]))
cat(sprintf("  出场: %s @ $%.8f\n", tv$ExitTime[8], tv$ExitPrice[8]))
cat(sprintf("  盈亏: %.2f%%\n\n", tv$PnL[8]))

cat("R回测:\n")
cat(sprintf("  入场: %s @ $%.8f\n", r$EntryTime[8], r$EntryPrice[8]))
cat(sprintf("  出场: %s @ $%.8f\n", r$ExitTime[8], r$ExitPrice[8]))
cat(sprintf("  盈亏: %.2f%% (%s)\n\n", r$PnLPercent[8], r$ExitReason[8]))

# 计算理论盈亏
tv_entry_price <- tv$EntryPrice[8]
tv_exit_price <- tv$ExitPrice[8]
tv_calculated_pnl <- (tv_exit_price - tv_entry_price) / tv_entry_price * 100

r_entry_price <- r$EntryPrice[8]
r_exit_price <- r$ExitPrice[8]
r_calculated_pnl <- (r_exit_price - r_entry_price) / r_entry_price * 100

cat("计算验证:\n")
cat(rep("=", 100), "\n\n", sep="")

cat(sprintf("TV计算盈亏: (%.8f - %.8f) / %.8f * 100 = %.2f%%\n",
            tv_exit_price, tv_entry_price, tv_entry_price, tv_calculated_pnl))
cat(sprintf("TV报告盈亏: %.2f%%\n", tv$PnL[8]))
cat(sprintf("差异: %.2f%%\n\n", abs(tv_calculated_pnl - tv$PnL[8])))

cat(sprintf("R计算盈亏: (%.8f - %.8f) / %.8f * 100 = %.2f%%\n",
            r_exit_price, r_entry_price, r_entry_price, r_calculated_pnl))
cat(sprintf("R报告盈亏: %.2f%%\n", r$PnLPercent[8]))
cat(sprintf("差异: %.2f%%\n\n", abs(r_calculated_pnl - r$PnLPercent[8])))

# 检查这段时间��K线数据
entry_time <- as.POSIXct("2025-10-11 05:29:59.999", tz="UTC")
exit_time <- as.POSIXct("2025-10-11 05:44:59.999", tz="UTC")

cat("这段时间的K线数据:\n")
cat(rep("=", 100), "\n\n", sep="")

window_start <- entry_time - 1800  # 前30分钟
window_end <- exit_time + 1800     # 后30分钟

nearby_data <- data[paste(window_start, window_end, sep="/")]

df <- as.data.frame(nearby_data)
df$Time <- index(nearby_data)

for (i in 1:min(10, nrow(df))) {
  marker <- ""
  if (df$Time[i] == entry_time) marker <- " <- 入场"
  if (df$Time[i] == exit_time) marker <- " <- 出场"

  cat(sprintf("%d. %s | O:%.8f H:%.8f L:%.8f C:%.8f%s\n",
              i,
              as.character(df$Time[i]),
              df$Open[i],
              df$High[i],
              df$Low[i],
              df$Close[i],
              marker))
}

# 检查止盈价格
tp_price_from_r <- r_entry_price * 1.10
sl_price_from_r <- r_entry_price * 0.90

cat("\n止盈止损价格:\n")
cat(rep("=", 100), "\n\n", sep="")

cat(sprintf("R入场价: $%.8f\n", r_entry_price))
cat(sprintf("止盈价(+10%%): $%.8f\n", tp_price_from_r))
cat(sprintf("止损价(-10%%): $%.8f\n", sl_price_from_r))
cat(sprintf("R出场价: $%.8f\n", r_exit_price))
cat(sprintf("\n是否触发止盈: %s (%.8f >= %.8f)\n",
            r_exit_price >= tp_price_from_r,
            r_exit_price,
            tp_price_from_r))

cat("\n")

# 结论
cat(rep("=", 100), "\n", sep="")
cat("结论\n")
cat(rep("=", 100), "\n\n", sep="")

if (abs(tv$PnL[8] - 28.09) < 0.1) {
  cat("TV的盈亏28.09%可能��:\n")
  cat("1. TradingView没有设置止盈,直接持有到出场时间\n")
  cat("2. TradingView使用了不同的出场价格\n")
  cat("3. TradingView在这笔交易没有触发止盈/止损\n\n")

  cat(sprintf("如果TV真的在05:44出场,出场价应该是$%.8f,盈亏应该是%.2f%%\n",
              tv_exit_price, tv_calculated_pnl))
}

if (abs(r$PnLPercent[8] - 10) < 0.1) {
  cat("R的盈亏10%是因为:\n")
  cat("1. R严格执行了止盈=10%的设置\n")
  cat("2. R在止盈价触发时立即平仓\n\n")
}

cat("可能的解释:\n")
cat("- TradingView这笔交易可能手动平仓,或者有特殊的出场逻辑\n")
cat("- 需要检查TradingView的Pine Script代码,看是否有特殊处理\n\n")
