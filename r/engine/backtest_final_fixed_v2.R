# PEPEUSDT回测系统 - 深度修复版 v2
#
# 修复内容：
# 1. OK 修复持仓管理逻辑：添加出场冷却期，防止同K线重复入场
# 2. OK 修复信号生成逻辑：删除错误的滞后，使用当前K线窗口
# 3. OK 修复入场时机逻辑：统一为下一根开盘价入场
# 4. OK 修复出场检查时机：入场K线不检查出场
# 5. OK 保留所有原有的Bug修复（资金复利、手续费等）
#
# 目标：与TradingView保持一致的交易逻辑

# ============================================================================
# 依赖包检查和安装
# ============================================================================

check_and_install <- function(package_name) {
  if (!require(package_name, character.only = TRUE, quietly = TRUE)) {
    cat(sprintf("正在安装 %s...\n", package_name))
    install.packages(package_name, repos = "https://cloud.r-project.org/")
    library(package_name, character.only = TRUE)
  }
}

# 核心依赖
suppressMessages({
  check_and_install("xts")
  check_and_install("data.table")
  check_and_install("RcppRoll")
})

# ============================================================================
# 辅助函数
# ============================================================================

#' 检测时间框架
#'
#' @param xts_data xts时间序列对象
#' @return 时间框架分钟数
detect_timeframe <- function(xts_data) {
  if (nrow(xts_data) < 2) return(NA)

  n_samples <- min(100, nrow(xts_data) - 1)
  time_diffs <- as.numeric(difftime(
    index(xts_data)[2:(n_samples+1)],
    index(xts_data)[1:n_samples],
    units = "mins"
  ))

  tf_minutes <- median(time_diffs, na.rm = TRUE)
  return(round(tf_minutes))
}

#' 转换天数为K线数量
#'
#' @param days 天数
#' @param tf_minutes 时间框架分钟数
#' @return K线数量
convert_days_to_bars <- function(days, tf_minutes) {
  bars_per_day <- 1440 / tf_minutes
  return(as.integer(days * bars_per_day))
}

#' 向量化信号生成（修复版）
#'
#' @param data xts数据
#' @param lookback_bars 回看K线数
#' @param drop_threshold 跌幅阈值（小数，如0.20表示20%）
#' @return 逻辑向量，TRUE表示有信号
generate_signals_vectorized_fixed <- function(data, lookback_bars, drop_threshold) {
  n <- nrow(data)

  # 边界检查
  if (n < lookback_bars + 1) {
    return(rep(FALSE, n))
  }

  # 预提取数据
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])

  # 修复：计算包含当前K线的窗口最高价（与TradingView一致）
  # align="right" 表示窗口右对齐到当前位置
  window_high <- RcppRoll::roll_max(high_vec, n = lookback_bars, align = "right", fill = NA)

  # 修复：不再额外滞后！直接使用当前窗口最高价
  # TradingView的 ta.highest(high, lookback) 就是包含当前K线的
  drop_percent <- (window_high - low_vec) / window_high

  # 生成信号
  signals <- !is.na(drop_percent) & (drop_percent >= drop_threshold)

  return(signals)
}

# ============================================================================
# 核心回测函数（深度修复版）
# ============================================================================

