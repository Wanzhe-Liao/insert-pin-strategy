# ============================================================================
# Pine Script对齐版回测函数 - 含手续费版本
# ============================================================================
# 创建日期：2025-10-26
# 基于：backtest_pine_aligned.R
# 主要改进：添加完整的手续费计算逻辑
#
# 手续费设置：
# - 费率：0.075% (对齐Pine Script的commission_value=0.075)
# - 入场扣费：开仓金额 × 0.075%
# - 出场扣费：平仓金额 × 0.075%
# - 总成本：每个完整交易周期约0.15%
# ============================================================================

suppressMessages({
  library(xts)
})

# ============================================================================
# 常量定义
# ============================================================================

# 手续费率（0.075%）
FEE_RATE <- 0.00075

cat(sprintf("\n手续费率设置: %.5f%% (%.5f)\n", FEE_RATE * 100, FEE_RATE))
cat("对齐Pine Script: commission_value=0.075\n\n")

# ============================================================================
# 时间框架检测函数（保持不变）
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
# 信号生成函数（保持不变）
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
# Pine Script对齐版回测函数 - 含手续费
# ============================================================================

backtest_strategy_with_fees <- function(data, lookbackDays, minDropPercent,
                                       takeProfitPercent, stopLossPercent,
                                       next_bar_entry = FALSE,
                                       fee_rate = FEE_RATE,
                                       verbose = FALSE) {
  tryCatch({
    # 数据验证
    if (nrow(data) < 10) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
        TP_Count = 0, SL_Count = 0, Both_Trigger_Count = 0,
        Total_Fees = 0, Fee_Percentage = 0,
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
        Total_Fees = 0, Fee_Percentage = 0,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 初始化回测变量
    initial_capital <- 10000
    capital <- initial_capital
    position <- 0
    entry_price <- 0
    entry_index <- 0
    trades <- c()
    capital_curve <- c()

    # 统计变量
    tp_count <- 0
    sl_count <- 0
    both_count <- 0
    total_fees <- 0  # 累积手续费

    # 逐K线模拟交易
    for (i in 1:nrow(data)) {
      # ========== 入场逻辑（含手续费）==========
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
          # 计算入场手续费
          entry_fee <- capital * fee_rate
          capital_after_fee <- capital - entry_fee

          # 记录手续费
          total_fees <- total_fees + entry_fee

          # 开仓
          position <- capital_after_fee / entry_price
          capital <- 0

          if (verbose) {
            cat(sprintf("Entry at bar %d: Price=%.8f, Fee=%.4f USDT\n",
                       i, entry_price, entry_fee))
          }
        }
      }

      # ========== 出场逻辑（Pine Script对齐版 + 手续费）==========
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
            # 同时触发：模拟时间顺序
            both_count <- both_count + 1

            if (!is.na(current_open)) {
              if (current_close >= current_open) {
                # 阳线：先触发止盈
                exit_price <- tp_price
                exit_reason <- "TP_first"
                tp_count <- tp_count + 1
              } else {
                # 阴线：先触发止损
                exit_price <- sl_price
                exit_reason <- "SL_first"
                sl_count <- sl_count + 1
              }
            } else {
              # 默认止盈优先
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

          # 执行出场（含手续费）
          if (exit_triggered) {
            # 计算出场前价值
            exit_value_before_fee <- position * exit_price

            # 计算出场手续费
            exit_fee <- exit_value_before_fee * fee_rate
            exit_value_after_fee <- exit_value_before_fee - exit_fee

            # 记录手续费
            total_fees <- total_fees + exit_fee

            # 计算盈亏（基于实际到手资金）
            pnl_percent <- ((exit_value_after_fee - initial_capital) / initial_capital) * 100

            trades <- c(trades, pnl_percent)
            capital <- exit_value_after_fee

            # 重置为初始资金，准备下一笔交易
            capital <- initial_capital
            position <- 0

            if (verbose) {
              cat(sprintf("Exit at bar %d: Price=%.8f, Fee=%.4f USDT, Reason=%s, PnL=%.2f%%\n",
                         i, exit_price, exit_fee, exit_reason, pnl_percent))
            }

            entry_price <- 0
            entry_index <- 0
          }
        }
      }

      # 记录净值曲线
      portfolio_value <- if (position > 0 && !is.na(data[i, "Close"]) && data[i, "Close"] > 0) {
        # 持仓中：按当前价计算价值（不扣出场手续费，因为还未出场）
        position * as.numeric(data[i, "Close"])
      } else {
        capital
      }
      capital_curve <- c(capital_curve, portfolio_value)
    }

    # 处理未平仓的持仓（含手续费）
    if (position > 0) {
      final_price <- as.numeric(data[nrow(data), "Close"])
      if (!is.na(final_price) && final_price > 0 && entry_price > 0) {
        # 强制平仓
        exit_value_before_fee <- position * final_price
        exit_fee <- exit_value_before_fee * fee_rate
        exit_value_after_fee <- exit_value_before_fee - exit_fee

        total_fees <- total_fees + exit_fee

        final_pnl <- ((exit_value_after_fee - initial_capital) / initial_capital) * 100
        trades <- c(trades, final_pnl)
        capital <- exit_value_after_fee

        if (verbose) {
          cat(sprintf("Force exit at end: Price=%.8f, Fee=%.4f USDT, PnL=%.2f%%\n",
                     final_price, exit_fee, final_pnl))
        }
      }
    }

    # 如果没有完成任何交易
    if (length(trades) == 0) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = signal_count,
        TP_Count = 0, SL_Count = 0, Both_Trigger_Count = 0,
        Total_Fees = 0, Fee_Percentage = 0,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 计算性能指标
    final_capital <- capital
    return_pct <- ((final_capital - initial_capital) / initial_capital) * 100

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

    # 手续费占比
    fee_percentage <- (total_fees / initial_capital) * 100

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
      Total_Fees = total_fees,
      Fee_Percentage = fee_percentage,
      BH_Return = bh_return,
      Excess_Return = excess_return,
      Trades = trades
    ))

  }, error = function(e) {
    # 错误处理
    return(list(
      Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
      Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
      TP_Count = 0, SL_Count = 0, Both_Trigger_Count = 0,
      Total_Fees = 0, Fee_Percentage = 0,
      BH_Return = NA, Excess_Return = NA,
      Error = as.character(e$message)
    ))
  })
}

