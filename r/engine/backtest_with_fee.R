# ============================================================================
# Pine Script 对齐版回测函数 - 包含手续费和盘中触发
# ============================================================================
#
# 核心特性：
# 1. 使用 High/Low 价格进行盘中触发判断
# 2. 包含双边手续费模型（每边0.075%）
# 3. 精确的出场价格计算
# 4. 自动时间框架检测和转换
#
# ============================================================================

library(data.table)
library(lubridate)

#' 检测数据的时间框架（分钟数）
#'
#' @param data data.table，包含timestamp列
#' @return 整数，时间框架的分钟数
detect_timeframe <- function(data) {
  if (nrow(data) < 2) {
    stop("数据行数不足，无法检测时间框架")
  }

  # 计算前100个时间差的中位数（避免异常值影响）
  n_samples <- min(100, nrow(data) - 1)
  time_diffs <- diff(data$timestamp[1:(n_samples + 1)])
  median_diff <- median(as.numeric(time_diffs), na.rm = TRUE)

  # 转换为分钟（确保是整数）
  timeframe_minutes <- as.integer(round(median_diff / 60))

  # 如果检测到0分钟，说明时间差异太小或数据有问题
  if (timeframe_minutes == 0) {
    # 尝试查看实际时间差
    cat("警告：检测到时间框架为0分钟，正在重新检测...\n")
    cat(sprintf("前5个时间戳: %s\n", paste(head(data$timestamp, 5), collapse=", ")))
    cat(sprintf("时间差（秒）: %s\n", paste(head(as.numeric(time_diffs), 5), collapse=", ")))

    # 假设是15分钟（从数据名称推断）
    timeframe_minutes <- 15L
    cat("使用默认时间框架: 15 分钟\n")
  }

  cat(sprintf("检测到时间框架: %d 分钟\n", timeframe_minutes))
  return(timeframe_minutes)
}

#' 将回看天数转换为K线数量
#'
#' @param lookback_days 回看天数
#' @param timeframe_minutes 时间框架（分钟）
#' @return 整数，K线数量
convert_days_to_bars <- function(lookback_days, timeframe_minutes) {
  minutes_per_day <- 24 * 60
  bars <- ceiling((lookback_days * minutes_per_day) / timeframe_minutes)
  cat(sprintf("回看 %d 天 = %d 根K线（时间框架：%d分钟）\n",
              lookback_days, bars, timeframe_minutes))
  return(bars)
}

#' 生成交易信号（使用High/Low判断跌幅）
#'
#' @param data data.table，包含OHLC数据
#' @param lookback_bars 回看K线数量
#' @param drop_threshold 跌幅阈值（如0.2表示20%）
#' @return data.table，添加了信号列
generate_signals <- function(data, lookback_bars, drop_threshold) {
  cat(sprintf("\n生成交易信号...\n"))
  cat(sprintf("  回看K线数: %d\n", lookback_bars))
  cat(sprintf("  跌幅阈值: %.1f%%\n", drop_threshold * 100))

  data <- copy(data)
  data[, signal := 0]

  # 从第lookback_bars根K线开始计算
  for (i in (lookback_bars + 1):nrow(data)) {
    # 获取回看窗口
    window_start <- i - lookback_bars
    window_end <- i - 1

    # 计算窗口内的最高价（使用High）
    window_high <- max(data$high[window_start:window_end], na.rm = TRUE)

    # 计算当前K线相对于窗口最高价的跌幅（使用Low）
    current_low <- data$low[i]
    drop_from_high <- (window_high - current_low) / window_high

    # 如果跌幅达到阈值，产生买入信号
    if (!is.na(drop_from_high) && drop_from_high >= drop_threshold) {
      data[i, signal := 1]
    }
  }

  n_signals <- sum(data$signal == 1)
  cat(sprintf("  生成信号数: %d\n", n_signals))

  return(data)
}

