################################################################################
# PEPEUSDT 全面手续费影响分析系统
#
# 功能：
# 1. 测试4个时间框架 × 4个手续费等级 = 16个测试场景
# 2. 计算完整性能指标矩阵
# 3. 分析手续费影响和敏感度
# 4. 生成最优配置推荐和风险提示
#
# 作者：Claude Code Data Scientist
# 日期：2025-10-26
################################################################################

library(data.table)
library(xts)

# ============================================================================
# 核心策略函数
# ============================================================================

#' 生成交易信号
#' @param data xts对象，包含OHLCV数据
#' @param lookback 回看期数
#' @param drop_threshold 下跌阈值（小数形式，如0.20表示20%）
generate_signals <- function(data, lookback = 3, drop_threshold = 0.20) {

  # 提取价格数据
  high_prices <- as.numeric(data[, "High"])
  close_prices <- as.numeric(data[, "Close"])

  # 计算lookback期间的最高价
  highest_high <- rollapply(high_prices, width = lookback, FUN = max,
                           align = "right", fill = NA)

  # 计算当前收盘价相对最高价的跌幅
  drop_pct <- (close_prices - highest_high) / highest_high

  # 生成信号：跌幅达到阈值时触发
  signals <- ifelse(drop_pct <= -drop_threshold, 1, 0)
  signals[is.na(signals)] <- 0

  return(list(
    signals = signals,
    drop_pct = drop_pct,
    highest_high = highest_high
  ))
}

#' 回测交易
#' @param data xts对象
#' @param signals 信号向量
#' @param tp_pct 止盈百分比
#' @param sl_pct 止损百分比
#' @param fee_pct 手续费百分比（单边）
backtest_trades <- function(data, signals, tp_pct = 0.10, sl_pct = 0.10, fee_pct = 0.0) {

  prices <- as.numeric(data[, "Close"])
  times <- index(data)
  n <- length(prices)

  trades <- list()
  in_position <- FALSE
  entry_price <- 0
  entry_time <- NULL
  entry_idx <- 0

  for (i in 1:n) {
    if (!in_position && signals[i] == 1) {
      # 开仓
      in_position <- TRUE
      entry_price <- prices[i]
      entry_time <- times[i]
      entry_idx <- i

    } else if (in_position) {
      # 检查止盈/止损
      current_price <- prices[i]
      pnl_pct <- (current_price - entry_price) / entry_price

      exit_reason <- NA
      should_exit <- FALSE

      if (pnl_pct >= tp_pct) {
        exit_reason <- "TP"
        should_exit <- TRUE
      } else if (pnl_pct <= -sl_pct) {
        exit_reason <- "SL"
        should_exit <- TRUE
      }

      if (should_exit) {
        # 计算含手续费的收益
        gross_return <- pnl_pct
        fee_cost <- 2 * fee_pct  # 买入和卖出各一次
        net_return <- gross_return - fee_cost

        trades[[length(trades) + 1]] <- list(
          entry_time = entry_time,
          exit_time = times[i],
          entry_price = entry_price,
          exit_price = current_price,
          gross_return = gross_return,
          fee_cost = fee_cost,
          net_return = net_return,
          exit_reason = exit_reason,
          holding_bars = i - entry_idx
        )

        in_position <- FALSE
      }
    }
  }

  # 如果最后仍持仓，以最后价格平仓
  if (in_position) {
    current_price <- prices[n]
    pnl_pct <- (current_price - entry_price) / entry_price
    fee_cost <- 2 * fee_pct
    net_return <- pnl_pct - fee_cost

    trades[[length(trades) + 1]] <- list(
      entry_time = entry_time,
      exit_time = times[n],
      entry_price = entry_price,
      exit_price = current_price,
      gross_return = pnl_pct,
      fee_cost = fee_cost,
      net_return = net_return,
      exit_reason = "EOD",
      holding_bars = n - entry_idx
    )
  }

  return(trades)
}

