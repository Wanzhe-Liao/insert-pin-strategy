# PEPEUSDT修正版优化脚本 - 修复lookbackDays语义问题
# 核心修复：正确将lookbackDays（天数）转换为bar数，对齐Pine Script逻辑
#
# Pine Script逻辑：
# lookbackDays = 3 表示回看3天的历史数据
# highestHighPrev = ta.highest(high, lookbackDays)[1]
#
# 修正说明：
# - 15分钟图：3天 = 3 × (1440/15) = 288 根K线
# - 1小时图：3天 = 3 × (1440/60) = 72 根K线
# - 原代码错误：直接使用 lookbackDays=3 作为3根K线

# 加载必要的包
suppressMessages({
  library(pbapply)
  library(parallel)
  library(xts)
})

# 配置参数
CLUSTER_CORES <- 32
NEXT_BAR_ENTRY <- FALSE  # 收盘价入场，对齐Pine Script的process_orders_on_close=true

# 参数网格（用户指定的版本）
tp_seq <- seq(5, 20, by = 1)
param_grid <- expand.grid(
  lookbackDays = 3:7,
  minDropPercent = seq(5, 20, by = 1),
  takeProfitPercent = tp_seq,
  stopLossPercent = tp_seq
)

cat("=== PEPEUSDT修正版参数优化 ===\n")
cat("参数组合总数:", nrow(param_grid), "\n")
cat("修复内容: 正确转换lookbackDays为实际bar数\n\n")

# 加载数据
load("data/liaochu.RData")

# 筛选PEPEUSDT相关标的
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat("PEPEUSDT分时框架:", paste(pepe_symbols, collapse=", "), "\n")
cat("分时框架数量:", length(pepe_symbols), "\n\n")

# ============================================================================
# 核心修复函数：自动检测时间框架并转换天数为bar数
# ============================================================================

detect_timeframe_minutes <- function(xts_data) {
  # 自动检测xts数据的时间框架（返回分钟数）
  if (nrow(xts_data) < 2) return(NA)

  # 计算前100个时间戳的差值（避免异常值）
  n_samples <- min(100, nrow(xts_data) - 1)
  time_diffs <- as.numeric(difftime(index(xts_data)[2:(n_samples+1)],
                                     index(xts_data)[1:n_samples],
                                     units = "mins"))

  # 使用中位数（更鲁棒）
  tf_minutes <- median(time_diffs, na.rm = TRUE)
  return(round(tf_minutes))
}

# ============================================================================
# 修正版信号生成函数
# ============================================================================

build_signals_fixed <- function(data, lookbackDays, minDropPercent) {
  # 数据验证
  if (nrow(data) < 10) {
    return(rep(FALSE, nrow(data)))
  }

  # 关键修复：检测时间框架并正确转换天数为bar数
  tf_minutes <- detect_timeframe_minutes(data)

  if (is.na(tf_minutes) || tf_minutes <= 0) {
    warning("无法检测时间框架，使用默认15分钟")
    tf_minutes <- 15
  }

  # 正确转换：lookbackDays（天） → lookbackBars（根K线）
  # 公式：bars_per_day = 1440分钟/天 / tf_minutes
  bars_per_day <- 1440 / tf_minutes
  lookbackBars <- as.integer(lookbackDays * bars_per_day)

  # 调试信息（首次调用时输出）
  if (!exists(".signal_debug_printed", envir = .GlobalEnv)) {
    cat(sprintf("  [调试] 时间框架: %d分钟 | lookbackDays: %d天 → lookbackBars: %d根K线\n",
                tf_minutes, lookbackDays, lookbackBars))
    assign(".signal_debug_printed", TRUE, envir = .GlobalEnv)
  }

  # 初始化信号向量
  signals <- rep(FALSE, nrow(data))

  # 确保有足够的历史数据
  if (nrow(data) <= lookbackBars) {
    return(signals)
  }

  # 提取价格数据
  high_prices <- as.numeric(data[, "High"])
  low_prices <- as.numeric(data[, "Low"])

  # 从第 lookbackBars+1 根K线开始计算信号
  for (i in (lookbackBars + 1):nrow(data)) {
    # 计算过去 lookbackBars 根K线的最高价（不包括当前K线）
    # 对应 Pine Script: ta.highest(high, lookbackDays)[1]
    window_start <- max(1, i - lookbackBars)
    window_end <- i - 1

    window_highs <- high_prices[window_start:window_end]
    window_high <- max(window_highs, na.rm = TRUE)

    current_low <- low_prices[i]

    # 计算跌幅百分比
    if (!is.na(window_high) && !is.na(current_low) && window_high > 0) {
      drop_percent <- ((window_high - current_low) / window_high) * 100

      # 满足条件则标记信号
      if (drop_percent >= minDropPercent) {
        signals[i] <- TRUE
      }
    }
  }

  return(signals)
}

# ============================================================================
# 回测函数（带详细统计）
# ============================================================================

