# PEPEUSDT参数优化 - 使用QCrypto::backtest（真正并行版）
#
# 功能：
# 1. 使用QCrypto包的C++后端回测引擎
# 2. 真正的32核并行优化
# 3. 确保信号生成逻辑与TradingView一致
# 4. 0.075%手续费
#
# 作者：Claude Code
# 日期：2025-10-27

# ============================================================================
# 初始化
# ============================================================================

cat("\n", rep("=", 80), "\n", sep="")
cat("PEPEUSDT参数优化 - QCrypto::backtest并行版\n")
cat(rep("=", 80), "\n\n", sep="")

# 加载必要的库
suppressMessages({
  library(parallel)
  library(data.table)
  library(xts)
  library(QCrypto)
  library(RcppRoll)
})

# 配置
CLUSTER_CORES <- 32
FEE_RATE <- 0.00075  # 0.075% (QCrypto使用小数形式)
INITIAL_CAPITAL <- 10000
NEXT_BAR_ENTRY <- FALSE  # 当前K线收盘价入场

cat("配置信息:\n")
cat(sprintf("  CPU核心数: %d\n", CLUSTER_CORES))
cat(sprintf("  手续费率: %.3f%%\n", FEE_RATE * 100))
cat(sprintf("  初始资金: %d USDT\n", INITIAL_CAPITAL))
cat(sprintf("  入场模式: %s\n\n", if(NEXT_BAR_ENTRY) "下一根开盘" else "当前收盘"))

# ============================================================================
# 核心函数：信号生成（与TradingView对齐）
# ============================================================================

#' 检测时间框架
detect_timeframe <- function(data) {
  if (nrow(data) < 2) return(NA)
  time_diffs <- as.numeric(difftime(index(data)[2:min(100, nrow(data))],
                                   index(data)[1:min(99, nrow(data)-1)],
                                   units = "mins"))
  return(median(time_diffs, na.rm = TRUE))
}

#' 生成买入信号
#'
#' 逻辑：当前K线的Low相对于过去N天最高价下跌超过阈值
#'
generate_buy_signals <- function(data, lookback_bars, drop_threshold) {
  n <- nrow(data)

  if (n < lookback_bars + 1) {
    return(rep(0, n))
  }

  # 提取数据
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])

  # 计算回看窗口内的最高价（使用RcppRoll加速）
  # align="right"表示包含当前K线
  window_high <- RcppRoll::roll_max(high_vec, n = lookback_bars,
                                    align = "right", fill = NA)

  # 关键修正：不包括当前K线的最高价
  # 向前推一位，使得window_high[i]是i之前lookback_bars根K线的最高价
  window_high_prev <- c(NA, window_high[1:(n-1)])

  # 计算跌幅：当前Low相对于之前N根K线最高价的跌幅
  drop_percent <- (window_high_prev - low_vec) / window_high_prev

  # 生成买入信号：跌幅达到阈值时买入
  buy_signal <- ifelse(!is.na(drop_percent) & (drop_percent >= drop_threshold), 1, 0)

  return(buy_signal)
}

