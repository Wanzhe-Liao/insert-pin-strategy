# 使用QCrypto::backtest函数适配"三日暴跌接针策略"
#
# 功能：
# 1. 将策略逻辑转换为QCrypto::backtest所需的信号格式
# 2. 利用QCrypto的C++后端提升性能
# 3. 支持止盈/止损逻辑
#
# 作者：Claude Code
# 日期：2025-10-26

library(QCrypto)
library(xts)
library(RcppRoll)

# ============================================================================
# 信号生成函数（适配QCrypto）
# ============================================================================

#' 生成"三日暴跌接针"策略的买入信号
#'
#' @param data xts数据（需包含High, Low列）
#' @param lookback_bars 回看K线数
#' @param drop_threshold 跌幅阈值（如0.20表示20%）
#' @return 买入信号向量（0/1）
generate_buy_signals <- function(data, lookback_bars, drop_threshold) {
  n <- nrow(data)

  if (n < lookback_bars + 1) {
    return(rep(0, n))
  }

  # 提取数据
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])

  # 计算回看窗口内的最高价（使用RcppRoll加速）
  window_high <- RcppRoll::roll_max(high_vec, n = lookback_bars, align = "right", fill = NA)

  # 滞后一根K线（不包括当前K线）
  window_high_prev <- c(NA, window_high[1:(n-1)])

  # 计算跌幅
  drop_percent <- (window_high_prev - low_vec) / window_high_prev

  # 生成买入信号
  buy_signal <- ifelse(!is.na(drop_percent) & (drop_percent >= drop_threshold), 1, 0)

  return(buy_signal)
}

#' 生成止盈/止损的卖出信号
#'
#' @param data xts数据（需包含High, Low列）
#' @param entry_price 入场价格向量
#' @param take_profit 止盈比例（如0.10表示10%）
#' @param stop_loss 止损比例（如0.10表示10%）
#' @return 卖出信号向量（0/1）
generate_sell_signals <- function(data, entry_price, take_profit, stop_loss) {
  n <- nrow(data)
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])

  sell_signal <- rep(0, n)

  for (i in 1:n) {
    if (entry_price[i] > 0) {
      tp_price <- entry_price[i] * (1 + take_profit)
      sl_price <- entry_price[i] * (1 - stop_loss)

      # 检查是否触发止盈或止损
      if (!is.na(high_vec[i]) && high_vec[i] >= tp_price) {
        sell_signal[i] <- 1
      } else if (!is.na(low_vec[i]) && low_vec[i] <= sl_price) {
        sell_signal[i] <- 1
      }
    }
  }

  return(sell_signal)
}

# ============================================================================
# 主回测函数（使用QCrypto::backtest）
# ============================================================================

#' 使用QCrypto::backtest执行策略回测
#'
#' @param data xts数据（OHLC格式）
#' @param lookback_days 回看天数
#' @param drop_threshold 跌幅阈值（小数，如0.20）
#' @param take_profit 止盈比例（小数）
#' @param stop_loss 止损比例（小数）
#' @param initial_capital 初始资金
#' @param fee_rate 手续费率（小数，如0.00075）
#' @return QCrypto回测结果
backtest_with_qcrypto <- function(data,
                                  lookback_days,
                                  drop_threshold,
                                  take_profit,
                                  stop_loss,
                                  initial_capital = 10000,
                                  fee_rate = 0.00075) {

  # 检测时间框架
  if (nrow(data) < 2) {
    stop("数据行数不足")
  }

  time_diffs <- as.numeric(difftime(index(data)[2:min(100, nrow(data))],
                                   index(data)[1:min(99, nrow(data)-1)],
                                   units = "mins"))
  tf_minutes <- median(time_diffs, na.rm = TRUE)

  # 转换天数为K线数
  bars_per_day <- 1440 / tf_minutes
  lookback_bars <- as.integer(lookback_days * bars_per_day)

  if (nrow(data) < lookback_bars + 1) {
    stop(sprintf("数据不足：需要%d根，实际%d根", lookback_bars+1, nrow(data)))
  }

  # 生成买入信号
  buy_signal <- generate_buy_signals(data, lookback_bars, drop_threshold)

  # 简单策略：买入后立即计算止盈/止损
  # 注意：QCrypto::backtest是简化版，不支持复杂的盘中止盈止损
  # 这里我们使用收盘价作为入场价
  close_vec <- as.numeric(data[, "Close"])

  # 生成卖出信号（简化版：买入后下一根K线检查止盈止损）
  sell_signal <- rep(0, nrow(data))
  in_position <- FALSE
  entry_price <- 0

  for (i in 1:nrow(data)) {
    if (!in_position && buy_signal[i] == 1) {
      # 买入
      in_position <- TRUE
      entry_price <- close_vec[i]
    } else if (in_position && i > 1) {
      # 检查止盈/止损
      high <- as.numeric(data[i, "High"])
      low <- as.numeric(data[i, "Low"])

      tp_price <- entry_price * (1 + take_profit)
      sl_price <- entry_price * (1 - stop_loss)

      if (!is.na(high) && high >= tp_price) {
        sell_signal[i] <- 1
        in_position <- FALSE
      } else if (!is.na(low) && low <= sl_price) {
        sell_signal[i] <- 1
        in_position <- FALSE
      }
    }
  }

  # 调用QCrypto::backtest
  # 注意：QCrypto使用Open价格，我们这里用Close（更保守）
  result <- QCrypto::backtest(
    open = close_vec,
    buy_signal = buy_signal,
    sell_signal = sell_signal,
    initial_capital = initial_capital,
    fee = fee_rate
  )

  return(result)
}

