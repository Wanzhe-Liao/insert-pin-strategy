# ============================================================================
# 详细对比验证脚本 - 用于诊断TradingView与R回测差异
# ============================================================================
# 目标：
# 1. 回测具体参数组合：lookbackDays=3, minDrop=20%, TP=10%, SL=10%
# 2. 输出前10笔交易的完整详情
# 3. 生成可对比的CSV文件
# 4. 检查异常交易和常见问题
# 5. 分析quick_test_10params_results.csv中的异常模式
# ============================================================================

suppressMessages({
  library(xts)
})

cat("\n")
cat(rep("=", 80), "\n", sep="")
cat("详细对比验证脚本 - TradingView vs R 回测差异诊断\n")
cat(rep("=", 80), "\n\n")

# ============================================================================
# 第1部分：加载数据和设置参数
# ============================================================================

cat("第1部分：数据加载\n")
cat(rep("-", 80), "\n", sep="")

# 加载数据
load("data/liaochu.RData")

# 目标参数
TARGET_SYMBOL <- "PEPEUSDT_15m"
TARGET_LOOKBACK <- 3
TARGET_MINDROP <- 20
TARGET_TP <- 10
TARGET_SL <- 10

cat(sprintf("目标标的: %s\n", TARGET_SYMBOL))
cat(sprintf("目标参数: lookback=%d天, minDrop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n\n",
            TARGET_LOOKBACK, TARGET_MINDROP, TARGET_TP, TARGET_SL))

# 获取数据
if (!TARGET_SYMBOL %in% names(cryptodata)) {
  stop(sprintf("错误：找不到标的 %s", TARGET_SYMBOL))
}

data <- cryptodata[[TARGET_SYMBOL]]
cat(sprintf("数据行数: %d\n", nrow(data)))
cat(sprintf("时间范围: %s 至 %s\n",
            format(index(data)[1], "%Y-%m-%d %H:%M"),
            format(index(data)[nrow(data)], "%Y-%m-%d %H:%M")))

# 检测时间框架
detect_timeframe_minutes <- function(xts_data) {
  if (nrow(xts_data) < 2) return(NA)
  n_samples <- min(100, nrow(xts_data) - 1)
  time_diffs <- as.numeric(difftime(index(xts_data)[2:(n_samples+1)],
                                     index(xts_data)[1:n_samples],
                                     units = "mins"))
  tf_minutes <- median(time_diffs, na.rm = TRUE)
  return(round(tf_minutes))
}

tf_minutes <- detect_timeframe_minutes(data)
cat(sprintf("检测到时间框架: %d分钟\n", tf_minutes))

bars_per_day <- 1440 / tf_minutes
lookbackBars <- as.integer(TARGET_LOOKBACK * bars_per_day)
cat(sprintf("回看天数%d天 = %d根K线\n\n", TARGET_LOOKBACK, lookbackBars))

# ============================================================================
# 第2部分：信号生成（带详细日志）
# ============================================================================

cat("第2部分：信号生成\n")
cat(rep("-", 80), "\n", sep="")

generate_signals_with_log <- function(data, lookbackBars, minDropPercent, log_limit = 10) {
  n <- nrow(data)
  signals <- rep(FALSE, n)
  signal_details <- list()

  high_prices <- as.numeric(data[, "High"])
  low_prices <- as.numeric(data[, "Low"])

  cat(sprintf("从第%d根K线开始扫描信号...\n", lookbackBars + 1))

  signal_count <- 0

  for (i in (lookbackBars + 1):n) {
    window_start <- max(1, i - lookbackBars)
    window_end <- i - 1

    window_high <- max(high_prices[window_start:window_end], na.rm = TRUE)
    current_low <- low_prices[i]

    if (!is.na(window_high) && !is.na(current_low) && window_high > 0) {
      drop_percent <- ((window_high - current_low) / window_high) * 100

      if (drop_percent >= minDropPercent) {
        signals[i] <- TRUE
        signal_count <- signal_count + 1

        # 记录信号详情
        signal_info <- list(
          signal_no = signal_count,
          bar_index = i,
          timestamp = index(data)[i],
          window_high = window_high,
          current_low = current_low,
          drop_percent = drop_percent,
          close_price = as.numeric(data[i, "Close"])
        )

        signal_details[[signal_count]] <- signal_info

        # 输出前几个信号
        if (signal_count <= log_limit) {
          cat(sprintf("  信号#%d [K线%d]: %s\n",
                      signal_count, i, format(signal_info$timestamp, "%Y-%m-%d %H:%M")))
          cat(sprintf("    回看窗口最高价: %.8f\n", window_high))
          cat(sprintf("    当前K线最低价: %.8f\n", current_low))
          cat(sprintf("    下跌幅度: %.2f%%\n", drop_percent))
          cat(sprintf("    收盘价: %.8f\n\n", signal_info$close_price))
        }
      }
    }

    # 进度显示
    if (i %% 10000 == 0) {
      cat(sprintf("  已扫描: %d/%d K线 (%.1f%%) | 信号数: %d\n",
                  i, n, i/n*100, signal_count))
    }
  }

  cat(sprintf("\n信号生成完成！总信号数: %d\n\n", signal_count))

  return(list(
    signals = signals,
    details = signal_details,
    count = signal_count
  ))
}

