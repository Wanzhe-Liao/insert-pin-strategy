# PEPEUSDT修正版测试脚本
# 用于快速验证lookbackDays修复是否有效
#
# 测试目标：
# 1. 对比原始方法和修正方法的信号数量
# 2. 验证Trade_Count从0变为正常值
# 3. 输出详细的调试信息

suppressMessages({
  library(xts)
})

cat("=== PEPEUSDT修正版测试 ===\n\n")

# 加载数据
cat("加载数据...\n")
load("data/liaochu.RData")

# 获取PEPEUSDT数据
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat("找到PEPEUSDT时间框架:", paste(pepe_symbols, collapse=", "), "\n\n")

# 测试参数（与Pine Script对齐）
TEST_PARAMS <- list(
  lookbackDays = 3,
  minDropPercent = 20.0,
  takeProfitPercent = 10.0,
  stopLossPercent = 10.0
)

cat("测试参数:\n")
cat(sprintf("  lookbackDays = %d\n", TEST_PARAMS$lookbackDays))
cat(sprintf("  minDropPercent = %.1f%%\n", TEST_PARAMS$minDropPercent))
cat(sprintf("  takeProfitPercent = %.1f%%\n", TEST_PARAMS$takeProfitPercent))
cat(sprintf("  stopLossPercent = %.1f%%\n\n", TEST_PARAMS$stopLossPercent))

# ============================================================================
# 原始方法（错误的）- 直接使用lookbackDays作为bar数
# ============================================================================

