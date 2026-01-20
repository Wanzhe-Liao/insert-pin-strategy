# ============================================================================
# 回测版本对比测试脚本
# ============================================================================
#
# 对比三种版本：
# - 版本A：无手续费 + 收盘价触发（旧版）
# - 版本B：无手续费 + 盘中触发（改进版）
# - 版本C：0.075%手续费 + 盘中触发（最终版）
#
# ============================================================================

library(data.table)
library(lubridate)

# 加载回测函数
source("backtest_with_fee.R")

# ============================================================================
# 版本A：无手续费 + 收盘价触发（旧版逻辑）
# ============================================================================

backtest_version_a <- function(data,
                                initial_capital = 1000,
                                take_profit = 0.10,
                                stop_loss = 0.10) {

  cat("\n执行回测 [版本A: 无手续费 + 收盘价触发]...\n")

  capital <- initial_capital
  position <- 0
  entry_price <- 0
  in_position <- FALSE

  trades <- list()
  trade_id <- 0

  for (i in 1:nrow(data)) {
    row <- data[i]

    if (!in_position && row$signal == 1) {
      entry_price <- row$close
      position <- capital / entry_price
      take_profit_price <- entry_price * (1 + take_profit)
      stop_loss_price <- entry_price * (1 - stop_loss)
      in_position <- TRUE
      entry_time <- row$timestamp
      entry_index <- i
      next
    }

    if (in_position) {
      exit_triggered <- FALSE
      exit_price <- 0
      exit_type <- ""

      # 使用收盘价判断
      if (row$close >= take_profit_price) {
        exit_price <- row$close
        exit_type <- "TP"
        exit_triggered <- TRUE
      } else if (row$close <= stop_loss_price) {
        exit_price <- row$close
        exit_type <- "SL"
        exit_triggered <- TRUE
      }

      if (exit_triggered) {
        exit_value <- position * exit_price
        profit <- exit_value - capital
        profit_pct <- (exit_value / capital - 1) * 100
        capital <- exit_value

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
          capital_after = capital
        )

        in_position <- FALSE
        position <- 0
        entry_price <- 0
      }
    }
  }

  # 最后强制平仓
  if (in_position) {
    last_row <- data[nrow(data)]
    exit_price <- last_row$close
    exit_value <- position * exit_price
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
      capital_after = capital
    )
  }

  if (length(trades) > 0) {
    trades_dt <- rbindlist(trades)
  } else {
    trades_dt <- data.table()
  }

  stats <- calculate_statistics(trades_dt, initial_capital, capital)

  return(list(
    trades = trades_dt,
    stats = stats,
    final_capital = capital
  ))
}

# ============================================================================
# 版本B：无手续费 + 盘中触发
# ============================================================================

backtest_version_b <- function(data,
                                initial_capital = 1000,
                                take_profit = 0.10,
                                stop_loss = 0.10) {

  cat("\n执行回测 [版本B: 无手续费 + 盘中触发]...\n")

  capital <- initial_capital
  position <- 0
  entry_price <- 0
  in_position <- FALSE

  trades <- list()
  trade_id <- 0

  for (i in 1:nrow(data)) {
    row <- data[i]

    if (!in_position && row$signal == 1) {
      entry_price <- row$close
      position <- capital / entry_price
      take_profit_price <- entry_price * (1 + take_profit)
      stop_loss_price <- entry_price * (1 - stop_loss)
      in_position <- TRUE
      entry_time <- row$timestamp
      entry_index <- i
      next
    }

    if (in_position) {
      exit_triggered <- FALSE
      exit_price <- 0
      exit_type <- ""

      # 使用High/Low判断（盘中触发）
      tp_triggered <- row$high >= take_profit_price
      sl_triggered <- row$low <= stop_loss_price

      if (tp_triggered && sl_triggered) {
        is_green <- row$close >= row$open
        if (is_green) {
          exit_price <- take_profit_price
          exit_type <- "TP"
        } else {
          exit_price <- stop_loss_price
          exit_type <- "SL"
        }
        exit_triggered <- TRUE
      } else if (tp_triggered) {
        exit_price <- take_profit_price
        exit_type <- "TP"
        exit_triggered <- TRUE
      } else if (sl_triggered) {
        exit_price <- stop_loss_price
        exit_type <- "SL"
        exit_triggered <- TRUE
      }

      if (exit_triggered) {
        exit_value <- position * exit_price
        profit <- exit_value - capital
        profit_pct <- (exit_value / capital - 1) * 100
        capital <- exit_value

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
          capital_after = capital
        )

        in_position <- FALSE
        position <- 0
        entry_price <- 0
      }
    }
  }

  # 最后强制平仓
  if (in_position) {
    last_row <- data[nrow(data)]
    exit_price <- last_row$close
    exit_value <- position * exit_price
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
      capital_after = capital
    )
  }

  if (length(trades) > 0) {
    trades_dt <- rbindlist(trades)
  } else {
    trades_dt <- data.table()
  }

  stats <- calculate_statistics(trades_dt, initial_capital, capital)

  return(list(
    trades = trades_dt,
    stats = stats,
    final_capital = capital
  ))
}