# ============================================================================
# 便捷测试函数
# ============================================================================

#' 快速测试单个参数组合
#'
#' @param data xts数据
#' @param lookback_days 回看天数
#' @param drop_pct 跌幅百分比
#' @param tp_pct 止盈百分比
#' @param sl_pct 止损百分比
#' @return 回测结果摘要
test_qcrypto_strategy <- function(data, lookback_days, drop_pct, tp_pct, sl_pct) {

  cat(sprintf("测试参数: lookback=%d天, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n",
              lookback_days, drop_pct, tp_pct, sl_pct))

  result <- backtest_with_qcrypto(
    data = data,
    lookback_days = lookback_days,
    drop_threshold = drop_pct / 100,
    take_profit = tp_pct / 100,
    stop_loss = sl_pct / 100,
    initial_capital = 10000,
    fee_rate = 0.00075
  )

  # 计算统计
  trades <- result[result$buy_signal == 1 | result$sell_signal == 1, ]
  buy_count <- sum(result$buy_signal, na.rm = TRUE)
  sell_count <- sum(result$sell_signal, na.rm = TRUE)

  # 提取最终资金（假设backtest_cpp返回capital列）
  if ("capital" %in% names(result)) {
    final_capital <- tail(result$capital, 1)
    return_pct <- ((final_capital - 10000) / 10000) * 100

    cat(sprintf("结果: 买入信号=%d, 卖出信号=%d, 最终资金=%.2f, 收益=%.2f%%\n",
                buy_count, sell_count, final_capital, return_pct))
  } else {
    cat("注意：backtest_cpp返回格式可能不同，请检查结果列\n")
    print(head(result))
  }

  return(result)
}

# ============================================================================
# 示例用法
# ============================================================================

cat("\nOK QCrypto适配器加载完成！\n\n")
cat("主要函数：\n")
cat("  - backtest_with_qcrypto(): 使用QCrypto::backtest执行策略\n")
cat("  - test_qcrypto_strategy(): 快速测试单个参数组合\n")
cat("  - generate_buy_signals(): 生成买入信号\n")
cat("  - generate_sell_signals(): 生成卖出信号\n\n")

cat("示例用法：\n")
cat('  load("liaochu.RData")\n')
cat('  data <- cryptodata$PEPEUSDT_15m\n')
cat('  result <- test_qcrypto_strategy(data, lookback_days=3, drop_pct=20, tp_pct=10, sl_pct=10)\n\n')

cat("优势：\n")
cat("  OK 使用QCrypto的C++后端，性能优秀\n")
cat("  OK 简洁的信号接口\n")
cat("  OK 自动处理复利和手续费\n\n")

cat("限制：\n")
cat("  WARN QCrypto::backtest是简化版，止盈/止损逻辑可能不如自定义实现精确\n")
cat("  WARN 需要将策略转换为买卖信号格式\n\n")