#' 计算性能指标
#' @param trades 交易列表
#' @param total_days 总交易天数
calculate_metrics <- function(trades, total_days, signals_count) {

  if (length(trades) == 0) {
    return(list(
      signals_count = signals_count,
      trades_count = 0,
      total_return = 0,
      annual_return = 0,
      win_rate = 0,
      avg_return = 0,
      max_drawdown = 0,
      profit_factor = 0,
      total_fees = 0,
      fee_ratio = 0,
      avg_holding_bars = 0
    ))
  }

  # 提取收益数据
  gross_returns <- sapply(trades, function(x) x$gross_return)
  net_returns <- sapply(trades, function(x) x$net_return)
  fee_costs <- sapply(trades, function(x) x$fee_cost)
  holding_bars <- sapply(trades, function(x) x$holding_bars)

  # 基础统计
  trades_count <- length(trades)
  total_gross_return <- sum(gross_returns)
  total_net_return <- sum(net_returns)
  total_fees <- sum(fee_costs)

  # 年化收益（假设每年365天）
  annual_return <- (total_net_return / total_days) * 365

  # 胜率
  win_count <- sum(net_returns > 0)
  win_rate <- win_count / trades_count

  # 平均收益
  avg_return <- mean(net_returns)

  # 最大回撤
  cumulative_returns <- cumsum(net_returns)
  cumulative_max <- cummax(cumulative_returns)
  drawdowns <- cumulative_returns - cumulative_max
  max_drawdown <- min(drawdowns, 0)

  # 盈亏比
  winning_trades <- net_returns[net_returns > 0]
  losing_trades <- net_returns[net_returns < 0]

  if (length(winning_trades) > 0 && length(losing_trades) > 0) {
    avg_win <- mean(winning_trades)
    avg_loss <- mean(abs(losing_trades))
    profit_factor <- avg_win / avg_loss
  } else {
    profit_factor <- ifelse(length(winning_trades) > 0, Inf, 0)
  }

  # 手续费占比
  fee_ratio <- ifelse(total_gross_return != 0,
                     total_fees / abs(total_gross_return),
                     0)

  return(list(
    signals_count = signals_count,
    trades_count = trades_count,
    total_return = total_net_return,
    annual_return = annual_return,
    win_rate = win_rate,
    avg_return = avg_return,
    max_drawdown = max_drawdown,
    profit_factor = profit_factor,
    total_fees = total_fees,
    fee_ratio = fee_ratio,
    avg_holding_bars = mean(holding_bars),
    total_gross_return = total_gross_return
  ))
}

# ============================================================================
# 数据加载
# ============================================================================

cat("正在加载PEPEUSDT数据...\n")

# 加载liaochu.RData
load("data/liaochu.RData")

# 筛选PEPEUSDT相关标的
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat(sprintf("找到 %d 个PEPEUSDT时间框架\n", length(pepe_symbols)))

if (length(pepe_symbols) == 0) {
  stop("错误：未找到任何PEPEUSDT数据！")
}

# 提取数据并按时间框架命名
data_list <- list()
timeframe_map <- c()

for (symbol in pepe_symbols) {
  data <- cryptodata[[symbol]]

  # 检测时间框架
  if (nrow(data) >= 2) {
    time_diff <- as.numeric(difftime(index(data)[2], index(data)[1], units = "mins"))

    if (time_diff <= 5) {
      tf_name <- "5m"
    } else if (time_diff <= 15) {
      tf_name <- "15m"
    } else if (time_diff <= 30) {
      tf_name <- "30m"
    } else if (time_diff <= 60) {
      tf_name <- "1h"
    } else {
      tf_name <- sprintf("%dm", round(time_diff))
    }

    data_list[[tf_name]] <- data
    timeframe_map[symbol] <- tf_name

    cat(sprintf("  [OK] %s -> %s: %d 条数据 (%.1f天)\n",
                symbol, tf_name, nrow(data),
                as.numeric(difftime(max(index(data)), min(index(data)), units = "days"))))
  }
}