#' 生成卖出信号（基于QCrypto的简化逻辑）
#'
#' QCrypto::backtest的限制：
#' - 无法精确模拟盘中止盈止损
#' - 只能在K线结束时检查
#'
#' 策略：
#' - 买入后，下一根K线检查High是否触发TP，或Low是否触发SL
#'
generate_sell_signals <- function(data, buy_signal, take_profit, stop_loss) {
  n <- nrow(data)

  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])
  close_vec <- as.numeric(data[, "Close"])
  open_vec <- as.numeric(data[, "Open"])

  sell_signal <- rep(0, n)
  in_position <- FALSE
  entry_price <- 0

  for (i in 1:n) {
    if (!in_position && buy_signal[i] == 1) {
      # 买入：使用当前K线收盘价
      in_position <- TRUE
      entry_price <- close_vec[i]

    } else if (in_position && i > 1) {
      # 检查止盈/止损
      tp_price <- entry_price * (1 + take_profit)
      sl_price <- entry_price * (1 - stop_loss)

      # 检查当前K线是否触发止盈或止损
      hit_tp <- !is.na(high_vec[i]) && high_vec[i] >= tp_price
      hit_sl <- !is.na(low_vec[i]) && low_vec[i] <= sl_price

      if (hit_tp || hit_sl) {
        # 同时触发：根据K线颜色判断
        if (hit_tp && hit_sl) {
          if (close_vec[i] >= open_vec[i]) {
            # 阳线：先触发止盈
            sell_signal[i] <- 1
          } else {
            # 阴线：先触发止损
            sell_signal[i] <- 1
          }
        } else if (hit_tp) {
          sell_signal[i] <- 1
        } else if (hit_sl) {
          sell_signal[i] <- 1
        }

        in_position <- FALSE
      }
    }
  }

  return(sell_signal)
}

# ============================================================================
# 单个参数组合的回测函数（worker函数）
# ============================================================================

backtest_single_param_qcrypto <- function(param_idx, symbol_data, param_grid,
                                         tf_minutes, initial_capital, fee_rate) {
  params <- param_grid[param_idx, ]

  result <- tryCatch({
    # 转换天数为K线数
    bars_per_day <- 1440 / tf_minutes
    lookback_bars <- as.integer(params$lookbackDays * bars_per_day)

    if (nrow(symbol_data) < lookback_bars + 1) {
      stop("数据不足")
    }

    # 生成买入信号
    buy_signal <- generate_buy_signals(
      data = symbol_data,
      lookback_bars = lookback_bars,
      drop_threshold = params$minDropPercent / 100
    )

    # 生成卖出信号
    sell_signal <- generate_sell_signals(
      data = symbol_data,
      buy_signal = buy_signal,
      take_profit = params$takeProfitPercent / 100,
      stop_loss = params$stopLossPercent / 100
    )

    # 提取收盘价作为入场价格
    close_vec <- as.numeric(symbol_data[, "Close"])

    # 调用QCrypto::backtest
    backtest_result <- QCrypto::backtest(
      open = close_vec,
      buy_signal = buy_signal,
      sell_signal = sell_signal,
      initial_capital = initial_capital,
      fee = fee_rate
    )

    # 计算统计指标
    buy_count <- sum(buy_signal, na.rm = TRUE)
    sell_count <- sum(sell_signal, na.rm = TRUE)

    # 提取最终资金
    if ("capital" %in% names(backtest_result)) {
      final_capital <- tail(backtest_result$capital, 1)
      return_pct <- ((final_capital - initial_capital) / initial_capital) * 100

      # 计算胜率
      trades <- backtest_result[backtest_result$sell_signal == 1, ]
      if (nrow(trades) > 0 && "profit" %in% names(trades)) {
        win_rate <- sum(trades$profit > 0, na.rm = TRUE) / nrow(trades) * 100
      } else {
        win_rate <- NA
      }

      # 计算最大回撤
      if ("capital" %in% names(backtest_result)) {
        capital_series <- backtest_result$capital
        cummax_capital <- cummax(capital_series)
        drawdown <- (cummax_capital - capital_series) / cummax_capital * 100
        max_drawdown <- max(drawdown, na.rm = TRUE)
      } else {
        max_drawdown <- NA
      }

      # 计算手续费
      total_fees <- (buy_count + sell_count) * initial_capital * fee_rate
      fee_percentage <- (total_fees / initial_capital) * 100

    } else {
      # QCrypto返回格式可能不同
      final_capital <- NA
      return_pct <- NA
      win_rate <- NA
      max_drawdown <- NA
      total_fees <- 0
      fee_percentage <- 0
    }

    list(
      Signal_Count = buy_count,
      Trade_Count = sell_count,
      Final_Capital = final_capital,
      Return_Percentage = return_pct,
      Win_Rate = win_rate,
      Max_Drawdown = max_drawdown,
      Total_Fees = total_fees,
      Fee_Percentage = fee_percentage,
      Error = ""
    )

  }, error = function(e) {
    list(
      Signal_Count = 0,
      Trade_Count = 0,
      Final_Capital = NA,
      Return_Percentage = NA,
      Win_Rate = NA,
      Max_Drawdown = NA,
      Total_Fees = 0,
      Fee_Percentage = 0,
      Error = as.character(e$message)
    )
  })

  # 返回结果（包含参数信息）
  return(data.frame(
    Timeframe_Minutes = tf_minutes,
    lookbackDays = params$lookbackDays,
    minDropPercent = params$minDropPercent,
    takeProfitPercent = params$takeProfitPercent,
    stopLossPercent = params$stopLossPercent,
    Signal_Count = result$Signal_Count,
    Trade_Count = result$Trade_Count,
    Final_Capital = result$Final_Capital,
    Return_Percentage = result$Return_Percentage,
    Win_Rate = result$Win_Rate,
    Max_Drawdown = result$Max_Drawdown,
    Total_Fees = result$Total_Fees,
    Fee_Percentage = result$Fee_Percentage,
    Error = result$Error,
    stringsAsFactors = FALSE
  ))
}