# ============================================================================
# 主测试函数
# ============================================================================

run_comparison_test <- function() {
  cat("\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("回测版本对比测试\n")
  cat(rep("=", 80), "\n", sep = "")

  # 加载数据
  cat("\n加载数据: PEPEUSDT_15m...\n")

  # 首先尝试从RData文件加载
  rdata_path <- "data/liaochu.RData"

  if (file.exists(rdata_path)) {
    cat("从 liaochu.RData 加载数据...\n")
    load(rdata_path)

    # 获取数据对象（可能是cryptodata或liaochu）
    if (exists("cryptodata")) {
      crypto_list <- cryptodata
    } else if (exists("liaochu")) {
      crypto_list <- liaochu
    } else {
      stop("在 RData 文件中未找到 cryptodata 或 liaochu 对象")
    }

    # 查找PEPE相关的15分钟数据
    pepe_names <- names(crypto_list)[grepl("PEPE.*15m", names(crypto_list), ignore.case = TRUE)]

    if (length(pepe_names) == 0) {
      pepe_names <- names(crypto_list)[grepl("PEPE", names(crypto_list), ignore.case = TRUE)]
    }

    if (length(pepe_names) == 0) {
      stop("在 RData 文件中未找到 PEPE 数据")
    }

    cat(sprintf("找到PEPE数据: %s\n", pepe_names[1]))
    data <- crypto_list[[pepe_names[1]]]

  } else {
    # 尝试从CSV加载
    csv_path <- "PEPEUSDT_15m.csv"
    if (!file.exists(csv_path)) {
      stop("数据文件不存在。需要 liaochu.RData 或 PEPEUSDT_15m.csv")
    }
    cat("从 CSV 文件加载数据...\n")
    data <- fread(csv_path)
  }

  # 处理xts对象
  if (inherits(data, "xts")) {
    cat("数据是xts对象，正在转换为data.table...\n")
    require(xts)

    # 提取时间索引
    timestamps <- index(data)

    # 转换为data.table
    data <- as.data.table(data)
    data[, timestamp := timestamps]

    # 确保列名正确（转换为小写）
    setnames(data, tolower(names(data)))

  } else {
    # 转换为data.table
    data <- as.data.table(data)

    # 确保列名正确（转换为小写）
    setnames(data, tolower(names(data)))

    # 确保有timestamp列
    if (!"timestamp" %in% names(data)) {
      if ("open_time" %in% names(data)) {
        data[, timestamp := as.POSIXct(open_time / 1000, origin = "1970-01-01", tz = "UTC")]
      } else if ("time" %in% names(data)) {
        if (is.numeric(data$time[1]) && data$time[1] > 1e9) {
          data[, timestamp := as.POSIXct(time / 1000, origin = "1970-01-01", tz = "UTC")]
        } else {
          data[, timestamp := as.POSIXct(time)]
        }
      } else {
        stop("无法找到时间戳列")
      }
    } else {
      if (is.numeric(data$timestamp[1]) && data$timestamp[1] > 1e9) {
        data[, timestamp := as.POSIXct(timestamp / 1000, origin = "1970-01-01", tz = "UTC")]
      } else if (!inherits(data$timestamp, "POSIXct")) {
        data[, timestamp := as.POSIXct(timestamp)]
      }
    }
  }

  cat(sprintf("数据行数: %d\n", nrow(data)))
  cat(sprintf("时间范围: %s 到 %s\n",
              format(min(data$timestamp)), format(max(data$timestamp))))

  # 参数设置
  lookback_days <- 3
  drop_threshold <- 0.20
  initial_capital <- 1000
  take_profit <- 0.10
  stop_loss <- 0.10
  fee_rate <- 0.00075

  cat("\n参数设置:\n")
  cat(sprintf("  回看天数: %d\n", lookback_days))
  cat(sprintf("  跌幅阈值: %.1f%%\n", drop_threshold * 100))
  cat(sprintf("  初始资金: $%.2f\n", initial_capital))
  cat(sprintf("  止盈: %.1f%%\n", take_profit * 100))
  cat(sprintf("  止损: %.1f%%\n", stop_loss * 100))
  cat(sprintf("  单边手续费: %.3f%%\n", fee_rate * 100))

  # 检测时间框架并生成信号（所有版本共用）
  timeframe_minutes <- detect_timeframe(data)
  lookback_bars <- convert_days_to_bars(lookback_days, timeframe_minutes)
  data_with_signals <- generate_signals(data, lookback_bars, drop_threshold)

  # ========================================
  # 版本A：无手续费 + 收盘价触发
  # ========================================
  cat("\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("版本A：无手续费 + 收盘价触发（旧版）\n")
  cat(rep("=", 80), "\n", sep = "")

  result_a <- backtest_version_a(
    data_with_signals,
    initial_capital = initial_capital,
    take_profit = take_profit,
    stop_loss = stop_loss
  )

  print_statistics(result_a$stats, initial_capital, result_a$final_capital)

  # ========================================
  # 版本B：无手续费 + 盘中触发
  # ========================================
  cat("\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("版本B：无手续费 + 盘中触发（改进版）\n")
  cat(rep("=", 80), "\n", sep = "")

  result_b <- backtest_version_b(
    data_with_signals,
    initial_capital = initial_capital,
    take_profit = take_profit,
    stop_loss = stop_loss
  )

  print_statistics(result_b$stats, initial_capital, result_b$final_capital)

  # ========================================
  # 版本C：0.075%手续费 + 盘中触发
  # ========================================
  cat("\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("版本C：0.075%手续费 + 盘中触发（最终版）\n")
  cat(rep("=", 80), "\n", sep = "")

  result_c <- backtest_with_intrabar_and_fee(
    data_with_signals,
    initial_capital = initial_capital,
    take_profit = take_profit,
    stop_loss = stop_loss,
    fee_rate = fee_rate
  )

  print_statistics(result_c$stats, initial_capital, result_c$final_capital)

  # ========================================
  # 性能对比表
  # ========================================
  cat("\n\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("性能对比汇总\n")
  cat(rep("=", 80), "\n", sep = "")

  comparison <- data.table(
    版本 = c("A: 无费用+收盘触发", "B: 无费用+盘中触发", "C: 0.075%费+盘中触发"),
    总交易次数 = c(result_a$stats$total_trades,
                result_b$stats$total_trades,
                result_c$stats$total_trades),
    盈利次数 = c(result_a$stats$winning_trades,
              result_b$stats$winning_trades,
              result_c$stats$winning_trades),
    亏损次数 = c(result_a$stats$losing_trades,
              result_b$stats$losing_trades,
              result_c$stats$losing_trades),
    胜率 = sprintf("%.2f%%", c(result_a$stats$win_rate,
                              result_b$stats$win_rate,
                              result_c$stats$win_rate)),
    最终资金 = sprintf("$%.2f", c(result_a$final_capital,
                                 result_b$final_capital,
                                 result_c$final_capital)),
    总盈亏 = sprintf("$%.2f", c(result_a$stats$total_profit,
                               result_b$stats$total_profit,
                               result_c$stats$total_profit)),
    总收益率 = sprintf("%.2f%%", c(result_a$stats$total_return,
                                 result_b$stats$total_return,
                                 result_c$stats$total_return)),
    平均盈亏 = sprintf("$%.2f", c(result_a$stats$avg_profit,
                                 result_b$stats$avg_profit,
                                 result_c$stats$avg_profit)),
    最大盈利 = sprintf("$%.2f", c(result_a$stats$max_profit,
                                 result_b$stats$max_profit,
                                 result_c$stats$max_profit)),
    最大亏损 = sprintf("$%.2f", c(result_a$stats$max_loss,
                                 result_b$stats$max_loss,
                                 result_c$stats$max_loss)),
    总手续费 = sprintf("$%.2f", c(0, 0, result_c$stats$total_fees))
  )

  print(comparison)

  # ========================================
  # 关键差异分析
  # ========================================
  cat("\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("关键差异分析\n")
  cat(rep("=", 80), "\n", sep = "")

  cat("\n1. 触发机制影响 (A vs B):\n")
  profit_diff_ab <- result_b$stats$total_profit - result_a$stats$total_profit
  return_diff_ab <- result_b$stats$total_return - result_a$stats$total_return
  cat(sprintf("   盘中触发相比收盘触发:\n"))
  cat(sprintf("   - 盈亏差异: $%.2f (%.2f%%)\n", profit_diff_ab, return_diff_ab))
  cat(sprintf("   - 说明: %s\n",
              ifelse(profit_diff_ab > 0,
                     "盘中触发能更快止盈/止损，提高了收益",
                     "盘中触发可能过早出场，降低了收益")))

  cat("\n2. 手续费影响 (B vs C):\n")
  profit_diff_bc <- result_c$stats$total_profit - result_b$stats$total_profit
  return_diff_bc <- result_c$stats$total_return - result_b$stats$total_return
  cat(sprintf("   手续费对收益的影响:\n"))
  cat(sprintf("   - 盈亏差异: $%.2f (%.2f%%)\n", profit_diff_bc, return_diff_bc))
  cat(sprintf("   - 总手续费: $%.2f\n", result_c$stats$total_fees))
  cat(sprintf("   - 手续费占初始资金: %.2f%%\n",
              result_c$stats$total_fees / initial_capital * 100))
  cat(sprintf("   - 手续费占总盈亏: %.2f%%\n",
              abs(result_c$stats$total_fees / result_b$stats$total_profit * 100)))

  cat("\n3. 综合影响 (A vs C):\n")
  profit_diff_ac <- result_c$stats$total_profit - result_a$stats$total_profit
  return_diff_ac <- result_c$stats$total_return - result_a$stats$total_return
  cat(sprintf("   从旧版到最终版:\n"))
  cat(sprintf("   - 盈亏差异: $%.2f (%.2f%%)\n", profit_diff_ac, return_diff_ac))
  cat(sprintf("   - 说明: 这是考虑盘中触发和手续费后的真实表现\n"))

  # ========================================
  # 交易细节对比（前5笔）
  # ========================================
  cat("\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("前5笔交易对比\n")
  cat(rep("=", 80), "\n", sep = "")

  n_compare <- min(5, result_a$stats$total_trades,
                   result_b$stats$total_trades,
                   result_c$stats$total_trades)

  if (n_compare > 0) {
    for (i in 1:n_compare) {
      cat(sprintf("\n交易 #%d:\n", i))

      # 版本A
      if (i <= nrow(result_a$trades)) {
        trade_a <- result_a$trades[i]
        cat(sprintf("  [A] 出场: %s @ $%.6f, 盈亏: $%.2f (%.2f%%), 类型: %s\n",
                    format(trade_a$exit_time), trade_a$exit_price,
                    trade_a$profit, trade_a$profit_pct, trade_a$exit_type))
      }

      # 版本B
      if (i <= nrow(result_b$trades)) {
        trade_b <- result_b$trades[i]
        cat(sprintf("  [B] 出场: %s @ $%.6f, 盈亏: $%.2f (%.2f%%), 类型: %s\n",
                    format(trade_b$exit_time), trade_b$exit_price,
                    trade_b$profit, trade_b$profit_pct, trade_b$exit_type))
      }

      # 版本C
      if (i <= nrow(result_c$trades)) {
        trade_c <- result_c$trades[i]
        cat(sprintf("  [C] 出场: %s @ $%.6f, 盈亏: $%.2f (%.2f%%), 类型: %s, 手续费: $%.2f\n",
                    format(trade_c$exit_time), trade_c$exit_price,
                    trade_c$profit, trade_c$profit_pct, trade_c$exit_type,
                    trade_c$total_fee))
      }
    }
  }

  cat("\n")
  cat(rep("=", 80), "\n", sep = "")
  cat("测试完成！\n")
  cat(rep("=", 80), "\n", sep = "")

  # 返回所有结果
  return(list(
    version_a = result_a,
    version_b = result_b,
    version_c = result_c,
    comparison = comparison
  ))
}

# ============================================================================
# 执行测试
# ============================================================================

# 运行对比测试
results <- run_comparison_test()

# 可以进一步分析结果
cat("\n提示：结果已保存在 'results' 变量中\n")
cat("  - results$version_a: 版本A的完整结果\n")
cat("  - results$version_b: 版本B的完整结果\n")
cat("  - results$version_c: 版本C的完整结果\n")
cat("  - results$comparison: 对比表\n")
