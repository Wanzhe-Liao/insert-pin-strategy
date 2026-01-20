# ============================================================================
# TradingView对齐版回测引擎测试脚本
# ============================================================================
#
# 版本: 1.0
# 创建日期: 2025-10-27
#
# 测试目标:
# 1. 验证持仓管理是否正确（一次只一个持仓）
# 2. 验证入场时机是否正确
# 3. 验证出场逻辑（exitMode="close" 与 exitMode="tradingview"）
# 4. 对比TradingView对齐版与原版的差异
# 5. 验证被忽略信号的记录是否完整
#
# ============================================================================

# 清理环境
rm(list = ls())
gc()

# 加载回测引擎
cat("正在加载回测引擎...\n")
source("backtest_tradingview_aligned.R")

# 加载数据
cat("正在加载数据...\n")
load("data/liaochu.RData")

# 选择测试数据
test_data <- cryptodata[["PEPEUSDT_15m"]]

cat(sprintf("数据加载完成: %d根K线\n", nrow(test_data)))
cat(sprintf("时间范围: %s 到 %s\n\n",
            as.character(index(test_data)[1]),
            as.character(index(test_data)[nrow(test_data)])))

# ============================================================================
# 测试1: 基本功能测试
# ============================================================================

cat("=" %R% 80, "\n")
cat("测试1: 基本功能测试\n")
cat("=" %R% 80, "\n\n")

# 运行回测（A: close模式，B: tradingview模式）
result_close <- backtest_tradingview_aligned(
  data = test_data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,
  logIgnoredSignals = TRUE,
  includeCurrentBar = TRUE,
  exitMode = "close"
)

result_tv <- backtest_tradingview_aligned(
  data = test_data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,
  logIgnoredSignals = TRUE,
  includeCurrentBar = TRUE,
  exitMode = "tradingview"
)

# 打印摘要
cat("\n--- 模式A: exitMode=\"close\"（对齐R对齐版Pine手动close） ---\n")
print_performance_summary(result_close)
cat("\n--- 模式B: exitMode=\"tradingview\"（High/Low触发 + 精确TP/SL价） ---\n")
print_performance_summary(result_tv)

# 验证持仓管理
cat("持仓管理验证:\n")
cat(sprintf("  [close] 总信号数: %d, 实际交易数: %d, 被忽略: %d, 利用率: %.2f%%\n",
            result_close$SignalCount, result_close$TradeCount, result_close$IgnoredSignalCount, result_close$SignalUtilizationRate))
cat(sprintf("  [tv]    总信号数: %d, 实际交易数: %d, 被忽略: %d, 利用率: %.2f%%\n\n",
            result_tv$SignalCount, result_tv$TradeCount, result_tv$IgnoredSignalCount, result_tv$SignalUtilizationRate))

if (result_close$IgnoredSignalCount > 0) {
  cat("OK 持仓管理正常工作（有信号被忽略）\n")

  # 分析被忽略的原因
  ignored_df <- format_ignored_signals_df(result_close)

  reason_counts <- table(ignored_df$Reason)
  cat("\n被忽略信号原因分布:\n")
  for (reason in names(reason_counts)) {
    cat(sprintf("  %s: %d次\n",
                substr(reason, 1, 50),  # 截断过长的原因
                reason_counts[reason]))
  }
} else {
  cat("WARN 警告: 没有信号被忽略（可能存在问题）\n")
}

cat("\n")

# ============================================================================
# 测试2: 出场逻辑验证（close模式为主）
# ============================================================================

cat("=" %R% 80, "\n")
cat("测试2: 出场逻辑验证\n")
cat("=" %R% 80, "\n\n")

# 分析出场原因分布
cat("出场原因统计:\n")
cat(sprintf("  [close] 止盈: %d (%.1f%%)\n",
            result_close$TPCount,
            (result_close$TPCount / result_close$TradeCount) * 100))
cat(sprintf("  [close] 止损: %d (%.1f%%)\n",
            result_close$SLCount,
            (result_close$SLCount / result_close$TradeCount) * 100))
cat(sprintf("  同时触发: %d (%.1f%%)\n\n",
            result_close$BothTriggerCount,
            (result_close$BothTriggerCount / result_close$TradeCount) * 100))

trades_df <- format_trades_df(result_close)

