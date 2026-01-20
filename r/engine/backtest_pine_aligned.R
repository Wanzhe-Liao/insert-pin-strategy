# Pine Script对齐版回测函数
# 完全对齐Pine Script的strategy.exit()行为
#
# 核心改进：
# 1. 使用High/Low判断止盈止损触发（而非Close）
# 2. 使用精确的TP/SL价格作为出场价（而非Close）
# 3. 处理同时触发止盈和止损的情况（模拟时间顺序）
#
# 创建日期：2025-10-26
# 基于：optimize_pepe_fixed.R

suppressMessages({
  library(xts)
})

# ============================================================================
# 时间框架检测函数（与原版相同）
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

# ============================================================================
# 信号生成函数（与原版相同）
# ============================================================================

build_signals_pine_aligned <- function(data, lookbackDays, minDropPercent) {
  if (nrow(data) < 10) {
    return(rep(FALSE, nrow(data)))
  }

  # 检测时间框架并转换天数为bar数
  tf_minutes <- detect_timeframe_minutes(data)

  if (is.na(tf_minutes) || tf_minutes <= 0) {
    warning("无法检测时间框架，使用默认15分钟")
    tf_minutes <- 15
  }

  # 转换：lookbackDays（天） → lookbackBars（根K线）
  bars_per_day <- 1440 / tf_minutes
  lookbackBars <- as.integer(lookbackDays * bars_per_day)

  # 初始化信号向量
  signals <- rep(FALSE, nrow(data))

  if (nrow(data) <= lookbackBars) {
    return(signals)
  }

  # 提取价格数据
  high_prices <- as.numeric(data[, "High"])
  low_prices <- as.numeric(data[, "Low"])

  # 从第 lookbackBars+1 根K线开始计算信号
  for (i in (lookbackBars + 1):nrow(data)) {
    window_start <- max(1, i - lookbackBars)
    window_end <- i - 1

    window_highs <- high_prices[window_start:window_end]
    window_high <- max(window_highs, na.rm = TRUE)

    current_low <- low_prices[i]

    # 计算跌幅百分比
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
# Pine Script对齐版回测函数（核心改进）
# ============================================================================

backtest_strategy_pine_aligned <- function(data, lookbackDays, minDropPercent,
                                          takeProfitPercent, stopLossPercent,
                                          next_bar_entry = FALSE,
                                          verbose = FALSE) {
  tryCatch({
    # 数据验证
    if (nrow(data) < 10) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
        TP_Count = 0, SL_Count = 0, Both_Trigger_Count = 0,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 生成信号
    signals <- build_signals_pine_aligned(data, lookbackDays, minDropPercent)
    signal_count <- sum(signals, na.rm = TRUE)

    if (signal_count == 0) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
        TP_Count = 0, SL_Count = 0, Both_Trigger_Count = 0,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 初始化回测变量
    capital <- 10000
    position <- 0
    entry_price <- 0
    entry_index <- 0
    trades <- c()
    capital_curve <- c()

    # 统计变量
    tp_count <- 0      # 止盈次数
    sl_count <- 0      # 止损次数
    both_count <- 0    # 同时触发次数

    # 逐K线模拟交易
    for (i in 1:nrow(data)) {
      # ========== 入场逻辑 ==========
      if (signals[i] && position == 0) {
        # 根据next_bar_entry决定入场价格
        if (next_bar_entry && i < nrow(data)) {
          entry_price <- as.numeric(data[i+1, "Open"])
          entry_index <- i + 1
        } else {
          entry_price <- as.numeric(data[i, "Close"])
          entry_index <- i
        }

        # 验证入场价格有效
        if (!is.na(entry_price) && entry_price > 0) {
          position <- capital / entry_price
          capital <- 0

          if (verbose) {
            cat(sprintf("Entry at bar %d: Price=%.8f\n", i, entry_price))
          }
        }
      }

      # ========== 出场逻辑（Pine Script对齐版）==========
      # 只有在入场后的K线才检查出场
      if (position > 0 && i >= entry_index) {
        current_high <- as.numeric(data[i, "High"])
        current_low <- as.numeric(data[i, "Low"])
        current_close <- as.numeric(data[i, "Close"])
        current_open <- as.numeric(data[i, "Open"])

        if (!is.na(current_high) && !is.na(current_low) &&
            !is.na(current_close) && entry_price > 0) {

          # 计算止盈止损价格
          tp_price <- entry_price * (1 + takeProfitPercent / 100)
          sl_price <- entry_price * (1 - stopLossPercent / 100)

          # 检查是否触发（使用High/Low，对齐Pine Script）
          hit_tp <- current_high >= tp_price
          hit_sl <- current_low <= sl_price

          exit_triggered <- FALSE
          exit_price <- NA
          exit_reason <- ""

          if (hit_tp && hit_sl) {
            # 同时触发：模拟时间顺序（对齐Pine Script）
            both_count <- both_count + 1

            # 判断K线方向来决定哪个先触发
            if (!is.na(current_open)) {
              if (current_close >= current_open) {
                # 上涨K线（阳线）：假设先触发止盈
                exit_price <- tp_price
                exit_reason <- "TP_first"
                tp_count <- tp_count + 1
              } else {
                # 下跌K线（阴线）：假设先触发止损
                exit_price <- sl_price
                exit_reason <- "SL_first"
                sl_count <- sl_count + 1
              }
            } else {
              # 无法判断K线方向，默认止盈优先
              exit_price <- tp_price
              exit_reason <- "TP_default"
              tp_count <- tp_count + 1
            }
            exit_triggered <- TRUE

          } else if (hit_tp) {
            # 仅触发止盈
            exit_price <- tp_price
            exit_reason <- "TP"
            tp_count <- tp_count + 1
            exit_triggered <- TRUE

          } else if (hit_sl) {
            # 仅触发止损
            exit_price <- sl_price
            exit_reason <- "SL"
            sl_count <- sl_count + 1
            exit_triggered <- TRUE
          }

          # 执行出场
          if (exit_triggered) {
            pnl_percent <- ((exit_price - entry_price) / entry_price) * 100
            exit_capital <- position * exit_price

            trades <- c(trades, pnl_percent)
            capital <- exit_capital
            position <- 0

            if (verbose) {
              cat(sprintf("Exit at bar %d: Price=%.8f, Reason=%s, PnL=%.2f%%\n",
                         i, exit_price, exit_reason, pnl_percent))
            }

            entry_price <- 0
            entry_index <- 0
          }
        }
      }

      # 记录净值曲线
      portfolio_value <- if (position > 0 && !is.na(data[i, "Close"]) && data[i, "Close"] > 0) {
        position * as.numeric(data[i, "Close"])
      } else {
        capital
      }
      capital_curve <- c(capital_curve, portfolio_value)
    }

    # 处理未平仓的持仓（与Pine Script一致）
    if (position > 0) {
      final_price <- as.numeric(data[nrow(data), "Close"])
      if (!is.na(final_price) && final_price > 0 && entry_price > 0) {
        final_pnl <- ((final_price - entry_price) / entry_price) * 100
        trades <- c(trades, final_pnl)
        capital <- position * final_price

        if (verbose) {
          cat(sprintf("Force exit at end: Price=%.8f, PnL=%.2f%%\n",
                     final_price, final_pnl))
        }
      }
    }

    # 如果没有完成任何交易
    if (length(trades) == 0) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = signal_count,
        TP_Count = 0, SL_Count = 0, Both_Trigger_Count = 0,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 计算性能指标
    final_capital <- capital
    return_pct <- ((final_capital - 10000) / 10000) * 100

    # 最大回撤
    if (length(capital_curve) > 0) {
      peak <- cummax(capital_curve)
      drawdown <- (capital_curve - peak) / peak * 100
      max_drawdown <- min(drawdown, na.rm = TRUE)
    } else {
      max_drawdown <- 0
    }

    # 胜率
    win_rate <- sum(trades > 0) / length(trades) * 100

    # 买入持有收益
    first_close <- as.numeric(data[1, "Close"])
    last_close <- as.numeric(data[nrow(data), "Close"])
    if (!is.na(first_close) && !is.na(last_close) && first_close > 0) {
      bh_return <- ((last_close - first_close) / first_close) * 100
    } else {
      bh_return <- NA
    }

    excess_return <- return_pct - bh_return

    return(list(
      Final_Capital = final_capital,
      Return_Percentage = return_pct,
      Max_Drawdown = max_drawdown,
      Win_Rate = win_rate,
      Trade_Count = length(trades),
      Signal_Count = signal_count,
      TP_Count = tp_count,
      SL_Count = sl_count,
      Both_Trigger_Count = both_count,
      BH_Return = bh_return,
      Excess_Return = excess_return,
      Trades = trades  # 所有交易的盈亏列表
    ))

  }, error = function(e) {
    # 错误处理
    return(list(
      Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
      Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
      TP_Count = 0, SL_Count = 0, Both_Trigger_Count = 0,
      BH_Return = NA, Excess_Return = NA,
      Error = as.character(e$message)
    ))
  })
}

# ============================================================================
# 对比测试函数：同时运行原版和Pine对齐版
# ============================================================================

compare_backtest_versions <- function(data, lookbackDays, minDropPercent,
                                     takeProfitPercent, stopLossPercent,
                                     next_bar_entry = FALSE) {
  cat("\n=== 回测版本对比测试 ===\n\n")
  cat("参数配置：\n")
  cat(sprintf("  lookbackDays: %d\n", lookbackDays))
  cat(sprintf("  minDropPercent: %.1f%%\n", minDropPercent))
  cat(sprintf("  takeProfitPercent: %.1f%%\n", takeProfitPercent))
  cat(sprintf("  stopLossPercent: %.1f%%\n", stopLossPercent))
  cat(sprintf("  next_bar_entry: %s\n\n", next_bar_entry))

  # 运行Pine对齐版
  cat("运行Pine Script对齐版...\n")
  result_pine <- backtest_strategy_pine_aligned(
    data, lookbackDays, minDropPercent,
    takeProfitPercent, stopLossPercent,
    next_bar_entry = next_bar_entry,
    verbose = FALSE
  )

  # 加载原版函数（如果存在）
  if (exists("backtest_strategy_fixed")) {
    cat("运行原版（Close价）...\n")
    result_original <- backtest_strategy_fixed(
      data, lookbackDays, minDropPercent,
      takeProfitPercent, stopLossPercent
    )

    # 对比结果
    cat("\n=== 结果对比 ===\n\n")

    comparison <- data.frame(
      Metric = c("信号数", "交易次数", "止盈次数", "止损次数",
                 "同时触发", "收益率(%)", "胜率(%)", "最大回撤(%)"),
      Pine_Aligned = c(
        result_pine$Signal_Count,
        result_pine$Trade_Count,
        result_pine$TP_Count,
        result_pine$SL_Count,
        result_pine$Both_Trigger_Count,
        round(result_pine$Return_Percentage, 2),
        round(result_pine$Win_Rate, 2),
        round(result_pine$Max_Drawdown, 2)
      ),
      Original = c(
        result_original$Signal_Count,
        result_original$Trade_Count,
        NA,  # 原版无此统计
        NA,  # 原版无此统计
        NA,  # 原版无此统计
        round(result_original$Return_Percentage, 2),
        round(result_original$Win_Rate, 2),
        round(result_original$Max_Drawdown, 2)
      ),
      stringsAsFactors = FALSE
    )

    # 计算差异
    comparison$Difference <- comparison$Pine_Aligned - comparison$Original
    comparison$Diff_Pct <- round((comparison$Difference / comparison$Original) * 100, 1)

    print(comparison)

    cat("\n关键差异分析：\n")
    trade_diff <- result_pine$Trade_Count - result_original$Trade_Count
    if (trade_diff > 0) {
      cat(sprintf("  Pine对齐版多执行了 %d 笔交易 (+%.1f%%)\n",
                 trade_diff,
                 (trade_diff / result_original$Trade_Count) * 100))
      cat("  原因：使用High/Low触发，能捕捉盘中止盈/止损\n")
    } else if (trade_diff < 0) {
      cat(sprintf("  Pine对齐版少执行了 %d 笔交易\n", abs(trade_diff)))
    } else {
      cat("  两版本交易次数相同\n")
    }

  } else {
    cat("\n=== Pine Script对齐版结果 ===\n\n")
    cat(sprintf("信号数: %d\n", result_pine$Signal_Count))
    cat(sprintf("交易次数: %d\n", result_pine$Trade_Count))
    cat(sprintf("  - 止盈: %d (%.1f%%)\n",
               result_pine$TP_Count,
               (result_pine$TP_Count / result_pine$Trade_Count) * 100))
    cat(sprintf("  - 止损: %d (%.1f%%)\n",
               result_pine$SL_Count,
               (result_pine$SL_Count / result_pine$Trade_Count) * 100))
    cat(sprintf("  - 同时触发: %d\n", result_pine$Both_Trigger_Count))
    cat(sprintf("收益率: %.2f%%\n", result_pine$Return_Percentage))
    cat(sprintf("胜率: %.2f%%\n", result_pine$Win_Rate))
    cat(sprintf("最大回撤: %.2f%%\n", result_pine$Max_Drawdown))
    cat(sprintf("买入持有: %.2f%%\n", result_pine$BH_Return))
    cat(sprintf("超额收益: %.2f%%\n", result_pine$Excess_Return))
  }

  return(result_pine)
}

# ============================================================================
# 使用示例
# ============================================================================

if (FALSE) {
  # 加载数据
  load(file.path("data", "liaochu.RData"))

  # 选择PEPEUSDT_15m数据
  data <- cryptodata[["PEPEUSDT_15m"]]

  # 运行对比测试
  result <- compare_backtest_versions(
    data,
    lookbackDays = 3,
    minDropPercent = 20,
    takeProfitPercent = 10,
    stopLossPercent = 10,
    next_bar_entry = FALSE  # 对齐Pine Script的process_orders_on_close=true
  )

  # 查看所有交易的盈亏分布
  if (!is.null(result$Trades) && length(result$Trades) > 0) {
    cat("\n交易盈亏分布：\n")
    print(summary(result$Trades))

    cat("\n盈利交易：\n")
    winning_trades <- result$Trades[result$Trades > 0]
    if (length(winning_trades) > 0) {
      cat(sprintf("  数量: %d\n", length(winning_trades)))
      cat(sprintf("  平均: %.2f%%\n", mean(winning_trades)))
      cat(sprintf("  最大: %.2f%%\n", max(winning_trades)))
    }

    cat("\n亏损交易：\n")
    losing_trades <- result$Trades[result$Trades < 0]
    if (length(losing_trades) > 0) {
      cat(sprintf("  数量: %d\n", length(losing_trades)))
      cat(sprintf("  平均: %.2f%%\n", mean(losing_trades)))
      cat(sprintf("  最大: %.2f%%\n", min(losing_trades)))
    }
  }
}

cat("\nOK Pine Script对齐版回测函数已加载\n")
cat("主要函数：\n")
cat("  - backtest_strategy_pine_aligned(): Pine对齐版回测\n")
cat("  - compare_backtest_versions(): 对比测试工具\n")
cat("  - build_signals_pine_aligned(): 信号生成\n\n")
