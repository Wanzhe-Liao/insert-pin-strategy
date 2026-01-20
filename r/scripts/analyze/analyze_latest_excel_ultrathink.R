# 使用最新Excel文件进行100%对齐深度分析
# 目标：入场时间和入场价格都必须100%对齐
# 2025-10-27

library(readxl)

cat("\n================================================================================\n")
cat("100%对齐深度分析 - 使用最新Excel数据\n")
cat("================================================================================\n\n")

# 读取最新Excel文件
excel_path <- "c:/Users/ROG/Downloads/三日暴跌接针策略_BINANCE_PEPEUSDT_2025-10-27_b2b3d.xlsx"

cat("读取最新Excel文件...\n")
trades_raw <- read_excel(excel_path, sheet = "交易清单")

cat(sprintf("原始数据行数: %d\n", nrow(trades_raw)))
cat(sprintf("列数: %d\n\n", ncol(trades_raw)))

# 提取入场和出场
entries <- trades_raw[trades_raw$信号 == "做多", ]
exits <- trades_raw[trades_raw$信号 == "止盈/止损", ]

cat(sprintf("入场交易: %d笔\n", nrow(entries)))
cat(sprintf("出场交易: %d笔\n\n", nrow(exits)))

# 转换Excel日期为可读格式
convert_excel_date <- function(excel_serial) {
  # Excel日期起点是1899-12-30
  base_date <- as.POSIXct("1899-12-30", tz = "UTC")
  result_date <- base_date + excel_serial * 86400
  return(result_date)
}

# 创建TradingView交易汇总
tv_trades <- data.frame()

trade_ids <- unique(trades_raw$`交易 #`)

for (id in trade_ids) {
  trade_data <- trades_raw[trades_raw$`交易 #` == id, ]
  entry_row <- trade_data[trade_data$信号 == "做多", ]
  exit_row <- trade_data[trade_data$信号 == "止盈/止损", ]

  if (nrow(entry_row) > 0 && nrow(exit_row) > 0) {
    entry_date <- convert_excel_date(entry_row$`日期/时间`[1])
    exit_date <- convert_excel_date(exit_row$`日期/时间`[1])

    tv_trades <- rbind(tv_trades, data.frame(
      TradeId = id,
      EntryTime = format(entry_date, "%Y-%m-%d %H:%M:%S"),
      EntryPrice = entry_row$`价格 USDT`[1],
      ExitTime = format(exit_date, "%Y-%m-%d %H:%M:%S"),
      ExitPrice = exit_row$`价格 USDT`[1],
      PnL = exit_row$`净损益 %`[1],
      stringsAsFactors = FALSE
    ))
  }
}

# 保存TradingView数据
write.csv(tv_trades, "outputs/tv_trades_latest_b2b3d.csv", row.names = FALSE)
cat("OK 最新TradingView交易数据已保存: tv_trades_latest_b2b3d.csv\n\n")

# 读取R回测结果
r_trades <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)

cat(rep("=", 120), "\n", sep="")
cat("逐笔精确对比 (TV最新Excel vs R回测)\n")
cat(rep("=", 120), "\n\n", sep="")

misaligned_entries <- c()

for (i in 1:9) {
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
  cat(sprintf("交易 #%d\n", i))
  cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))

  # 提取时间（精确到分钟）
  tv_entry <- substr(tv_trades$EntryTime[i], 1, 16)
  r_entry <- substr(r_trades$EntryTime[i], 1, 16)

  tv_entry_full <- tv_trades$EntryTime[i]
  r_entry_full <- r_trades$EntryTime[i]

  cat("入场时间:\n")
  cat(sprintf("  TV:  %s\n", tv_entry))
  cat(sprintf("  R:   %s\n", r_entry))

  entry_time_match <- (tv_entry == r_entry)

  if (entry_time_match) {
    cat("  OK 完全一致\n\n")
  } else {
    cat("  FAIL 不一致\n")

    # 计算时间差
    tv_time <- as.POSIXct(tv_entry_full, format="%Y-%m-%d %H:%M:%S", tz="UTC")
    r_time <- as.POSIXct(r_entry_full, format="%Y-%m-%d %H:%M:%S", tz="UTC")
    time_diff_mins <- as.numeric(difftime(r_time, tv_time, units="mins"))

    cat(sprintf("  时间差: R比TV晚 %+.0f分钟\n\n", time_diff_mins))

    misaligned_entries <- c(misaligned_entries, i)
  }

  cat("入场价格:\n")
  cat(sprintf("  TV:  $%.8f\n", tv_trades$EntryPrice[i]))
  cat(sprintf("  R:   $%.8f\n", r_trades$EntryPrice[i]))

  price_diff_pct <- abs(tv_trades$EntryPrice[i] - r_trades$EntryPrice[i]) / tv_trades$EntryPrice[i] * 100
  price_match <- price_diff_pct < 0.01

  if (price_match) {
    cat(sprintf("  差异: %.4f%% OK 基本一致\n\n", price_diff_pct))
  } else {
    cat(sprintf("  差异: %.4f%% FAIL 需要修正\n\n", price_diff_pct))
  }

  cat("盈亏:\n")
  cat(sprintf("  TV:  %.2f%%\n", tv_trades$PnL[i]))
  cat(sprintf("  R:   %.2f%%\n\n", r_trades$PnLPercent[i]))
}