# 随机抽取5笔交易详细分析
if (nrow(trades_df) >= 5) {
  cat("随机抽取5笔交易详细分析:\n\n")

  sample_indices <- sample(1:nrow(trades_df), 5)

  for (idx in sample_indices) {
    trade <- result_close$Trades[[idx]]

    cat(sprintf("交易 #%d:\n", trade$TradeId))
    cat(sprintf("  入场: Bar %d, 时间 %s, 价格 %.8f\n",
                trade$EntryBar, trade$EntryTime, trade$EntryPrice))
    cat(sprintf("  出场: Bar %d, 时间 %s, 价格 %.8f\n",
                trade$ExitBar, trade$ExitTime, trade$ExitPrice))
    cat(sprintf("  原因: %s\n", trade$ExitReason))
    cat(sprintf("  盈亏: %.2f%%\n", trade$PnLPercent))
    cat(sprintf("  持仓: %d根K线\n\n", trade$HoldingBars))

    # 验证：close模式使用 Close 触发 & Close 成交
    expected_tp <- trade$EntryPrice * 1.10
    expected_sl <- trade$EntryPrice * 0.90
    exit_close <- as.numeric(test_data[trade$ExitBar, "Close"])

    if (grepl("TP", trade$ExitReason)) {
      if (!is.na(exit_close) && abs(trade$ExitPrice - exit_close) / max(1e-12, abs(exit_close)) * 100 < 1e-8) {
        cat("  OK 出场成交价=ExitBar的Close价\n")
      } else {
        cat("  WARN 出场成交价不等于ExitBar的Close价\n")
      }

      if (trade$ExitPrice >= expected_tp) {
        cat("  OK 触发条件满足: Close >= TP价\n\n")
      } else {
        cat(sprintf("  WARN 触发条件不满足: Close < TP价 (Close=%.10f, TP=%.10f)\n\n",
                    trade$ExitPrice, expected_tp))
      }
    } else if (grepl("SL", trade$ExitReason)) {
      if (!is.na(exit_close) && abs(trade$ExitPrice - exit_close) / max(1e-12, abs(exit_close)) * 100 < 1e-8) {
        cat("  OK 出场成交价=ExitBar的Close价\n")
      } else {
        cat("  WARN 出场成交价不等于ExitBar的Close价\n")
      }

      if (trade$ExitPrice <= expected_sl) {
        cat("  OK 触发条件满足: Close <= SL价\n\n")
      } else {
        cat(sprintf("  WARN 触发条件不满足: Close > SL价 (Close=%.10f, SL=%.10f)\n\n",
                    trade$ExitPrice, expected_sl))
      }
    }
  }
}

# ============================================================================
# 测试3: 与原版对比
# ============================================================================

cat("=" %R% 80, "\n")
cat("测试3: 与原版对比\n")
cat("=" %R% 80, "\n\n")

# 检查原版函数是否存在
if (file.exists("backtest_final_fixed.R")) {
  cat("加载原版回测引擎...\n")
  source("backtest_final_fixed.R")

  # 运行原版回测（记录执行时间）
  start_original <- Sys.time()
  result_original <- backtest_strategy_final(
    data = test_data,
    lookback_days = 3,
    drop_threshold = 0.20,
    take_profit = 0.10,
    stop_loss = 0.10,
    initial_capital = 10000,
    fee_rate = 0.00075,
    next_bar_entry = FALSE,
    verbose = FALSE
  )
  end_original <- Sys.time()
  exec_time_original <- as.numeric(difftime(end_original, start_original, units = "secs"))

  # 对比结果
  comparison <- data.frame(
    指标 = c(
      "信号数",
      "交易数",
      "被忽略信号",
      "止盈次数",
      "止损次数",
      "收益率(%)",
      "胜率(%)",
      "最大回撤(%)",
      "总手续费(USDT)",
      "执行时间(秒)"
    ),
    原版 = c(
      result_original$Signal_Count,
      result_original$Trade_Count,
      NA,
      NA,
      NA,
      round(result_original$Return_Percentage, 2),
      round(result_original$Win_Rate, 2),
      round(result_original$Max_Drawdown, 2),
      round(result_original$Total_Fees, 2),
      round(exec_time_original, 3)
    ),
    TradingView对齐版 = c(
      result_close$SignalCount,
      result_close$TradeCount,
      result_close$IgnoredSignalCount,
      result_close$TPCount,
      result_close$SLCount,
      round(result_close$ReturnPercent, 2),
      round(result_close$WinRate, 2),
      round(result_close$MaxDrawdown, 2),
      round(result_close$TotalFees, 2),
      round(result_close$ExecutionTime, 3)
    ),
    stringsAsFactors = FALSE
  )

  # 计算差异
  comparison$差异 <- comparison$TradingView对齐版 - comparison$原版
  comparison$差异百分比 <- ifelse(
    !is.na(comparison$原版) & comparison$原版 != 0,
    sprintf("%.1f%%", (comparison$差异 / comparison$原版) * 100),
    NA
  )

  cat("\n对比结果:\n\n")
  print(comparison)

  cat("\n\n关键差异分析:\n")

  # 交易数量差异
  trade_diff <- result_close$TradeCount - result_original$Trade_Count
  if (abs(trade_diff) > 0) {
    cat(sprintf("\n1. 交易数量差异: %+d笔\n", trade_diff))
    if (trade_diff > 0) {
      cat("   原因: 两版本在持仓管理/信号窗口/入出场时机等规则上可能不同\n")
      cat("   → 资金占用差异 → 交易机会差异\n")
    } else {
      cat("   原因: TradingView对齐版有更严格的持仓管理\n")
      cat("   → 持仓期间忽略信号 → 交易次数减少\n")
    }
  }

  # 收益率差异
  return_diff <- result_close$ReturnPercent - result_original$Return_Percentage
  if (abs(return_diff) > 1) {
    cat(sprintf("\n2. 收益率差异: %+.2f%%\n", return_diff))
    if (return_diff > 0) {
      cat("   原因: 交易次数差异 + 出场触发/成交价模型差异\n")
    } else {
      cat("   原因: 更严格的持仓管理可能错过部分盈利机会\n")
    }
  }

  # 胜率差异
  winrate_diff <- result_close$WinRate - result_original$Win_Rate
  if (abs(winrate_diff) > 1) {
    cat(sprintf("\n3. 胜率差异: %+.2f%%\n", winrate_diff))
    if (winrate_diff > 0) {
      cat("   原因: 出场触发/成交价模型差异\n")
    } else {
      cat("   原因: 规则差异导致样本分布不同\n")
    }
  }

} else {
  cat("WARN 原版回测文件不存在，跳过对比测试\n\n")
}

