# PEPEUSDT快速测试 - 10个参数组合
# 用于验证修正版脚本是否可行，重点检查是否有交易

suppressMessages({
  library(xts)
})

cat("=== PEPEUSDT 10参数组合快速测试 ===\n\n")

# 加载数据
cat("加载数据...\n")
load("data/liaochu.RData")

# 获取PEPEUSDT数据
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat("找到PEPEUSDT时间框架:", paste(pepe_symbols, collapse=", "), "\n\n")

# ============================================================================
# 定义10个测试参数组合（覆盖不同场景）
# ============================================================================

test_params <- data.frame(
  No = 1:10,
  lookbackDays = c(3, 3, 3, 4, 4, 5, 5, 6, 7, 3),
  minDropPercent = c(10, 15, 20, 10, 15, 10, 20, 15, 10, 25),
  takeProfitPercent = c(10, 10, 10, 12, 12, 15, 15, 10, 10, 8),
  stopLossPercent = c(10, 10, 10, 12, 12, 15, 15, 10, 10, 8),
  stringsAsFactors = FALSE
)

cat("测试参数组合（10个）:\n")
print(test_params)
cat("\n")

# ============================================================================
# 辅助函数
# ============================================================================

detect_timeframe_minutes <- function(xts_data) {
  if (nrow(xts_data) < 2) return(NA)
  n_samples <- min(100, nrow(xts_data) - 1)
  time_diffs <- as.numeric(difftime(index(xts_data)[2:(n_samples+1)],
                                     index(xts_data)[1:n_samples],
                                     units = "mins"))
  tf_minutes <- median(time_diffs, na.rm = TRUE)
  return(round(tf_minutes))
}

build_signals_fixed <- function(data, lookbackDays, minDropPercent) {
  if (nrow(data) < 10) {
    return(rep(FALSE, nrow(data)))
  }

  # 检测时间框架并转换
  tf_minutes <- detect_timeframe_minutes(data)
  if (is.na(tf_minutes) || tf_minutes <= 0) {
    tf_minutes <- 15
  }

  bars_per_day <- 1440 / tf_minutes
  lookbackBars <- as.integer(lookbackDays * bars_per_day)

  if (nrow(data) <= lookbackBars) {
    return(rep(FALSE, nrow(data)))
  }

  signals <- rep(FALSE, nrow(data))
  high_prices <- as.numeric(data[, "High"])
  low_prices <- as.numeric(data[, "Low"])

  for (i in (lookbackBars + 1):nrow(data)) {
    window_start <- max(1, i - lookbackBars)
    window_end <- i - 1

    window_high <- max(high_prices[window_start:window_end], na.rm = TRUE)
    current_low <- low_prices[i]

    if (!is.na(window_high) && !is.na(current_low) && window_high > 0) {
      drop_percent <- ((window_high - current_low) / window_high) * 100
      if (drop_percent >= minDropPercent) {
        signals[i] <- TRUE
      }
    }
  }

  return(signals)
}

backtest_strategy <- function(data, lookbackDays, minDropPercent,
                              takeProfitPercent, stopLossPercent,
                              next_bar_entry = FALSE) {
  tryCatch({
    if (nrow(data) < 10) {
      return(list(
        Signal_Count = 0, Trade_Count = 0, Final_Capital = NA,
        Return_Percentage = NA, Win_Rate = NA, Error = "数据不足"
      ))
    }

    # 生成信号
    signals <- build_signals_fixed(data, lookbackDays, minDropPercent)
    signal_count <- sum(signals, na.rm = TRUE)

    if (signal_count == 0) {
      return(list(
        Signal_Count = 0, Trade_Count = 0, Final_Capital = NA,
        Return_Percentage = NA, Win_Rate = NA, Error = "无信号"
      ))
    }

    # 回测
    capital <- 10000
    position <- 0
    entry_price <- 0
    trades <- c()

    for (i in 1:nrow(data)) {
      # 入场
      if (signals[i] && position == 0) {
        if (next_bar_entry && i < nrow(data)) {
          entry_price <- as.numeric(data[i+1, "Open"])
        } else {
          entry_price <- as.numeric(data[i, "Close"])
        }

        if (!is.na(entry_price) && entry_price > 0) {
          position <- capital / entry_price
          capital <- 0
        }
      }

      # 持仓管理
      if (position > 0) {
        current_price <- as.numeric(data[i, "Close"])

        if (!is.na(current_price) && current_price > 0 && entry_price > 0) {
          pnl_percent <- ((current_price - entry_price) / entry_price) * 100

          if (pnl_percent >= takeProfitPercent || pnl_percent <= -stopLossPercent) {
            exit_capital <- position * current_price
            trades <- c(trades, pnl_percent)
            capital <- exit_capital
            position <- 0
            entry_price <- 0
          }
        }
      }
    }

    # 未平仓处理
    if (position > 0) {
      final_price <- as.numeric(data[nrow(data), "Close"])
      if (!is.na(final_price) && final_price > 0) {
        final_pnl <- ((final_price - entry_price) / entry_price) * 100
        trades <- c(trades, final_pnl)
        capital <- position * final_price
      }
    }

    # 计算指标
    final_capital <- capital
    return_pct <- ((final_capital - 10000) / 10000) * 100
    win_rate <- if (length(trades) > 0) sum(trades > 0) / length(trades) * 100 else 0

    return(list(
      Signal_Count = signal_count,
      Trade_Count = length(trades),
      Final_Capital = final_capital,
      Return_Percentage = return_pct,
      Win_Rate = win_rate,
      Error = NA
    ))

  }, error = function(e) {
    return(list(
      Signal_Count = 0, Trade_Count = 0, Final_Capital = NA,
      Return_Percentage = NA, Win_Rate = NA, Error = as.character(e$message)
    ))
  })
}