backtest_strategy_fixed <- function(data, lookbackDays, minDropPercent,
                                    takeProfitPercent, stopLossPercent) {
  tryCatch({
    # 数据验证
    if (nrow(data) < 10) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 使用修正版信号生成
    signals <- build_signals_fixed(data, lookbackDays, minDropPercent)
    signal_count <- sum(signals, na.rm = TRUE)

    # 如果没有信号，直接返回
    if (signal_count == 0) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
        BH_Return = NA, Excess_Return = NA
      ))
    }

    # 初始化回测变量
    capital <- 10000
    position <- 0
    entry_price <- 0
    trades <- c()
    capital_curve <- c()

    # 逐K线模拟交易
    for (i in 1:nrow(data)) {
      # 入场逻辑
      if (signals[i] && position == 0) {
        # 根据NEXT_BAR_ENTRY决定入场价格
        if (NEXT_BAR_ENTRY && i < nrow(data)) {
          entry_price <- as.numeric(data[i+1, "Open"])
        } else {
          entry_price <- as.numeric(data[i, "Close"])
        }

        # 验证入场价格有效
        if (!is.na(entry_price) && entry_price > 0) {
          position <- capital / entry_price
          capital <- 0
        }
      }

      # 持仓管理
      if (position > 0) {
        current_price <- as.numeric(data[i, "Close"])

        if (!is.na(current_price) && current_price > 0 && entry_price > 0) {
          # 计算盈亏百分比
          pnl_percent <- ((current_price - entry_price) / entry_price) * 100

          # 检查止盈或止损
          if (pnl_percent >= takeProfitPercent || pnl_percent <= -stopLossPercent) {
            # 出场
            exit_capital <- position * current_price
            trades <- c(trades, pnl_percent)
            capital <- exit_capital
            position <- 0
            entry_price <- 0
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

    # 处理未平仓的持仓
    if (position > 0) {
      final_price <- as.numeric(data[nrow(data), "Close"])
      if (!is.na(final_price) && final_price > 0 && entry_price > 0) {
        final_pnl <- ((final_price - entry_price) / entry_price) * 100
        trades <- c(trades, final_pnl)
        capital <- position * final_price
      }
    }

    # 如果没有完成任何交易
    if (length(trades) == 0) {
      return(list(
        Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
        Win_Rate = NA, Trade_Count = 0, Signal_Count = signal_count,
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
      BH_Return = bh_return,
      Excess_Return = excess_return
    ))

  }, error = function(e) {
    # 错误处理
    return(list(
      Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
      Win_Rate = NA, Trade_Count = 0, Signal_Count = 0,
      BH_Return = NA, Excess_Return = NA,
      Error = as.character(e$message)
    ))
  })
}

# ============================================================================
# 单个参数组合测试函数（带进度更新）
# ============================================================================

test_single_combination <- function(i, param_grid, symbols_data, progress_env) {
  params <- param_grid[i, ]

  results <- list()
  for (symbol in names(symbols_data)) {
    data <- symbols_data[[symbol]]

    # 执行回测
    result <- backtest_strategy_fixed(
      data,
      params$lookbackDays,
      params$minDropPercent,
      params$takeProfitPercent,
      params$stopLossPercent
    )

    # 组装结果
    results[[length(results) + 1]] <- data.frame(
      Symbol = symbol,
      lookbackDays = as.numeric(params$lookbackDays),
      minDropPercent = as.numeric(params$minDropPercent),
      takeProfitPercent = as.numeric(params$takeProfitPercent),
      stopLossPercent = as.numeric(params$stopLossPercent),
      Signal_Count = as.integer(result$Signal_Count),
      Trade_Count = as.integer(result$Trade_Count),
      Final_Capital = as.numeric(result$Final_Capital),
      Return_Percentage = as.numeric(result$Return_Percentage),
      Max_Drawdown = as.numeric(result$Max_Drawdown),
      Win_Rate = as.numeric(result$Win_Rate),
      BH_Return = as.numeric(result$BH_Return),
      Excess_Return = as.numeric(result$Excess_Return),
      stringsAsFactors = FALSE
    )
  }

  # 更新进度
  progress_env$completed <- progress_env$completed + 1
  if (progress_env$completed %% 50 == 0 || progress_env$completed == progress_env$total) {
    cat(sprintf("\r进度: %d/%d (%.1f%%) ",
                progress_env$completed, progress_env$total,
                (progress_env$completed / progress_env$total) * 100))
    flush.console()
  }

  return(do.call(rbind, results))
}

# ============================================================================
# 主执行流程
# ============================================================================

# 准备PEPEUSDT数据
pepe_data <- cryptodata[pepe_symbols]
names(pepe_data) <- pepe_symbols

cat("\n开始修正版PEPEUSDT优化...\n")
cat("使用", CLUSTER_CORES, "个CPU核心\n")
cat("参数组合总数:", nrow(param_grid), "\n")
cat("分时框架数:", length(pepe_symbols), "\n")
cat("总计算任务数:", nrow(param_grid), "个参数组合\n\n")

# 创建进度环境
progress_env <- new.env()
progress_env$completed <- 0
progress_env$total <- nrow(param_grid)

# 重置调试标志
if (exists(".signal_debug_printed", envir = .GlobalEnv)) {
  rm(".signal_debug_printed", envir = .GlobalEnv)
}

# 开始计时
start_time <- Sys.time()

# 创建集群
cat("初始化并行集群...\n")
cl <- makeCluster(CLUSTER_CORES)
clusterEvalQ(cl, {
  suppressMessages(library(xts))
})

# 导出必要的变量和函数到集群
clusterExport(cl, c(
  "detect_timeframe_minutes",
  "build_signals_fixed",
  "backtest_strategy_fixed",
  "test_single_combination",
  "pepe_data",
  "param_grid",
  "NEXT_BAR_ENTRY",
  "progress_env"
), envir = environment())

# 执行并行计算
cat("开始并行计算...\n\n")
results_list <- parLapply(cl, 1:nrow(param_grid), function(i) {
  test_single_combination(i, param_grid, pepe_data, progress_env)
})

# 停止集群
stopCluster(cl)

cat("\n\n计算完成！\n")

# 合并结果
all_results <- do.call(rbind, results_list)

# 保存结果
output_file <- "pepe_results_fixed.csv"
write.csv(all_results, output_file, row.names = FALSE)

end_time <- Sys.time()
elapsed_time <- end_time - start_time

# ============================================================================
# 结果统计和对比
# ============================================================================

cat("\n=== 结果统计 ===\n")
cat("结果已保存到:", output_file, "\n")
cat("总行数:", nrow(all_results), "\n")
cat("计算耗时:", round(as.numeric(elapsed_time, units = "mins"), 2), "分钟\n\n")

# 有效结果统计
valid_results <- all_results[!is.na(all_results$Return_Percentage), ]
cat("有效结果数:", nrow(valid_results), "/", nrow(all_results), "\n")

if (nrow(valid_results) > 0) {
  cat("\n性能指标汇总:\n")
  cat("  最佳收益率:", round(max(valid_results$Return_Percentage, na.rm = TRUE), 2), "%\n")
  cat("  平均收益率:", round(mean(valid_results$Return_Percentage, na.rm = TRUE), 2), "%\n")
  cat("  平均交易次数:", round(mean(valid_results$Trade_Count, na.rm = TRUE), 1), "\n")
  cat("  平均信号数:", round(mean(valid_results$Signal_Count, na.rm = TRUE), 1), "\n")
  cat("  平均胜率:", round(mean(valid_results$Win_Rate, na.rm = TRUE), 2), "%\n")

  # 找出最优参数
  cat("\n=== 各时间框架最优参数 ===\n")
  for (sym in pepe_symbols) {
    sym_results <- valid_results[valid_results$Symbol == sym, ]
    if (nrow(sym_results) > 0) {
      best_idx <- which.max(sym_results$Return_Percentage)
      best <- sym_results[best_idx, ]
      cat(sprintf("\n%s:\n", sym))
      cat(sprintf("  lookbackDays=%d, minDrop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n",
                  best$lookbackDays, best$minDropPercent,
                  best$takeProfitPercent, best$stopLossPercent))
      cat(sprintf("  收益率=%.2f%%, 交易次数=%d, 信号数=%d, 胜率=%.1f%%\n",
                  best$Return_Percentage, best$Trade_Count,
                  best$Signal_Count, best$Win_Rate))
    }
  }
}

# 对比原始结果（如果存在）
if (file.exists("pepe_results.csv")) {
  cat("\n=== 与原始版本对比 ===\n")
  old_results <- read.csv("pepe_results.csv", stringsAsFactors = FALSE)

  cat("原始版本:\n")
  cat("  平均信号数:", round(mean(old_results$Signal_Count, na.rm = TRUE), 1), "\n")
  cat("  平均交易数:", round(mean(old_results$Trade_Count, na.rm = TRUE), 1), "\n")

  cat("修正版本:\n")
  cat("  平均信号数:", round(mean(all_results$Signal_Count, na.rm = TRUE), 1), "\n")
  cat("  平均交易数:", round(mean(all_results$Trade_Count, na.rm = TRUE), 1), "\n")

  cat("\n差异分析:\n")
  signal_diff <- mean(all_results$Signal_Count, na.rm = TRUE) - mean(old_results$Signal_Count, na.rm = TRUE)
  trade_diff <- mean(all_results$Trade_Count, na.rm = TRUE) - mean(old_results$Trade_Count, na.rm = TRUE)

  cat(sprintf("  信号数变化: %+.1f (%.1f%%)\n",
              signal_diff,
              signal_diff / mean(old_results$Signal_Count, na.rm = TRUE) * 100))
  cat(sprintf("  交易数变化: %+.1f\n", trade_diff))
}

cat("\n优化完成！请查看", output_file, "文件获取详细结果。\n")