#' 完整回测函数（深度修复版）
#'
#' @param data xts数据
#' @param lookback_days 回看天数
#' @param drop_threshold 跌幅阈值（小数）
#' @param take_profit 止盈百分比（小数）
#' @param stop_loss 止损百分比（小数）
#' @param initial_capital 初始资金
#' @param fee_rate 手续费率（小数，0.00075表示0.075%）
#' @param next_bar_entry 是否下一根开盘入场（强烈建议TRUE）
#' @param verbose 是否输出详细日志
#' @return 回测结果列表
backtest_strategy_v2 <- function(data,
                                 lookback_days,
                                 drop_threshold,
                                 take_profit,
                                 stop_loss,
                                 initial_capital = 10000,
                                 fee_rate = 0.00075,
                                 next_bar_entry = TRUE,  # 默认改为TRUE
                                 verbose = FALSE) {

  # 开始计时
  start_time <- Sys.time()

  # ========== 数据验证 ==========
  if (nrow(data) < 10) {
    return(list(
      Symbol = NA,
      Signal_Count = 0,
      Trade_Count = 0,
      Final_Capital = NA,
      Return_Percentage = NA,
      Win_Rate = NA,
      Max_Drawdown = NA,
      Total_Fees = 0,
      Error = "数据行数不足"
    ))
  }

  # ========== 参数准备 ==========

  # 检测时间框架
  tf_minutes <- detect_timeframe(data)
  if (is.na(tf_minutes) || tf_minutes <= 0) {
    tf_minutes <- 15
  }

  # 转换天数为K线数
  lookback_bars <- convert_days_to_bars(lookback_days, tf_minutes)

  # 验证数据长度
  if (nrow(data) < lookback_bars + 1) {
    return(list(
      Symbol = NA,
      Signal_Count = 0,
      Trade_Count = 0,
      Final_Capital = NA,
      Return_Percentage = NA,
      Win_Rate = NA,
      Max_Drawdown = NA,
      Total_Fees = 0,
      Error = sprintf("数据不足：需要%d根，实际%d根", lookback_bars+1, nrow(data))
    ))
  }

  if (verbose) {
    cat(sprintf("\n=== 回测参数 ===\n"))
    cat(sprintf("时间框架: %d分钟\n", tf_minutes))
    cat(sprintf("回看: %d天 = %d根K线\n", lookback_days, lookback_bars))
    cat(sprintf("数据: %d根K线\n", nrow(data)))
    cat(sprintf("跌幅阈值: %.2f%%\n", drop_threshold * 100))
    cat(sprintf("止盈/止损: %.2f%% / %.2f%%\n", take_profit * 100, stop_loss * 100))
    cat(sprintf("入场方式: %s\n", ifelse(next_bar_entry, "下一根开盘", "当前收盘")))
    cat(sprintf("================\n\n"))
  }

  # ========== 生成信号（修复版） ==========
  signals <- generate_signals_vectorized_fixed(data, lookback_bars, drop_threshold)
  signal_count <- sum(signals, na.rm = TRUE)

  if (verbose) {
    cat(sprintf("信号生成完成：共 %d 个信号\n\n", signal_count))
  }

  if (signal_count == 0) {
    return(list(
      Symbol = NA,
      Signal_Count = 0,
      Trade_Count = 0,
      Final_Capital = initial_capital,
      Return_Percentage = 0,
      Win_Rate = 0,
      Max_Drawdown = 0,
      Total_Fees = 0,
      Error = "无信号"
    ))
  }

  # ========== 预提取数据 ==========
  n_bars <- nrow(data)
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])
  close_vec <- as.numeric(data[, "Close"])
  open_vec <- as.numeric(data[, "Open"])
  time_vec <- index(data)

  # ========== 初始化交易状态 ==========
  capital <- initial_capital
  position <- 0
  entry_price <- 0
  entry_index <- 0
  capital_before_trade <- 0

  # 关键修复：添加出场冷却期
  last_exit_index <- 0

  # 预分配数组
  max_trades <- signal_count
  trades <- numeric(max_trades)
  trade_count <- 0

  # 记录每笔交易详情（用于调试）
  trade_details <- vector("list", max_trades)

  capital_curve <- numeric(n_bars)
  total_fees <- 0

  # 统计
  tp_count <- 0
  sl_count <- 0
  both_count <- 0

  # 常量
  EPSILON <- 1e-10

  # ========== 主回测循环 ==========
  i <- 1
  while (i <= n_bars) {

    # ===== 入场逻辑（修复版） =====
    # 修复1：添加冷却期检查 (i > last_exit_index)
    # 修复2：强制下一根开盘入场（与TradingView一致）
    if (signals[i] && position == 0 && i > last_exit_index) {

      # 记录入场前的资金
      capital_before_trade <- capital

      # 修复：统一使用下一根开盘价入场
      if (next_bar_entry) {
        if (i < n_bars) {
          entry_price <- open_vec[i + 1]
          entry_index <- i + 1
          signal_bar_index <- i  # 记录信号K线位置
          i <- i + 1  # 跳到入场K线
          if (i > n_bars) break
        } else {
          # 最后一根K线无法入场
          i <- i + 1
          next
        }
      } else {
        # 当前收盘入场（不推荐）
        entry_price <- close_vec[i]
        entry_index <- i
        signal_bar_index <- i
      }

      # 验证入场价格
      if (is.na(entry_price) || entry_price <= EPSILON) {
        position <- 0
        entry_index <- 0
        i <- i + 1
        next
      }

      # 计算手续费并开仓
      entry_fee <- capital * fee_rate
      capital_after_fee <- capital - entry_fee
      total_fees <- total_fees + entry_fee

      position <- capital_after_fee / entry_price
      capital <- 0

      if (verbose) {
        cat(sprintf("[Trade %d - ENTRY]\n", trade_count + 1))
        cat(sprintf("  信号K线: %d (%s)\n", signal_bar_index, time_vec[signal_bar_index]))
        cat(sprintf("  入场K线: %d (%s)\n", entry_index, time_vec[entry_index]))
        cat(sprintf("  入场价格: %.8f\n", entry_price))
        cat(sprintf("  入场资金: %.2f\n", capital_before_trade))
        cat(sprintf("  入场手续费: %.4f\n", entry_fee))
        cat(sprintf("  持仓数量: %.4f\n", position))
        cat("\n")
      }
    }

    # ===== 出场逻辑（修复版） =====
    # 修复：使用 i > entry_index 而不是 >=
    # 这样入场K线不会立即检查出场（与TradingView一致）
    if (position > 0 && i > entry_index) {
      current_high <- high_vec[i]
      current_low <- low_vec[i]
      current_close <- close_vec[i]
      current_open <- open_vec[i]

      # 验证数据有效性
      if (is.na(current_high) || is.na(current_low) ||
          is.na(current_close) || entry_price <= EPSILON) {
        i <- i + 1
        next
      }

      # 计算止盈止损价格
      tp_price <- entry_price * (1 + take_profit)
      sl_price <- entry_price * (1 - stop_loss)

      # 检查触发
      hit_tp <- (current_high >= tp_price - EPSILON)
      hit_sl <- (current_low <= sl_price + EPSILON)

      exit_triggered <- FALSE
      exit_price <- NA
      exit_reason <- ""

      if (hit_tp && hit_sl) {
        # 同时触发：严谨判断
        both_count <- both_count + 1

        if (!is.na(current_open)) {
          if (current_open >= tp_price - EPSILON) {
            exit_price <- tp_price
            exit_reason <- "TP_gap_open"
            tp_count <- tp_count + 1
          } else if (current_open <= sl_price + EPSILON) {
            exit_price <- sl_price
            exit_reason <- "SL_gap_down"
            sl_count <- sl_count + 1
          } else {
            # 根据K线颜色判断
            if (current_close >= current_open) {
              exit_price <- tp_price
              exit_reason <- "TP_green"
              tp_count <- tp_count + 1
            } else {
              exit_price <- sl_price
              exit_reason <- "SL_red"
              sl_count <- sl_count + 1
            }
          }
        } else {
          exit_price <- tp_price
          exit_reason <- "TP_default"
          tp_count <- tp_count + 1
        }
        exit_triggered <- TRUE

      } else if (hit_tp) {
        exit_price <- tp_price
        exit_reason <- "TP"
        tp_count <- tp_count + 1
        exit_triggered <- TRUE

      } else if (hit_sl) {
        exit_price <- sl_price
        exit_reason <- "SL"
        sl_count <- sl_count + 1
        exit_triggered <- TRUE
      }

      # 执行出场
      if (exit_triggered) {
        exit_value_before_fee <- position * exit_price
        exit_fee <- exit_value_before_fee * fee_rate
        exit_value_after_fee <- exit_value_before_fee - exit_fee

        total_fees <- total_fees + exit_fee

        # 计算盈亏
        trade_pnl_amount <- exit_value_after_fee - capital_before_trade
        trade_pnl_percent <- (trade_pnl_amount / capital_before_trade) * 100

        # 记录交易
        trade_count <- trade_count + 1
        trades[trade_count] <- trade_pnl_percent

        # 记录交易详情
        trade_details[[trade_count]] <- list(
          trade_id = trade_count,
          entry_bar = entry_index,
          entry_time = as.character(time_vec[entry_index]),
          entry_price = entry_price,
          exit_bar = i,
          exit_time = as.character(time_vec[i]),
          exit_price = exit_price,
          exit_reason = exit_reason,
          bars_held = i - entry_index,
          pnl_percent = trade_pnl_percent,
          capital_before = capital_before_trade,
          capital_after = exit_value_after_fee
        )

        # 更新资金
        capital <- exit_value_after_fee

        if (verbose) {
          cat(sprintf("[Trade %d - EXIT]\n", trade_count))
          cat(sprintf("  出场K线: %d (%s)\n", i, time_vec[i]))
          cat(sprintf("  出场价格: %.8f\n", exit_price))
          cat(sprintf("  出场原因: %s\n", exit_reason))
          cat(sprintf("  持仓时长: %d根K线\n", i - entry_index))
          cat(sprintf("  盈亏: %.2f%% (%.2f)\n", trade_pnl_percent, trade_pnl_amount))
          cat(sprintf("  出场手续费: %.4f\n", exit_fee))
          cat(sprintf("  当前资金: %.2f\n", capital))
          cat("\n")
        }

        # 重置持仓状态
        position <- 0
        entry_price <- 0
        entry_index <- 0
        capital_before_trade <- 0

        # 关键修复：设置冷却期
        last_exit_index <- i
      }
    }

    # ===== 记录净值曲线 =====
    portfolio_value <- if (position > 0 && i >= entry_index) {
      position * close_vec[i]
    } else {
      capital
    }
    capital_curve[i] <- portfolio_value

    i <- i + 1
  }

  # ========== 处理未平仓 ==========
  if (position > 0) {
    final_price <- close_vec[n_bars]
    if (!is.na(final_price) && final_price > EPSILON && entry_price > EPSILON) {
      exit_value_before_fee <- position * final_price
      exit_fee <- exit_value_before_fee * fee_rate
      exit_value_after_fee <- exit_value_before_fee - exit_fee

      total_fees <- total_fees + exit_fee

      trade_pnl_percent <- ((exit_value_after_fee - capital_before_trade) / capital_before_trade) * 100

      trade_count <- trade_count + 1
      trades[trade_count] <- trade_pnl_percent

      # 记录强制平仓详情
      trade_details[[trade_count]] <- list(
        trade_id = trade_count,
        entry_bar = entry_index,
        entry_time = as.character(time_vec[entry_index]),
        entry_price = entry_price,
        exit_bar = n_bars,
        exit_time = as.character(time_vec[n_bars]),
        exit_price = final_price,
        exit_reason = "FORCE_EXIT",
        bars_held = n_bars - entry_index,
        pnl_percent = trade_pnl_percent,
        capital_before = capital_before_trade,
        capital_after = exit_value_after_fee
      )

      capital <- exit_value_after_fee

      if (verbose) {
        cat(sprintf("[Trade %d - FORCE EXIT]\n", trade_count))
        cat(sprintf("  出场K线: %d (最后一根)\n", n_bars))
        cat(sprintf("  出场价格: %.8f\n", final_price))
        cat(sprintf("  盈亏: %.2f%%\n", trade_pnl_percent))
        cat("\n")
      }
    }
  }

  # ========== 计算统计指标 ==========

  final_capital <- capital
  return_pct <- ((final_capital - initial_capital) / initial_capital) * 100

  # 胜率
  if (trade_count > 0) {
    trades_actual <- trades[1:trade_count]
    win_rate <- sum(trades_actual > 0) / trade_count * 100
  } else {
    win_rate <- 0
    trades_actual <- numeric(0)
  }

  # 最大回撤
  if (any(!is.na(capital_curve) & capital_curve > 0)) {
    peak <- cummax(capital_curve)
    drawdown <- (capital_curve - peak) / peak * 100
    max_drawdown <- abs(min(drawdown, na.rm = TRUE))
  } else {
    max_drawdown <- 0
  }

  # 计算耗时
  elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  if (verbose) {
    cat(sprintf("=== 回测完成 ===\n"))
    cat(sprintf("信号数: %d\n", signal_count))
    cat(sprintf("交易数: %d\n", trade_count))
    cat(sprintf("最终资金: %.2f\n", final_capital))
    cat(sprintf("总收益: %.2f%%\n", return_pct))
    cat(sprintf("胜率: %.2f%%\n", win_rate))
    cat(sprintf("最大回撤: %.2f%%\n", max_drawdown))
    cat(sprintf("总手续费: %.2f\n", total_fees))
    cat(sprintf("耗时: %.3f秒\n", elapsed_time))
    cat(sprintf("================\n\n"))
  }

  # ========== 返回结果 ==========
  return(list(
    # 基本信息
    Signal_Count = signal_count,
    Trade_Count = trade_count,

    # 收益指标
    Initial_Capital = initial_capital,
    Final_Capital = final_capital,
    Return_Percentage = return_pct,

    # 风险指标
    Win_Rate = win_rate,
    Max_Drawdown = max_drawdown,

    # 成本统计
    Total_Fees = total_fees,
    Fee_Percentage = (total_fees / initial_capital) * 100,
    Avg_Fee_Per_Trade = if(trade_count > 0) total_fees / trade_count else 0,

    # 交易明细
    TP_Count = tp_count,
    SL_Count = sl_count,
    Both_Count = both_count,
    Trades = trades_actual,
    Trade_Details = trade_details[1:trade_count],

    # 性能
    Elapsed_Time = elapsed_time,

    # 错误
    Error = NA
  ))
}

