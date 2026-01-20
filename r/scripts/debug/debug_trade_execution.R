# 调试交易执行：为什么2023-05-06的信号没有产生交易？

library(xts)

# 加载数据和回测引擎
load('data/liaochu.RData')
source('backtest_tradingview_aligned.R')

data <- cryptodata[["PEPEUSDT_15m"]]

cat("========================================\n")
cat("调试交易执行逻辑\n")
cat("========================================\n\n")

# 运行回测
cat("运行回测...\n")
result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 50,
  stopLossPercent = 50
)

cat("\n========================================\n")
cat("回测结果摘要\n")
cat("========================================\n")
print_performance_summary(result)

cat("\n========================================\n")
cat("前5笔交易详情\n")
cat("========================================\n")
if (!is.null(result$trades) && nrow(result$trades) > 0) {
  trades_df <- format_trades_df(result$trades)
  print(head(trades_df, 5))

  cat("\n第一笔交易:\n")
  first_trade <- trades_df[1,]
  print(first_trade)

  cat("\n第一笔交易详细信息:\n")
  cat("入场时间:", as.character(first_trade$EntryTime), "\n")
  cat("入场日期:", format(first_trade$EntryTime, "%Y-%m-%d"), "\n")
  cat("入场价格:", first_trade$EntryPrice, "\n")
}

cat("\n========================================\n")
cat("被忽略的信号（前10个）\n")
cat("========================================\n")
if (!is.null(result$ignored_signals) && length(result$ignored_signals) > 0) {
  ignored_df <- format_ignored_signals_df(result$ignored_signals)
  print(head(ignored_df, 10))

  # 检查2023-05-06的被忽略信号
  cat("\n2023-05-06的被忽略信号:\n")
  may6_ignored <- ignored_df[format(ignored_df$Time, "%Y-%m-%d") == "2023-05-06",]
  if (nrow(may6_ignored) > 0) {
    print(may6_ignored)
  } else {
    cat("无被忽略信号\n")
  }
}

cat("\n========================================\n")
cat("关键问题分析\n")
cat("========================================\n\n")

# 生成信号
signals <- generate_drop_signals(data, lookbackDays=3, minDropPercent=20)

# 2023-05-06的信号
may6_indices <- which(format(index(data), "%Y-%m-%d") == "2023-05-06")
may6_signals <- signals[may6_indices]

cat("2023-05-06 信号统计:\n")
cat("- K线数:", length(may6_indices), "\n")
cat("- 信号数:", sum(may6_signals), "\n")

if (sum(may6_signals) > 0) {
  signal_idx <- may6_indices[which(may6_signals)[1]]
  cat("- 第一个信号索引:", signal_idx, "\n")
  cat("- 第一个信号时间:", as.character(index(data)[signal_idx]), "\n")

  # 检查这个信号是否在交易列表中
  if (!is.null(result$trades) && nrow(result$trades) > 0) {
    trades_df <- format_trades_df(result$trades)
    matching_trade <- trades_df[format(trades_df$EntryTime, "%Y-%m-%d %H:%M:%S") ==
                                  format(index(data)[signal_idx], "%Y-%m-%d %H:%M:%S"),]

    if (nrow(matching_trade) > 0) {
      cat("\n找到匹配的交易!\n")
      print(matching_trade)
    } else {
      cat("\n未找到匹配的交易（信号被忽略或跳过）\n")

      # 检查ignored_signals
      if (!is.null(result$ignored_signals) && length(result$ignored_signals) > 0) {
        ignored_df <- format_ignored_signals_df(result$ignored_signals)
        matching_ignored <- ignored_df[format(ignored_df$Time, "%Y-%m-%d %H:%M:%S") ==
                                         format(index(data)[signal_idx], "%Y-%m-%d %H:%M:%S"),]

        if (nrow(matching_ignored) > 0) {
          cat("\n信号被忽略，原因:\n")
          print(matching_ignored)
        }
      }
    }
  }
}

# 检查索引4的详细信息
cat("\n\n========================================\n")
cat("索引4（第一个信号）详细分析\n")
cat("========================================\n")

idx <- 4
cat("时间:", as.character(index(data)[idx]), "\n")
cat("Open:", data[idx, "Open"], "\n")
cat("High:", data[idx, "High"], "\n")
cat("Low:", data[idx, "Low"], "\n")
cat("Close:", data[idx, "Close"], "\n")

# 计算信号
window_high <- max(data[1:3, "High"])
current_low <- as.numeric(data[idx, "Low"])
drop_pct <- (window_high - current_low) / window_high * 100

cat("\n信号计算:\n")
cat("窗口[1,3]最高价:", window_high, "\n")
cat("当前最低价:", current_low, "\n")
cat("跌幅:", sprintf("%.2f%%", drop_pct), "\n")
cat("信号:", drop_pct >= 20, "\n")

# 如果这个信号应该入场，计算止盈止损
if (drop_pct >= 20) {
  entry_price <- as.numeric(data[idx, "Close"])
  tp_price <- entry_price * (1 + 50/100)
  sl_price <- entry_price * (1 - 50/100)

  cat("\n假设入场:\n")
  cat("入场价格(Close):", entry_price, "\n")
  cat("止盈价格(+50%):", tp_price, "\n")
  cat("止损价格(-50%):", sl_price, "\n")

  # 检查下一根K线是否触发止盈/止损
  if (idx < nrow(data)) {
    next_high <- as.numeric(data[idx+1, "High"])
    next_low <- as.numeric(data[idx+1, "Low"])

    cat("\n下一根K线(索引", idx+1, "):\n")
    cat("时间:", as.character(index(data)[idx+1]), "\n")
    cat("High:", next_high, "\n")
cat("Low:", next_low, "\n")

    tp_hit <- next_high >= tp_price
    sl_hit <- next_low <= sl_price

    cat("止盈触发:", tp_hit, "\n")
    cat("止损触发:", sl_hit, "\n")

    if (tp_hit && sl_hit) {
      cat("同时触发止盈止损！需要检查优先级\n")
    }
  }
}

cat("\n\n调试完成\n")