signal_result <- generate_signals_with_log(data, lookbackBars, TARGET_MINDROP, log_limit = 10)

# ============================================================================
# 第3部分：回测执行（记录每笔交易详情）
# ============================================================================

cat("第3部分：回测执行\n")
cat(rep("-", 80), "\n", sep="")

backtest_with_detailed_trades <- function(data, signals, takeProfitPercent, stopLossPercent) {
  capital <- 10000
  position <- 0
  entry_price <- 0
  entry_bar <- 0

  trades <- list()
  trade_count <- 0

  cat("开始回测...\n\n")

  for (i in 1:nrow(data)) {
    # 入场逻辑
    if (signals[i] && position == 0) {
      entry_price <- as.numeric(data[i, "Close"])

      if (!is.na(entry_price) && entry_price > 0) {
        position <- capital / entry_price
        capital <- 0
        entry_bar <- i

        trade_count <- trade_count + 1

        # 记录入场信息（待完成）
        trades[[trade_count]] <- list(
          trade_no = trade_count,
          signal_bar = i,
          signal_time = index(data)[i],
          signal_price = entry_price,
          entry_bar = i,
          entry_time = index(data)[i],
          entry_price = entry_price,
          exit_bar = NA,
          exit_time = NA,
          exit_price = NA,
          pnl_percent = NA,
          exit_type = NA,
          holding_bars = NA
        )

        if (trade_count <= 10) {
          cat(sprintf("交易#%d 入场 [K线%d]: %s\n",
                      trade_count, i, format(index(data)[i], "%Y-%m-%d %H:%M")))
          cat(sprintf("  入场价格: %.8f\n", entry_price))
          cat(sprintf("  止盈目标: %.8f (+%.1f%%)\n",
                      entry_price * (1 + takeProfitPercent/100), takeProfitPercent))
          cat(sprintf("  止损价格: %.8f (-%.1f%%)\n\n",
                      entry_price * (1 - stopLossPercent/100), stopLossPercent))
        }
      }
    }

    # 持仓管理
    if (position > 0) {
      current_price <- as.numeric(data[i, "Close"])

      if (!is.na(current_price) && current_price > 0 && entry_price > 0) {
        pnl_percent <- ((current_price - entry_price) / entry_price) * 100

        # 检查止盈止损
        if (pnl_percent >= takeProfitPercent) {
          # 止盈
          exit_capital <- position * current_price
          capital <- exit_capital

          # 更新交易记录
          trades[[trade_count]]$exit_bar <- i
          trades[[trade_count]]$exit_time <- index(data)[i]
          trades[[trade_count]]$exit_price <- current_price
          trades[[trade_count]]$pnl_percent <- pnl_percent
          trades[[trade_count]]$exit_type <- "TP"
          trades[[trade_count]]$holding_bars <- i - entry_bar

          if (trade_count <= 10) {
            cat(sprintf("交易#%d 止盈 [K线%d]: %s\n",
                        trade_count, i, format(index(data)[i], "%Y-%m-%d %H:%M")))
            cat(sprintf("  出场价格: %.8f\n", current_price))
            cat(sprintf("  盈亏: +%.2f%%\n", pnl_percent))
            cat(sprintf("  持仓时间: %d根K线\n\n", i - entry_bar))
          }

          position <- 0
          entry_price <- 0
          entry_bar <- 0

        } else if (pnl_percent <= -stopLossPercent) {
          # 止损
          exit_capital <- position * current_price
          capital <- exit_capital

          # 更新交易记录
          trades[[trade_count]]$exit_bar <- i
          trades[[trade_count]]$exit_time <- index(data)[i]
          trades[[trade_count]]$exit_price <- current_price
          trades[[trade_count]]$pnl_percent <- pnl_percent
          trades[[trade_count]]$exit_type <- "SL"
          trades[[trade_count]]$holding_bars <- i - entry_bar

          if (trade_count <= 10) {
            cat(sprintf("交易#%d 止损 [K线%d]: %s\n",
                        trade_count, i, format(index(data)[i], "%Y-%m-%d %H:%M")))
            cat(sprintf("  出场价格: %.8f\n", current_price))
            cat(sprintf("  盈亏: %.2f%%\n", pnl_percent))
            cat(sprintf("  持仓时间: %d根K线\n\n", i - entry_bar))
          }

          position <- 0
          entry_price <- 0
          entry_bar <- 0
        }
      }
    }
  }

  # 处理未平仓
  if (position > 0) {
    final_price <- as.numeric(data[nrow(data), "Close"])
    if (!is.na(final_price) && final_price > 0) {
      final_pnl <- ((final_price - entry_price) / entry_price) * 100
      capital <- position * final_price

      trades[[trade_count]]$exit_bar <- nrow(data)
      trades[[trade_count]]$exit_time <- index(data)[nrow(data)]
      trades[[trade_count]]$exit_price <- final_price
      trades[[trade_count]]$pnl_percent <- final_pnl
      trades[[trade_count]]$exit_type <- "未平仓"
      trades[[trade_count]]$holding_bars <- nrow(data) - entry_bar

      cat(sprintf("交易#%d 未平仓（强制平仓） [K线%d]: %s\n",
                  trade_count, nrow(data), format(index(data)[nrow(data)], "%Y-%m-%d %H:%M")))
      cat(sprintf("  最终价格: %.8f\n", final_price))
      cat(sprintf("  盈亏: %.2f%%\n\n", final_pnl))
    }
  }

  cat(sprintf("回测完成！总交易数: %d\n\n", trade_count))

  return(list(
    trades = trades,
    final_capital = capital
  ))
}