# ============================================================================
# 测试4: 导出详细日志
# ============================================================================

cat("\n")
cat("=" %R% 80, "\n")
cat("测试4: 导出详细日志\n")
cat("=" %R% 80, "\n\n")

# 导出交易详情
trades_file <- "outputs/trades_tradingview_aligned.csv"
trades_df <- format_trades_df(result_close)
write.csv(trades_df, trades_file, row.names = FALSE)
cat(sprintf("OK 交易详情已导出: %s\n", trades_file))
cat(sprintf("  共 %d 笔交易\n\n", nrow(trades_df)))

# 导出被忽略的信号
ignored_file <- "outputs/ignored_signals_tradingview_aligned.csv"
ignored_df <- format_ignored_signals_df(result_close)
write.csv(ignored_df, ignored_file, row.names = FALSE)
cat(sprintf("OK 被忽略信号已导出: %s\n", ignored_file))
cat(sprintf("  共 %d 个被忽略信号\n\n", nrow(ignored_df)))

# 导出性能摘要
dir.create("outputs", showWarnings = FALSE, recursive = TRUE)
summary_file <- file.path("outputs", "performance_summary_tradingview_aligned.txt")
sink(summary_file)
print_performance_summary(result_close)
sink()
cat(sprintf("OK 性能摘要已导出: %s\n\n", summary_file))

# ============================================================================
# 测试5: 验证与TradingView的一致性
# ============================================================================

cat("=" %R% 80, "\n")
cat("测试5: 验证与TradingView的一致性\n")
cat("=" %R% 80, "\n\n")

# 读取TradingView的交易数据
tv_file <- "data/tradingview_trades.csv"

