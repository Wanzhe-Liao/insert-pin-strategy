# ========================================
# PEPEUSDT 数据深度分析和信号调试
# ========================================
# 目标: 完整诊断信号生成逻辑,对齐Pine Script行为

library(xts)

cat("=" , rep("=", 70), "=\n", sep="")
cat("  PEPEUSDT 综合数据分析和信号生成调试\n")
cat("=" , rep("=", 70), "=\n\n", sep="")

# 加载数据
load("data/liaochu.RData")

# ========================================
# 任务 1: 数据基础统计
# ========================================
cat("\n[任务 1] 数据基础统计\n")
cat(rep("-", 80), "\n", sep="")

pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat("发现的PEPEUSDT时间框架:", length(pepe_symbols), "个\n")
cat("时间框架列表:", paste(pepe_symbols, collapse=", "), "\n\n")

# 详细分析每个时间框架
for (symbol in pepe_symbols) {
  data <- cryptodata[[symbol]]

  cat(sprintf("\n--- %s ---\n", symbol))
  cat(sprintf("  总行数: %d\n", nrow(data)))

  if (nrow(data) > 0) {
    # 时间范围
    time_idx <- index(data)
    cat(sprintf("  时间范围: %s 至 %s\n",
                as.character(time_idx[1]),
                as.character(time_idx[length(time_idx)])))

    # 计算实际时间间隔
    if (nrow(data) > 1) {
      time_diffs <- as.numeric(difftime(time_idx[2:min(100, length(time_idx))],
                                       time_idx[1:min(99, length(time_idx)-1)],
                                       units="mins"))
      avg_interval <- median(time_diffs, na.rm=TRUE)
      cat(sprintf("  实际平均时间间隔: %.2f 分钟\n", avg_interval))

      # 验证时间框架名称
      expected_interval <- switch(symbol,
        "PEPEUSDT_5m" = 5,
        "PEPEUSDT_15m" = 15,
        "PEPEUSDT_30m" = 30,
        "PEPEUSDT_1h" = 60,
        NA
      )

      if (!is.na(expected_interval)) {
        if (abs(avg_interval - expected_interval) < 1) {
          cat(sprintf("  验证结果: PASS (与预期%d分钟一致)\n", expected_interval))
        } else {
          cat(sprintf("  验证结果: WARNING (预期%d分钟,实际%.2f分钟)\n",
                     expected_interval, avg_interval))
        }
      }
    }

    # 数据完整性检查
    na_open <- sum(is.na(data$Open))
    na_high <- sum(is.na(data$High))
    na_low <- sum(is.na(data$Low))
    na_close <- sum(is.na(data$Close))

    cat(sprintf("  NA值统计: Open=%d, High=%d, Low=%d, Close=%d\n",
               na_open, na_high, na_low, na_close))

    # 价格统计
    cat(sprintf("  价格范围:\n"))
    cat(sprintf("    最高价: %.8f - %.8f\n",
               min(data$High, na.rm=TRUE), max(data$High, na.rm=TRUE)))
    cat(sprintf("    最低价: %.8f - %.8f\n",
               min(data$Low, na.rm=TRUE), max(data$Low, na.rm=TRUE)))

    # 计算理论上3天对应的bar数
    if (nrow(data) > 1) {
      bars_per_day <- 1440 / avg_interval  # 1440分钟/天
      cat(sprintf("  每天理论bar数: %.0f (3天 = %.0f bars)\n",
                 bars_per_day, bars_per_day * 3))
    }
  }
}

# ========================================
# 任务 2: Pine Script逻辑的精确实现
# ========================================
cat("\n\n[任务 2] Pine Script 精确逻辑实现测试\n")
cat(rep("-", 80), "\n", sep="")

cat("\nPine Script 原始逻辑:\n")
cat("  lookbackDays = input.int(3)\n")
cat("  minDropPercent = input.float(20)\n")
cat("  highestHighPrev = ta.highest(high, lookbackDays)[1]\n")
cat("  percentDrop = (highestHighPrev - low) / highestHighPrev * 100\n")
cat("  longSignal = percentDrop >= minDropPercent\n\n")