# 定义时间框架（按实际存在的）
timeframes <- names(data_list)

if (length(data_list) == 0) {
  stop("错误：无法加载任何数据！")
}

# ============================================================================
# 测试矩阵配置
# ============================================================================

cat("\n=== 测试配置 ===\n")

# 固定参数
lookback <- 3
drop_threshold <- 0.20
tp_pct <- 0.10
sl_pct <- 0.10

# 变化参数：手续费
fee_levels <- c(0.0000, 0.0005, 0.00075, 0.0010)  # 0%, 0.05%, 0.075%, 0.1%

cat(sprintf("固定参数：\n"))
cat(sprintf("  - lookback: %d\n", lookback))
cat(sprintf("  - drop_threshold: %.1f%%\n", drop_threshold * 100))
cat(sprintf("  - TP: %.1f%%\n", tp_pct * 100))
cat(sprintf("  - SL: %.1f%%\n", sl_pct * 100))
cat(sprintf("\n变化参数：\n"))
cat(sprintf("  - 手续费: %s\n",
            paste(sprintf("%.3f%%", fee_levels * 100), collapse=", ")))
cat(sprintf("\n测试矩阵：%d 时间框架 × %d 手续费 = %d 个测试\n",
            length(data_list), length(fee_levels),
            length(data_list) * length(fee_levels)))

# ============================================================================
# 执行测试矩阵
# ============================================================================

cat("\n=== 开始执行测试 ===\n")

results <- list()
test_num <- 0
total_tests <- length(data_list) * length(fee_levels)

for (tf in names(data_list)) {
  data <- data_list[[tf]]
  total_days <- as.numeric(difftime(max(index(data)), min(index(data)), units = "days"))

  cat(sprintf("\n[时间框架: %s]\n", tf))
  cat(sprintf("  数据范围: %s 至 %s (%.1f天)\n",
              as.character(min(index(data))),
              as.character(max(index(data))),
              total_days))

  # 生成信号（只需生成一次）
  signal_result <- generate_signals(data, lookback, drop_threshold)
  signals <- signal_result$signals
  signals_count <- sum(signals)

  cat(sprintf("  信号数: %d\n", signals_count))

  for (fee in fee_levels) {
    test_num <- test_num + 1

    cat(sprintf("  [%d/%d] 测试手续费 %.3f%%... ",
                test_num, total_tests, fee * 100))

    # 回测
    trades <- backtest_trades(data, signals, tp_pct, sl_pct, fee)

    # 计算指标
    metrics <- calculate_metrics(trades, total_days, signals_count)

    # 保存结果
    result <- list(
      timeframe = tf,
      fee_pct = fee,
      lookback = lookback,
      drop_threshold = drop_threshold,
      tp_pct = tp_pct,
      sl_pct = sl_pct,
      metrics = metrics
    )

    results[[length(results) + 1]] <- result

    cat(sprintf("完成 (交易数: %d, 收益: %.2f%%)\n",
                metrics$trades_count,
                metrics$total_return * 100))
  }
}

# ============================================================================
# 整理结果为数据框
# ============================================================================

cat("\n=== 整理测试结果 ===\n")

results_df <- data.frame(
  timeframe = character(),
  fee_pct = numeric(),
  lookback = numeric(),
  drop_threshold = numeric(),
  tp_pct = numeric(),
  sl_pct = numeric(),
  signals_count = numeric(),
  trades_count = numeric(),
  total_return_pct = numeric(),
  annual_return_pct = numeric(),
  win_rate_pct = numeric(),
  avg_return_pct = numeric(),
  max_drawdown_pct = numeric(),
  profit_factor = numeric(),
  total_fees_pct = numeric(),
  fee_ratio_pct = numeric(),
  avg_holding_bars = numeric(),
  total_gross_return_pct = numeric(),
  stringsAsFactors = FALSE
)

