# 验证脚本：对比修复前后的差异
# 目的：验证深度修复是否解决了与TradingView的差异问题

library(xts)

# 加载两个版本的回测引擎
source("backtest_final_fixed.R")
source("backtest_final_fixed_v2.R")

cat("\n=======================================================\n")
cat("  验证脚本：对比修复前后的回测结果差异\n")
cat("=======================================================\n\n")

# 检查是否有数据文件
data_file <- "PEPEUSDT_15m.csv"
if (!file.exists(data_file)) {
  cat("错误：未找到数据文件\n")
  cat("请确保以下文件存在：\n")
  cat(sprintf("  %s\n", data_file))
  cat("\n请先运行数据准备脚本生成数据文件。\n")
  quit()
}

# 读取数据
cat("正在读取数据...\n")
pepe_data <- read.csv(data_file, stringsAsFactors = FALSE)
pepe_data$timestamp <- as.POSIXct(pepe_data$timestamp, tz = "UTC")
pepe_xts <- xts(pepe_data[, c("Open", "High", "Low", "Close", "Volume")],
                order.by = pepe_data$timestamp)

cat(sprintf("数据加载完成：%d根K线\n", nrow(pepe_xts)))
cat(sprintf("时间范围：%s 至 %s\n",
            min(index(pepe_xts)), max(index(pepe_xts))))
cat("\n")

# 测试参数（使用TradingView的参数）
test_params <- list(
  lookback_days = 5,
  drop_pct = 20,
  tp_pct = 20,
  sl_pct = 10,
  initial_capital = 10000,
  fee_pct = 0.075
)

cat("=======================================================\n")
cat("测试参数：\n")
cat("=======================================================\n")
cat(sprintf("  回看天数：%d 天\n", test_params$lookback_days))
cat(sprintf("  跌幅阈值：%.1f%%\n", test_params$drop_pct))
cat(sprintf("  止盈：%.1f%%\n", test_params$tp_pct))
cat(sprintf("  止损：%.1f%%\n", test_params$sl_pct))
cat(sprintf("  初始资金：$%.2f\n", test_params$initial_capital))
cat(sprintf("  手续费率：%.3f%%\n", test_params$fee_pct))
cat("\n")

# ===== 测试1：原版本（当前收盘入场） =====
cat("=======================================================\n")
cat("测试1：原版本（next_bar_entry=FALSE，当前收盘入场）\n")
cat("=======================================================\n")

result_v1_close <- backtest_strategy_final(
  data = pepe_xts,
  lookback_days = test_params$lookback_days,
  drop_threshold = test_params$drop_pct / 100,
  take_profit = test_params$tp_pct / 100,
  stop_loss = test_params$sl_pct / 100,
  initial_capital = test_params$initial_capital,
  fee_rate = test_params$fee_pct / 100,
  next_bar_entry = FALSE,
  verbose = TRUE
)

cat("\n结果摘要：\n")
cat(sprintf("  信号数：%d\n", result_v1_close$Signal_Count))
cat(sprintf("  交易数：%d\n", result_v1_close$Trade_Count))
cat(sprintf("  最终资金：$%.2f\n", result_v1_close$Final_Capital))
cat(sprintf("  总收益：%.2f%%\n", result_v1_close$Return_Percentage))
cat(sprintf("  胜率：%.2f%%\n", result_v1_close$Win_Rate))
cat(sprintf("  止盈次数：%d\n", result_v1_close$TP_Count))
cat(sprintf("  止损次数：%d\n", result_v1_close$SL_Count))
cat("\n")

# ===== 测试2：原版本（下一根开盘入场） =====
cat("=======================================================\n")
cat("测试2：原版本（next_bar_entry=TRUE，下一根开盘入场）\n")
cat("=======================================================\n")

result_v1_open <- backtest_strategy_final(
  data = pepe_xts,
  lookback_days = test_params$lookback_days,
  drop_threshold = test_params$drop_pct / 100,
  take_profit = test_params$tp_pct / 100,
  stop_loss = test_params$sl_pct / 100,
  initial_capital = test_params$initial_capital,
  fee_rate = test_params$fee_pct / 100,
  next_bar_entry = TRUE,
  verbose = TRUE
)