# 实现方式1: 直接使用bar数(当前R代码的做法)
signal_method_1 <- function(data, lookbackBars, minDropPercent) {
  n <- nrow(data)
  signals <- rep(FALSE, n)

  if (n < lookbackBars + 1) return(signals)

  for (i in (lookbackBars + 1):n) {
    # 回看窗口: [i-lookbackBars, i-1]
    window_high <- max(data$High[(i-lookbackBars):(i-1)], na.rm=TRUE)
    current_low <- data$Low[i]

    if (!is.na(window_high) && !is.na(current_low) && window_high > 0) {
      drop_percent <- (window_high - current_low) / window_high * 100
      if (drop_percent >= minDropPercent) {
        signals[i] <- TRUE
      }
    }
  }

  return(signals)
}

# 实现方式2: 转换为实际天数(更符合Pine Script语义)
signal_method_2 <- function(data, lookbackDays, minDropPercent, bars_per_day) {
  lookbackBars <- as.integer(lookbackDays * bars_per_day)
  return(signal_method_1(data, lookbackBars, minDropPercent))
}

# 测试两种方法的差异
test_symbol <- "PEPEUSDT_15m"
if (test_symbol %in% pepe_symbols) {
  data <- cryptodata[[test_symbol]]

  cat(sprintf("\n使用 %s 进行测试 (共%d行数据)\n", test_symbol, nrow(data)))

  # 计算时间间隔
  time_idx <- index(data)
  time_diffs <- as.numeric(difftime(time_idx[2:min(100, length(time_idx))],
                                   time_idx[1:min(99, length(time_idx)-1)],
                                   units="mins"))
  avg_interval <- median(time_diffs, na.rm=TRUE)
  bars_per_day <- 1440 / avg_interval

  cat(sprintf("平均时间间隔: %.2f 分钟\n", avg_interval))
  cat(sprintf("每天bar数: %.0f\n\n", bars_per_day))

  # 测试参数组合
  test_params <- data.frame(
    lookback = c(3, 3, 5, 7),
    drop = c(5, 20, 10, 15),
    description = c(
      "lookback=3bars, drop=5%",
      "lookback=3bars, drop=20%",
      "lookback=5bars, drop=10%",
      "lookback=7bars, drop=15%"
    ),
    stringsAsFactors = FALSE
  )

  cat("方法1: 直接使用bar数(当前R代码逻辑)\n")
  cat(rep("-", 60), "\n", sep="")
  for (i in 1:nrow(test_params)) {
    signals <- signal_method_1(data, test_params$lookback[i], test_params$drop[i])
    signal_count <- sum(signals, na.rm=TRUE)

    cat(sprintf("  %s: %d 个信号 (%.2f%%)\n",
               test_params$description[i],
               signal_count,
               signal_count / nrow(data) * 100))

    if (signal_count > 0) {
      signal_idx <- which(signals)
      cat(sprintf("    首个信号位置: bar %d (时间: %s)\n",
                 signal_idx[1], as.character(time_idx[signal_idx[1]])))

      # 显示详细信息
      idx <- signal_idx[1]
      window_start <- max(1, idx - test_params$lookback[i])
      window_high <- max(data$High[window_start:(idx-1)], na.rm=TRUE)
      current_low <- data$Low[idx]
      drop <- (window_high - current_low) / window_high * 100

      cat(sprintf("    窗口: [%d:%d], 最高价=%.8f, 当前最低=%.8f, 跌幅=%.2f%%\n",
                 window_start, idx-1, window_high, current_low, drop))
    }
  }

  cat("\n方法2: 转换为实际天数(Pine Script语义)\n")
  cat(rep("-", 60), "\n", sep="")
  for (i in 1:nrow(test_params)) {
    signals <- signal_method_2(data, test_params$lookback[i], test_params$drop[i], bars_per_day)
    signal_count <- sum(signals, na.rm=TRUE)
    lookbackBars <- as.integer(test_params$lookback[i] * bars_per_day)

    cat(sprintf("  %s天 (=%d bars), drop=%.0f%%: %d 个信号 (%.2f%%)\n",
               test_params$lookback[i],
               lookbackBars,
               test_params$drop[i],
               signal_count,
               signal_count / nrow(data) * 100))

    if (signal_count > 0) {
      signal_idx <- which(signals)
      cat(sprintf("    首个信号位置: bar %d (时间: %s)\n",
                 signal_idx[1], as.character(time_idx[signal_idx[1]])))
    }
  }
}

# ========================================
# 任务 3: 标准测试 - lookbackDays=3, minDropPercent=20
# ========================================
cat("\n\n[任务 3] 标准测试: lookbackDays=3, minDropPercent=20\n")
cat(rep("-", 80), "\n", sep="")

cat("\n这是Pine Script默认参数,我们对比两种实现:\n\n")