# ============================================================================
# 加载数据
# ============================================================================

cat("加载数据...\n")
load("data/liaochu.RData")

# 获取所有PEPEUSDT时间框架
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat(sprintf("找到 %d 个PEPEUSDT时间框架:\n", length(pepe_symbols)))
for (sym in pepe_symbols) {
  cat(sprintf("  - %s: %d 根K线\n", sym, nrow(cryptodata[[sym]])))
}
cat("\n")

# ============================================================================
# 参数网格
# ============================================================================

cat("生成参数网格...\n")

tp_seq <- seq(0.5, 5, by = 0.1)
param_grid <- expand.grid(
  lookbackDays = 1:5,
  minDropPercent = seq(2, 10, by = 1),
  takeProfitPercent = tp_seq,
  stopLossPercent = tp_seq,
  stringsAsFactors = FALSE
)

cat(sprintf("参数范围:\n"))
cat(sprintf("  - lookbackDays: %d-%d (%d个值)\n",
            min(param_grid$lookbackDays), max(param_grid$lookbackDays),
            length(unique(param_grid$lookbackDays))))
cat(sprintf("  - minDropPercent: %.0f%%-%.0f%% (%d个值)\n",
            min(param_grid$minDropPercent), max(param_grid$minDropPercent),
            length(unique(param_grid$minDropPercent))))
cat(sprintf("  - takeProfitPercent: %.1f%%-%.1f%% (%d个值)\n",
            min(param_grid$takeProfitPercent), max(param_grid$takeProfitPercent),
            length(unique(param_grid$takeProfitPercent))))
cat(sprintf("  - stopLossPercent: %.1f%%-%.1f%% (%d个值)\n",
            min(param_grid$stopLossPercent), max(param_grid$stopLossPercent),
            length(unique(param_grid$stopLossPercent))))
cat(sprintf("\n总参数组合数: %d\n", nrow(param_grid)))
cat(sprintf("总测试数: %d × %d = %d\n\n",
            nrow(param_grid), length(pepe_symbols),
            nrow(param_grid) * length(pepe_symbols)))

# ============================================================================
# 主执行流程（真正并行）
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("开始并行优化（使用QCrypto::backtest）\n")
cat(rep("=", 80), "\n\n", sep="")

# 记录开始时间
overall_start_time <- Sys.time()

# 创建并行集群
cat(sprintf("启动 %d 核并行集群...\n", CLUSTER_CORES))
cl <- makeCluster(CLUSTER_CORES)

# 导出必要的变量和函数
cat("导出变量和函数到集群...\n")
clusterEvalQ(cl, {
  suppressMessages({
    library(xts)
    library(data.table)
    library(RcppRoll)
    library(QCrypto)
  })
})

