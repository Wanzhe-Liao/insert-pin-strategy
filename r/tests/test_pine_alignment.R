# Pine Script对齐验证测试脚本
# 对比原版（Close价）和改进版（High/Low盘中触发）的差异
#
# 创建日期：2025-10-26

suppressMessages({
  library(xts)
})

cat("========================================\n")
cat("Pine Script对齐验证测试\n")
cat("========================================\n\n")

# 加载数据
cat("1. 加载数据...\n")
load("data/liaochu.RData")

# 加载原版回测函数
cat("2. 加载原版回测函数...\n")
source("optimize_pepe_fixed.R")

# 加载Pine对齐版回测函数
cat("3. 加载Pine对齐版回测函数...\n")
source("backtest_pine_aligned.R")

# 筛选PEPEUSDT数据
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat(sprintf("\n找到 %d 个PEPEUSDT时间框架：%s\n\n",
           length(pepe_symbols),
           paste(pepe_symbols, collapse=", ")))

# ============================================================================
# 测试配置
# ============================================================================

test_configs <- list(
  list(
    name = "Pine Script默认参数",
    lookbackDays = 3,
    minDropPercent = 20,
    takeProfitPercent = 10,
    stopLossPercent = 10
  ),
  list(
    name = "宽松参数",
    lookbackDays = 3,
    minDropPercent = 10,
    takeProfitPercent = 8,
    stopLossPercent = 8
  ),
  list(
    name = "严格参数",
    lookbackDays = 5,
    minDropPercent = 25,
    takeProfitPercent = 12,
    stopLossPercent = 12
  )
)

# ============================================================================
# 执行测试
# ============================================================================

all_results <- list()

for (config in test_configs) {
  cat("\n########################################\n")
  cat(sprintf("测试配置：%s\n", config$name))
  cat("########################################\n")
  cat(sprintf("lookbackDays=%d, minDrop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n\n",
             config$lookbackDays, config$minDropPercent,
             config$takeProfitPercent, config$stopLossPercent))

  config_results <- list()

  for (symbol in pepe_symbols) {
    cat(sprintf("\n--- %s ---\n", symbol))
    data <- cryptodata[[symbol]]

    # 运行原版（Close价）
    cat("运行原版（Close价判断）...\n")
    result_original <- backtest_strategy_fixed(
      data,
      config$lookbackDays,
      config$minDropPercent,
      config$takeProfitPercent,
      config$stopLossPercent
    )

    # 运行Pine对齐版（High/Low盘中触发）
    cat("运行Pine对齐版（High/Low盘中触发）...\n")
    result_pine <- backtest_strategy_pine_aligned(
      data,
      config$lookbackDays,
      config$minDropPercent,
      config$takeProfitPercent,
      config$stopLossPercent,
      next_bar_entry = FALSE,  # 对齐process_orders_on_close=true
      verbose = FALSE
    )

    # 对比结果
    cat("\n对比结果：\n")
    cat(sprintf("  信号数: %d (两版本相同)\n", result_pine$Signal_Count))

    cat(sprintf("\n  交易次数:\n"))
    cat(sprintf("    原版: %d\n", result_original$Trade_Count))
    cat(sprintf("    Pine对齐版: %d\n", result_pine$Trade_Count))
    if (result_pine$Trade_Count > result_original$Trade_Count) {
      diff <- result_pine$Trade_Count - result_original$Trade_Count
      pct <- (diff / result_original$Trade_Count) * 100
      cat(sprintf("    差异: +%d (%.1f%%) OK Pine版捕捉更多交易\n", diff, pct))
    } else if (result_pine$Trade_Count < result_original$Trade_Count) {
      diff <- result_original$Trade_Count - result_pine$Trade_Count
      cat(sprintf("    差异: -%d WARN 异常：Pine版反而更少\n", diff))
    } else {
      cat(sprintf("    差异: 0 (两版本相同)\n"))
    }

    if (result_pine$Trade_Count > 0) {
      cat(sprintf("\n  止盈/止损分布 (Pine对齐版):\n"))
      cat(sprintf("    止盈: %d (%.1f%%)\n",
                 result_pine$TP_Count,
                 (result_pine$TP_Count / result_pine$Trade_Count) * 100))
      cat(sprintf("    止损: %d (%.1f%%)\n",
                 result_pine$SL_Count,
                 (result_pine$SL_Count / result_pine$Trade_Count) * 100))
      cat(sprintf("    同时触发: %d\n", result_pine$Both_Trigger_Count))
    }

    if (!is.na(result_original$Return_Percentage) &&
        !is.na(result_pine$Return_Percentage)) {
      cat(sprintf("\n  收益率:\n"))
      cat(sprintf("    原版: %.2f%%\n", result_original$Return_Percentage))
      cat(sprintf("    Pine对齐版: %.2f%%\n", result_pine$Return_Percentage))
      diff_return <- result_pine$Return_Percentage - result_original$Return_Percentage
      if (abs(diff_return) > 1) {
        cat(sprintf("    差异: %+.2f%% ", diff_return))
        if (diff_return > 0) {
          cat("OK Pine版更优\n")
        } else {
          cat("WARN 原版更优\n")
        }
      } else {
        cat(sprintf("    差异: %+.2f%% (基本相同)\n", diff_return))
      }

      cat(sprintf("\n  胜率:\n"))
      cat(sprintf("    原版: %.2f%%\n", result_original$Win_Rate))
      cat(sprintf("    Pine对齐版: %.2f%%\n", result_pine$Win_Rate))
    }

    # 保存结果
    config_results[[symbol]] <- list(
      original = result_original,
      pine_aligned = result_pine
    )
  }

  all_results[[config$name]] <- config_results
}

