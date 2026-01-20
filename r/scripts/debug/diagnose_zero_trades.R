# ========================================
# 诊断 Trade_Count = 0 的根本原因
# ========================================
# 专门分析为什么有大量信号但无交易发生

library(xts)

cat("========================================\n")
cat("Trade_Count = 0 问题诊断\n")
cat("========================================\n\n")

# 加载数据
load("data/liaochu.RData")
pepe_results <- read.csv("outputs/pepe_results.csv", stringsAsFactors=FALSE)

cat(sprintf("pepe_results.csv 总行数: %d\n", nrow(pepe_results)))

# 找出异常案例: Signal_Count > 0 但 Trade_Count = 0
anomalies <- pepe_results[
  pepe_results$Signal_Count > 0 & pepe_results$Trade_Count == 0,
]

cat(sprintf("异常案例数: %d (%.1f%%)\n\n",
           nrow(anomalies), nrow(anomalies)/nrow(pepe_results)*100))

if (nrow(anomalies) > 0) {
  cat("前10个异常案例:\n")
  print(head(anomalies[, c("Symbol", "lookbackDays", "minDropPercent",
                          "takeProfitPercent", "stopLossPercent", "Signal_Count")], 10))
}

# ========================================
# 深度分析函数
# ========================================

deep_diagnose <- function(data, lookbackDays, minDropPercent, takeProfitPercent, stopLossPercent) {
  cat("\n----------------------------------------\n")
  cat("深度诊断分析\n")
  cat("----------------------------------------\n")

  # 生成信号
  n <- nrow(data)
  signals <- rep(FALSE, n)

  if (n < lookbackDays + 1) {
    cat("数据不足: 需要至少", lookbackDays+1, "行,实际", n, "行\n")
    return()
  }

  for (i in (lookbackDays + 1):n) {
    window_high <- max(data$High[(i-lookbackDays):(i-1)], na.rm=TRUE)
    current_low <- data$Low[i]

    if (!is.na(window_high) && !is.na(current_low) && window_high > 0) {
      drop_percent <- (window_high - current_low) / window_high * 100
      if (drop_percent >= minDropPercent) {
        signals[i] <- TRUE
      }
    }
  }

  signal_count <- sum(signals, na.rm=TRUE)
  signal_indices <- which(signals)

  cat(sprintf("总信号数: %d\n", signal_count))

  if (signal_count == 0) {
    cat("没有信号生成\n")
    return()
  }

  # 显示前几个信号的详细信息
  cat("\n前5个信号详情:\n")
  for (idx in head(signal_indices, 5)) {
    window_high <- max(data$High[(idx-lookbackDays):(idx-1)], na.rm=TRUE)
    current_low <- data$Low[idx]
    drop <- (window_high - current_low) / window_high * 100
    entry_price <- as.numeric(data$Close[idx])

    cat(sprintf("  [Bar %d, 时间=%s]\n", idx, as.character(index(data)[idx])))
    cat(sprintf("    窗口最高=%.8f, 当前最低=%.8f, 跌幅=%.2f%%\n",
               window_high, current_low, drop))
    cat(sprintf("    入场价(收盘)=%.8f\n", entry_price))

    # 模拟后续走势
    if (idx < n) {
      max_pnl <- -Inf
      min_pnl <- Inf
      exit_bar <- NA
      exit_reason <- NA

      for (j in (idx+1):min(idx+50, n)) {  # 最多看50个bar
        current_price <- as.numeric(data$Close[j])
        if (!is.na(current_price) && current_price > 0 && entry_price > 0) {
          pnl <- (current_price - entry_price) / entry_price * 100

          max_pnl <- max(max_pnl, pnl)
          min_pnl <- min(min_pnl, pnl)

          if (pnl >= takeProfitPercent) {
            exit_bar <- j
            exit_reason <- sprintf("止盈(%.2f%%)", pnl)
            break
          }

          if (pnl <= -stopLossPercent) {
            exit_bar <- j
            exit_reason <- sprintf("止损(%.2f%%)", pnl)
            break
          }
        }
      }

      cat(sprintf("    后续走势: 最高盈利=%.2f%%, 最大回撤=%.2f%%\n",
                 max_pnl, min_pnl))

      if (!is.na(exit_bar)) {
        cat(sprintf("    出场位置: Bar %d, 原因: %s\n", exit_bar, exit_reason))
      } else {
        cat("    未触发止盈止损 (在50个bar内)\n")
      }
    }
    cat("\n")
  }

  # 回测统计
  cat("\n回测模拟:\n")

  capital <- 10000
  position <- 0
  entry_price <- NA
  trades <- numeric(0)

  entry_count <- 0
  exit_count <- 0
  failed_entries <- 0
  failed_exits <- 0

  for (i in 1:n) {
    # 入场逻辑
    if (signals[i] && position == 0) {
      entry_price_candidate <- as.numeric(data$Close[i])

      if (is.na(entry_price_candidate) || entry_price_candidate <= 0) {
        failed_entries <- failed_entries + 1
        next
      }

      position <- capital / entry_price_candidate
      capital <- 0
      entry_price <- entry_price_candidate
      entry_count <- entry_count + 1
    }

    # 持仓管理
    if (position > 0) {
      current_price <- as.numeric(data$Close[i])

      if (is.na(current_price) || current_price <= 0 ||
          is.na(entry_price) || entry_price <= 0) {
        failed_exits <- failed_exits + 1
        next
      }

      pnl_percent <- (current_price - entry_price) / entry_price * 100

      if (pnl_percent >= takeProfitPercent || pnl_percent <= -stopLossPercent) {
        exit_capital <- position * current_price
        trades <- c(trades, pnl_percent)
        capital <- exit_capital
        position <- 0
        entry_price <- NA
        exit_count <- exit_count + 1
      }
    }
  }

  # 强制平仓
  if (position > 0) {
    final_price <- as.numeric(data$Close[n])
    if (!is.na(final_price) && final_price > 0 && !is.na(entry_price) && entry_price > 0) {
      final_pnl <- (final_price - entry_price) / entry_price * 100
      trades <- c(trades, final_pnl)
      capital <- position * final_price
      exit_count <- exit_count + 1
    }
  }

  cat(sprintf("  信号总数: %d\n", signal_count))
  cat(sprintf("  成功入场: %d\n", entry_count))
  cat(sprintf("  失败入场: %d (价格NA或<=0)\n", failed_entries))
  cat(sprintf("  成功出场: %d\n", exit_count))
  cat(sprintf("  失败出场: %d (价格NA或<=0)\n", failed_exits))
  cat(sprintf("  最终交易数: %d\n", length(trades)))

  if (length(trades) > 0) {
    cat(sprintf("  最终资金: %.2f\n", capital))
    cat(sprintf("  总收益率: %.2f%%\n", (capital-10000)/10000*100))
  } else {
    cat("  原因分析:\n")
    if (entry_count == 0) {
      cat("    - 入场失败: 所有信号bar的收盘价都是NA或<=0\n")
    } else if (exit_count == 0) {
      cat("    - 出场失败: 持仓期间价格都是NA或<=0,无法计算盈亏\n")
      cat("    - 或者止盈止损条件从未触发\n")
    }
  }
}