# ============================================================================
# 对比测试函数：有/无手续费版本对比
# ============================================================================

compare_fee_impact <- function(data, lookbackDays, minDropPercent,
                              takeProfitPercent, stopLossPercent,
                              next_bar_entry = FALSE) {
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("手续费影响对比测试\n")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

  cat("参数配置：\n")
  cat(sprintf("  lookbackDays: %d\n", lookbackDays))
  cat(sprintf("  minDropPercent: %.1f%%\n", minDropPercent))
  cat(sprintf("  takeProfitPercent: %.1f%%\n", takeProfitPercent))
  cat(sprintf("  stopLossPercent: %.1f%%\n", stopLossPercent))
  cat(sprintf("  手续费率: %.5f%%\n\n", FEE_RATE * 100))

  # 运行含手续费版本
  cat("运行含手续费版本...\n")
  result_with_fee <- backtest_strategy_with_fees(
    data, lookbackDays, minDropPercent,
    takeProfitPercent, stopLossPercent,
    next_bar_entry = next_bar_entry,
    fee_rate = FEE_RATE,
    verbose = FALSE
  )

  # 运行无手续费版本
  cat("运行无手续费版本...\n")
  result_no_fee <- backtest_strategy_with_fees(
    data, lookbackDays, minDropPercent,
    takeProfitPercent, stopLossPercent,
    next_bar_entry = next_bar_entry,
    fee_rate = 0,  # 手续费为0
    verbose = FALSE
  )

  # 对比结果
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("结果对比\n")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

  comparison <- data.frame(
    Metric = c("信号数", "交易次数", "止盈次数", "止损次数",
               "收益率(%)", "胜率(%)", "最大回撤(%)", "总手续费(USDT)", "手续费占比(%)"),
    With_Fee = c(
      result_with_fee$Signal_Count,
      result_with_fee$Trade_Count,
      result_with_fee$TP_Count,
      result_with_fee$SL_Count,
      round(result_with_fee$Return_Percentage, 2),
      round(result_with_fee$Win_Rate, 2),
      round(result_with_fee$Max_Drawdown, 2),
      round(result_with_fee$Total_Fees, 2),
      round(result_with_fee$Fee_Percentage, 2)
    ),
    No_Fee = c(
      result_no_fee$Signal_Count,
      result_no_fee$Trade_Count,
      result_no_fee$TP_Count,
      result_no_fee$SL_Count,
      round(result_no_fee$Return_Percentage, 2),
      round(result_no_fee$Win_Rate, 2),
      round(result_no_fee$Max_Drawdown, 2),
      0,
      0
    ),
    stringsAsFactors = FALSE
  )

  # 计算差异
  comparison$Difference <- comparison$With_Fee - comparison$No_Fee

  print(comparison)

  cat("\n关键发现：\n")
  cat(sprintf("  手续费总额: %.2f USDT (%.2f%%)\n",
             result_with_fee$Total_Fees,
             result_with_fee$Fee_Percentage))
  cat(sprintf("  收益率损失: %.2f%%\n",
             result_no_fee$Return_Percentage - result_with_fee$Return_Percentage))
  cat(sprintf("  平均每笔手续费: %.2f USDT\n",
             result_with_fee$Total_Fees / result_with_fee$Trade_Count))

  cat("\n")
  return(result_with_fee)
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
  result <- compare_fee_impact(
    data,
    lookbackDays = 3,
    minDropPercent = 20,
    takeProfitPercent = 10,
    stopLossPercent = 10,
    next_bar_entry = FALSE
  )

  # 查看详细交易列表
  if (!is.null(result$Trades) && length(result$Trades) > 0) {
    cat("\n交易盈亏分布（含手续费）：\n")
    print(summary(result$Trades))
  }
}

cat("\nOK Pine Script对齐版回测函数（含手续费）已加载\n")
cat("主要函数：\n")
cat("  - backtest_strategy_with_fees(): 含手续费回测\n")
cat("  - compare_fee_impact(): 手续费影响对比\n")
cat(sprintf("  - 手续费率: %.5f%% (FEE_RATE = %.5f)\n\n", FEE_RATE * 100, FEE_RATE))
