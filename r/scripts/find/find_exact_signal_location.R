# 精确定位信号出现的位置
# 直接在K线索引中查找

library(xts)
library(RcppRoll)

cat("\n================================================================================\n")
cat("精确定位>=20%信号的K线位置\n")
cat("================================================================================\n\n")

# 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

# 读取回测结果
r_backtest <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)
tv_excel <- read.csv("outputs/tv_trades_latest_b2b3d.csv", stringsAsFactors = FALSE)

# 计算信号
high_vec <- as.numeric(data[, "High"])
low_vec <- as.numeric(data[, "Low"])
close_vec <- as.numeric(data[, "Close"])

lookbackBars <- 3
window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)
drop_percent <- (window_high - low_vec) / window_high * 100
signals <- !is.na(drop_percent) & (drop_percent >= 20)

# 找到所有信号
signal_indices <- which(signals)

cat(sprintf("总信号数: %d\n\n", length(signal_indices)))

# 显示第8、9、10、11个信号
cat("第8-11个信号的详细信息:\n")
cat(rep("=", 120), "\n", sep="")

for (i in 8:11) {
  if (i <= length(signal_indices)) {
    idx <- signal_indices[i]
    time_str <- as.character(index(data)[idx])
    close_price <- close_vec[idx]
    drop_pct <- drop_percent[idx]
    win_high <- window_high[idx]
    cur_low <- low_vec[idx]

    cat(sprintf("\n信号#%d (K线索引: %d):\n", i, idx))
    cat(sprintf("  时间: %s\n", time_str))
    cat(sprintf("  收盘价: $%.8f\n", close_price))
    cat(sprintf("  窗口最高: $%.8f\n", win_high))
    cat(sprintf("  当前最低: $%.8f\n", cur_low))
    cat(sprintf("  跌幅: %.2f%%\n", drop_pct))

    # 显示前后各2根K线
    cat("\n  前后K线context:\n")
    for (j in (idx-2):(idx+2)) {
      if (j > 0 && j <= nrow(data)) {
        marker <- if (j == idx) " ← 信号K线" else ""
        cat(sprintf("    %s: Close=$%.8f%s\n",
                    as.character(index(data)[j]),
                    close_vec[j],
                    marker))
      }
    }
  }
}

cat("\n")
cat(rep("=", 120), "\n", sep="")
cat("R回测交易#8和#9的入场信息\n")
cat(rep("=", 120), "\n\n")

# 找到R回测交易#8和#9对应的K线索引
for (trade_id in 8:9) {
  r_time <- as.POSIXct(r_backtest$EntryTime[trade_id], format="%Y-%m-%d %H:%M:%S", tz="UTC")
  r_price <- r_backtest$EntryPrice[trade_id]

  # 找到最接近的K线
  time_diffs <- abs(as.numeric(difftime(index(data), r_time, units="secs")))
  closest_idx <- which.min(time_diffs)

  cat(sprintf("R回测交易#%d:\n", trade_id))
  cat(sprintf("  记录时间: %s\n", r_backtest$EntryTime[trade_id]))
  cat(sprintf("  记录价格: $%.8f\n", r_price))
  cat(sprintf("  最接近K线索引: %d\n", closest_idx))
  cat(sprintf("  最接近K线时间: %s\n", as.character(index(data)[closest_idx])))
  cat(sprintf("  最接近K线收盘价: $%.8f\n", close_vec[closest_idx]))
  cat(sprintf("  该K线是否有信号: %s\n", if (signals[closest_idx]) "OK 是" else "FAIL 否"))

  # 检查这是第几个信号
  if (signals[closest_idx]) {
    signal_num <- which(signal_indices == closest_idx)
    cat(sprintf("  这是第 %d 个信号\n", signal_num))
  }

  cat("\n")
}

cat(rep("=", 120), "\n", sep="")
cat("Excel交易#8和#9的入场信息\n")
cat(rep("=", 120), "\n\n")

for (trade_id in 8:9) {
  excel_price <- tv_excel$EntryPrice[trade_id]

  cat(sprintf("Excel交易#%d:\n", trade_id))
  cat(sprintf("  记录时间: %s\n", tv_excel$EntryTime[trade_id]))
  cat(sprintf("  记录价格: $%.8f\n", excel_price))

  # 在所有信号中查找最接近的价格
  min_price_diff <- Inf
  best_signal_idx <- NA
  best_signal_num <- NA

  for (i in seq_along(signal_indices)) {
    sig_idx <- signal_indices[i]
    sig_price <- close_vec[sig_idx]
    price_diff <- abs(sig_price - excel_price) / excel_price * 100

    if (price_diff < min_price_diff) {
      min_price_diff <- price_diff
      best_signal_idx <- sig_idx
      best_signal_num <- i
    }
  }

  if (!is.na(best_signal_idx)) {
    cat(sprintf("  最接近的信号: 第%d个\n", best_signal_num))
    cat(sprintf("  信号K线索引: %d\n", best_signal_idx))
    cat(sprintf("  信号时间: %s\n", as.character(index(data)[best_signal_idx])))
    cat(sprintf("  信号价格: $%.8f\n", close_vec[best_signal_idx]))
    cat(sprintf("  价格差异: %.4f%%\n", min_price_diff))
  }

  cat("\n")
}

cat(rep("=", 120), "\n", sep="")
cat("关键结论\n")
cat(rep("=", 120), "\n\n")

cat("1. R回测交易#8对应哪个信号？\n")
cat("2. R回测交易#9对应哪个信号？\n")
cat("3. Excel交易#8对应哪个信号？\n")
cat("4. Excel交易#9对应哪个信号？\n")
cat("5. 为什么R和Excel选择了不同的信号？\n\n")

cat("完成！\n\n")