# ============================================================================
# 执行测试
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("开始测试...\n")
cat(rep("=", 80), "\n\n", sep="")

all_results <- list()
test_no <- 0

for (symbol in pepe_symbols) {
  cat("测试标的:", symbol, "\n")
  cat(rep("-", 80), "\n", sep="")

  data <- cryptodata[[symbol]]
  cat(sprintf("数据行数: %d | 时间范围: %s 至 %s\n",
              nrow(data),
              format(index(data)[1], "%Y-%m-%d %H:%M"),
              format(index(data)[nrow(data)], "%Y-%m-%d %H:%M")))

  # 检测时间框架
  tf_mins <- detect_timeframe_minutes(data)
  cat(sprintf("时间框架: %d分钟\n\n", tf_mins))

  for (i in 1:nrow(test_params)) {
    test_no <- test_no + 1
    params <- test_params[i, ]

    cat(sprintf("  [%d/%d] 参数组合%d: lookback=%d天, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n",
                test_no, nrow(test_params) * length(pepe_symbols),
                params$No, params$lookbackDays, params$minDropPercent,
                params$takeProfitPercent, params$stopLossPercent))

    # 执行回测
    result <- backtest_strategy(
      data,
      params$lookbackDays,
      params$minDropPercent,
      params$takeProfitPercent,
      params$stopLossPercent,
      next_bar_entry = FALSE  # 对齐Pine Script
    )

    # 输出结果
    cat(sprintf("    信号数: %d | 交易数: %d",
                result$Signal_Count, result$Trade_Count))

    if (result$Trade_Count > 0) {
      cat(sprintf(" | 收益: %.2f%% | 胜率: %.1f%% OK\n",
                  result$Return_Percentage, result$Win_Rate))
    } else if (result$Signal_Count > 0) {
      cat(" | 有信号但无交易 WARN\n")
    } else {
      cat(" | 无信号 WARN\n")
    }

    if (!is.na(result$Error)) {
      cat(sprintf("    错误: %s\n", result$Error))
    }

    # 保存结果
    all_results[[length(all_results) + 1]] <- data.frame(
      Test_No = test_no,
      Symbol = symbol,
      Timeframe = sprintf("%dm", tf_mins),
      lookbackDays = params$lookbackDays,
      minDropPercent = params$minDropPercent,
      takeProfitPercent = params$takeProfitPercent,
      stopLossPercent = params$stopLossPercent,
      Signal_Count = result$Signal_Count,
      Trade_Count = result$Trade_Count,
      Final_Capital = result$Final_Capital,
      Return_Percentage = result$Return_Percentage,
      Win_Rate = result$Win_Rate,
      Error = ifelse(is.na(result$Error), "", result$Error),
      stringsAsFactors = FALSE
    )
  }

  cat("\n")
}

# ============================================================================
# 结果汇总
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("测试完成！\n")
cat(rep("=", 80), "\n\n", sep="")

# 合并结果
results_df <- do.call(rbind, all_results)

# 保存CSV
output_file <- "quick_test_10params_results.csv"
write.csv(results_df, output_file, row.names = FALSE)
cat("结果已保存到:", output_file, "\n\n")