backtest_result <- backtest_with_detailed_trades(
  data,
  signal_result$signals,
  TARGET_TP,
  TARGET_SL
)

# ============================================================================
# 第4部分：汇总统计
# ============================================================================

cat("第4部分：统计汇总\n")
cat(rep("-", 80), "\n", sep="")

trades <- backtest_result$trades
n_trades <- length(trades)

if (n_trades > 0) {
  # 转换为数据框
  trades_df <- data.frame(
    Trade_No = sapply(trades, function(x) x$trade_no),
    Signal_Time = sapply(trades, function(x) format(x$signal_time, "%Y-%m-%d %H:%M:%S")),
    Signal_Price = sapply(trades, function(x) x$signal_price),
    Entry_Time = sapply(trades, function(x) format(x$entry_time, "%Y-%m-%d %H:%M:%S")),
    Entry_Price = sapply(trades, function(x) x$entry_price),
    Exit_Time = sapply(trades, function(x) {
      if (is.na(x$exit_time)) return(NA)
      format(x$exit_time, "%Y-%m-%d %H:%M:%S")
    }),
    Exit_Price = sapply(trades, function(x) x$exit_price),
    PnL_Percent = sapply(trades, function(x) x$pnl_percent),
    Exit_Type = sapply(trades, function(x) x$exit_type),
    Holding_Bars = sapply(trades, function(x) x$holding_bars),
    stringsAsFactors = FALSE
  )

  # 计算统计
  pnl_values <- as.numeric(trades_df$PnL_Percent)
  pnl_values <- pnl_values[!is.na(pnl_values)]

  wins <- sum(pnl_values > 0)
  losses <- sum(pnl_values <= 0)
  win_rate <- if (length(pnl_values) > 0) wins / length(pnl_values) * 100 else 0

  final_capital <- backtest_result$final_capital
  total_return <- ((final_capital - 10000) / 10000) * 100

  avg_pnl <- mean(pnl_values, na.rm = TRUE)
  avg_win <- mean(pnl_values[pnl_values > 0], na.rm = TRUE)
  avg_loss <- mean(pnl_values[pnl_values <= 0], na.rm = TRUE)

  avg_holding <- mean(as.numeric(trades_df$Holding_Bars), na.rm = TRUE)
  avg_holding_hours <- avg_holding * tf_minutes / 60

  tp_count <- sum(trades_df$Exit_Type == "TP", na.rm = TRUE)
  sl_count <- sum(trades_df$Exit_Type == "SL", na.rm = TRUE)

  cat(sprintf("信号总数: %d\n", signal_result$count))
  cat(sprintf("交易总数: %d\n", n_trades))
  cat(sprintf("最终资金: $%.2f\n", final_capital))
  cat(sprintf("总收益率: %.2f%%\n\n", total_return))

  cat(sprintf("胜率: %.2f%% (%d胜 / %d负)\n", win_rate, wins, losses))
  cat(sprintf("平均盈亏: %.2f%%\n", avg_pnl))
  cat(sprintf("平均盈利: %.2f%%\n", avg_win))
  cat(sprintf("平均亏损: %.2f%%\n\n", avg_loss))

  cat(sprintf("止盈次数: %d (%.1f%%)\n", tp_count, tp_count/n_trades*100))
  cat(sprintf("止损次数: %d (%.1f%%)\n\n", sl_count, sl_count/n_trades*100))

  cat(sprintf("平均持仓: %.1f根K线 (约%.1f小时)\n\n", avg_holding, avg_holding_hours))

  # 保存详细交易记录
  output_file <- "detailed_trades_comparison.csv"
  write.csv(trades_df, output_file, row.names = FALSE)
  cat(sprintf("详细交易记录已保存: %s\n\n", output_file))

  # 显示前10笔交易
  cat("前10笔交易详情:\n")
  cat(rep("-", 80), "\n", sep="")
  print(head(trades_df, 10))
  cat("\n")

} else {
  cat("警告：没有产生任何交易！\n\n")
}