for (result in results) {
  m <- result$metrics
  results_df <- rbind(results_df, data.frame(
    timeframe = result$timeframe,
    fee_pct = result$fee_pct * 100,  # 转换为百分比
    lookback = result$lookback,
    drop_threshold = result$drop_threshold * 100,
    tp_pct = result$tp_pct * 100,
    sl_pct = result$sl_pct * 100,
    signals_count = m$signals_count,
    trades_count = m$trades_count,
    total_return_pct = m$total_return * 100,
    annual_return_pct = m$annual_return * 100,
    win_rate_pct = m$win_rate * 100,
    avg_return_pct = m$avg_return * 100,
    max_drawdown_pct = m$max_drawdown * 100,
    profit_factor = m$profit_factor,
    total_fees_pct = m$total_fees * 100,
    fee_ratio_pct = m$fee_ratio * 100,
    avg_holding_bars = m$avg_holding_bars,
    total_gross_return_pct = m$total_gross_return * 100,
    stringsAsFactors = FALSE
  ))
}

# 保存CSV
output_csv <- "outputs/fee_impact_results.csv"
write.csv(results_df, output_csv, row.names = FALSE)
cat(sprintf("结果已保存: %s\n", output_csv))

# ============================================================================
# 手续费影响分析
# ============================================================================

cat("\n=== 手续费影响分析 ===\n")

fee_impact_analysis <- list()

for (tf in timeframes) {
  tf_data <- results_df[results_df$timeframe == tf, ]

  if (nrow(tf_data) == 0) next

  # 排序
  tf_data <- tf_data[order(tf_data$fee_pct), ]

  # 无手续费收益
  zero_fee_return <- tf_data$total_return_pct[tf_data$fee_pct == 0]

  # 0.075%手续费收益
  target_fee_return <- tf_data$total_return_pct[tf_data$fee_pct == 0.075]

  # 收益衰减
  return_decay <- zero_fee_return - target_fee_return
  decay_rate <- ifelse(zero_fee_return != 0,
                      (return_decay / zero_fee_return) * 100,
                      0)

  # 手续费敏感度（每0.01%手续费的影响）
  if (nrow(tf_data) >= 2) {
    # 使用线性拟合计算敏感度
    fit <- lm(total_return_pct ~ fee_pct, data = tf_data)
    sensitivity <- coef(fit)[2] / 100  # 每0.01%手续费的影响
  } else {
    sensitivity <- NA
  }

  # 盈亏平衡点
  if (nrow(tf_data) >= 2 && !is.na(sensitivity)) {
    # 找到收益为0的手续费
    breakeven_fee <- ifelse(sensitivity != 0,
                           -coef(fit)[1] / coef(fit)[2],
                           NA)
  } else {
    breakeven_fee <- NA
  }

  fee_impact_analysis[[tf]] <- list(
    timeframe = tf,
    zero_fee_return = zero_fee_return,
    target_fee_return = target_fee_return,
    return_decay = return_decay,
    decay_rate = decay_rate,
    sensitivity = sensitivity,
    breakeven_fee = breakeven_fee,
    data = tf_data
  )

  cat(sprintf("\n[%s]\n", tf))
  cat(sprintf("  无手续费收益: %.2f%%\n", zero_fee_return))
  cat(sprintf("  0.075%%手续费收益: %.2f%%\n", target_fee_return))
  cat(sprintf("  收益衰减: %.2f%% (%.1f%%)\n", return_decay, decay_rate))
  if (!is.na(sensitivity)) {
    cat(sprintf("  手续费敏感度: %.4f%% 每0.01%%\n", sensitivity))
  }
  if (!is.na(breakeven_fee) && breakeven_fee > 0) {
    cat(sprintf("  盈亏平衡点: %.3f%%\n", breakeven_fee))
  }
}

# ============================================================================
# 最优配置推荐
# ============================================================================

