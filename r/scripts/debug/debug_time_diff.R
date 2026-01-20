# 深度调试：为什么R第一笔交易比TradingView晚3天
# TradingView: 2023-05-06 (Excel 45052)
# R: 2023-05-09 02:14:59

library(xts)
library(TTR)

# 1. 加载数据
cat("========================================\n")
cat("1. 数据完整性验证\n")
cat("========================================\n")

load('data/liaochu.RData')
data <- cryptodata[["PEPEUSDT_15m"]]

cat("R数据第一根K线:", as.character(index(data)[1]), "\n")
cat("R数据最后一根K线:", as.character(index(data)[nrow(data)]), "\n")
cat("总K线数:", nrow(data), "\n\n")

# 2. 检查前几天的数据
cat("========================================\n")
cat("2. 前几天数据检查\n")
cat("========================================\n")

for (date_str in c("2023-05-06", "2023-05-07", "2023-05-08", "2023-05-09")) {
  day_data <- data[paste0(date_str, "/", date_str)]
  cat(sprintf("%s: %d根K线\n", date_str, nrow(day_data)))
  if (nrow(day_data) > 0) {
    cat("  第一根:", as.character(index(day_data)[1]), "\n")
    cat("  最后一根:", as.character(index(day_data)[nrow(day_data)]), "\n")
    cat("  High范围:", min(day_data[,"High"]), "-", max(day_data[,"High"]), "\n")
    cat("  Low范围:", min(day_data[,"Low"]), "-", max(day_data[,"Low"]), "\n")
  }
  cat("\n")
}

# 3. 加载信号生成函数
cat("========================================\n")
cat("3. 信号生成函数分析\n")
cat("========================================\n")

source('backtest_tradingview_aligned.R')

# 手动实现信号生成（与脚本保持一致）
lookbackDays <- 3
minDropPercent <- 20

# 计算lookback周期数（15分钟K线）
lookbackBars <- lookbackDays * 24 * 4  # 3天 * 24小时 * 4个15分钟
cat("lookbackBars计算:", lookbackDays, "天 * 24小时 * 4 = ", lookbackBars, "根K线\n\n")

# 4. 逐K线检查前10根K线的信号生成逻辑
cat("========================================\n")
cat("4. 前10根K线详细分析\n")
cat("========================================\n")

for (i in 1:min(10, nrow(data))) {
  current_time <- index(data)[i]
  current_low <- as.numeric(data[i, "Low"])

  cat(sprintf("\n--- K线 #%d ---\n", i))
  cat("时间:", as.character(current_time), "\n")
  cat("Low:", current_low, "\n")

  if (i > lookbackBars) {
    # 计算前lookbackBars的最高价
    lookback_start <- i - lookbackBars
    lookback_end <- i - 1
    window_high <- max(data[lookback_start:lookback_end, "High"])

    drop_pct <- (window_high - current_low) / window_high * 100
    signal <- drop_pct >= minDropPercent

    cat(sprintf("Lookback窗口: [%d, %d] (前%d根)\n", lookback_start, lookback_end, lookbackBars))
    cat("窗口最高价:", window_high, "\n")
    cat("跌幅:", sprintf("%.2f%%", drop_pct), "\n")
    cat("信号:", signal, "\n")
  } else {
    cat(sprintf("索引 %d <= lookbackBars %d，无法计算信号（需要更多历史数据）\n", i, lookbackBars))
  }
}

# 5. 找到第一个信号
cat("\n========================================\n")
cat("5. 第一个信号定位\n")
cat("========================================\n")

signals <- generate_drop_signals(data, lookbackDays=3, minDropPercent=20)
first_signal_idx <- which(signals)[1]

if (!is.na(first_signal_idx)) {
  cat("第一个信号索引:", first_signal_idx, "\n")
  cat("第一个信号时间:", as.character(index(data)[first_signal_idx]), "\n")

  # 详细分析第一个信号
  lookback_start <- first_signal_idx - lookbackBars
  lookback_end <- first_signal_idx - 1
  window_high <- max(data[lookback_start:lookback_end, "High"])
  current_low <- as.numeric(data[first_signal_idx, "Low"])
  drop_pct <- (window_high - current_low) / window_high * 100

  cat("\n第一个信号详情:\n")
  cat("Lookback窗口:", as.character(index(data)[lookback_start]), "到",
      as.character(index(data)[lookback_end]), "\n")
  cat("窗口最高价:", window_high, "\n")
  cat("当前最低价:", current_low, "\n")
  cat("跌幅:", sprintf("%.2f%%", drop_pct), "\n")
}

# 6. 手动检查TradingView第一笔对应的K线
cat("\n========================================\n")
cat("6. TradingView第一笔对应K线检查\n")
cat("========================================\n")

