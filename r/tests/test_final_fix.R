# 测试最终修复：收盘价出场 + 移除冷却期
# 验证时间和盈亏是否完全对齐
# 2025-10-27

cat("\n================================================================================\n")
cat("测试最终修复：收盘价出场 + 移除冷却期\n")
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
  logIgnoredSignals = FALSE
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
  write.csv(trades_df, "outputs/r_backtest_trades_final.csv", row.names = FALSE)

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
  cat(sprintf("胜率: %.2f%% (%d胜/%d负)\n",
              sum(trades_df$PnLPercent > 0) / nrow(trades_df) * 100,
              sum(trades_df$PnLPercent > 0),
              sum(trades_df$PnLPercent <= 0)))
  cat(sprintf("平均盈亏: %.2f%%\n", mean(trades_df$PnLPercent)))
  cat(sprintf("总收益率: %.2f%%\n", result$ReturnPercent))

  cat("\nOK 结果已保存: r_backtest_trades_final.csv\n\n")

} else {
  cat("FAIL 没有交易记录\n")
}

cat("完成!\n\n")
