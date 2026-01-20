# 找出真正的信号触发时刻
# 扩大搜索范围，找出实际的>=20%跌幅信号

library(xts)
library(RcppRoll)

cat("\n================================================================================\n")
cat("寻找真正的信号触发时刻（扩大搜索范围）\n")
cat("================================================================================\n\n")

# 加载K线数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

# 读取Excel和R数据
tv_excel <- read.csv("outputs/tv_trades_latest_b2b3d.csv", stringsAsFactors = FALSE)
r_backtest <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)

# 计算所有K线的信号
high_vec <- as.numeric(data[, "High"])
low_vec <- as.numeric(data[, "Low"])
close_vec <- as.numeric(data[, "Close"])

# 使用3根K线回看窗口
lookbackBars <- 3
window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)
drop_percent <- (window_high - low_vec) / window_high * 100

# 找出所有>=20%跌幅的信号
signal_bars <- which(!is.na(drop_percent) & drop_percent >= 20)

cat(sprintf("总K线数: %d\n", nrow(data)))
cat(sprintf(">=20%%跌幅的K线数: %d\n\n", length(signal_bars)))

if (length(signal_bars) > 0) {
  cat("前20个信号触发时刻:\n")
  cat(rep("-", 120), "\n", sep="")
  cat(sprintf("%-5s %-25s %-15s %-15s %-15s %-10s\n",
              "序号", "时间", "窗口最高价", "当前��低价", "当前收盘价", "跌幅%"))
  cat(rep("-", 120), "\n", sep="")

  for (i in 1:min(20, length(signal_bars))) {
    bar <- signal_bars[i]
    time_str <- as.character(index(data)[bar])
    win_high <- window_high[bar]
    cur_low <- low_vec[bar]
    cur_close <- close_vec[bar]
    drop_pct <- drop_percent[bar]

    cat(sprintf("%-5d %-25s $%.8f      $%.8f      $%.8f      %.2f%%\n",
                i, time_str, win_high, cur_low, cur_close, drop_pct))
  }
  cat("\n")
}

cat(rep("=", 120), "\n", sep="")
cat("逐笔交易的信号搜索\n")
cat(rep("=", 120), "\n\n")

# 对每笔交易，在其附近搜索实际的信号触发时刻
for (trade_id in 1:9) {
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
  cat(sprintf("交易 #%d\n", trade_id))
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))

  # Excel和R的时间（可能有时区问题）
  excel_time_str <- tv_excel$EntryTime[trade_id]
  r_time_str <- r_backtest$EntryTime[trade_id]

  cat(sprintf("Excel入场时间: %s\n", excel_time_str))
  cat(sprintf("R回测入场时间: %s\n", r_time_str))
  cat(sprintf("Excel入场价格: $%.8f\n", tv_excel$EntryPrice[trade_id]))
  cat(sprintf("R回测入场价格: $%.8f\n\n", r_backtest$EntryPrice[trade_id]))

  # 尝试多种时区解析Excel时间
  excel_time <- tryCatch({
    as.POSIXct(excel_time_str, format="%Y-%m-%d %H:%M:%S", tz="UTC")
  }, error = function(e) NA)

  r_time <- as.POSIXct(r_time_str, format="%Y-%m-%d %H:%M:%S", tz="UTC")

  # 搜索范围：Excel时间前后24小时（96根15分钟K线）
  if (!is.na(excel_time)) {
    # 找到最接近Excel时间的K线
    time_diffs <- abs(as.numeric(difftime(index(data), excel_time, units="mins")))
    closest_bar <- which.min(time_diffs)

    search_start <- max(1, closest_bar - 96)
    search_end <- min(nrow(data), closest_bar + 96)

    # 在搜索范围内找>=20%信号
    nearby_signals <- intersect(signal_bars, search_start:search_end)

    if (length(nearby_signals) > 0) {
      cat(sprintf("在Excel时间前后24小时找到 %d 个>=20%%信号:\n", length(nearby_signals)))
      cat(rep("-", 120), "\n", sep="")

      for (sig_bar in nearby_signals) {
        sig_time <- index(data)[sig_bar]
        time_diff_hours <- as.numeric(difftime(sig_time, excel_time, units="hours"))

        cat(sprintf("  时间: %s (Excel时间%+.1f小时)\n", as.character(sig_time), time_diff_hours))
        cat(sprintf("    窗口最高: $%.8f, 当前最低: $%.8f, 当前收盘: $%.8f\n",
                    window_high[sig_bar], low_vec[sig_bar], close_vec[sig_bar]))
        cat(sprintf("    跌幅: %.2f%%, 收盘价与Excel入场价差异: %.4f%%\n",
                    drop_percent[sig_bar],
                    abs(close_vec[sig_bar] - tv_excel$EntryPrice[trade_id]) / tv_excel$EntryPrice[trade_id] * 100))
        cat("\n")
      }
    } else {
      cat("WARN 在Excel时间前后24小时未找到任何>=20%信号\n\n")
    }
  }

  # 同���搜索R时间附近
  time_diffs_r <- abs(as.numeric(difftime(index(data), r_time, units="mins")))
  closest_bar_r <- which.min(time_diffs_r)

  search_start_r <- max(1, closest_bar_r - 96)
  search_end_r <- min(nrow(data), closest_bar_r + 96)

  nearby_signals_r <- intersect(signal_bars, search_start_r:search_end_r)

  if (length(nearby_signals_r) > 0) {
    cat(sprintf("在R时间前后24小时找到 %d 个>=20%%信号:\n", length(nearby_signals_r)))
    cat(rep("-", 120), "\n", sep="")

    for (sig_bar in nearby_signals_r) {
      sig_time <- index(data)[sig_bar]
      time_diff_hours <- as.numeric(difftime(sig_time, r_time, units="hours"))

      cat(sprintf("  时间: %s (R时间%+.1f小时)\n", as.character(sig_time), time_diff_hours))
      cat(sprintf("    窗口最高: $%.8f, 当前最低: $%.8f, 当前收盘: $%.8f\n",
                  window_high[sig_bar], low_vec[sig_bar], close_vec[sig_bar]))
      cat(sprintf("    跌幅: %.2f%%, 收盘价与R入场价差异: %.4f%%\n",
                  drop_percent[sig_bar],
                  abs(close_vec[sig_bar] - r_backtest$EntryPrice[trade_id]) / r_backtest$EntryPrice[trade_id] * 100))
      cat("\n")
    }
  } else {
    cat("WARN 在R时间前后24小时未找到任何>=20%信号\n\n")
  }

  cat("\n")
}

cat(rep("=", 120), "\n", sep="")
cat("关键发现\n")
cat(rep("=", 120), "\n\n")

cat("问题诊断:\n")
cat("1. K线时间戳与Excel时间存在8小时时区差异\n")
cat("2. 在Excel/R标记的入场时刻，计算出的跌幅都<20%\n")
cat("3. 需要在更大范围内搜索真正的>=20%信号触发时刻\n")
cat("4. 可能的原因：\n")
cat("   - 时区转换问题\n")
cat("   - TradingView使用不同的时间基准\n")
cat("   - lookbackDays参数的实际含义不是3根K线\n\n")

cat("完成！\n\n")
