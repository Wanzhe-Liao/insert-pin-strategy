# 检查回测结果结构

library(xts)

load('data/liaochu.RData')
source('backtest_tradingview_aligned.R')

data <- cryptodata[["PEPEUSDT_15m"]]

# 运行回测
result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 50,
  stopLossPercent = 50
)

cat("========================================\n")
cat("结果结构检查\n")
cat("========================================\n\n")

cat("result的类型:", class(result), "\n")
cat("result的长度:", length(result), "\n")
cat("result的元素名称:\n")
print(names(result))

cat("\n========================================\n")
cat("trades检查\n")
cat("========================================\n")
cat("trades是否为NULL:", is.null(result$trades), "\n")
if (!is.null(result$trades)) {
  cat("trades类型:", class(result$trades), "\n")
  cat("trades长度:", length(result$trades), "\n")
  if (length(result$trades) > 0) {
    cat("第一笔交易:\n")
    print(result$trades[[1]])
  }
}

cat("\n========================================\n")
cat("ignored_signals检查\n")
cat("========================================\n")
cat("ignored_signals是否为NULL:", is.null(result$ignored_signals), "\n")
if (!is.null(result$ignored_signals)) {
  cat("ignored_signals类型:", class(result$ignored_signals), "\n")
  cat("ignored_signals长度:", length(result$ignored_signals), "\n")
  if (length(result$ignored_signals) > 0) {
    cat("第一个被忽略信号:\n")
    print(result$ignored_signals[[1]])
  }
}

cat("\n========================================\n")
cat("提取交易时间\n")
cat("========================================\n")

if (!is.null(result$trades) && length(result$trades) > 0) {
  cat("总交易数:", length(result$trades), "\n\n")

  for (i in 1:min(7, length(result$trades))) {
    trade <- result$trades[[i]]
    cat(sprintf("交易 #%d:\n", i))
    cat("  入场时间:", as.character(trade$entry_time), "\n")
    cat("  入场价格:", trade$entry_price, "\n")
    cat("  出场时间:", as.character(trade$exit_time), "\n")
    cat("  出场价格:", trade$exit_price, "\n")
    cat("  收益率:", sprintf("%.2f%%", trade$pnl_pct), "\n")
    cat("  出场原因:", trade$exit_type, "\n\n")
  }

  # 检查第一笔交易的时间
  first_trade <- result$trades[[1]]
  cat("第一笔交易详情:\n")
  cat("入场日期:", format(first_trade$entry_time, "%Y-%m-%d"), "\n")
  cat("入场完整时间:", as.character(first_trade$entry_time), "\n")
}

cat("\n========================================\n")
cat("提取被忽略信号时间\n")
cat("========================================\n")

if (!is.null(result$ignored_signals) && length(result$ignored_signals) > 0) {
  cat("总被忽略信号数:", length(result$ignored_signals), "\n\n")

  for (i in 1:min(10, length(result$ignored_signals))) {
    sig <- result$ignored_signals[[i]]
    cat(sprintf("被忽略信号 #%d:\n", i))
    cat("  时间:", as.character(sig$time), "\n")
    cat("  原因:", sig$reason, "\n\n")
  }

  # 检查是否有2023-05-06的被忽略信号
  may6_ignored <- sapply(result$ignored_signals, function(sig) {
    format(sig$time, "%Y-%m-%d") == "2023-05-06"
  })

  if (any(may6_ignored)) {
    cat("2023-05-06的被忽略信号:\n")
    may6_sigs <- result$ignored_signals[may6_ignored]
    for (sig in may6_sigs) {
      cat("  时间:", as.character(sig$time), "\n")
      cat("  原因:", sig$reason, "\n")
    }
  } else {
    cat("2023-05-06没有被忽略的信号\n")
  }
}

cat("\n调试完成\n")