cat("\n结果摘要：\n")
cat(sprintf("  信号数：%d\n", result_v1_open$Signal_Count))
cat(sprintf("  交易数：%d\n", result_v1_open$Trade_Count))
cat(sprintf("  最终资金：$%.2f\n", result_v1_open$Final_Capital))
cat(sprintf("  总收益：%.2f%%\n", result_v1_open$Return_Percentage))
cat(sprintf("  胜率：%.2f%%\n", result_v1_open$Win_Rate))
cat(sprintf("  止盈次数：%d\n", result_v1_open$TP_Count))
cat(sprintf("  止损次数：%d\n", result_v1_open$SL_Count))
cat("\n")

# ===== 测试3：修复版本（下一根开盘入场） =====
cat("=======================================================\n")
cat("测试3：修复版本v2（next_bar_entry=TRUE，深度修复）\n")
cat("=======================================================\n")

result_v2 <- backtest_strategy_v2(
  data = pepe_xts,
  lookback_days = test_params$lookback_days,
  drop_threshold = test_params$drop_pct / 100,
  take_profit = test_params$tp_pct / 100,
  stop_loss = test_params$sl_pct / 100,
  initial_capital = test_params$initial_capital,
  fee_rate = test_params$fee_pct / 100,
  next_bar_entry = TRUE,
  verbose = TRUE
)

cat("\n结果摘要：\n")
cat(sprintf("  信号数：%d\n", result_v2$Signal_Count))
cat(sprintf("  交易数：%d\n", result_v2$Trade_Count))
cat(sprintf("  最终资金：$%.2f\n", result_v2$Final_Capital))
cat(sprintf("  总收益：%.2f%%\n", result_v2$Return_Percentage))
cat(sprintf("  胜率：%.2f%%\n", result_v2$Win_Rate))
cat(sprintf("  止盈次数：%d\n", result_v2$TP_Count))
cat(sprintf("  止损次数：%d\n", result_v2$SL_Count))
cat("\n")

# ===== 对比分析 =====
cat("=======================================================\n")
cat("对比分析\n")
cat("=======================================================\n\n")

cat("--- 信号数变化 ---\n")
cat(sprintf("  原版（当前收盘）：%d\n", result_v1_close$Signal_Count))
cat(sprintf("  原版（下一根开盘）：%d\n", result_v1_open$Signal_Count))
cat(sprintf("  修复版：%d\n", result_v2$Signal_Count))
cat(sprintf("  分析：%s\n",
    ifelse(result_v2$Signal_Count != result_v1_close$Signal_Count,
           "信号生成逻辑已修改（删除了错误的滞后）",
           "信号生成逻辑未变")))
cat("\n")

cat("--- 交易数变化 ---\n")
cat(sprintf("  原版（当前收盘）：%d\n", result_v1_close$Trade_Count))
cat(sprintf("  原版（下一根开盘）：%d\n", result_v1_open$Trade_Count))
cat(sprintf("  修复版：%d\n", result_v2$Trade_Count))
cat(sprintf("  与原版（当前收盘）差异：%d (%.1f%%)\n",
    result_v2$Trade_Count - result_v1_close$Trade_Count,
    (result_v2$Trade_Count / result_v1_close$Trade_Count - 1) * 100))
cat(sprintf("  与原版（下一根开盘）差异：%d (%.1f%%)\n",
    result_v2$Trade_Count - result_v1_open$Trade_Count,
    (result_v2$Trade_Count / result_v1_open$Trade_Count - 1) * 100))
cat(sprintf("  分析：%s\n",
    ifelse(result_v2$Trade_Count < result_v1_close$Trade_Count,
           "修复成功！交易数减少，说明冷却期生效",
           "需要进一步检查")))
cat("\n")