for (symbol in pepe_symbols) {
  data <- cryptodata[[symbol]]

  if (nrow(data) < 10) {
    cat(sprintf("%s: 数据不足,跳过\n", symbol))
    next
  }

  # 计算时间间隔
  time_idx <- index(data)
  if (nrow(data) > 1) {
    time_diffs <- as.numeric(difftime(time_idx[2:min(100, length(time_idx))],
                                     time_idx[1:min(99, length(time_idx)-1)],
                                     units="mins"))
    avg_interval <- median(time_diffs, na.rm=TRUE)
    bars_per_day <- 1440 / avg_interval
  } else {
    bars_per_day <- NA
  }

  # 方法1: 直接3个bar
  sig1 <- signal_method_1(data, 3, 20)
  count1 <- sum(sig1, na.rm=TRUE)

  # 方法2: 3天
  sig2 <- if (!is.na(bars_per_day)) {
    signal_method_2(data, 3, 20, bars_per_day)
  } else {
    rep(FALSE, nrow(data))
  }
  count2 <- sum(sig2, na.rm=TRUE)

  cat(sprintf("%s (总%d bars):\n", symbol, nrow(data)))
  cat(sprintf("  方法1 (3 bars回看): %d 信号\n", count1))
  if (!is.na(bars_per_day)) {
    cat(sprintf("  方法2 (3天=%d bars回看): %d 信号\n",
               as.integer(3 * bars_per_day), count2))
  }
  cat("\n")
}

# ========================================
# 任务 4: 回测逻辑验证
# ========================================
cat("\n[任务 4] 回测逻辑验证 - 为什么Trade_Count=0?\n")
cat(rep("-", 80), "\n", sep="")

# 简化的回测函数,添加详细日志
backtest_with_logging <- function(data, signals, takeProfitPercent, stopLossPercent,
                                  max_log_trades = 5) {
  capital <- 10000
  position <- 0
  entry_price <- NA
  trades <- numeric(0)

  signal_count <- sum(signals, na.rm=TRUE)
  cat(sprintf("  总信号数: %d\n", signal_count))

  logged_trades <- 0

  for (i in 1:nrow(data)) {
    # 入场逻辑
    if (signals[i] && position == 0) {
      entry_price <- as.numeric(data$Close[i])

      if (!is.na(entry_price) && entry_price > 0) {
        position <- capital / entry_price
        capital <- 0

        if (logged_trades < max_log_trades) {
          cat(sprintf("  [Bar %d] 入场: 价格=%.8f, 仓位=%.2f\n",
                     i, entry_price, position))
          logged_trades <- logged_trades + 1
        }
      }
    }

    # 出场逻辑
    if (position > 0) {
      current_price <- as.numeric(data$Close[i])

      if (!is.na(current_price) && current_price > 0 && !is.na(entry_price) && entry_price > 0) {
        pnl_percent <- (current_price - entry_price) / entry_price * 100

        # 检查止盈止损
        if (pnl_percent >= takeProfitPercent || pnl_percent <= -stopLossPercent) {
          exit_capital <- position * current_price
          trades <- c(trades, pnl_percent)

          if (length(trades) <= max_log_trades) {
            cat(sprintf("  [Bar %d] 出场: 价格=%.8f, 盈亏=%.2f%%, 原因=%s\n",
                       i, current_price, pnl_percent,
                       ifelse(pnl_percent >= takeProfitPercent, "止盈", "止损")))
          }

          capital <- exit_capital
          position <- 0
          entry_price <- NA
        }
      }
    }
  }

  # 未平仓处理
  if (position > 0) {
    final_price <- as.numeric(data$Close[nrow(data)])
    if (!is.na(final_price) && final_price > 0 && !is.na(entry_price) && entry_price > 0) {
      final_pnl <- (final_price - entry_price) / entry_price * 100
      trades <- c(trades, final_pnl)
      capital <- position * final_price
      cat(sprintf("  [最后] 强制平仓: 价格=%.8f, 盈亏=%.2f%%\n",
                 final_price, final_pnl))
    }
  }

  cat(sprintf("  最终交易次数: %d\n", length(trades)))
  if (length(trades) > 0) {
    cat(sprintf("  最终资金: %.2f\n", capital))
    cat(sprintf("  总收益率: %.2f%%\n", (capital - 10000) / 10000 * 100))
  }

  return(list(
    trade_count = length(trades),
    final_capital = capital,
    trades = trades
  ))
}