# ============================================================================
# 便捷包装函数
# ============================================================================

#' 运行单个参数组合的回测（v2版本）
#'
#' @param data xts数据
#' @param lookback_days 回看天数
#' @param drop_pct 跌幅百分比
#' @param tp_pct 止盈百分比
#' @param sl_pct 止损百分比
#' @param initial_capital 初始资金
#' @param fee_pct 手续费百分比
#' @param next_bar_entry 是否下一根开盘入场
#' @return 回测结果data.frame
run_single_test_v2 <- function(data, lookback_days, drop_pct, tp_pct, sl_pct,
                                initial_capital = 10000, fee_pct = 0.075,
                                next_bar_entry = TRUE) {

  result <- backtest_strategy_v2(
    data = data,
    lookback_days = lookback_days,
    drop_threshold = drop_pct / 100,
    take_profit = tp_pct / 100,
    stop_loss = sl_pct / 100,
    initial_capital = initial_capital,
    fee_rate = fee_pct / 100,
    next_bar_entry = next_bar_entry,
    verbose = FALSE
  )

  return(data.frame(
    lookbackDays = lookback_days,
    minDropPercent = drop_pct,
    takeProfitPercent = tp_pct,
    stopLossPercent = sl_pct,
    Signal_Count = result$Signal_Count,
    Trade_Count = result$Trade_Count,
    Final_Capital = result$Final_Capital,
    Return_Percentage = result$Return_Percentage,
    Win_Rate = result$Win_Rate,
    Max_Drawdown = result$Max_Drawdown,
    Total_Fees = result$Total_Fees,
    Elapsed_Time = result$Elapsed_Time,
    stringsAsFactors = FALSE
  ))
}

cat("\nOK backtest_final_fixed_v2.R 加载完成！\n")
cat("\n=== 深度修复内容 ===\n")
cat("1. 持仓管理：添加出场冷却期，防止同K线重复入场\n")
cat("2. 信号生成：删除错误的滞后，使用当前K线窗口（与TradingView一致）\n")
cat("3. 入场时机：统一为下一根开盘价入场\n")
cat("4. 出场检查：入场K线不检查出场\n")
cat("5. 保留原有：资金复利、手续费计算等所有修复\n")
cat("\n主要函数:\n")
cat("  - backtest_strategy_v2(): 深度修复版回测函数\n")
cat("  - run_single_test_v2(): 便捷测试函数\n")
cat("  - generate_signals_vectorized_fixed(): 修复版信号生成\n")
cat("\n建议：使用 next_bar_entry=TRUE（默认）以匹配TradingView\n\n")