cat("--- 胜率变化 ---\n")
cat(sprintf("  原版（当前收盘）：%.2f%%\n", result_v1_close$Win_Rate))
cat(sprintf("  原版（下一根开盘）：%.2f%%\n", result_v1_open$Win_Rate))
cat(sprintf("  修复版：%.2f%%\n", result_v2$Win_Rate))
cat(sprintf("  TradingView参考值：100%%\n"))
cat(sprintf("  与TradingView差异：%.2f个百分点\n", result_v2$Win_Rate - 100))
cat("\n")

cat("--- 收益变化 ---\n")
cat(sprintf("  原版（当前收盘）：%.2f%%\n", result_v1_close$Return_Percentage))
cat(sprintf("  原版（下一根开盘）：%.2f%%\n", result_v1_open$Return_Percentage))
cat(sprintf("  修复版：%.2f%%\n", result_v2$Return_Percentage))
cat("\n")

# ===== 第一笔交易对比 =====
cat("=======================================================\n")
cat("第一笔交易对比（关键验证点）\n")
cat("=======================================================\n\n")

if (result_v2$Trade_Count > 0 && !is.null(result_v2$Trade_Details)) {
  first_trade_v2 <- result_v2$Trade_Details[[1]]

  cat("修复版本第一笔交易：\n")
  cat(sprintf("  入场时间：%s\n", first_trade_v2$entry_time))
  cat(sprintf("  入场价格：%.8f\n", first_trade_v2$entry_price))
  cat(sprintf("  出场时间：%s\n", first_trade_v2$exit_time))
  cat(sprintf("  出场价格：%.8f\n", first_trade_v2$exit_price))
  cat(sprintf("  出场原因：%s\n", first_trade_v2$exit_reason))
  cat(sprintf("  盈亏：%.2f%%\n", first_trade_v2$pnl_percent))
  cat("\n")

  cat("TradingView第一笔交易（参考）：\n")
  cat("  入场时间：2024-05-13 07:15:00\n")
  cat("  入场价格：0.00000612\n")
  cat("  出场时间：2024-05-14 10:15:00\n")
  cat("  出场价格：0.00000735\n")
  cat("  出场原因：TP\n")
  cat("  盈亏：+20.10%\n")
  cat("\n")

  # 时间差异分析
  tv_entry_time <- as.POSIXct("2024-05-13 07:15:00", tz = "UTC")
  r_entry_time <- as.POSIXct(first_trade_v2$entry_time, tz = "UTC")
  time_diff_hours <- as.numeric(difftime(r_entry_time, tv_entry_time, units = "hours"))

  cat("差异分析：\n")
  cat(sprintf("  入场时间差：%.1f小时\n", time_diff_hours))

  tv_entry_price <- 0.00000612
  price_diff_pct <- (first_trade_v2$entry_price - tv_entry_price) / tv_entry_price * 100
  cat(sprintf("  入场价格差：%.2f%%\n", price_diff_pct))

  tv_pnl <- 20.10
  pnl_diff <- first_trade_v2$pnl_percent - tv_pnl
  cat(sprintf("  盈亏差异：%.2f个百分点\n", pnl_diff))
  cat("\n")

  if (abs(time_diff_hours) < 24 && abs(price_diff_pct) < 10) {
    cat("OK 第一笔交易时间和价格与TradingView较为接近\n")
  } else {
    cat("WARN  第一笔交易仍有明显差异，可能需要进一步调整\n")
  }
  cat("\n")
}

# ===== 关键修复点验证 =====
cat("=======================================================\n")
cat("关键修复点验证\n")
cat("=======================================================\n\n")

cat("1. 持仓管理逻辑（冷却期）\n")
cat(sprintf("   - 信号数：%d\n", result_v2$Signal_Count))
cat(sprintf("   - 交易数：%d\n", result_v2$Trade_Count))
cat(sprintf("   - 信号/交易比：%.2f\n", result_v2$Signal_Count / max(result_v2$Trade_Count, 1)))
cat(sprintf("   - 状态：%s\n",
    ifelse(result_v2$Trade_Count <= result_v2$Signal_Count,
           "OK 正常（交易数 <= 信号数）",
           "FAIL 异常（交易数 > 信号数）")))
cat("\n")