clusterExport(cl, c(
  "detect_timeframe",
  "generate_buy_signals",
  "generate_sell_signals",
  "backtest_single_param_qcrypto",
  "param_grid",
  "INITIAL_CAPITAL",
  "FEE_RATE",
  "NEXT_BAR_ENTRY"
), envir = environment())

cat("OK 集群准备完成\n")

# 对每个时间框架进行并行优化
all_results <- list()

for (i in 1:length(pepe_symbols)) {
  symbol_name <- pepe_symbols[i]
  symbol_data <- cryptodata[[symbol_name]]
  tf_minutes <- detect_timeframe(symbol_data)

  cat(sprintf("\n[%d/%d] 处理: %s (时间框架: %d分钟)\n",
              i, length(pepe_symbols), symbol_name, tf_minutes))
  cat(rep("-", 80), "\n", sep="")
  cat(sprintf("参数组合数: %d\n", nrow(param_grid)))

  # 导出当前symbol的数据和时间框架
  clusterExport(cl, c("symbol_data", "tf_minutes"), envir = environment())

  # 真正的并行执行：使用parLapply在32核上并行处理所有参数组合
  cat("开始并行回测（使用QCrypto::backtest）...\n")
  start_time <- Sys.time()

  results_list <- parLapply(cl, 1:nrow(param_grid), function(idx) {
    backtest_single_param_qcrypto(idx, symbol_data, param_grid, tf_minutes,
                                 INITIAL_CAPITAL, FEE_RATE)
  })

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  # 合并结果
  results_df <- rbindlist(results_list)
  results_df$Symbol <- symbol_name

  # 统计
  valid_results <- results_df[!is.na(results_df$Return_Percentage), ]
  cat(sprintf("OK 完成! 用时: %.1f秒 | 有效结果: %d/%d (%.1f%%)\n",
              elapsed,
              nrow(valid_results), nrow(results_df),
              nrow(valid_results) / nrow(results_df) * 100))

  if (nrow(valid_results) > 0) {
    cat(sprintf("   平均收益: %.2f%% | 平均交易数: %.1f | 平均胜率: %.1f%%\n",
                mean(valid_results$Return_Percentage, na.rm = TRUE),
                mean(valid_results$Trade_Count, na.rm = TRUE),
                mean(valid_results$Win_Rate, na.rm = TRUE)))
  }

  all_results[[i]] <- results_df
}

# 停止集群
stopCluster(cl)

# 记录结束时间
overall_end_time <- Sys.time()
elapsed_time <- as.numeric(difftime(overall_end_time, overall_start_time, units = "mins"))

cat("\n\n", rep("=", 80), "\n", sep="")
cat("优化完成!（使用QCrypto::backtest）\n")
cat(rep("=", 80), "\n\n", sep="")

# ============================================================================
# 结果汇总
# ============================================================================

cat("汇总结果...\n")
all_results_df <- rbindlist(all_results)

# 保存完整结果
output_file <- "pepe_qcrypto_optimization_results.csv"
write.csv(all_results_df, output_file, row.names = FALSE)
cat(sprintf("OK 完整结果已保存: %s (%d 行)\n", output_file, nrow(all_results_df)))

# 提取最优参数（按时间框架）
cat("\n生成最优参数报告...\n")
valid_results <- all_results_df[!is.na(all_results_df$Return_Percentage) &
                               all_results_df$Trade_Count > 0, ]