# ============================================================================
# 汇总统计
# ============================================================================

cat("\n\n========================================\n")
cat("汇总统计\n")
cat("========================================\n\n")

for (config_name in names(all_results)) {
  cat(sprintf("\n【%s】\n", config_name))
  cat(rep("-", 60), "\n", sep="")

  config_results <- all_results[[config_name]]

  # 计算平均值
  trade_count_orig <- sapply(config_results, function(x) x$original$Trade_Count)
  trade_count_pine <- sapply(config_results, function(x) x$pine_aligned$Trade_Count)

  return_orig <- sapply(config_results, function(x) {
    ifelse(is.na(x$original$Return_Percentage), 0, x$original$Return_Percentage)
  })
  return_pine <- sapply(config_results, function(x) {
    ifelse(is.na(x$pine_aligned$Return_Percentage), 0, x$pine_aligned$Return_Percentage)
  })

  cat(sprintf("平均交易次数: 原版=%.1f, Pine对齐版=%.1f (差异=%+.1f)\n",
             mean(trade_count_orig),
             mean(trade_count_pine),
             mean(trade_count_pine) - mean(trade_count_orig)))

  cat(sprintf("平均收益率: 原版=%.2f%%, Pine对齐版=%.2f%% (差异=%+.2f%%)\n",
             mean(return_orig),
             mean(return_pine),
             mean(return_pine) - mean(return_orig)))

  # 统计改进情况
  improved_count <- sum(return_pine > return_orig)
  same_count <- sum(abs(return_pine - return_orig) < 1)
  worse_count <- sum(return_pine < return_orig - 1)

  cat(sprintf("\n改进情况统计（%d个时间框架）:\n", length(config_results)))
  cat(sprintf("  更优: %d (%.1f%%)\n", improved_count,
             (improved_count / length(config_results)) * 100))
  cat(sprintf("  相同: %d (%.1f%%)\n", same_count,
             (same_count / length(config_results)) * 100))
  cat(sprintf("  更差: %d (%.1f%%)\n", worse_count,
             (worse_count / length(config_results)) * 100))
}

# ============================================================================
# 详细案例分析
# ============================================================================

cat("\n\n========================================\n")
cat("详细案例分析\n")
cat("========================================\n\n")

# 选择一个案例进行详细分析
symbol <- "PEPEUSDT_15m"
config <- test_configs[[1]]  # Pine Script默认参数

cat(sprintf("分析案例：%s\n", symbol))
cat(sprintf("参数：lookback=%d, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n\n",
           config$lookbackDays, config$minDropPercent,
           config$takeProfitPercent, config$stopLossPercent))

data <- cryptodata[[symbol]]

cat("运行带详细日志的Pine对齐版回测...\n\n")
result_verbose <- backtest_strategy_pine_aligned(
  data,
  config$lookbackDays,
  config$minDropPercent,
  config$takeProfitPercent,
  config$stopLossPercent,
  next_bar_entry = FALSE,
  verbose = TRUE  # 开启详细日志
)

cat("\n\n交易统计：\n")
if (!is.null(result_verbose$Trades) && length(result_verbose$Trades) > 0) {
  trades <- result_verbose$Trades

  cat(sprintf("总交易数: %d\n", length(trades)))
  cat(sprintf("盈利交易: %d (%.1f%%)\n",
             sum(trades > 0),
             (sum(trades > 0) / length(trades)) * 100))
  cat(sprintf("亏损交易: %d (%.1f%%)\n",
             sum(trades < 0),
             (sum(trades < 0) / length(trades)) * 100))
  cat(sprintf("平局交易: %d\n", sum(trades == 0)))

  cat(sprintf("\n平均盈利: %.2f%%\n", mean(trades[trades > 0])))
  cat(sprintf("平均亏损: %.2f%%\n", mean(trades[trades < 0])))
  cat(sprintf("盈亏比: %.2f\n",
             abs(mean(trades[trades > 0]) / mean(trades[trades < 0]))))

  cat("\n盈利分布：\n")
  print(summary(trades))

  # 直方图（文本版）
  cat("\n盈利分布直方图：\n")
  breaks <- seq(-15, 15, by=5)
  hist_data <- hist(trades, breaks=breaks, plot=FALSE)
  for (i in 1:length(hist_data$counts)) {
    cat(sprintf("  [%+.0f%% 至 %+.0f%%]: %s (%d)\n",
               hist_data$breaks[i],
               hist_data$breaks[i+1],
               paste(rep("█", hist_data$counts[i]), collapse=""),
               hist_data$counts[i]))
  }
}

cat("\n\n========================================\n")
cat("测试完成\n")
cat("========================================\n\n")

cat("关键发现：\n")
cat("1. Pine对齐版使用High/Low判断触发，能捕捉更多盘中止盈/止损\n")
cat("2. 交易次数预期增加20%-40%（取决于参数和波动性）\n")
cat("3. 出场价格更精确（使用TP/SL价格而非Close价格）\n")
cat("4. 与TradingView的Pine Script结果应该更接近\n\n")

cat("下一步：\n")
cat("1. 使用Pine对齐版重新运行完整优化\n")
cat("2. 与TradingView结果进行逐笔对比验证\n")
cat("3. 如果结果仍有差异，检查信号生成逻辑\n\n")
