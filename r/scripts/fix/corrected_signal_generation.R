# ========================================
# 修正后的信号生成脚本
# ========================================
# 核心修正: 正确实现Pine Script的lookbackDays语义
# Pine Script: lookbackDays=3 表示回看3天的数据
# 需要根据时间框架转换为实际bar数

library(xts)

# ========================================
# 修正后的信号生成函数
# ========================================

# 方法1: 原始方法 - 直接使用bar数
build_signals_original <- function(data, lookbackBars, minDropPercent) {
  n <- nrow(data)
  signals <- rep(FALSE, n)

  if (n < lookbackBars + 1) return(signals)

  for (i in (lookbackBars + 1):n) {
    # ta.highest(high, lookbackBars)[1] 的实现
    # [1]表示向前偏移1个bar,所以窗口是[i-lookbackBars, i-1]
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

# 方法2: 修正方法 - 转换lookbackDays为实际bar数
build_signals_corrected <- function(data, lookbackDays, minDropPercent, timeframe_mins) {
  # 计算实际需要回看的bar数
  # lookbackDays=3 表示3天,需要转换为bar数
  bars_per_day <- 1440 / timeframe_mins  # 1440分钟/天
  lookbackBars <- as.integer(lookbackDays * bars_per_day)

  cat(sprintf("  lookbackDays=%d, timeframe=%d分钟 -> lookbackBars=%d\n",
             lookbackDays, timeframe_mins, lookbackBars))

  return(build_signals_original(data, lookbackBars, minDropPercent))
}

# 自动检测时间框架
detect_timeframe <- function(data) {
  if (nrow(data) < 2) return(NA)

  time_idx <- index(data)
  time_diffs <- as.numeric(difftime(time_idx[2:min(100, length(time_idx))],
                                   time_idx[1:min(99, length(time_idx)-1)],
                                   units="mins"))
  avg_interval <- median(time_diffs, na.rm=TRUE)

  return(avg_interval)
}

# ========================================
# 修正后的回测函数
# ========================================

backtest_strategy_corrected <- function(data, lookbackDays, minDropPercent,
                                       takeProfitPercent, stopLossPercent,
                                       use_corrected_method = TRUE,
                                       verbose = FALSE) {
  tryCatch({
    if (nrow(data) < 10) {
      return(list(
        Signal_Count = 0, Trade_Count = 0, Final_Capital = NA,
        Return_Percentage = NA, Max_Drawdown = NA, Win_Rate = NA,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 生成信号
    if (use_corrected_method) {
      timeframe_mins <- detect_timeframe(data)
      if (is.na(timeframe_mins)) {
        return(list(
          Signal_Count = 0, Trade_Count = 0, Final_Capital = NA,
          Return_Percentage = NA, Max_Drawdown = NA, Win_Rate = NA,
          BH_Return = NA, Excess_Return = NA
        ))
      }
      signals <- build_signals_corrected(data, lookbackDays, minDropPercent, timeframe_mins)
    } else {
      signals <- build_signals_original(data, lookbackDays, minDropPercent)
    }

    signal_count <- sum(signals, na.rm=TRUE)

    if (verbose) {
      cat(sprintf("  信号总数: %d (%.2f%%)\n", signal_count, signal_count/nrow(data)*100))
    }

    if (signal_count == 0) {
      return(list(
        Signal_Count = 0, Trade_Count = 0, Final_Capital = NA,
        Return_Percentage = NA, Max_Drawdown = NA, Win_Rate = NA,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 回测逻辑
    capital <- 10000
    position <- 0
    entry_price <- NA
    trades <- numeric(0)
    capital_curve <- numeric(nrow(data))

    for (i in 1:nrow(data)) {
      # 入场
      if (signals[i] && position == 0) {
        entry_price <- as.numeric(data$Close[i])

        if (!is.na(entry_price) && entry_price > 0) {
          position <- capital / entry_price
          capital <- 0

          if (verbose && length(trades) < 5) {
            cat(sprintf("  入场 [Bar %d]: 价格=%.8f\n", i, entry_price))
          }
        }
      }

      # 持仓管理
      if (position > 0) {
        current_price <- as.numeric(data$Close[i])

        if (!is.na(current_price) && current_price > 0 &&
            !is.na(entry_price) && entry_price > 0) {
          pnl_percent <- (current_price - entry_price) / entry_price * 100

          # 止盈止损检查
          if (pnl_percent >= takeProfitPercent || pnl_percent <= -stopLossPercent) {
            exit_capital <- position * current_price
            trades <- c(trades, pnl_percent)
            capital <- exit_capital
            position <- 0

            if (verbose && length(trades) <= 5) {
              cat(sprintf("  出场 [Bar %d]: 价格=%.8f, 盈亏=%.2f%% (%s)\n",
                         i, current_price, pnl_percent,
                         ifelse(pnl_percent >= takeProfitPercent, "止盈", "止损")))
            }

            entry_price <- NA
          }
        }
      }

      # 记录资金曲线
      portfolio_value <- if (position > 0 && !is.na(data$Close[i])) {
        position * as.numeric(data$Close[i])
      } else {
        capital
      }
      capital_curve[i] <- portfolio_value
    }

    # 处理未平仓
    if (position > 0) {
      final_price <- as.numeric(data$Close[nrow(data)])
      if (!is.na(final_price) && final_price > 0 && !is.na(entry_price) && entry_price > 0) {
        final_pnl <- (final_price - entry_price) / entry_price * 100
        trades <- c(trades, final_pnl)
        capital <- position * final_price

        if (verbose) {
          cat(sprintf("  强制平仓: 价格=%.8f, 盈亏=%.2f%%\n", final_price, final_pnl))
        }
      }
    }

    # 计算指标
    if (length(trades) == 0) {
      return(list(
        Signal_Count = signal_count, Trade_Count = 0, Final_Capital = NA,
        Return_Percentage = NA, Max_Drawdown = NA, Win_Rate = NA,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    final_capital <- capital
    return_pct <- (final_capital - 10000) / 10000 * 100

    # 最大回撤
    peak <- cummax(capital_curve)
    drawdown <- (capital_curve - peak) / peak * 100
    max_drawdown <- min(drawdown, na.rm=TRUE)

    # 胜率
    win_rate <- sum(trades > 0) / length(trades) * 100

    # Buy & Hold
    bh_return <- (as.numeric(data$Close[nrow(data)]) - as.numeric(data$Close[1])) /
                 as.numeric(data$Close[1]) * 100
    excess_return <- return_pct - bh_return

    if (verbose) {
      cat(sprintf("  交易次数: %d\n", length(trades)))
      cat(sprintf("  最终收益: %.2f%%\n", return_pct))
      cat(sprintf("  胜率: %.2f%%\n", win_rate))
    }

    return(list(
      Signal_Count = signal_count,
      Trade_Count = length(trades),
      Final_Capital = final_capital,
      Return_Percentage = return_pct,
      Max_Drawdown = max_drawdown,
      Win_Rate = win_rate,
      BH_Return = bh_return,
      Excess_Return = excess_return
    ))

  }, error = function(e) {
    if (verbose) {
      cat(sprintf("  错误: %s\n", e$message))
    }
    return(list(
      Signal_Count = 0, Trade_Count = 0, Final_Capital = NA,
      Return_Percentage = NA, Max_Drawdown = NA, Win_Rate = NA,
      BH_Return = NA, Excess_Return = NA
    ))
  })
}

# ========================================
# 测试和对比
# ========================================

cat("========================================\n")
cat("修正后的信号生成和回测测试\n")
cat("========================================\n\n")

# 加载数据
load("data/liaochu.RData")

pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat("PEPEUSDT时间框架:", paste(pepe_symbols, collapse=", "), "\n\n")

# 对比测试
test_params <- list(
  list(lookback=3, drop=20, tp=10, sl=10, desc="Pine Script默认参数"),
  list(lookback=3, drop=5, tp=6, sl=6, desc="宽松参数"),
  list(lookback=5, drop=15, tp=8, sl=8, desc="中等参数")
)

for (symbol in pepe_symbols) {
  data <- cryptodata[[symbol]]

  cat(sprintf("\n========== %s (共%d bars) ==========\n", symbol, nrow(data)))

  timeframe_mins <- detect_timeframe(data)
  if (!is.na(timeframe_mins)) {
    cat(sprintf("时间框架: %.0f 分钟\n\n", timeframe_mins))
  }

  for (params in test_params) {
    cat(sprintf("参数: %s (lookback=%d, drop=%d%%, TP=%d%%, SL=%d%%)\n",
               params$desc, params$lookback, params$drop, params$tp, params$sl))

    # 原始方法
    cat("  [原始方法 - 直接使用bar数]\n")
    result_old <- backtest_strategy_corrected(
      data, params$lookback, params$drop, params$tp, params$sl,
      use_corrected_method = FALSE, verbose = TRUE
    )

    # 修正方法
    cat("  [修正方法 - 转换为实际天数]\n")
    result_new <- backtest_strategy_corrected(
      data, params$lookback, params$drop, params$tp, params$sl,
      use_corrected_method = TRUE, verbose = TRUE
    )

    cat(sprintf("  对比: 信号数 %d -> %d, 交易数 %d -> %d\n\n",
               result_old$Signal_Count, result_new$Signal_Count,
               result_old$Trade_Count, result_new$Trade_Count))
  }
}

cat("\n========================================\n")
cat("测试完成!\n")
cat("========================================\n")