# 统计对齐率
entry_time_matches <- sum(substr(tv_trades$EntryTime, 1, 16) == substr(r_trades$EntryTime, 1, 16))
entry_price_matches <- sum(abs(tv_trades$EntryPrice - r_trades$EntryPrice) / tv_trades$EntryPrice * 100 < 0.01)

cat(rep("=", 120), "\n", sep="")
cat("对齐率统计\n")
cat(rep("=", 120), "\n\n", sep="")

cat(sprintf("入场时间完全一致: %d/9 (%.1f%%)\n", entry_time_matches, entry_time_matches/9*100))
cat(sprintf("入场价格基本一致(<0.01%%): %d/9 (%.1f%%)\n\n", entry_price_matches, entry_price_matches/9*100))

if (entry_time_matches == 9 && entry_price_matches == 9) {
  cat("🎉🎉🎉 完美！达到100%完全对齐！🎉🎉🎉\n\n")
} else {
  cat(sprintf("WARN 尚未达到100%%对齐\n\n"))

  cat("需要修正的交易:\n")
  for (trade_id in misaligned_entries) {
    cat(sprintf("  - 交易#%d: ", trade_id))

    tv_time <- as.POSIXct(tv_trades$EntryTime[trade_id], format="%Y-%m-%d %H:%M:%S", tz="UTC")
    r_time <- as.POSIXct(r_trades$EntryTime[trade_id], format="%Y-%m-%d %H:%M:%S", tz="UTC")
    time_diff_mins <- as.numeric(difftime(r_time, tv_time, units="mins"))

    cat(sprintf("TV %s vs R %s (差%+.0f分钟)\n",
                substr(tv_trades$EntryTime[trade_id], 1, 16),
                substr(r_trades$EntryTime[trade_id], 1, 16),
                time_diff_mins))
  }
  cat("\n")
}

# 分析不对齐的模式
if (length(misaligned_entries) > 0) {
  cat(rep("=", 120), "\n", sep="")
  cat("不对齐模式分析\n")
  cat(rep("=", 120), "\n\n", sep="")

  time_diffs <- numeric()

  for (trade_id in misaligned_entries) {
    tv_time <- as.POSIXct(tv_trades$EntryTime[trade_id], format="%Y-%m-%d %H:%M:%S", tz="UTC")
    r_time <- as.POSIXct(r_trades$EntryTime[trade_id], format="%Y-%m-%d %H:%M:%S", tz="UTC")
    time_diff_mins <- as.numeric(difftime(r_time, tv_time, units="mins"))

    time_diffs <- c(time_diffs, time_diff_mins)
  }

  cat(sprintf("时间差异: %s\n", paste(sprintf("%+.0f分钟", time_diffs), collapse=", ")))

  if (all(time_diffs == time_diffs[1])) {
    cat(sprintf("\nOK 模式: 所有不对齐交易都偏移相同时间(%+.0f分钟)\n", time_diffs[1]))
    cat("   可能原因: 信号检测或入场执行的系统性延迟\n")
  } else if (all(time_diffs %% 15 == 0)) {
    cat("\nOK 模式: 所有偏移都是15分钟的倍数\n")
    cat("   可能原因: K线边界条件或窗口计算差异\n")
  } else {
    cat("\nWARN 模式: 时间偏移不规律\n")
    cat("   需要逐笔分析K线数据\n")
  }
}

cat("\n完成！\n\n")