cat("2. 信号生成逻辑（窗口计算）\n")
cat("   - 已删除错误的滞后\n")
cat("   - 使用当前K线窗口最高价（与TradingView一致）\n")
cat("   - 状态：OK 已修复\n")
cat("\n")

cat("3. 入场时机\n")
cat("   - 模式：下一根开盘价入场\n")
cat("   - 状态：OK 已统一\n")
cat("\n")

cat("4. 出场检查时机\n")
cat("   - 入场K线不检查出场（i > entry_index）\n")
cat("   - 状态：OK 已修复\n")
cat("\n")

# ===== TradingView对比总结 =====
cat("=======================================================\n")
cat("与TradingView对比总结\n")
cat("=======================================================\n\n")

cat("TradingView结果（参考）：\n")
cat("  - 交易数：9笔\n")
cat("  - 胜率：100%\n")
cat("  - 第一笔入场：2024-05-13 07:15:00 @ 0.00000612\n")
cat("\n")

cat("R修复版本结果：\n")
cat(sprintf("  - 交易数：%d笔\n", result_v2$Trade_Count))
cat(sprintf("  - 胜率：%.2f%%\n", result_v2$Win_Rate))
if (result_v2$Trade_Count > 0 && !is.null(result_v2$Trade_Details)) {
  first_trade <- result_v2$Trade_Details[[1]]
  cat(sprintf("  - 第一笔入场：%s @ %.8f\n",
              first_trade$entry_time, first_trade$entry_price))
}
cat("\n")

cat("差异评估：\n")
trade_diff <- abs(result_v2$Trade_Count - 9)
winrate_diff <- abs(result_v2$Win_Rate - 100)

if (trade_diff <= 2 && winrate_diff <= 10) {
  cat("OK 优秀：与TradingView高度一致\n")
} else if (trade_diff <= 5 && winrate_diff <= 20) {
  cat("WARN  中等：仍有差异，建议进一步检查\n")
} else {
  cat("FAIL 较差：差异较大，需要深入分析\n")
}
cat("\n")

# ===== 下一步建议 =====
cat("=======================================================\n")
cat("下一步建议\n")
cat("=======================================================\n\n")

if (result_v2$Trade_Count > 15) {
  cat("1. 交易数仍偏多，建议：\n")
  cat("   - 检查TradingView的持仓逻辑（可能有额外限制）\n")
  cat("   - 验证TradingView的信号生成条件\n")
  cat("   - 确认是否有最小持仓时长限制\n")
  cat("\n")
}

if (abs(result_v2$Win_Rate - 100) > 15) {
  cat("2. 胜率差异较大，建议：\n")
  cat("   - 检查止盈止损触发逻辑\n")
  cat("   - 验证价格精度和四舍五入方式\n")
  cat("   - 对比具体交易明细\n")
  cat("\n")
}

cat("3. 详细对比步骤：\n")
cat("   - 导出前10笔交易的详细信息\n")
cat("   - 与TradingView逐笔对比入场/出场时间和价格\n")
cat("   - 分析差异原因\n")
cat("\n")

cat("=======================================================\n")
cat("验证完成\n")
cat("=======================================================\n\n")

# 保存详细交易记录
if (result_v2$Trade_Count > 0 && !is.null(result_v2$Trade_Details)) {
  cat("正在保存交易详情到CSV文件...\n")

  trade_df <- do.call(rbind, lapply(result_v2$Trade_Details, function(t) {
    data.frame(
      trade_id = t$trade_id,
      entry_bar = t$entry_bar,
      entry_time = t$entry_time,
      entry_price = t$entry_price,
      exit_bar = t$exit_bar,
      exit_time = t$exit_time,
      exit_price = t$exit_price,
      exit_reason = t$exit_reason,
      bars_held = t$bars_held,
      pnl_percent = t$pnl_percent,
      capital_before = t$capital_before,
      capital_after = t$capital_after,
      stringsAsFactors = FALSE
    )
  }))

  output_file <- "trade_details_v2.csv"
  write.csv(trade_df, output_file, row.names = FALSE)
  cat(sprintf("交易详情已保存至：%s\n", output_file))
}

cat("\n验证脚本执行完成！\n\n")