# 统计分析
cat("=== 统计摘要 ===\n\n")

total_tests <- nrow(results_df)
tests_with_signals <- sum(results_df$Signal_Count > 0)
tests_with_trades <- sum(results_df$Trade_Count > 0)
tests_profitable <- sum(results_df$Return_Percentage > 0, na.rm = TRUE)

cat(sprintf("总测试数: %d\n", total_tests))
cat(sprintf("有信号的测试: %d (%.1f%%)\n",
            tests_with_signals, tests_with_signals/total_tests*100))
cat(sprintf("有交易的测试: %d (%.1f%%) OK\n",
            tests_with_trades, tests_with_trades/total_tests*100))
cat(sprintf("盈利的测试: %d (%.1f%%)\n",
            tests_profitable, tests_profitable/total_tests*100))

cat("\n")

if (tests_with_trades > 0) {
  valid_results <- results_df[results_df$Trade_Count > 0, ]

  cat("=== 有交易的测试详情 ===\n\n")
  cat(sprintf("平均信号数: %.1f\n", mean(valid_results$Signal_Count)))
  cat(sprintf("平均交易数: %.1f\n", mean(valid_results$Trade_Count)))
  cat(sprintf("平均收益率: %.2f%%\n", mean(valid_results$Return_Percentage, na.rm = TRUE)))
  cat(sprintf("平均胜率: %.1f%%\n", mean(valid_results$Win_Rate, na.rm = TRUE)))
  cat(sprintf("最佳收益率: %.2f%%\n", max(valid_results$Return_Percentage, na.rm = TRUE)))
  cat(sprintf("最差收益率: %.2f%%\n", min(valid_results$Return_Percentage, na.rm = TRUE)))

  cat("\n=== 最佳参数组合 ===\n")
  best_idx <- which.max(valid_results$Return_Percentage)
  best <- valid_results[best_idx, ]

  cat(sprintf("\n标的: %s\n", best$Symbol))
  cat(sprintf("参数: lookback=%d天, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n",
              best$lookbackDays, best$minDropPercent,
              best$takeProfitPercent, best$stopLossPercent))
  cat(sprintf("表现: 信号=%d, 交易=%d, 收益=%.2f%%, 胜率=%.1f%%\n",
              best$Signal_Count, best$Trade_Count,
              best$Return_Percentage, best$Win_Rate))

  cat("\n=== 按时间框架分组 ===\n")
  for (tf in unique(results_df$Timeframe)) {
    tf_data <- results_df[results_df$Timeframe == tf, ]
    tf_valid <- tf_data[tf_data$Trade_Count > 0, ]

    cat(sprintf("\n%s:\n", tf))
    cat(sprintf("  有交易的组合: %d/%d\n", nrow(tf_valid), nrow(tf_data)))
    if (nrow(tf_valid) > 0) {
      cat(sprintf("  平均收益: %.2f%%\n", mean(tf_valid$Return_Percentage, na.rm = TRUE)))
      cat(sprintf("  平均交易数: %.1f\n", mean(tf_valid$Trade_Count)))
    }
  }
}

cat("\n")

# 结论
cat(rep("=", 80), "\n", sep="")
cat("测试结论\n")
cat(rep("=", 80), "\n\n", sep="")

if (tests_with_trades >= total_tests * 0.8) {
  cat("OK 优秀！超过80%的测试产生了交易，脚本运行正常。\n")
  cat("OK 建议：可以运行完整的参数优化。\n")
} else if (tests_with_trades >= total_tests * 0.5) {
  cat("OK 良好！超过50%的测试产生了交易。\n")
  cat("WARN  建议：检查无交易的参数组合，可能阈值过高。\n")
} else if (tests_with_trades > 0) {
  cat("WARN  警告！只有部分测试产生了交易。\n")
  cat("WARN  建议：调整参数范围，降低minDropPercent阈值。\n")
} else {
  cat("FAIL 错误！所有测试都没有产生交易。\n")
  cat("FAIL 建议：检查脚本逻辑或数据质量。\n")
}

cat("\n下一步操作:\n")
if (tests_with_trades > 0) {
  cat("  1. 查看详细结果: results <- read.csv('quick_test_10params_results.csv')\n")
  cat("  2. 如果满意，运行完整优化: source('optimize_pepe_fixed.R')\n")
} else {
  cat("  1. 检查数据: str(cryptodata$PEPEUSDT_15m)\n")
  cat("  2. 查看错误日志: results_df$Error\n")
}

cat("\n测试完成！\n")
