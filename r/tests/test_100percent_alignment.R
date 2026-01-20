# 测试100%对齐：使用下一根K线收盘价入场 + 同一K线限制
# 验证是否达到9笔交易，与TradingView完全一致
# 2025-10-27

cat("\n================================================================================\n")
cat("测试100%对齐：信号延迟入场 + 同一K线限制\n")
cat("================================================================================\n\n")

library(xts)
library(data.table)
library(RcppRoll)

# 加载数据
load("data/liaochu.RData")

# 加载修复后的回测函数
source("backtest_tradingview_aligned.R")

# 获取PEPEUSDT 15分钟数据
data <- cryptodata[["PEPEUSDT_15m"]]

cat("数据行数:", nrow(data), "\n")
cat("数据范围:", as.character(index(data)[1]), "至", as.character(index(data)[nrow(data)]), "\n\n")

# 运行回测
cat("运行回测中...\n\n")

result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = TRUE,
  logIgnoredSignals = TRUE
)

# 提取交易数据
if (length(result$Trades) > 0) {
  trades_list <- result$Trades

  trades_df <- data.frame(
    TradeId = sapply(trades_list, function(x) x$TradeId),
    EntryTime = sapply(trades_list, function(x) x$EntryTime),
    EntryPrice = sapply(trades_list, function(x) x$EntryPrice),
    ExitTime = sapply(trades_list, function(x) x$ExitTime),
    ExitPrice = sapply(trades_list, function(x) x$ExitPrice),
    ExitReason = sapply(trades_list, function(x) x$ExitReason),
    PnLPercent = sapply(trades_list, function(x) x$PnLPercent),
    HoldingBars = sapply(trades_list, function(x) x$HoldingBars),
    stringsAsFactors = FALSE
  )

  # 保存结果
  write.csv(trades_df, "outputs/r_backtest_trades_100percent.csv", row.names = FALSE)

  cat("\n交易详情:\n")
  cat(rep("=", 100), "\n\n", sep="")

  for (i in 1:nrow(trades_df)) {
    cat(sprintf("交易 #%d:\n", trades_df$TradeId[i]))
    cat(sprintf("  入场: %s @ %.8f\n", trades_df$EntryTime[i], trades_df$EntryPrice[i]))
    cat(sprintf("  出场: %s @ %.8f\n", trades_df$ExitTime[i], trades_df$ExitPrice[i]))
    cat(sprintf("  原因: %s\n", trades_df$ExitReason[i]))
    cat(sprintf("  盈亏: %.2f%%\n", trades_df$PnLPercent[i]))
    cat(sprintf("  持仓: %d根K线\n", trades_df$HoldingBars[i]))
    cat("\n")
  }

  cat(rep("=", 100), "\n", sep="")
  cat("汇总统计\n")
  cat(rep("=", 100), "\n\n", sep="")

  cat(sprintf("交易总数: %d\n", nrow(trades_df)))
  cat(sprintf("信号总数: %d\n", result$SignalCount))
  cat(sprintf("被忽略信号: %d\n", result$IgnoredSignalCount))
  cat(sprintf("胜率: %.2f%% (%d胜/%d负)\n",
              sum(trades_df$PnLPercent > 0) / nrow(trades_df) * 100,
              sum(trades_df$PnLPercent > 0),
              sum(trades_df$PnLPercent <= 0)))
  cat(sprintf("平均盈亏: %.2f%%\n", mean(trades_df$PnLPercent)))
  cat(sprintf("总收益率: %.2f%%\n", result$ReturnPercent))

  # 关键验证
  cat("\n")
  cat(rep("=", 100), "\n", sep="")
  cat("关键验证\n")
  cat(rep("=", 100), "\n\n", sep="")

  if (nrow(trades_df) == 9) {
    cat("OK 交易数量: 9笔（与TradingView一致）\n")
  } else {
    cat(sprintf("FAIL 交易数量: %d笔（预期9笔）\n", nrow(trades_df)))
  }

  if (result$IgnoredSignalCount == 2) {
    cat("OK 被忽略信号: 2个（同一K线限制生效）\n")
  } else {
    cat(sprintf("WARN 被忽略信号: %d个（预期2个）\n", result$IgnoredSignalCount))
  }

  if (sum(trades_df$PnLPercent > 0) == nrow(trades_df)) {
    cat("OK 胜率: 100%（与TradingView一致）\n")
  } else {
    cat(sprintf("FAIL 胜率: %.2f%%（预期100%%）\n",
                sum(trades_df$PnLPercent > 0) / nrow(trades_df) * 100))
  }

  cat("\nOK 结果已保存: r_backtest_trades_100percent.csv\n\n")

  # 显示被忽略的信号
  if (result$IgnoredSignalCount > 0) {
    cat(rep("=", 100), "\n", sep="")
    cat("被忽略的信号（同一K线限制）\n")
    cat(rep("=", 100), "\n\n", sep="")

    ignored_list <- result$IgnoredSignals
    for (i in 1:min(10, length(ignored_list))) {
      sig <- ignored_list[[i]]
      cat(sprintf("#%d: Bar=%d, 时间=%s\n", i, sig$Bar, sig$Timestamp))
      cat(sprintf("    原因: %s\n\n", sig$Reason))
    }
  }

} else {
  cat("FAIL 没有交易记录\n")
}

cat("完成!\n\n")