build_signals_original <- function(data, lookbackDays, minDropPercent) {
  if (nrow(data) < lookbackDays + 1) {
    return(rep(FALSE, nrow(data)))
  }

  lookbackBars <- lookbackDays  # 错误：直接使用天数作为bar数
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

# ============================================================================
# 修正方法（正确的）- 根据时间框架转换天数为bar数
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

  # 检测时间框架
  tf_minutes <- detect_timeframe_minutes(data)
  if (is.na(tf_minutes) || tf_minutes <= 0) {
    tf_minutes <- 15
  }

  # 正确转换：lookbackDays（天） → lookbackBars（根K线）
  bars_per_day <- 1440 / tf_minutes
  lookbackBars <- as.integer(lookbackDays * bars_per_day)

  cat(sprintf("    时间框架: %d分钟\n", tf_minutes))
  cat(sprintf("    每天K线数: %.0f根\n", bars_per_day))
  cat(sprintf("    lookbackDays=%d天 → lookbackBars=%d根K线\n",
              lookbackDays, lookbackBars))

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

# ============================================================================
# 简单回测函数
# ============================================================================

simple_backtest <- function(data, signals, takeProfitPercent, stopLossPercent, next_bar_entry = FALSE) {
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

  return_pct <- ((capital - 10000) / 10000) * 100
  win_rate <- if (length(trades) > 0) sum(trades > 0) / length(trades) * 100 else 0

  return(list(
    Trade_Count = length(trades),
    Return_Percentage = return_pct,
    Win_Rate = win_rate,
    Trades = trades
  ))
}

# ============================================================================
# 对每个时间框架进行测试
# ============================================================================

cat("\n" , rep("=", 70), "\n", sep="")

for (symbol in pepe_symbols) {
  cat("\n测试标的:", symbol, "\n")
  cat(rep("-", 70), "\n", sep="")

  data <- cryptodata[[symbol]]
  cat(sprintf("数据行数: %d\n", nrow(data)))
  cat(sprintf("时间范围: %s 至 %s\n",
              format(index(data)[1], "%Y-%m-%d %H:%M"),
              format(index(data)[nrow(data)], "%Y-%m-%d %H:%M")))
  cat("\n")

  # 测试原始方法
  cat("  [1] 原始方法（错误）:\n")
  cat(sprintf("    lookbackDays=%d → 直接作为%d根K线使用\n",
              TEST_PARAMS$lookbackDays, TEST_PARAMS$lookbackDays))

  signals_original <- build_signals_original(
    data,
    TEST_PARAMS$lookbackDays,
    TEST_PARAMS$minDropPercent
  )
  signal_count_original <- sum(signals_original, na.rm = TRUE)
  cat(sprintf("    信号数: %d\n", signal_count_original))

  if (signal_count_original > 0) {
    bt_original <- simple_backtest(
      data, signals_original,
      TEST_PARAMS$takeProfitPercent,
      TEST_PARAMS$stopLossPercent,
      next_bar_entry = FALSE
    )
    cat(sprintf("    交易数: %d\n", bt_original$Trade_Count))
    cat(sprintf("    收益率: %.2f%%\n", bt_original$Return_Percentage))
    if (bt_original$Trade_Count > 0) {
      cat(sprintf("    胜率: %.1f%%\n", bt_original$Win_Rate))
    }
  } else {
    cat("    交易数: 0 (无信号)\n")
  }

  cat("\n")

  # 测试修正方法
  cat("  [2] 修正方法（正确）:\n")
  signals_fixed <- build_signals_fixed(
    data,
    TEST_PARAMS$lookbackDays,
    TEST_PARAMS$minDropPercent
  )
  signal_count_fixed <- sum(signals_fixed, na.rm = TRUE)
  cat(sprintf("    信号数: %d\n", signal_count_fixed))

  if (signal_count_fixed > 0) {
    bt_fixed <- simple_backtest(
      data, signals_fixed,
      TEST_PARAMS$takeProfitPercent,
      TEST_PARAMS$stopLossPercent,
      next_bar_entry = FALSE
    )
    cat(sprintf("    交易数: %d\n", bt_fixed$Trade_Count))
    cat(sprintf("    收益率: %.2f%%\n", bt_fixed$Return_Percentage))
    if (bt_fixed$Trade_Count > 0) {
      cat(sprintf("    胜率: %.1f%%\n", bt_fixed$Win_Rate))
    }

    # 显示前5个信号的详细信息
    signal_indices <- which(signals_fixed)
    if (length(signal_indices) > 0) {
      cat("\n    前5个信号详情:\n")
      for (idx in head(signal_indices, 5)) {
        cat(sprintf("      [%d] %s | High=%.8f Low=%.8f Close=%.8f\n",
                    idx,
                    format(index(data)[idx], "%Y-%m-%d %H:%M"),
                    as.numeric(data[idx, "High"]),
                    as.numeric(data[idx, "Low"]),
                    as.numeric(data[idx, "Close"])))
      }
    }
  } else {
    cat("    交易数: 0 (无信号)\n")
  }

  cat("\n")

  # 对比分析
  cat("  [对比分析]:\n")
  signal_diff <- signal_count_fixed - signal_count_original
  cat(sprintf("    信号数变化: %d → %d (%+d, %.1f%%变化)\n",
              signal_count_original, signal_count_fixed, signal_diff,
              if (signal_count_original > 0) signal_diff / signal_count_original * 100 else NA))

  if (signal_count_original > 0 && signal_count_fixed > 0) {
    trade_diff <- bt_fixed$Trade_Count - bt_original$Trade_Count
    cat(sprintf("    交易数变化: %d → %d (%+d)\n",
                bt_original$Trade_Count, bt_fixed$Trade_Count, trade_diff))

    return_diff <- bt_fixed$Return_Percentage - bt_original$Return_Percentage
    cat(sprintf("    收益率变化: %.2f%% → %.2f%% (%+.2f%%)\n",
                bt_original$Return_Percentage, bt_fixed$Return_Percentage, return_diff))
  }

  cat("\n", rep("=", 70), "\n", sep="")
}

# ============================================================================
# 总结
# ============================================================================

cat("\n=== 测试总结 ===\n\n")

cat("核心修复说明:\n")
cat("  1. 原始方法: lookbackDays=3 被错误地当作3根K线\n")
cat("  2. 修正方法: lookbackDays=3 正确转换为实际天数对应的K线数\n")
cat("     - 15分钟图: 3天 = 288根K线\n")
cat("     - 1小时图: 3天 = 72根K线\n")
cat("     - 5分钟图: 3天 = 864根K线\n\n")

cat("预期效果:\n")
cat("  1. 修正后信号数应该显著减少（窗口变大，条件更严格）\n")
cat("  2. 修正后的结果应该与Pine Script更接近\n")
cat("  3. Trade_Count应该从0变为正常值\n\n")

cat("下一步:\n")
cat("  如果测试结果符合预期，请运行完整优化:\n")
cat("  source('optimize_pepe_fixed.R')\n\n")