if (nrow(valid_results) > 0) {
  # 按Symbol分组，取收益率最高的
  best_by_symbol <- valid_results[, .SD[order(-Return_Percentage, Max_Drawdown)][1], by = Symbol]

  # 保存最优参数
  best_file <- "pepe_qcrypto_best_parameters.csv"
  write.csv(best_by_symbol, best_file, row.names = FALSE)
  cat(sprintf("OK 最优参数已保存: %s\n", best_file))

  # 显示最优参数
  cat("\n", rep("=", 80), "\n", sep="")
  cat("各时间框架最优参数（QCrypto::backtest）\n")
  cat(rep("=", 80), "\n\n", sep="")

  for (i in 1:nrow(best_by_symbol)) {
    row <- best_by_symbol[i, ]
    cat(sprintf("%s (时间框架: %d分钟)\n", row$Symbol, row$Timeframe_Minutes))
    cat(sprintf("  参数: lookback=%d天, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n",
                row$lookbackDays, row$minDropPercent,
                row$takeProfitPercent, row$stopLossPercent))
    cat(sprintf("  表现: 信号=%d, 交易=%d, 收益=%.2f%%, 胜率=%.1f%%, 回撤=%.2f%%\n",
                row$Signal_Count, row$Trade_Count,
                row$Return_Percentage, row$Win_Rate, row$Max_Drawdown))
    cat(sprintf("  手续费: 总计%.2f USDT (%.2f%%)\n",
                row$Total_Fees, row$Fee_Percentage))
    cat("\n")
  }
}

# ============================================================================
# 统计总结
# ============================================================================

cat(rep("=", 80), "\n", sep="")
cat("执行统计\n")
cat(rep("=", 80), "\n\n", sep="")

cat(sprintf("总测试数: %d\n", nrow(all_results_df)))
cat(sprintf("有效结果: %d (%.1f%%)\n",
            nrow(valid_results),
            nrow(valid_results) / nrow(all_results_df) * 100))

if (nrow(valid_results) > 0) {
  cat(sprintf("有交易的结果: %d (%.1f%%)\n",
              sum(valid_results$Trade_Count > 0),
              sum(valid_results$Trade_Count > 0) / nrow(valid_results) * 100))

  profitable <- sum(valid_results$Return_Percentage > 0, na.rm = TRUE)
  cat(sprintf("盈利的结果: %d (%.1f%%)\n",
              profitable,
              profitable / nrow(valid_results) * 100))

  cat(sprintf("\n性能指标:\n"))
  cat(sprintf("  平均收益率: %.2f%%\n", mean(valid_results$Return_Percentage, na.rm = TRUE)))
  cat(sprintf("  最佳收益率: %.2f%%\n", max(valid_results$Return_Percentage, na.rm = TRUE)))
  cat(sprintf("  平均交易数: %.1f\n", mean(valid_results$Trade_Count, na.rm = TRUE)))
  cat(sprintf("  平均胜率: %.1f%%\n", mean(valid_results$Win_Rate, na.rm = TRUE)))
  cat(sprintf("  平均回撤: %.2f%%\n", mean(valid_results$Max_Drawdown, na.rm = TRUE)))
  cat(sprintf("  平均手续费: %.2f USDT\n", mean(valid_results$Total_Fees, na.rm = TRUE)))
}

cat(sprintf("\n执行时间: %.1f 分钟\n", elapsed_time))
cat(sprintf("平均每个测试: %.3f 秒\n", (elapsed_time * 60) / nrow(all_results_df)))

# 性能分析
tests_per_core <- nrow(all_results_df) / CLUSTER_CORES
cat(sprintf("每核心处理: %.0f 个测试\n", tests_per_core))

cat("\n", rep("=", 80), "\n", sep="")
cat("所有任务完成！（使用QCrypto::backtest）\n")
cat(rep("=", 80), "\n\n", sep="")

cat("生成的文件:\n")
cat(sprintf("  1. %s - 完整结果 (%d 行)\n", output_file, nrow(all_results_df)))
if (exists("best_file")) {
  cat(sprintf("  2. %s - 最优参数 (%d 行)\n", best_file, nrow(best_by_symbol)))
}

cat("\n下一步:\n")
cat("  1. 查看最优参数: read.csv('pepe_qcrypto_best_parameters.csv')\n")
cat("  2. 分析完整结果: read.csv('pepe_qcrypto_optimization_results.csv')\n")
cat("  3. 与TradingView对比验证\n\n")