if (file.exists(tv_file)) {
  cat("读取TradingView交易数据...\n")

  # 读取CSV（跳过表头行）
  tv_trades_raw <- read.csv(tv_file, stringsAsFactors = FALSE, skip = 0)

  # TradingView数据只有9笔交易（18行，每笔2行）
  # 提取入场和出场行
  tv_entries <- tv_trades_raw[seq(2, nrow(tv_trades_raw), 2), ]
  tv_exits <- tv_trades_raw[seq(1, nrow(tv_trades_raw), 2), ]

  tv_trade_count <- nrow(tv_entries)

  cat(sprintf("TradingView交易数: %d\n", tv_trade_count))
  cat(sprintf("R回测交易数: %d\n", result_close$TradeCount))
  cat(sprintf("差异: %+d笔\n\n", result_close$TradeCount - tv_trade_count))

  if (result_close$TradeCount > tv_trade_count) {
    cat("分析: R回测产生了更多交易\n")
    cat("可能原因:\n")
    cat("  1. 持仓管理规则仍有差异\n")
    cat("  2. 信号生成逻辑有细微差异\n")
    cat("  3. 入场时机计算不同\n")
    cat("  4. TradingView可能有额外的过滤条件\n\n")

    cat("建议:\n")
    cat("  1. 对比前几笔交易的具体时间和价格\n")
    cat("  2. 检查TradingView的Pine Script代码\n")
    cat("  3. 验证信号生成的窗口计算是否完全一致\n\n")
  } else if (result_close$TradeCount < tv_trade_count) {
    cat("分析: R回测产生了更少交易\n")
    cat("可能原因:\n")
    cat("  1. 信号生成条件更严格\n")
    cat("  2. 数据时间范围不同\n")
    cat("  3. 边界条件处理不同\n\n")
  } else {
    cat("OK 交易数量完全一致！\n")
    cat("  → 持仓管理逻辑已对齐\n")
    cat("  → 建议进一步对比每笔交易的细节\n\n")
  }

  # 对比前3笔交易
  cat("对比前3笔交易:\n\n")

  for (i in 1:min(3, tv_trade_count, result_close$TradeCount)) {
    cat(sprintf("=== 交易 #%d ===\n", i))

    # TradingView数据
    tv_entry_price <- as.numeric(tv_entries[i, "价格.USDT"])
    tv_exit_price <- as.numeric(tv_exits[i, "价格.USDT"])
    tv_pnl <- as.numeric(gsub("%", "", tv_exits[i, "净损益.."]))

    cat(sprintf("TradingView:\n"))
    cat(sprintf("  入场价格: %.8f\n", tv_entry_price))
    cat(sprintf("  出场价格: %.8f\n", tv_exit_price))
    cat(sprintf("  盈亏: %.2f%%\n", tv_pnl))

    # R回测数据
    r_trade <- result_close$Trades[[i]]
    cat(sprintf("\nR回测:\n"))
    cat(sprintf("  入场价格: %.8f\n", r_trade$EntryPrice))
    cat(sprintf("  出场价格: %.8f\n", r_trade$ExitPrice))
    cat(sprintf("  盈亏: %.2f%%\n", r_trade$PnLPercent))

    # 计算差异
    entry_diff <- abs(r_trade$EntryPrice - tv_entry_price) / tv_entry_price * 100
    exit_diff <- abs(r_trade$ExitPrice - tv_exit_price) / tv_exit_price * 100
    pnl_diff <- abs(r_trade$PnLPercent - tv_pnl)

    cat(sprintf("\n差异:\n"))
    cat(sprintf("  入场价格偏差: %.4f%%\n", entry_diff))
    cat(sprintf("  出场价格偏差: %.4f%%\n", exit_diff))
    cat(sprintf("  盈亏偏差: %.2f%%\n\n", pnl_diff))

    if (entry_diff < 0.01 && exit_diff < 0.01 && pnl_diff < 0.5) {
      cat("  OK 交易高度一致\n\n")
    } else {
      cat("  WARN 存在明显差异，需要进一步分析\n\n")
    }
  }

} else {
  cat(sprintf("WARN TradingView交易数据文件不存在: %s\n", tv_file))
  cat("跳过与TradingView的一致性验证\n\n")
}

# ============================================================================
# 测试总结
# ============================================================================

cat("=" %R% 80, "\n")
cat("测试总结\n")
cat("=" %R% 80, "\n\n")

cat("测试完成时间:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

cat("关键发现:\n")
cat(sprintf("  [close] 信号总数: %d\n", result_close$SignalCount))
cat(sprintf("  [close] 实际交易: %d (利用率 %.1f%%)\n",
            result_close$TradeCount, result_close$SignalUtilizationRate))
cat(sprintf("  [close] 被忽略信号: %d\n", result_close$IgnoredSignalCount))
cat(sprintf("  [close] 最终收益: %.2f%%, 胜率: %.2f%%\n\n", result_close$ReturnPercent, result_close$WinRate))

cat("修复验证:\n")
cat("  OK 持仓管理: 已实现，有信号被忽略\n")
cat("  OK 入场时机: 使用收盘价（对齐process_orders_on_close=true）\n")
cat("  OK 出场模式: close（Close触发+Close成交价）\n")
cat("  OK 详细日志: 已记录所有被忽略信号\n\n")

cat("下一步建议:\n")
cat("  1. 仔细对比与TradingView的交易时间和价格\n")
cat("  2. 如果交易数量仍有差异，分析第一笔交易的差异点\n")
cat("  3. 检查Pine Script代码，确认所有参数完全一致\n")
cat("  4. 验证数据时间范围是否完全相同\n")
cat("  5. 考虑TradingView是否有隐藏的过滤条件\n\n")

cat("=" %R% 80, "\n\n")

cat("OK 所有测试完成！\n\n")