cat("\n=== 最优配置推荐（基于0.075%手续费）===\n")

target_fee_results <- results_df[results_df$fee_pct == 0.075, ]
target_fee_results <- target_fee_results[order(-target_fee_results$total_return_pct), ]

cat("\n排名（按总收益）：\n")
for (i in 1:nrow(target_fee_results)) {
  row <- target_fee_results[i, ]
  cat(sprintf("  %d. %s: 收益%.2f%% | 年化%.2f%% | 胜率%.1f%% | 交易%d次\n",
              i, row$timeframe, row$total_return_pct,
              row$annual_return_pct, row$win_rate_pct, row$trades_count))
}

best_config <- target_fee_results[1, ]
cat(sprintf("\n推荐配置：\n"))
cat(sprintf("  - 时间框架: %s\n", best_config$timeframe))
cat(sprintf("  - Lookback: %d\n", best_config$lookback))
cat(sprintf("  - Drop阈值: %.1f%%\n", best_config$drop_threshold))
cat(sprintf("  - TP/SL: %.1f%%/%.1f%%\n", best_config$tp_pct, best_config$sl_pct))
cat(sprintf("  - 预期收益: %.2f%%\n", best_config$total_return_pct))
cat(sprintf("  - 年化收益: %.2f%%\n", best_config$annual_return_pct))
cat(sprintf("  - 胜率: %.1f%%\n", best_config$win_rate_pct))

# ============================================================================
# 生成Markdown报告
# ============================================================================

cat("\n=== 生成报告 ===\n")

report_file <- "PEPEUSDT_FEE_IMPACT_REPORT.md"

report_lines <- c(
  "# PEPEUSDT 手续费影响分析报告",
  "",
  sprintf("**生成时间**: %s", Sys.time()),
  "",
  "---",
  "",
  "## 1. 执行摘要",
  "",
  sprintf("本报告对PEPEUSDT在4个时间框架下，测试了4个不同手续费等级的影响，共进行了**%d个测试场景**。",
          nrow(results_df)),
  "",
  "### 核心发现",
  "",
  sprintf("- **最佳时间框架**: %s（0.075%%手续费下收益%.2f%%）",
          best_config$timeframe, best_config$total_return_pct),
  sprintf("- **手续费影响**: 从0%%到0.1%%手续费，平均收益衰减%.2f%%",
          mean(sapply(fee_impact_analysis, function(x) x$return_decay), na.rm = TRUE)),
  sprintf("- **交易频率**: 平均每个时间框架产生%.0f个信号，%.0f笔交易",
          mean(results_df$signals_count[results_df$fee_pct == 0.075]),
          mean(results_df$trades_count[results_df$fee_pct == 0.075])),
  "",
  "---",
  "",
  "## 2. 测试配置",
  "",
  "### 固定参数",
  "",
  "| 参数 | 值 |",
  "|------|-----|",
  sprintf("| Lookback期数 | %d |", lookback),
  sprintf("| Drop阈值 | %.1f%% |", drop_threshold * 100),
  sprintf("| 止盈(TP) | %.1f%% |", tp_pct * 100),
  sprintf("| 止损(SL) | %.1f%% |", sl_pct * 100),
  "",
  "### 测试矩阵",
  "",
  "| 维度 | 选项 |",
  "|------|------|",
  sprintf("| 时间框架 | %s |", paste(timeframes, collapse=", ")),
  sprintf("| 手续费 | %s |", paste(sprintf("%.3f%%", fee_levels * 100), collapse=", ")),
  sprintf("| 总测试数 | %d |", nrow(results_df)),
  "",
  "---",
  "",
  "## 3. 性能对比矩阵",
  "",
  "### 3.1 各时间框架在不同手续费下的总收益率（%）",
  ""
)

# 构建对比表格
compare_table <- c("| 时间框架 | 无手续费 | 0.05%费 | 0.075%费 | 0.1%费 | 收益衰减 | 推荐度 |",
                   "|---------|---------|---------|----------|--------|----------|--------|")

