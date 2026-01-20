# 运行回测并导出交易详情以便比对
# 2025-10-27

cat("\n================================================================================\n")
cat("运行回测并导出交易详情\n")
cat("================================================================================\n\n")

# 加载库和函数
suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
})

source("backtest_tradingview_aligned.R")
load("data/liaochu.RData")

# 运行回测
data <- cryptodata[["PEPEUSDT_15m"]]

result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 100,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,
  logIgnoredSignals = FALSE
)

# 提取交易详情
trades <- result$Trades

# 转换为data.frame
if (length(trades) > 0) {
  trades_df <- do.call(rbind, lapply(trades, function(t) {
    data.frame(
      TradeId = t$TradeId,
      EntryTime = t$EntryTime,
      EntryPrice = t$EntryPrice,
      ExitTime = t$ExitTime,
      ExitPrice = t$ExitPrice,
      ExitReason = t$ExitReason,
      PnLPercent = t$PnLPercent,
      HoldingBars = t$HoldingBars,
      stringsAsFactors = FALSE
    )
  }))

  # 保存
  write.csv(trades_df, "r_backtest_trades_latest.csv", row.names = FALSE)

  cat(sprintf("OK 交易数: %d\n", nrow(trades_df)))
  cat(sprintf("OK 胜率: %.2f%%\n", result$WinRate))
  cat(sprintf("OK 止盈: %d, 止损: %d\n", result$TPCount, result$SLCount))
  cat("\n前9笔交易:\n")
  print(head(trades_df, 9))

  cat("\n文件已保存: r_backtest_trades_latest.csv\n")
} else {
  cat("FAIL 无交易数据\n")
}
