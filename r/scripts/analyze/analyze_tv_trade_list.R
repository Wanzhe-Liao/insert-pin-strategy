# 分析TradingView交易清单
# 提取每笔交易的详细时间和价格

library(readxl)

file_path <- "c:/Users/ROG/Downloads/三日暴跌接针策略_BINANCE_PEPEUSDT_2025-10-27_df79a.xlsx"

cat("\n================================================================================\n")
cat("分析TradingView交易清单详情\n")
cat("================================================================================\n\n")

# 读取交易清单
trades <- read_excel(file_path, sheet = "交易清单")

cat(sprintf("总行数: %d\n", nrow(trades)))
cat(sprintf("列数: %d\n\n", ncol(trades)))

# 显示所有数据
cat("完整交易清单:\n")
cat(rep("=", 120), "\n", sep="")
print(trades, n = Inf)
cat("\n")

# 分离入场和出场
entries <- trades[trades$信号 == "做多", ]
exits <- trades[trades$信号 == "止盈/止损", ]

cat(rep("=", 120), "\n", sep="")
cat("入场交易 (共", nrow(entries), "笔)\n")
cat(rep("=", 120), "\n\n", sep="")
print(entries, n = Inf)
cat("\n")

cat(rep("=", 120), "\n", sep="")
cat("出场交易 (共", nrow(exits), "笔)\n")
cat(rep("=", 120), "\n\n", sep="")
print(exits, n = Inf)
cat("\n")

# 整理成易读格式
cat(rep("=", 120), "\n", sep="")
cat("逐笔交易详情\n")
cat(rep("=", 120), "\n\n", sep="")

trade_ids <- unique(trades$`交易 #`)

for (id in trade_ids) {
  trade_data <- trades[trades$`交易 #` == id, ]

  entry_row <- trade_data[trade_data$信号 == "做多", ]
  exit_row <- trade_data[trade_data$信号 == "止盈/止损", ]

  if (nrow(entry_row) > 0 && nrow(exit_row) > 0) {
    cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
    cat(sprintf("交易 #%d\n", id))
    cat(sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))

    # 转换Excel日期为可读格式
    entry_date_serial <- entry_row$`日期/时间`[1]
    exit_date_serial <- exit_row$`日期/时间`[1]

    # Excel日期起点是1899-12-30
    entry_date <- as.POSIXct("1899-12-30", tz = "UTC") + entry_date_serial * 86400
    exit_date <- as.POSIXct("1899-12-30", tz = "UTC") + exit_date_serial * 86400

    entry_time_str <- format(entry_date, "%Y-%m-%d %H:%M")
    exit_time_str <- format(exit_date, "%Y-%m-%d %H:%M")

    cat(sprintf("入场时间: %s\n", entry_time_str))
    cat(sprintf("入场价格: $%.8f\n", entry_row$`价格 USDT`[1]))
    cat(sprintf("出场时间: %s\n", exit_time_str))
    cat(sprintf("出场价格: $%.8f\n", exit_row$`价格 USDT`[1]))
    cat(sprintf("净损益: %.2f%%\n", exit_row$`净损益 %`[1]))
    cat("\n")
  }
}

# 保存为CSV（便于后续分析）
# 添加可读时间列
trades$EntryTime <- NA
trades$ExitTime <- NA

for (i in 1:nrow(trades)) {
  date_serial <- trades$`日期/时间`[i]
  readable_date <- as.POSIXct("1899-12-30", tz = "UTC") + date_serial * 86400
  readable_time_str <- format(readable_date, "%Y-%m-%d %H:%M:%S")

  if (trades$信号[i] == "做多") {
    trades$EntryTime[i] <- readable_time_str
  } else if (trades$信号[i] == "止盈/止损") {
    trades$ExitTime[i] <- readable_time_str
  }
}

# 创建逐笔比对格式
trade_summary <- data.frame()

for (id in trade_ids) {
  trade_data <- trades[trades$`交易 #` == id, ]
  entry_row <- trade_data[trade_data$信号 == "做多", ]
  exit_row <- trade_data[trade_data$信号 == "止盈/止损", ]

  if (nrow(entry_row) > 0 && nrow(exit_row) > 0) {
    entry_date_serial <- entry_row$`日期/时间`[1]
    exit_date_serial <- exit_row$`日期/时间`[1]

    entry_date <- as.POSIXct("1899-12-30", tz = "UTC") + entry_date_serial * 86400
    exit_date <- as.POSIXct("1899-12-30", tz = "UTC") + exit_date_serial * 86400

    trade_summary <- rbind(trade_summary, data.frame(
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

csv_path <- "outputs/tv_trades_from_excel_detailed.csv"
write.csv(trade_summary, csv_path, row.names = FALSE)
cat(sprintf("\nOK 详细交易数据已保存: %s\n\n", csv_path))

cat("完成！\n\n")