# ============================================================================
# 第5部分：异常检查
# ============================================================================

cat("第5部分：异常检查\n")
cat(rep("-", 80), "\n", sep="")

if (n_trades > 0) {
  # 检查异常高收益
  extreme_wins <- trades_df[!is.na(trades_df$PnL_Percent) & trades_df$PnL_Percent > 50, ]
  if (nrow(extreme_wins) > 0) {
    cat(sprintf("警告：发现%d笔异常高收益交易（>50%%）:\n", nrow(extreme_wins)))
    print(extreme_wins[, c("Trade_No", "Entry_Time", "Exit_Time", "PnL_Percent", "Exit_Type")])
    cat("\n")
  } else {
    cat("没有发现异常高收益交易（>50%）\n\n")
  }

  # 检查异常持仓时间
  if (!all(is.na(trades_df$Holding_Bars))) {
    max_holding <- max(trades_df$Holding_Bars, na.rm = TRUE)
    min_holding <- min(trades_df$Holding_Bars, na.rm = TRUE)

    cat(sprintf("持仓时间范围: %d - %d根K线\n", min_holding, max_holding))

    long_holds <- trades_df[!is.na(trades_df$Holding_Bars) & trades_df$Holding_Bars > 100, ]
    if (nrow(long_holds) > 0) {
      cat(sprintf("警告：发现%d笔持仓超过100根K线的交易:\n", nrow(long_holds)))
      print(long_holds[, c("Trade_No", "Entry_Time", "Holding_Bars", "Exit_Type")])
      cat("\n")
    } else {
      cat("没有发现异常长持仓交易\n\n")
    }
  }

  # 检查价格计算
  cat("价格计算验证（前5笔交易）:\n")
  for (i in 1:min(5, nrow(trades_df))) {
    trade <- trades_df[i, ]
    entry <- trade$Entry_Price
    exit <- trade$Exit_Price
    pnl <- trade$PnL_Percent

    if (!is.na(entry) && !is.na(exit) && !is.na(pnl)) {
      calculated_pnl <- ((exit - entry) / entry) * 100
      diff <- abs(calculated_pnl - pnl)

      cat(sprintf("  交易#%d: 入场=%.8f, 出场=%.8f\n", i, entry, exit))
      cat(sprintf("    记录盈亏=%.2f%%, 计算盈亏=%.2f%%, 差异=%.4f%%\n",
                  pnl, calculated_pnl, diff))

      if (diff > 0.01) {
        cat("    警告：盈亏计算可能有误！\n")
      }
    }
  }
  cat("\n")

} else {
  cat("无交易记录，跳过异常检查\n\n")
}

# ============================================================================
# 第6部分：分析quick_test_10params_results.csv中的异常模式
# ============================================================================

cat("第6部分：参数测试结果异常分析\n")
cat(rep("-", 80), "\n", sep="")