# ========================================
# 选择几个典型案例进行分析
# ========================================

if (nrow(anomalies) > 0) {
  # 案例1: 最多信号的异常案例
  cat("\n\n========================================\n")
  cat("案例1: 信号最多的异常情况\n")
  cat("========================================\n")

  case1_idx <- which.max(anomalies$Signal_Count)
  case1 <- anomalies[case1_idx, ]

  cat(sprintf("标的: %s\n", case1$Symbol))
  cat(sprintf("参数: lookback=%d, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n",
             case1$lookbackDays, case1$minDropPercent,
             case1$takeProfitPercent, case1$stopLossPercent))
  cat(sprintf("信号数: %d\n", case1$Signal_Count))

  if (case1$Symbol %in% names(cryptodata)) {
    data <- cryptodata[[case1$Symbol]]
    cat(sprintf("数据行数: %d\n", nrow(data)))

    deep_diagnose(data, case1$lookbackDays, case1$minDropPercent,
                 case1$takeProfitPercent, case1$stopLossPercent)
  }

  # 案例2: 典型参数组合 (lookback=3, drop=5)
  cat("\n\n========================================\n")
  cat("案例2: 典型参数 (lookback=3, drop=5%)\n")
  cat("========================================\n")

  typical_cases <- anomalies[
    anomalies$lookbackDays == 3 & anomalies$minDropPercent == 5,
  ]

  if (nrow(typical_cases) > 0) {
    case2 <- typical_cases[1, ]

    cat(sprintf("标的: %s\n", case2$Symbol))
    cat(sprintf("参数: lookback=%d, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n",
               case2$lookbackDays, case2$minDropPercent,
               case2$takeProfitPercent, case2$stopLossPercent))
    cat(sprintf("信号数: %d\n", case2$Signal_Count))

    if (case2$Symbol %in% names(cryptodata)) {
      data <- cryptodata[[case2$Symbol]]
      cat(sprintf("数据行数: %d\n", nrow(data)))

      deep_diagnose(data, case2$lookbackDays, case2$minDropPercent,
                   case2$takeProfitPercent, case2$stopLossPercent)
    }
  }

  # 案例3: Pine Script默认参数 (lookback=3, drop=20)
  cat("\n\n========================================\n")
  cat("案例3: Pine Script默认参数 (lookback=3, drop=20%)\n")
  cat("========================================\n")

  pine_cases <- anomalies[
    anomalies$lookbackDays == 3 & anomalies$minDropPercent == 20,
  ]

  if (nrow(pine_cases) > 0) {
    case3 <- pine_cases[1, ]

    cat(sprintf("标的: %s\n", case3$Symbol))
    cat(sprintf("参数: lookback=%d, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n",
               case3$lookbackDays, case3$minDropPercent,
               case3$takeProfitPercent, case3$stopLossPercent))
    cat(sprintf("信号数: %d\n", case3$Signal_Count))

    if (case3$Symbol %in% names(cryptodata)) {
      data <- cryptodata[[case3$Symbol]]
      cat(sprintf("数据行数: %d\n", nrow(data)))

      deep_diagnose(data, case3$lookbackDays, case3$minDropPercent,
                   case3$takeProfitPercent, case3$stopLossPercent)
    }
  }
}

cat("\n\n========================================\n")
cat("诊断完成\n")
cat("========================================\n")
