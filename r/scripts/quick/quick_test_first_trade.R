# 快速测试：验证第一笔交易是否与TradingView一致
#
# TradingView参考值：
# - 第一笔入场：2024-05-13 07:15:00
# - 入场价格：0.00000612
# - 出场时间：2024-05-14 10:15:00
# - 出场价格：0.00000735
# - 盈亏：+20.10%

library(xts)

cat("\n=======================================================\n")
cat("  快速测试：第一笔交易验证\n")
cat("=======================================================\n\n")

# 加载修复版本
source("backtest_final_fixed_v2.R")

# 读取数据
data_file <- "PEPEUSDT_15m.csv"
if (!file.exists(data_file)) {
  cat("错误：未找到数据文件\n")
  cat("请确保以下文件存在：", data_file, "\n")
  quit()
}

pepe_data <- read.csv(data_file, stringsAsFactors = FALSE)
pepe_data$timestamp <- as.POSIXct(pepe_data$timestamp, tz = "UTC")
pepe_xts <- xts(pepe_data[, c("Open", "High", "Low", "Close", "Volume")],
                order.by = pepe_data$timestamp)

cat(sprintf("数据范围：%s 至 %s\n", min(index(pepe_xts)), max(index(pepe_xts))))
cat(sprintf("数据量：%d根K线\n\n", nrow(pepe_xts)))

# 运行修复版本（详细日志）
cat("=======================================================\n")
cat("运行修复版本（详细日志模式）\n")
cat("=======================================================\n\n")

result <- backtest_strategy_v2(
  data = pepe_xts,
  lookback_days = 5,
  drop_threshold = 0.20,
  take_profit = 0.20,
  stop_loss = 0.10,
  initial_capital = 10000,
  fee_rate = 0.00075,
  next_bar_entry = TRUE,
  verbose = TRUE  # 开启详细日志
)

# 分析第一笔交易
if (result$Trade_Count > 0 && !is.null(result$Trade_Details)) {
  cat("\n=======================================================\n")
  cat("第一笔交易详细对比\n")
  cat("=======================================================\n\n")

  first_trade <- result$Trade_Details[[1]]

  cat("--- R系统（修复版） ---\n")
  cat(sprintf("交易ID：%d\n", first_trade$trade_id))
  cat(sprintf("入场时间：%s\n", first_trade$entry_time))
  cat(sprintf("入场价格：%.8f\n", first_trade$entry_price))
  cat(sprintf("出场时间：%s\n", first_trade$exit_time))
  cat(sprintf("出场价格：%.8f\n", first_trade$exit_price))
  cat(sprintf("出场原因：%s\n", first_trade$exit_reason))
  cat(sprintf("持仓时长：%d根K线（%.1f小时）\n",
              first_trade$bars_held, first_trade$bars_held * 0.25))
  cat(sprintf("盈亏：%.2f%%\n", first_trade$pnl_percent))
  cat(sprintf("入场资金：%.2f\n", first_trade$capital_before))
  cat(sprintf("出场资金：%.2f\n", first_trade$capital_after))
  cat("\n")

  cat("--- TradingView（参考值） ---\n")
  cat("交易ID：1\n")
  cat("入场时间：2024-05-13 07:15:00\n")
  cat("入场价格：0.00000612\n")
  cat("出场时间：2024-05-14 10:15:00\n")
  cat("出场价格：0.00000735\n")
  cat("出场原因：TP\n")
  cat("持仓时长：约27小时\n")
  cat("盈亏：+20.10%\n")
  cat("\n")

  cat("--- 差异分析 ---\n")

  # 时间差异
  tv_entry <- as.POSIXct("2024-05-13 07:15:00", tz = "UTC")
  r_entry <- as.POSIXct(first_trade$entry_time, tz = "UTC")
  time_diff_hours <- as.numeric(difftime(r_entry, tv_entry, units = "hours"))

  cat(sprintf("入场时间差异：%.1f小时", time_diff_hours))
  if (abs(time_diff_hours) <= 1) {
    cat(" OK 极好（<1小时）\n")
  } else if (abs(time_diff_hours) <= 24) {
    cat(" OK 良好（<1天）\n")
  } else if (abs(time_diff_hours) <= 72) {
    cat(" WARN  中等（<3天）\n")
  } else {
    cat(" FAIL 较差（>3天）\n")
  }

  # 价格差异
  tv_price <- 0.00000612
  r_price <- first_trade$entry_price
  price_diff_pct <- abs((r_price - tv_price) / tv_price) * 100

  cat(sprintf("入场价格差异：%.2f%%", price_diff_pct))
  if (price_diff_pct <= 1) {
    cat(" OK 极好（<1%）\n")
  } else if (price_diff_pct <= 5) {
    cat(" OK 良好（<5%）\n")
  } else if (price_diff_pct <= 10) {
    cat(" WARN  中等（<10%）\n")
  } else {
    cat(" FAIL 较差（>10%）\n")
  }

  # 盈亏差异
  tv_pnl <- 20.10
  r_pnl <- first_trade$pnl_percent
  pnl_diff <- abs(r_pnl - tv_pnl)

  cat(sprintf("盈亏差异：%.2f个百分点", pnl_diff))
  if (pnl_diff <= 1) {
    cat(" OK 极好（<1pp）\n")
  } else if (pnl_diff <= 5) {
    cat(" OK 良好（<5pp）\n")
  } else if (pnl_diff <= 10) {
    cat(" WARN  中等（<10pp）\n")
  } else {
    cat(" FAIL 较差（>10pp）\n")
  }

  cat("\n")

  # 总体评估
  cat("--- 总体评估 ---\n")
  score <- 0
  if (abs(time_diff_hours) <= 24) score <- score + 1
  if (price_diff_pct <= 10) score <- score + 1
  if (pnl_diff <= 10) score <- score + 1

  if (score == 3) {
    cat("OK 优秀：第一笔交易与TradingView高度一致！\n")
    cat("建议：继续验证后续交易\n")
  } else if (score == 2) {
    cat("WARN  良好：大部分指标接近，但仍有改进空间\n")
    cat("建议：检查数据源和参数设置\n")
  } else {
    cat("FAIL 需要改进：第一笔交易仍有明显差异\n")
    cat("建议：深入分析信号生成逻辑和数据源\n")
  }

} else {
  cat("\nFAIL 错误：没有产生任何交易！\n")
  cat("可能原因：\n")
  cat("- 数据范围不包含2024-05-13\n")
  cat("- 信号生成逻辑问题\n")
  cat("- 参数设置错误\n")
}

