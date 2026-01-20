# 调试第1笔交易的15分钟时间偏移
# 目标：查看2023-05-06 02:44附近的K线数据，找出为什么R在02:59入场而不是02:44
# 2025-10-27

cat("\n================================================================================\n")
cat("调试第1笔交易时间偏移\n")
cat("================================================================================\n\n")

library(xts)
library(data.table)
library(RcppRoll)

# 加载数据和函数
load("data/liaochu.RData")
source("backtest_tradingview_aligned.R")

data <- cryptodata[["PEPEUSDT_15m"]]

# TradingView第1笔交易时间
tv_first_entry <- as.POSIXct("2023-05-06 02:44:59", tz="UTC")

cat("TradingView第1笔入场时间:", as.character(tv_first_entry), "\n\n")

# 查看该时间附近的K线
window_start <- tv_first_entry - 3600  # 前1小时
window_end <- tv_first_entry + 3600    # 后1小时

nearby_data <- data[paste(window_start, window_end, sep="/")]

cat("该时间附近的K线数据:\n")
cat(rep("=", 100), "\n\n", sep="")

# 转换为data.frame以便查看
df <- as.data.frame(nearby_data)
df$Time <- index(nearby_data)

# 只显示时间和OHLC
for (i in 1:min(10, nrow(df))) {
  cat(sprintf("%d. %s | O:%.8f H:%.8f L:%.8f C:%.8f\n",
              i,
              as.character(df$Time[i]),
              df$Open[i],
              df$High[i],
              df$Low[i],
              df$Close[i]))
}

cat("\n")

# 生成信号，查看第1个信号出现的位置
signals <- generate_drop_signals(data, lookbackDays=3, minDropPercent=20)

first_signal_idx <- which(signals)[1]
first_signal_time <- index(data)[first_signal_idx]

cat("R回测第1个信号时间:\n")
cat(rep("=", 100), "\n\n", sep="")
cat(sprintf("索引: %d\n", first_signal_idx))
cat(sprintf("时间: %s\n", as.character(first_signal_time)))
cat(sprintf("与TV差异: %.1f分钟\n",
            as.numeric(difftime(first_signal_time, tv_first_entry, units="mins"))))

# 查看该信号K线的详细信息
signal_kline <- data[first_signal_idx, ]
cat(sprintf("\n信号K线数据:\n"))
cat(sprintf("  时间: %s\n", as.character(index(signal_kline))))
cat(sprintf("  开: %.8f\n", signal_kline$Open))
cat(sprintf("  高: %.8f\n", signal_kline$High))
cat(sprintf("  低: %.8f\n", signal_kline$Low))
cat(sprintf("  收: %.8f\n", signal_kline$Close))

# 检查TV时间对应的K线
tv_kline_idx <- which.min(abs(as.numeric(index(data) - tv_first_entry)))
tv_kline <- data[tv_kline_idx, ]

cat(sprintf("\nTV时间(02:44:59)对应的K线:\n"))
cat(sprintf("  索引: %d\n", tv_kline_idx))
cat(sprintf("  时间: %s\n", as.character(index(tv_kline))))
cat(sprintf("  开: %.8f\n", tv_kline$Open))
cat(sprintf("  高: %.8f\n", tv_kline$High))
cat(sprintf("  低: %.8f\n", tv_kline$Low))
cat(sprintf("  收: %.8f\n", tv_kline$Close))

# 检查该位置是否有信号
tv_has_signal <- signals[tv_kline_idx]
cat(sprintf("\nTV时间位置是否有信号: %s\n", tv_has_signal))

if (!tv_has_signal) {
  cat("\n为什么TV时间位置没有信号？让我们检查信号生成条件：\n")
  cat(rep("=", 100), "\n\n", sep="")

  # 手动计算该位置的跌幅
  if (tv_kline_idx > 3) {
    # 过去3根K线的最高价
    window_high <- max(data[(tv_kline_idx-3):(tv_kline_idx-1), "High"])
    current_low <- tv_kline$Low

    drop_pct <- (window_high - current_low) / window_high * 100

    cat(sprintf("过去3根K线最高价: %.8f\n", window_high))
    cat(sprintf("当前最低价: %.8f\n", current_low))
    cat(sprintf("跌幅: %.2f%%\n", drop_pct))
    cat(sprintf("是否>= 20%%: %s\n", drop_pct >= 20))

    if (drop_pct < 20) {
      cat("\nFAIL 跌幅不足20%，所以该位置没有信号\n")
      cat("   这可能解释了为什么R在后面的K线才入场\n")
    }
  }
}

# 对比R第一个信号位置的跌幅
cat(sprintf("\n\nR第一个信号位置(02:59:59)的跌幅计算:\n"))
cat(rep("=", 100), "\n\n", sep="")

if (first_signal_idx > 3) {
  window_high_r <- max(data[(first_signal_idx-3):(first_signal_idx-1), "High"])
  current_low_r <- signal_kline$Low

  drop_pct_r <- (window_high_r - current_low_r) / window_high_r * 100

  cat(sprintf("过去3根K线最高价: %.8f\n", window_high_r))
  cat(sprintf("当前最低价: %.8f\n", current_low_r))
  cat(sprintf("跌幅: %.2f%%\n", drop_pct_r))
  cat(sprintf("是否>= 20%%: %s\n", drop_pct_r >= 20))
}

cat("\n")
cat(rep("=", 100), "\n", sep="")
cat("结论\n")
cat(rep("=", 100), "\n\n", sep="")

cat("15分钟时间偏移的可能原因：\n")
cat("1. TV在02:44位置就满足了信号条件（需要检查TV的lookback计算）\n")
cat("2. R的信号生成逻辑与TV有细微差异（例如lookback窗口的定义）\n")
cat("3. TV使用不同的价格（如开盘价vs收盘价）来检测信号\n")
cat("4. Pine Script的ta.highest()行为与R的roll_max()不完全一致\n\n")

cat("建议下一步：\n")
cat("1. 检查Pine Script代码中信号生成的确切逻辑\n")
cat("2. 对比TV和R在02:44:59这根K线的历史数据（确认数据一致性）\n")
cat("3. 尝试调整lookback窗口的对齐方式\n\n")