results_file <- "outputs/quick_test_10params_results.csv"

if (file.exists(results_file)) {
  results <- read.csv(results_file, stringsAsFactors = FALSE)

  cat(sprintf("已加载参数测试结果: %d行\n\n", nrow(results)))

  # 过滤有效结果
  valid_results <- results[!is.na(results$Return_Percentage) & results$Trade_Count > 0, ]

  cat(sprintf("有效测试（有交易）: %d/%d (%.1f%%)\n\n",
              nrow(valid_results), nrow(results),
              nrow(valid_results)/nrow(results)*100))

  if (nrow(valid_results) > 0) {
    # 1. 收益率分布
    cat("收益率分布:\n")
    cat(sprintf("  最高: %.2f%%\n", max(valid_results$Return_Percentage)))
    cat(sprintf("  平均: %.2f%%\n", mean(valid_results$Return_Percentage)))
    cat(sprintf("  中位数: %.2f%%\n", median(valid_results$Return_Percentage)))
    cat(sprintf("  最低: %.2f%%\n\n", min(valid_results$Return_Percentage)))

    # 2. 异常高收益
    extreme_high <- valid_results[valid_results$Return_Percentage > 500, ]
    if (nrow(extreme_high) > 0) {
      cat(sprintf("发现%d个异常高收益参数组合（>500%%）:\n", nrow(extreme_high)))
      print(extreme_high[, c("Symbol", "Timeframe", "lookbackDays", "minDropPercent",
                             "takeProfitPercent", "stopLossPercent",
                             "Trade_Count", "Return_Percentage", "Win_Rate")])
      cat("\n异常高收益可能原因:\n")
      cat("  - 参数组合导致极少交易但命中高波动行情\n")
      cat("  - minDropPercent过高（25%）筛选出极端下跌后的强反弹\n")
      cat("  - 需要在TradingView中逐笔验证这些交易是否真实\n\n")
    }

    # 3. 异常低收益/亏损
    extreme_low <- valid_results[valid_results$Return_Percentage < -50, ]
    if (nrow(extreme_low) > 0) {
      cat(sprintf("发现%d个严重亏损参数组合（<-50%%）:\n", nrow(extreme_low)))
      print(extreme_low[, c("Symbol", "Timeframe", "lookbackDays", "minDropPercent",
                            "takeProfitPercent", "stopLossPercent",
                            "Trade_Count", "Return_Percentage", "Win_Rate")])
      cat("\n严重亏损可能原因:\n")
      cat("  - 止盈止损比例过大（15%）导致频繁止损\n")
      cat("  - minDropPercent过高错过最佳入场时机\n\n")
    }

    # 4. 按minDropPercent分组
    cat("按minDropPercent分组分析:\n")
    for (drop in sort(unique(valid_results$minDropPercent))) {
      subset <- valid_results[valid_results$minDropPercent == drop, ]
      cat(sprintf("  minDrop=%.0f%%: 平均收益=%.2f%%, 平均交易数=%.1f, 样本数=%d\n",
                  drop, mean(subset$Return_Percentage),
                  mean(subset$Trade_Count), nrow(subset)))
    }
    cat("\n")

    # 5. 按时间框架分组
    cat("按时间框架分组分析:\n")
    for (tf in sort(unique(valid_results$Timeframe))) {
      subset <- valid_results[valid_results$Timeframe == tf, ]
      cat(sprintf("  %s: 平均收益=%.2f%%, 平均交易数=%.1f, 样本数=%d\n",
                  tf, mean(subset$Return_Percentage),
                  mean(subset$Trade_Count), nrow(subset)))
    }
    cat("\n")

    # 6. 胜率分析
    cat("胜率分析:\n")
    cat(sprintf("  最高胜率: %.2f%%\n", max(valid_results$Win_Rate)))
    cat(sprintf("  平均胜率: %.2f%%\n", mean(valid_results$Win_Rate)))
    cat(sprintf("  最低胜率: %.2f%%\n\n", min(valid_results$Win_Rate)))

    # 7. 推荐验证的参数组合
    cat("推荐在TradingView中验证的参数组合:\n")
    cat(rep("-", 80), "\n", sep="")

    # 找出收益最高的3个
    top3 <- valid_results[order(-valid_results$Return_Percentage), ][1:min(3, nrow(valid_results)), ]
    cat("\n最高收益TOP3:\n")
    for (i in 1:nrow(top3)) {
      row <- top3[i, ]
      cat(sprintf("%d. %s | lookback=%d, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n",
                  i, row$Symbol, row$lookbackDays, row$minDropPercent,
                  row$takeProfitPercent, row$stopLossPercent))
      cat(sprintf("   收益=%.2f%%, 交易数=%d, 胜率=%.1f%%\n",
                  row$Return_Percentage, row$Trade_Count, row$Win_Rate))
    }

    # 找出中等收益且交易数较多的
    middle_freq <- valid_results[valid_results$Return_Percentage > 50 &
                                  valid_results$Return_Percentage < 200 &
                                  valid_results$Trade_Count > 100, ]
    if (nrow(middle_freq) > 0) {
      cat("\n中等收益+高频交易（更稳健）:\n")
      middle_freq <- middle_freq[order(-middle_freq$Return_Percentage), ]
      for (i in 1:min(3, nrow(middle_freq))) {
        row <- middle_freq[i, ]
        cat(sprintf("%d. %s | lookback=%d, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n",
                    i, row$Symbol, row$lookbackDays, row$minDropPercent,
                    row$takeProfitPercent, row$stopLossPercent))
        cat(sprintf("   收益=%.2f%%, 交易数=%d, 胜率=%.1f%%\n",
                    row$Return_Percentage, row$Trade_Count, row$Win_Rate))
      }
    }

  } else {
    cat("没有有效的测试结果\n")
  }

} else {
  cat(sprintf("文件不存在: %s\n", results_file))
}