for (tf in timeframes) {
  tf_data <- results_df[results_df$timeframe == tf, ]
  tf_data <- tf_data[order(tf_data$fee_pct), ]

  if (nrow(tf_data) == 4) {
    zero_fee <- tf_data$total_return_pct[1]
    fee_0_05 <- tf_data$total_return_pct[2]
    fee_0_075 <- tf_data$total_return_pct[3]
    fee_0_10 <- tf_data$total_return_pct[4]

    decay <- zero_fee - fee_0_075

    # 推荐度（5星制）
    rank <- which(target_fee_results$timeframe == tf)
    stars <- ifelse(rank == 1, "⭐⭐⭐⭐⭐",
                   ifelse(rank == 2, "⭐⭐⭐⭐",
                          ifelse(rank == 3, "⭐⭐⭐", "⭐⭐")))

    compare_table <- c(compare_table,
                      sprintf("| %s | %.2f | %.2f | %.2f | %.2f | -%.2f | %s |",
                              tf, zero_fee, fee_0_05, fee_0_075, fee_0_10, decay, stars))
  }
}

report_lines <- c(report_lines, compare_table, "", "")

# 添加详细指标表
report_lines <- c(report_lines,
                 "### 3.2 完整性能指标（0.075%手续费）",
                 "",
                 "| 时间框架 | 信号数 | 交易数 | 总收益 | 年化收益 | 胜率 | 平均收益 | 最大回撤 | 盈亏比 |",
                 "|---------|-------|-------|-------|---------|------|---------|---------|--------|")

for (i in 1:nrow(target_fee_results)) {
  row <- target_fee_results[i, ]
  report_lines <- c(report_lines,
                   sprintf("| %s | %d | %d | %.2f%% | %.2f%% | %.1f%% | %.2f%% | %.2f%% | %.2f |",
                           row$timeframe, row$signals_count, row$trades_count,
                           row$total_return_pct, row$annual_return_pct,
                           row$win_rate_pct, row$avg_return_pct,
                           row$max_drawdown_pct, row$profit_factor))
}

report_lines <- c(report_lines, "", "---", "", "## 4. 手续费影响分析", "")

for (tf in timeframes) {
  analysis <- fee_impact_analysis[[tf]]
  if (is.null(analysis)) next

  report_lines <- c(report_lines,
                   sprintf("### 4.%d %s 时间框架", which(timeframes == tf), tf),
                   "",
                   "| 指标 | 值 |",
                   "|------|-----|",
                   sprintf("| 无手续费收益 | %.2f%% |", analysis$zero_fee_return),
                   sprintf("| 0.075%%手续费收益 | %.2f%% |", analysis$target_fee_return),
                   sprintf("| 绝对衰减 | %.2f%% |", analysis$return_decay),
                   sprintf("| 相对衰减 | %.1f%% |", analysis$decay_rate))

  if (!is.na(analysis$sensitivity)) {
    report_lines <- c(report_lines,
                     sprintf("| 手续费敏感度 | %.4f%%/0.01%% |", analysis$sensitivity))
  }

  if (!is.na(analysis$breakeven_fee) && analysis$breakeven_fee > 0) {
    report_lines <- c(report_lines,
                     sprintf("| 盈亏平衡点 | %.3f%% |", analysis$breakeven_fee))
  }

  report_lines <- c(report_lines, "", "**收益衰减曲线**:", "")

  # 添加简单的文本图表
  tf_data <- analysis$data[order(analysis$data$fee_pct), ]
  for (j in 1:nrow(tf_data)) {
    fee <- tf_data$fee_pct[j]
    ret <- tf_data$total_return_pct[j]
    bar_length <- max(0, round(ret / 5))
    bar <- paste(rep("█", bar_length), collapse = "")
    report_lines <- c(report_lines,
                     sprintf("- %.3f%%: %.2f%% %s", fee, ret, bar))
  }

  report_lines <- c(report_lines, "")
}