#' 执行回测（包含手续费和盘中触发）
#'
#' @param data data.table，包含OHLC和信号
#' @param initial_capital 初始资金
#' @param take_profit 止盈百分比（如0.1表示10%）
#' @param stop_loss 止损百分比（如0.1表示10%）
#' @param fee_rate 单边手续费率（如0.00075表示0.075%）
#' @return list，包含交易记录和统计数据
backtest_with_intrabar_and_fee <- function(data,
                                            initial_capital = 1000,
                                            take_profit = 0.10,
                                            stop_loss = 0.10,
                                            fee_rate = 0.00075) {

  cat(sprintf("\n执行回测...\n"))
  cat(sprintf("  初始资金: $%.2f\n", initial_capital))
  cat(sprintf("  止盈: %.1f%%\n", take_profit * 100))
  cat(sprintf("  止损: %.1f%%\n", stop_loss * 100))
  cat(sprintf("  单边手续费: %.3f%% (双边总计: %.3f%%)\n",
              fee_rate * 100, fee_rate * 2 * 100))

  # 初始化
  capital <- initial_capital
  position <- 0
  entry_price <- 0
  in_position <- FALSE

  # 交易记录
  trades <- list()
  trade_id <- 0

  # 遍历每根K线
  for (i in 1:nrow(data)) {
    row <- data[i]

    # 如果没有持仓，检查是否有买入信号
    if (!in_position && row$signal == 1) {
      # 计算扣除手续费后的入场资金
      entry_capital <- capital * (1 - fee_rate)

      # 使用收盘价作为入场价
      entry_price <- row$close

      # 计算持仓数量
      position <- entry_capital / entry_price

      # 计算止盈止损价格
      take_profit_price <- entry_price * (1 + take_profit)
      stop_loss_price <- entry_price * (1 - stop_loss)

      in_position <- TRUE
      entry_time <- row$timestamp
      entry_index <- i

      cat(sprintf("\n[交易 #%d] 入场\n", trade_id + 1))
      cat(sprintf("  时间: %s\n", format(entry_time)))
      cat(sprintf("  入场价: $%.6f\n", entry_price))
      cat(sprintf("  投入资金: $%.2f (扣除手续费 $%.2f)\n",
                  entry_capital, capital * fee_rate))
      cat(sprintf("  持仓数量: %.4f\n", position))
      cat(sprintf("  止盈价: $%.6f (+%.1f%%)\n", take_profit_price, take_profit * 100))
      cat(sprintf("  止损价: $%.6f (-%.1f%%)\n", stop_loss_price, stop_loss * 100))

      next
    }

    # 如果有持仓，检查是否触发止盈或止损（盘中触发）
    if (in_position) {
      exit_triggered <- FALSE
      exit_price <- 0
      exit_type <- ""

      # 检查是否触发止盈（使用High价）
      tp_triggered <- row$high >= take_profit_price
      # 检查是否触发止损（使用Low价）
      sl_triggered <- row$low <= stop_loss_price

      # 判断优先级：如果同时触发，根据K线形态判断
      if (tp_triggered && sl_triggered) {
        # 阳线：先止盈
        # 阴线：先止损
        is_green <- row$close >= row$open

        if (is_green) {
          exit_price <- take_profit_price
          exit_type <- "TP"
          exit_triggered <- TRUE
        } else {
          exit_price <- stop_loss_price
          exit_type <- "SL"
          exit_triggered <- TRUE
        }

        cat(sprintf("  [同时触发] K线形态: %s, 优先: %s\n",
                    ifelse(is_green, "阳线", "阴线"), exit_type))

      } else if (tp_triggered) {
        exit_price <- take_profit_price
        exit_type <- "TP"
        exit_triggered <- TRUE

      } else if (sl_triggered) {
        exit_price <- stop_loss_price
        exit_type <- "SL"
        exit_triggered <- TRUE
      }

      # 执行出场
      if (exit_triggered) {
        # 计算出场金额（扣除手续费前）
        exit_value_before_fee <- position * exit_price

        # 扣除手续费
        exit_fee <- exit_value_before_fee * fee_rate
        exit_value <- exit_value_before_fee - exit_fee

        # 计算盈亏
        profit <- exit_value - capital
        profit_pct <- (exit_value / capital - 1) * 100

        # 更新资金
        capital <- exit_value

        # 记录交易
        trade_id <- trade_id + 1
        trades[[trade_id]] <- list(
          trade_id = trade_id,
          entry_time = entry_time,
          entry_price = entry_price,
          entry_index = entry_index,
          exit_time = row$timestamp,
          exit_price = exit_price,
          exit_index = i,
          exit_type = exit_type,
          position = position,
          profit = profit,
          profit_pct = profit_pct,
          capital_after = capital,
          entry_fee = initial_capital * fee_rate * (capital / initial_capital),  # 按比例计算
          exit_fee = exit_fee,
          total_fee = initial_capital * fee_rate * (capital / initial_capital) + exit_fee
        )

        cat(sprintf("\n[交易 #%d] 出场 (%s)\n", trade_id, exit_type))
        cat(sprintf("  时间: %s\n", format(row$timestamp)))
        cat(sprintf("  出场价: $%.6f\n", exit_price))
        cat(sprintf("  持仓时间: %d 根K线\n", i - entry_index))
        cat(sprintf("  出场金额: $%.2f (扣除手续费 $%.2f)\n",
                    exit_value, exit_fee))
        cat(sprintf("  盈亏: $%.2f (%.2f%%)\n", profit, profit_pct))
        cat(sprintf("  当前资金: $%.2f\n", capital))

        # 重置持仓状态
        in_position <- FALSE
        position <- 0
        entry_price <- 0
      }
    }
  }

  # 如果最后仍有持仓，使用最后收盘价平仓
  if (in_position) {
    last_row <- data[nrow(data)]
    exit_price <- last_row$close
    exit_value_before_fee <- position * exit_price
    exit_fee <- exit_value_before_fee * fee_rate
    exit_value <- exit_value_before_fee - exit_fee
    profit <- exit_value - capital
    profit_pct <- (exit_value / capital - 1) * 100
    capital <- exit_value

    trade_id <- trade_id + 1
    trades[[trade_id]] <- list(
      trade_id = trade_id,
      entry_time = entry_time,
      entry_price = entry_price,
      entry_index = entry_index,
      exit_time = last_row$timestamp,
      exit_price = exit_price,
      exit_index = nrow(data),
      exit_type = "FINAL",
      position = position,
      profit = profit,
      profit_pct = profit_pct,
      capital_after = capital,
      entry_fee = initial_capital * fee_rate,
      exit_fee = exit_fee,
      total_fee = initial_capital * fee_rate + exit_fee
    )

    cat(sprintf("\n[交易 #%d] 强制平仓（数据结束）\n", trade_id))
    cat(sprintf("  出场价: $%.6f\n", exit_price))
    cat(sprintf("  盈亏: $%.2f (%.2f%%)\n", profit, profit_pct))
  }

  # 转换为data.table
  if (length(trades) > 0) {
    trades_dt <- rbindlist(trades)
  } else {
    trades_dt <- data.table()
  }

  # 计算统计数据
  stats <- calculate_statistics(trades_dt, initial_capital, capital)

  return(list(
    trades = trades_dt,
    stats = stats,
    final_capital = capital
  ))
}