# TradingView第一笔: 2023-05-06 (假设是UTC时间)
tv_first_date <- as.POSIXct("2023-05-06 00:00:00", tz="UTC")
tv_date_str <- "2023-05-06"

may6_data <- data[tv_date_str]
cat("2023-05-06 K线数:", nrow(may6_data), "\n")

if (nrow(may6_data) > 0) {
  # 检查这一天的每根K线
  cat("\n逐K线检查2023-05-06:\n")
  may6_indices <- which(format(index(data), "%Y-%m-%d") == "2023-05-06")

  for (idx in may6_indices) {
    current_time <- index(data)[idx]
    current_low <- as.numeric(data[idx, "Low"])

    if (idx > lookbackBars) {
      lookback_start <- idx - lookbackBars
      lookback_end <- idx - 1
      window_high <- max(data[lookback_start:lookback_end, "High"])
      drop_pct <- (window_high - current_low) / window_high * 100
      signal <- drop_pct >= minDropPercent

      cat(sprintf("%s | Low=%.8f | WindowHigh=%.8f | Drop=%.2f%% | Signal=%s\n",
                  as.character(current_time), current_low, window_high, drop_pct, signal))

      if (signal) {
        cat("  *** 找到信号！这应该是第一笔交易 ***\n")
        break
      }
    } else {
      cat(sprintf("%s | 索引%d <= lookbackBars %d，跳过\n",
                  as.character(current_time), idx, lookbackBars))
    }
  }
}

# 7. 根本原因分析
cat("\n========================================\n")
cat("7. 根本原因分析\n")
cat("========================================\n")

cat("lookbackBars =", lookbackBars, "(", lookbackDays, "天)\n")
cat("数据起始索引: 1\n")
cat("第一个可能产生信号的索引:", lookbackBars + 1, "\n")
cat("第一个可能产生信号的时间:", as.character(index(data)[lookbackBars + 1]), "\n\n")

cat("结论:\n")
cat("- 如果数据从2023-05-06开始，需要", lookbackBars, "根K线的历史数据才能计算信号\n")
cat("- 这意味着前", lookbackDays, "天(", lookbackBars, "根K线)无法产生信号\n")
cat("- 第一个信号最早出现在索引", lookbackBars + 1, "处\n")

# 保存调试报告
sink("time_diff_debug_report.txt")
cat("========================================\n")
cat("R vs TradingView 时间差异调试报告\n")
cat("生成时间:", as.character(Sys.time()), "\n")
cat("========================================\n\n")

cat("已知信息:\n")
cat("- TradingView第一笔: 2023-05-06 (Excel序列号45052)\n")
cat("- R第一笔: 2023-05-09 02:14:59\n")
cat("- 差异: 约3天\n\n")

cat("数据检查:\n")
cat("- R数据起始: ", as.character(index(data)[1]), "\n")
cat("- R数据总K线数: ", nrow(data), "\n\n")

cat("信号生成参数:\n")
cat("- lookbackDays: ", lookbackDays, "\n")
cat("- lookbackBars: ", lookbackBars, " (", lookbackDays, "天 * 96根K线/天)\n")
cat("- minDropPercent: ", minDropPercent, "%\n\n")

cat("关键发现:\n")
cat("1. R的信号生成需要", lookbackBars, "根K线的历史数据\n")
cat("2. 前", lookbackBars, "根K线无法计算信号（索引1到", lookbackBars, "）\n")
cat("3. 第一个可能的信号出现在索引", lookbackBars + 1, ":", as.character(index(data)[lookbackBars + 1]), "\n")
cat("4. 这导致R的第一笔交易比TradingView晚约", lookbackDays, "天\n\n")

cat("根本原因:\n")
cat("R脚本使用了lookbackBars作为历史窗口，在计算信号时:\n")
cat("  - 需要前", lookbackBars, "根K线才能计算当前K线的信号\n")
cat("  - 导致前", lookbackDays, "天的数据无法产生交易信号\n\n")

cat("TradingView差异:\n")
cat("TradingView可能:\n")
cat("1. 使用了更早的历史数据（在图表显示范围之外）\n")
cat("2. 或者使用不同的lookback计算方式（如使用日期而非K线数）\n")
cat("3. 或者在数据起始处使用了不同的初始化逻辑\n\n")

if (!is.na(first_signal_idx)) {
  cat("R第一个信号:\n")
  cat("- 索引:", first_signal_idx, "\n")
  cat("- 时间:", as.character(index(data)[first_signal_idx]), "\n")
  cat("- 距离数据起始:", first_signal_idx - 1, "根K线\n")
}

sink()

cat("\n调试报告已保存到: time_diff_debug_report.txt\n")