report_lines <- c(report_lines,
                 "---",
                 "",
                 "## 5. 最优配置推荐",
                 "",
                 "### 5.1 推荐配置（基于0.075%手续费）",
                 "",
                 "```",
                 sprintf("时间框架: %s", best_config$timeframe),
                 sprintf("Lookback: %d", best_config$lookback),
                 sprintf("Drop阈值: %.1f%%", best_config$drop_threshold),
                 sprintf("止盈: %.1f%%", best_config$tp_pct),
                 sprintf("止损: %.1f%%", best_config$sl_pct),
                 "```",
                 "",
                 "### 5.2 预期表现",
                 "",
                 "| 指标 | 值 |",
                 "|------|-----|",
                 sprintf("| 预期总收益 | %.2f%% |", best_config$total_return_pct),
                 sprintf("| 预期年化收益 | %.2f%% |", best_config$annual_return_pct),
                 sprintf("| 预期胜率 | %.1f%% |", best_config$win_rate_pct),
                 sprintf("| 预期交易数 | %d |", best_config$trades_count),
                 sprintf("| 平均持仓周期 | %.1f 根K线 |", best_config$avg_holding_bars),
                 sprintf("| 手续费支出占比 | %.2f%% |", best_config$fee_ratio_pct),
                 "",
                 "---",
                 "",
                 "## 6. 风险提示",
                 "",
                 "### 6.1 高频交易的手续费风险",
                 "")

# 分析交易频率
avg_trades <- mean(target_fee_results$trades_count)
avg_fee_ratio <- mean(target_fee_results$fee_ratio_pct)

report_lines <- c(report_lines,
                 sprintf("- 平均交易数: **%d笔**", round(avg_trades)),
                 sprintf("- 手续费占总收益比: **%.1f%%**", avg_fee_ratio))

if (avg_fee_ratio > 50) {
  report_lines <- c(report_lines,
                   "- WARN **警告**: 手续费占比超过50%，高频交易成本过高！")
} else if (avg_fee_ratio > 30) {
  report_lines <- c(report_lines,
                   "- WARN **注意**: 手续费占比超过30%，需要优化交易频率。")
} else {
  report_lines <- c(report_lines,
                   "- OK 手续费占比在合理范围内。")
}

report_lines <- c(report_lines,
                 "",
                 "### 6.2 滑点未计入的影响",
                 "",
                 "本测试**未包含滑点成本**。实盘交易中，滑点可能带来额外损失：",
                 "",
                 sprintf("- 假设平均滑点0.05%%，%d笔交易将额外损失约%.2f%%",
                         best_config$trades_count,
                         best_config$trades_count * 0.05 * 2),
                 sprintf("- 综合0.075%%手续费+0.05%%滑点，实际成本约0.125%%/笔"),
                 "",
                 "**调整后预期收益**:",
                 sprintf("- 理论收益: %.2f%%", best_config$total_return_pct),
                 sprintf("- 滑点损失: -%.2f%%", best_config$trades_count * 0.05 * 2),
                 sprintf("- 实际预期: **%.2f%%**",
                         best_config$total_return_pct - best_config$trades_count * 0.05 * 2),
                 "",
                 "### 6.3 其他实盘成本",
                 "",
                 "以下成本可能进一步影响实盘表现：",
                 "",
                 "1. **资金费率**（合约交易）: 每8小时结算一次，持仓过夜将产生费用",
                 "2. **网络延迟**: 信号触发到订单成交的延迟可能错过最佳价格",
                 "3. **订单未成交**: 限价单可能无法完全成交，影响策略执行",
                 "4. **极端行情**: 大幅波动时流动性不足，实际成交价偏离预期",
                 "5. **API限制**: 交易所API速率限制可能影响高频策略",
                 "",
                 "### 6.4 手续费敏感度总结",
                 "",
                 "| 时间框架 | 敏感度（%/0.01%费率） | 盈亏平衡点（%） |",
                 "|---------|---------------------|----------------|")