cat("\n")

# ============================================================================
# 第7部分：诊断建议
# ============================================================================

cat("第7部分：诊断建议\n")
cat(rep("=", 80), "\n", sep="")

cat("\nTradingView对比验证清单:\n")
cat("1. 信号时间对比:\n")
cat("   - 打开detailed_trades_comparison.csv\n")
cat("   - 在TradingView中找到前10个交易的Signal_Time\n")
cat("   - 检查是否在同一时间触发信号\n\n")

cat("2. 入场价格对比:\n")
cat("   - 对比Entry_Price是否与TradingView一致\n")
cat("   - 注意：R使用收盘价入场，TradingView可能使用开盘价\n\n")

cat("3. 止盈止损价格对比:\n")
cat("   - R的TP价格 = Entry_Price * (1 + 0.10)\n")
cat("   - R的SL价格 = Entry_Price * (1 - 0.10)\n")
cat("   - 检查TradingView是否计算相同\n\n")

cat("4. 出场时间对比:\n")
cat("   - 对比Exit_Time是否一致\n")
cat("   - 检查Exit_Type（TP/SL）是否匹配\n\n")

cat("5. 盈亏计算验证:\n")
cat("   - PnL% = (Exit_Price - Entry_Price) / Entry_Price * 100\n")
cat("   - 如果公式不同，会导致收益差异\n\n")

if (n_trades > 0) {
  cat("关键数据对比:\n")
  cat(sprintf("  R回测总交易数: %d\n", n_trades))
  cat(sprintf("  R回测总收益率: %.2f%%\n", total_return))
  cat(sprintf("  R回测胜率: %.2f%%\n", win_rate))
  cat("\n请在TradingView中对比以上三个关键指标\n")
}

cat("\n常见差异原因:\n")
cat("1. 入场时机差异:\n")
cat("   - TradingView可能使用'次日开盘入场'\n")
cat("   - R使用'当前K线收盘入场'\n\n")

cat("2. 价格数据差异:\n")
cat("   - 数据源不同（币安、火币等）\n")
cat("   - 数据清洗方式不同\n\n")

cat("3. 信号判定差异:\n")
cat("   - Pine Script的highest()函数是否包含当前K线\n")
cat("   - R的回看窗口是否包含当前K线\n\n")

cat("4. 止盈止损触发差异:\n")
cat("   - TradingView可能使用盘中高低价触发\n")
cat("   - R使用收盘价触发\n\n")

cat(rep("=", 80), "\n", sep="")
cat("验证脚本执行完成！\n")
cat(rep("=", 80), "\n\n")

cat("生成的文件:\n")
cat("  - detailed_trades_comparison.csv (逐笔交易详情，用于对比)\n\n")

cat("下一步操作:\n")
cat("  1. 打开detailed_trades_comparison.csv查看前10笔交易\n")
cat("  2. 在TradingView中逐笔对比验证\n")
cat("  3. 根据差异调整策略逻辑或参数\n\n")
