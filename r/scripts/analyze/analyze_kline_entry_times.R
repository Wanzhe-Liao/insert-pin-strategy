# 分析K线数据，验证入场时间
# 重点分析交易#4和#9的不对齐原因

library(xts)

cat("\n================================================================================\n")
cat("K线数据深度分析 - 精确验证入场触发时刻\n")
cat("================================================================================\n\n")

# 加载K线数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

cat(sprintf("PEPEUSDT 15分钟K线数据行数: %d\n", nrow(data)))
cat(sprintf("数据范围: %s 至 %s\n\n",
            as.character(index(data)[1]),
            as.character(index(data)[nrow(data)])))

# 读取Excel提取的交易时间
tv_excel <- read.csv("outputs/tv_trades_latest_b2b3d.csv", stringsAsFactors = FALSE)
r_backtest <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)

cat(rep("=", 120), "\n", sep="")
cat("逐笔K线数据分析\n")
cat(rep("=", 120), "\n\n")

# 分析每笔交易的K线数据
for (trade_id in c(1, 2, 3, 4, 5, 6, 7, 8, 9)) {

  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
  cat(sprintf("交易 #%d\n", trade_id))
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))

  # Excel时间和R时间
  excel_entry_time <- as.POSIXct(tv_excel$EntryTime[trade_id], format="%Y-%m-%d %H:%M:%S", tz="UTC")
  r_entry_time <- as.POSIXct(r_backtest$EntryTime[trade_id], format="%Y-%m-%d %H:%M:%S", tz="UTC")

  cat(sprintf("Excel入场时间: %s\n", tv_excel$EntryTime[trade_id]))
  cat(sprintf("R回测入场时间: %s\n", r_backtest$EntryTime[trade_id]))

  time_diff_mins <- as.numeric(difftime(r_entry_time, excel_entry_time, units="mins"))
  cat(sprintf("时间差: %+.0f分钟\n\n", time_diff_mins))

  # 提取Excel时间附近的K线数据（前后各4根K线，共9根）
  excel_idx <- which(abs(as.numeric(difftime(index(data), excel_entry_time, units="mins"))) < 0.1)

  if (length(excel_idx) > 0) {
    excel_bar <- excel_idx[1]

    # 前后各4根K线
    start_bar <- max(1, excel_bar - 4)
    end_bar <- min(nrow(data), excel_bar + 4)

    nearby_data <- data[start_bar:end_bar, ]

    cat("Excel入场时刻附近的K线数据:\n")
    cat(rep("-", 120), "\n", sep="")
    cat(sprintf("%-20s %12s %12s %12s %12s\n", "时间", "Open", "High", "Low", "Close"))
    cat(rep("-", 120), "\n", sep="")

    for (i in 1:nrow(nearby_data)) {
      row_idx <- start_bar + i - 1
      time_str <- as.character(index(nearby_data)[i])

      marker <- ""
      if (row_idx == excel_bar) {
        marker <- " ← Excel入场"
      }

      # 检查R入场时间
      r_idx <- which(abs(as.numeric(difftime(index(data), r_entry_time, units="mins"))) < 0.1)
      if (length(r_idx) > 0 && row_idx == r_idx[1]) {
        marker <- paste0(marker, " ← R入场")
      }

      cat(sprintf("%-20s %12.8f %12.8f %12.8f %12.8f%s\n",
                  time_str,
                  as.numeric(nearby_data$Open[i]),
                  as.numeric(nearby_data$High[i]),
                  as.numeric(nearby_data$Low[i]),
                  as.numeric(nearby_data$Close[i]),
                  marker))
    }
    cat("\n")

    # 计算信号触发条件
    cat("信号触发条件分析:\n")
    cat(rep("-", 120), "\n", sep="")

    # 在Excel时间点计算
    if (excel_bar >= 4) {
      window_start <- excel_bar - 2
      window_end <- excel_bar

      window_high <- max(as.numeric(data$High[window_start:window_end]))
      excel_bar_low <- as.numeric(data$Low[excel_bar])
      excel_bar_close <- as.numeric(data$Close[excel_bar])

      drop_pct <- (window_high - excel_bar_low) / window_high * 100

      cat(sprintf("Excel时间点 (%s):\n", as.character(index(data)[excel_bar])))
      cat(sprintf("  过去3根K线最高价: $%.8f\n", window_high))
      cat(sprintf("  当前K线最低价: $%.8f\n", excel_bar_low))
      cat(sprintf("  当前K线收盘价: $%.8f\n", excel_bar_close))
      cat(sprintf("  计算跌幅: %.2f%%\n", drop_pct))

      if (drop_pct >= 20) {
        cat(sprintf("  OK 信号触发！(跌幅 >= 20%%)\n"))
      } else {
        cat(sprintf("  FAIL 信号未触发 (跌幅 < 20%%)\n"))
      }
      cat("\n")
    }

    # 在R时间点计算
    r_idx <- which(abs(as.numeric(difftime(index(data), r_entry_time, units="mins"))) < 0.1)
    if (length(r_idx) > 0) {
      r_bar <- r_idx[1]

      if (r_bar >= 4) {
        window_start <- r_bar - 2
        window_end <- r_bar

        window_high <- max(as.numeric(data$High[window_start:window_end]))
        r_bar_low <- as.numeric(data$Low[r_bar])
        r_bar_close <- as.numeric(data$Close[r_bar])

        drop_pct <- (window_high - r_bar_low) / window_high * 100

        cat(sprintf("R时间点 (%s):\n", as.character(index(data)[r_bar])))
        cat(sprintf("  过去3根K线最高价: $%.8f\n", window_high))
        cat(sprintf("  当前K线最低价: $%.8f\n", r_bar_low))
        cat(sprintf("  当前K线收盘价: $%.8f\n", r_bar_close))
        cat(sprintf("  计算跌幅: %.2f%%\n", drop_pct))

        if (drop_pct >= 20) {
          cat(sprintf("  OK 信号触发！(跌幅 >= 20%%)\n"))
        } else {
          cat(sprintf("  FAIL 信号未触发 (跌幅 < 20%%)\n"))
        }
        cat("\n")
      }
    }

  } else {
    cat("WARN 在K线数据中未找到Excel入场时间对应的K线\n\n")
  }

  cat("\n")
}

cat(rep("=", 120), "\n", sep="")
cat("关键发现总结\n")
cat(rep("=", 120), "\n\n")

cat("分析结论:\n")
cat("1. 检查Excel时间是否对应K线开盘时刻还是收盘时刻\n")
cat("2. 验证信号在哪个时刻真正触发（>=20%跌幅）\n")
cat("3. 确认process_orders_on_close=true的实际行为\n")
cat("4. 找出交易#4和#9的特殊之处\n\n")

cat("完成！\n\n")