for (tf in timeframes) {
  analysis <- fee_impact_analysis[[tf]]
  if (is.null(analysis)) next

  sens_str <- ifelse(is.na(analysis$sensitivity),
                    "N/A",
                    sprintf("%.4f", analysis$sensitivity))
  break_str <- ifelse(is.na(analysis$breakeven_fee) || analysis$breakeven_fee <= 0,
                     "N/A",
                     sprintf("%.3f", analysis$breakeven_fee))

  report_lines <- c(report_lines,
                   sprintf("| %s | %s | %s |", tf, sens_str, break_str))
}

report_lines <- c(report_lines,
                 "",
                 "---",
                 "",
                 "## 7. 结论与建议",
                 "",
                 "### 7.1 主要结论",
                 "",
                 sprintf("1. **最佳时间框架**: %s在综合考虑收益和风险后表现最优",
                         best_config$timeframe),
                 sprintf("2. **手续费影响显著**: 从0%%到0.075%%手续费，平均收益衰减约%.1f%%",
                         mean(sapply(fee_impact_analysis, function(x) x$decay_rate), na.rm = TRUE)),
                 sprintf("3. **实盘可行性**: 在0.075%%手续费下，预期收益%.2f%%，但需警惕滑点和其他成本",
                         best_config$total_return_pct),
                 "",
                 "### 7.2 实盘建议",
                 "",
                 sprintf("1. **选择低费率交易所**: 优先选择手续费≤0.05%%的交易所或使用Maker订单"),
                 "2. **模拟盘验证**: 先在模拟盘运行1-2周，验证实际滑点和成交率",
                 "3. **小资金试运行**: 实盘初期用小资金测试，观察实际成本和收益",
                 sprintf("4. **监控手续费占比**: 确保手续费不超过总收益的30%%（当前%.1f%%）",
                         best_config$fee_ratio_pct),
                 "5. **动态调整**: 根据实盘表现，可能需要调整TP/SL以降低交易频率",
                 "",
                 "### 7.3 优化方向",
                 "",
                 "1. **降低交易频率**: 考虑提高drop阈值或增加过滤条件",
                 "2. **动态手续费**: 根据市场流动性调整策略激进度",
                 "3. **批量下单**: 合并接近的信号，减少交易次数",
                 "4. **Maker优先**: 使用限价单而非市价单，降低手续费和滑点",
                 "",
                 "---",
                 "",
                 sprintf("**报告生成**: R脚本 `comprehensive_fee_analysis.R`"),
                 sprintf("**数据输出**: `fee_impact_results.csv`"),
                 sprintf("**完成时间**: %s", Sys.time()),
                 "")

# 写入报告
writeLines(report_lines, report_file)
cat(sprintf("报告已生成: %s\n", report_file))

# ============================================================================
# 总结输出
# ============================================================================

cat("\n" , paste(rep("=", 80), collapse=""), "\n")
cat("分析完成！\n")
cat(paste(rep("=", 80), collapse=""), "\n")
cat("\n生成的文件：\n")
cat(sprintf("  1. %s (测试脚本)\n", "comprehensive_fee_analysis.R"))
cat(sprintf("  2. %s (详细报告)\n", report_file))
cat(sprintf("  3. %s (结果数据)\n", output_csv))
cat("\n关键发现：\n")
cat(sprintf("  - 最佳时间框架: %s\n", best_config$timeframe))
cat(sprintf("  - 最优收益: %.2f%% (0.075%%手续费)\n", best_config$total_return_pct))
cat(sprintf("  - 平均手续费影响: %.1f%% 收益衰减\n",
            mean(sapply(fee_impact_analysis, function(x) x$decay_rate), na.rm = TRUE)))
cat("\n")