# 测试PEPEUSDT_15m
test_symbol <- "PEPEUSDT_15m"
if (test_symbol %in% pepe_symbols) {
  cat(sprintf("\n使用 %s 进行回测测试\n", test_symbol))
  data <- cryptodata[[test_symbol]]

  # 生成信号 (方法1: 3 bars, 5% drop)
  cat("\n测试1: lookback=3 bars, drop=5%, TP/SL=6%\n")
  signals <- signal_method_1(data, 3, 5)
  result <- backtest_with_logging(data, signals, 6, 6, max_log_trades=10)

  # 生成信号 (方法1: 3 bars, 20% drop)
  cat("\n测试2: lookback=3 bars, drop=20%, TP/SL=6%\n")
  signals <- signal_method_1(data, 3, 20)
  result <- backtest_with_logging(data, signals, 6, 6, max_log_trades=10)
}

# ========================================
# 任务 5: 对比pepe_results.csv
# ========================================
cat("\n\n[任务 5] 对比 pepe_results.csv 中的结果\n")
cat(rep("-", 80), "\n", sep="")

pepe_results_file <- "outputs/pepe_results.csv"
if (file.exists(pepe_results_file)) {
  pepe_results <- read.csv(pepe_results_file, stringsAsFactors=FALSE)

  cat(sprintf("pepe_results.csv 总行数: %d\n", nrow(pepe_results)))

  # 统计分析
  cat("\n信号统计:\n")
  cat(sprintf("  Signal_Count > 0: %d 行\n", sum(pepe_results$Signal_Count > 0, na.rm=TRUE)))
  cat(sprintf("  Trade_Count > 0: %d 行\n", sum(pepe_results$Trade_Count > 0, na.rm=TRUE)))
  cat(sprintf("  Trade_Count = 0 但 Signal_Count > 0: %d 行\n",
             sum(pepe_results$Trade_Count == 0 & pepe_results$Signal_Count > 0, na.rm=TRUE)))

  # 显示几个异常案例
  cat("\n异常案例 (有信号但无交易):\n")
  anomalies <- pepe_results[pepe_results$Signal_Count > 0 & pepe_results$Trade_Count == 0, ]
  if (nrow(anomalies) > 0) {
    print(head(anomalies[, c("Symbol", "lookbackDays", "minDropPercent",
                            "takeProfitPercent", "stopLossPercent", "Signal_Count")], 10))

    # 手动验证第一个异常案例
    if (nrow(anomalies) > 0) {
      test_case <- anomalies[1, ]
      cat(sprintf("\n手动验证案例: %s\n", test_case$Symbol))
      cat(sprintf("  参数: lookback=%d, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n",
                 test_case$lookbackDays, test_case$minDropPercent,
                 test_case$takeProfitPercent, test_case$stopLossPercent))

      if (test_case$Symbol %in% pepe_symbols) {
        data <- cryptodata[[test_case$Symbol]]
        signals <- signal_method_1(data, test_case$lookbackDays, test_case$minDropPercent)

        cat(sprintf("  重新计算信号数: %d (原记录: %d)\n",
                   sum(signals), test_case$Signal_Count))

        cat("\n  执行回测:\n")
        result <- backtest_with_logging(data, signals,
                                       test_case$takeProfitPercent,
                                       test_case$stopLossPercent,
                                       max_log_trades=5)
      }
    }
  }
} else {
  cat("文件不存在:", pepe_results_file, "\n")
}

# ========================================
# 任务 6: 总结和建议
# ========================================
cat("\n\n[任务 6] 总结和建议\n")
cat(rep("=", 80), "\n", sep="")

cat("\n关键发现:\n")
cat("1. lookbackDays参数语义问题:\n")
cat("   - Pine Script: lookbackDays=3 表示3天的历史数据\n")
cat("   - 当前R代码: 直接作为bar数使用,导致回看窗口过小\n")
cat("   - 建议: 根据时间框架转换为实际bar数\n\n")

cat("2. Trade_Count=0的可能原因:\n")
cat("   - 止盈止损设置过于宽松/严格\n")
cat("   - 信号生成后立即触发止损\n")
cat("   - 数据质量问题(NA值)\n")
cat("   - 入场价格计算错误\n\n")

cat("3. 建议改进:\n")
cat("   a) 修正lookbackDays转换逻辑\n")
cat("   b) 添加详细的交易日志\n")
cat("   c) 验证止盈止损触发条件\n")
cat("   d) 检查价格数据完整性\n")
cat("   e) 对比Pine Script的实际交易记录\n\n")

cat("分析完成!\n")
cat(rep("=", 80), "\n", sep="")