#' 计算回测统计数据
#'
#' @param trades data.table，交易记录
#' @param initial_capital 初始资金
#' @param final_capital 最终资金
#' @return list，统计数据
calculate_statistics <- function(trades, initial_capital, final_capital) {
  if (nrow(trades) == 0) {
    return(list(
      total_trades = 0,
      winning_trades = 0,
      losing_trades = 0,
      win_rate = 0,
      total_profit = 0,
      total_return = 0,
      avg_profit = 0,
      avg_profit_pct = 0,
      max_profit = 0,
      max_loss = 0,
      total_fees = 0
    ))
  }

  total_trades <- nrow(trades)
  winning_trades <- sum(trades$profit > 0)
  losing_trades <- sum(trades$profit < 0)
  win_rate <- winning_trades / total_trades * 100

  total_profit <- final_capital - initial_capital
  total_return <- (final_capital / initial_capital - 1) * 100

  avg_profit <- mean(trades$profit)
  avg_profit_pct <- mean(trades$profit_pct)

  max_profit <- max(trades$profit)
  max_loss <- min(trades$profit)

  total_fees <- sum(trades$total_fee, na.rm = TRUE)

  return(list(
    total_trades = total_trades,
    winning_trades = winning_trades,
    losing_trades = losing_trades,
    win_rate = win_rate,
    total_profit = total_profit,
    total_return = total_return,
    avg_profit = avg_profit,
    avg_profit_pct = avg_profit_pct,
    max_profit = max_profit,
    max_loss = max_loss,
    total_fees = total_fees
  ))
}