cat("\n=======================================================\n")
cat("整体统计\n")
cat("=======================================================\n\n")

cat(sprintf("信号总数：%d\n", result$Signal_Count))
cat(sprintf("交易总数：%d\n", result$Trade_Count))
cat(sprintf("信号/交易比：%.2f\n",
            result$Signal_Count / max(result$Trade_Count, 1)))
cat(sprintf("最终资金：$%.2f\n", result$Final_Capital))
cat(sprintf("总收益：%.2f%%\n", result$Return_Percentage))
cat(sprintf("胜率：%.2f%%\n", result$Win_Rate))
cat(sprintf("最大回撤：%.2f%%\n", result$Max_Drawdown))
cat(sprintf("总手续费：$%.2f\n", result$Total_Fees))
cat("\n")

cat("--- 与TradingView对比 ---\n")
cat("TradingView：9笔交易，100%胜率\n")
cat(sprintf("R系统：%d笔交易，%.2f%%胜率\n",
            result$Trade_Count, result$Win_Rate))

trade_count_diff <- abs(result$Trade_Count - 9)
winrate_diff <- abs(result$Win_Rate - 100)

cat(sprintf("交易数差异：%d笔", trade_count_diff))
if (trade_count_diff <= 2) {
  cat(" OK 优秀\n")
} else if (trade_count_diff <= 5) {
  cat(" WARN  中等\n")
} else {
  cat(" FAIL 较差\n")
}

cat(sprintf("胜率差异：%.2f个百分点", winrate_diff))
if (winrate_diff <= 10) {
  cat(" OK 优秀\n")
} else if (winrate_diff <= 20) {
  cat(" WARN  中等\n")
} else {
  cat(" FAIL 较差\n")
}

cat("\n=======================================================\n")
cat("测试完成\n")
cat("=======================================================\n\n")

# 显示前5笔交易
if (result$Trade_Count >= 5) {
  cat("前5笔交易概览：\n\n")
  for (i in 1:5) {
    trade <- result$Trade_Details[[i]]
    cat(sprintf("[%d] %s | Entry: %.8f | Exit: %.8f | %s | PnL: %+.2f%%\n",
                i, trade$entry_time, trade$entry_price, trade$exit_price,
                trade$exit_reason, trade$pnl_percent))
  }
  cat("\n")
}

cat("如需查看所有交易详情，请运行 verification_script.R\n\n")