#' 打印回测统计结果
#'
#' @param stats list，统计数据
#' @param initial_capital 初始资金
#' @param final_capital 最终资金
print_statistics <- function(stats, initial_capital, final_capital) {
  cat("\n" , rep("=", 70), "\n", sep = "")
  cat("回测统计结果\n")
  cat(rep("=", 70), "\n", sep = "")

  cat(sprintf("\n资金情况:\n"))
  cat(sprintf("  初始资金: $%.2f\n", initial_capital))
  cat(sprintf("  最终资金: $%.2f\n", final_capital))
  cat(sprintf("  总盈亏: $%.2f\n", stats$total_profit))
  cat(sprintf("  总收益率: %.2f%%\n", stats$total_return))

  cat(sprintf("\n交易统计:\n"))
  cat(sprintf("  总交易次数: %d\n", stats$total_trades))
  cat(sprintf("  盈利次数: %d\n", stats$winning_trades))
  cat(sprintf("  亏损次数: %d\n", stats$losing_trades))
  cat(sprintf("  胜率: %.2f%%\n", stats$win_rate))

  cat(sprintf("\n盈亏分析:\n"))
  cat(sprintf("  平均盈亏: $%.2f\n", stats$avg_profit))
  cat(sprintf("  平均盈亏率: %.2f%%\n", stats$avg_profit_pct))
  cat(sprintf("  最大单笔盈利: $%.2f\n", stats$max_profit))
  cat(sprintf("  最大单笔亏损: $%.2f\n", stats$max_loss))

  cat(sprintf("\n手续费:\n"))
  cat(sprintf("  总手续费: $%.2f\n", stats$total_fees))
  cat(sprintf("  手续费占初始资金: %.2f%%\n", stats$total_fees / initial_capital * 100))

  cat("\n", rep("=", 70), "\n", sep = "")
}

#' 完整的回测流程（主函数）
#'
#' @param data data.table，包含OHLC数据和timestamp
#' @param lookback_days 回看天数
#' @param drop_threshold 跌幅阈值
#' @param initial_capital 初始资金
#' @param take_profit 止盈百分比
#' @param stop_loss 止损百分比
#' @param fee_rate 单边手续费率
#' @return list，完整的回测结果
run_backtest <- function(data,
                        lookback_days = 3,
                        drop_threshold = 0.20,
                        initial_capital = 1000,
                        take_profit = 0.10,
                        stop_loss = 0.10,
                        fee_rate = 0.00075) {

  cat("\n", rep("=", 70), "\n", sep = "")
  cat("Pine Script 对齐版回测 - 盘中触发 + 手续费\n")
  cat(rep("=", 70), "\n", sep = "")

  # 1. 检测时间框架
  timeframe_minutes <- detect_timeframe(data)

  # 2. 转换回看天数为K线数量
  lookback_bars <- convert_days_to_bars(lookback_days, timeframe_minutes)

  # 3. 生成信号
  data_with_signals <- generate_signals(data, lookback_bars, drop_threshold)

  # 4. 执行回测
  result <- backtest_with_intrabar_and_fee(
    data_with_signals,
    initial_capital = initial_capital,
    take_profit = take_profit,
    stop_loss = stop_loss,
    fee_rate = fee_rate
  )

  # 5. 打印统计结果
  print_statistics(result$stats, initial_capital, result$final_capital)

  return(result)
}

# ============================================================================
# 导出函数
# ============================================================================

# 主要函数
# - run_backtest: 完整的回测流程
# - backtest_with_intrabar_and_fee: 核心回测引擎
# - generate_signals: 信号生成
# - detect_timeframe: 时间框架检测
# - convert_days_to_bars: 天数转K线数量
