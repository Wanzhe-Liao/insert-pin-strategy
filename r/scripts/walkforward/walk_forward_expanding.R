suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
  library(parallel)
  library(doParallel)
  library(foreach)
  library(lubridate)
  library(optparse)
})

option_list <- list(
  make_option(c("-d", "--dataset"), type="character", default="BTCUSDT_5m",
              help="Dataset name (e.g., BTCUSDT_5m, BTCUSDT_15m) [default: %default]"),
  make_option(c("-e", "--initial_train_end"), type="character", default="2019-12",
              help="Initial training end month (e.g., '2019-12') [default: %default]"),
  make_option(c("-c", "--cores"), type="integer", default=32,
              help="Number of parallel cores [default: %default]"),
  make_option(c("-o", "--output_dir"), type="character",
              default="walkforward",
              help="Output directory [default: %default]")
)

opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

dataset_name <- opt$dataset
initial_train_end <- opt$initial_train_end
n_cores <- opt$cores
output_dir <- opt$output_dir

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat(sprintf('%s Expanding Window Walk-Forward Analysis\n', dataset_name))
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('数据集: %s\n', dataset_name))
cat(sprintf('初始训练截止: %s\n', initial_train_end))
cat(sprintf('并行核心: %d\n', n_cores))
cat(sprintf('优化配置: 标准优化 (10000次采样)\n'))
cat(sprintf('输出目录: %s\n\n', output_dir))

source("backtest_tradingview_aligned.R")

cat('正在加载数据...\n')
load('data/liaochu.RData')
full_data <- cryptodata[[dataset_name]]
cat(sprintf('OK 数据行数: %d\n', nrow(full_data)))
cat(sprintf('OK 时间范围: %s 至 %s\n\n',
            as.character(index(full_data)[1]),
            as.character(index(full_data)[nrow(full_data)])))

split_data_by_month <- function(data) {
  dates <- index(data)
  year_month <- format(dates, "%Y-%m")
  unique_months <- unique(year_month)

  month_list <- list()
  for (ym in unique_months) {
    month_data <- data[year_month == ym]
    if (nrow(month_data) > 0) {
      month_list[[ym]] <- month_data
    }
  }

  cat(sprintf('OK 数据已切分为 %d 个月份\n', length(month_list)))
  return(month_list)
}

generate_expanding_windows <- function(month_ids, initial_end_month, test_size=1) {
  n_months <- length(month_ids)

  initial_end_idx <- which(month_ids == initial_end_month)
  if (length(initial_end_idx) == 0) {
    stop(sprintf("初始训练截止月份 '%s' 不在数据范围内", initial_end_month))
  }

  windows <- list()

  for (i in initial_end_idx:(n_months - test_size)) {
    train_start <- 1
    train_end <- i
    test_start <- i + 1
    test_end <- test_start + test_size - 1

    windows[[length(windows) + 1]] <- list(
      window_id = length(windows) + 1,
      train_months = month_ids[train_start:train_end],
      test_months = month_ids[test_start:test_end]
    )
  }

  cat(sprintf('OK 生成 %d 个扩展窗口 (训练集从%s逐步扩展至最新)\n',
              length(windows), month_ids[1]))

  return(windows)
}

standard_optimize_2stage <- function(train_data, cores=32) {
  cl <- makeCluster(cores)
  registerDoParallel(cl)

  clusterExport(cl, c('train_data', 'backtest_tradingview_aligned',
                      'generate_drop_signals', 'detect_timeframe_minutes',
                      'days_to_bars'), envir=environment())
  clusterEvalQ(cl, {
    suppressMessages({
      library(xts)
      library(data.table)
      library(RcppRoll)
    })
  })

  objective_function <- function(params_df, data) {
    results <- foreach(i = 1:nrow(params_df),
                       .combine = 'rbind',
                       .errorhandling = 'pass',
                       .export = c('data'),
                       .packages = c('xts', 'data.table', 'RcppRoll')) %dopar% {

      p <- params_df[i, ]

      tryCatch({
        result <- backtest_tradingview_aligned(
          data = data,
          lookbackDays = p$lookback,
          minDropPercent = p$minDrop,
          takeProfitPercent = p$TP,
          stopLossPercent = p$SL,
          initialCapital = 10000,
          feeRate = 0.00075,
          processOnClose = TRUE,
          verbose = FALSE,
          logIgnoredSignals = FALSE
        )

        if (!is.null(result) && result$TradeCount > 0) {
          max_return <- 2500
          max_trades <- 400
          normalized_return <- min(result$ReturnPercent / max_return, 1.0)
          normalized_winrate <- result$WinRate / 100
          normalized_drawdown_control <- 1 - abs(result$MaxDrawdown) / 100
          normalized_trades <- min(sqrt(result$TradeCount) / sqrt(max_trades), 1.0)

          w_return <- 0.35
          w_drawdown <- 0.30
          w_winrate <- 0.05
          w_trades <- 0.30

          composite_score <- w_return * normalized_return +
            w_drawdown * normalized_drawdown_control +
            w_winrate * normalized_winrate +
            w_trades * normalized_trades

          data.frame(
            lookback = p$lookback,
            minDrop = p$minDrop,
            TP = p$TP,
            SL = p$SL,
            score = composite_score,
            return_pct = result$ReturnPercent,
            win_rate = result$WinRate,
            max_dd = result$MaxDrawdown,
            trades = result$TradeCount,
            stringsAsFactors = FALSE
          )
        } else {
          data.frame(
            lookback = p$lookback,
            minDrop = p$minDrop,
            TP = p$TP,
            SL = p$SL,
            score = 0,
            return_pct = 0,
            win_rate = 0,
            max_dd = 0,
            trades = 0,
            stringsAsFactors = FALSE
          )
        }
      }, error = function(e) {
        data.frame(
          lookback = p$lookback,
          minDrop = p$minDrop,
          TP = p$TP,
          SL = p$SL,
          score = 0,
          return_pct = 0,
          win_rate = 0,
          max_dd = 0,
          trades = 0,
          stringsAsFactors = FALSE
        )
      })
    }

    return(results)
  }

  n_phase1 <- 5000
  n_phase2 <- 5000

  set.seed(42)
  phase1_params <- data.frame(
    lookback = sample(1:10, n_phase1, replace = TRUE),
    minDrop = round(runif(n_phase1, 0, 20) * 20) / 20,
    TP = round(runif(n_phase1, 0, 20) * 20) / 20,
    SL = round(runif(n_phase1, 0, 20) * 20) / 20
  )

  phase1_results <- objective_function(phase1_params, train_data)

  top20_pct_threshold <- quantile(phase1_results$score, 0.80)
  top_params <- phase1_results[phase1_results$score >= top20_pct_threshold, ]

  if (nrow(top_params) < 5) {
    top_params <- phase1_results[order(-phase1_results$score), ][1:min(10, nrow(phase1_results)), ]
  }

  phase2_params <- data.frame(
    lookback = integer(n_phase2),
    minDrop = numeric(n_phase2),
    TP = numeric(n_phase2),
    SL = numeric(n_phase2)
  )

  for (i in 1:n_phase2) {
    base <- top_params[sample(nrow(top_params), 1), ]
    phase2_params$lookback[i] <- pmax(1, pmin(10, round(base$lookback + rnorm(1, 0, 1))))
    phase2_params$minDrop[i] <- round(pmax(0, pmin(20, base$minDrop + rnorm(1, 0, 2))) * 20) / 20
    phase2_params$TP[i] <- round(pmax(0, pmin(20, base$TP + rnorm(1, 0, 2))) * 20) / 20
    phase2_params$SL[i] <- round(pmax(0, pmin(20, base$SL + rnorm(1, 0, 2))) * 20) / 20
  }

  phase2_results <- objective_function(phase2_params, train_data)

  final_results <- rbind(phase1_results, phase2_results)

  stopCluster(cl)

  best_idx <- which.max(final_results$score)
  best_params <- final_results[best_idx, ]

  return(list(
    best_params = best_params,
    all_results = final_results
  ))
}

walk_forward_expanding <- function(full_data, initial_train_end, cores=32) {
  month_list <- split_data_by_month(full_data)
  month_ids <- names(month_list)

  windows <- generate_expanding_windows(month_ids, initial_train_end, test_size=1)

  cat('\n')
  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat('开始Expanding Window滚动回测\n')
  cat('════════════════════════════════════════════════════════════════════════════\n\n')

  all_window_results <- list()
  start_total <- Sys.time()

  for (w in windows) {
    window_id <- w$window_id
    train_month_ids <- w$train_months
    test_month_ids <- w$test_months

    cat('────────────────────────────────────────────────────────────────────────────\n')
    cat(sprintf('[Window %d/%d] 训练: %s ~ %s (%d月) | 测试: %s\n',
                window_id, length(windows),
                train_month_ids[1],
                train_month_ids[length(train_month_ids)],
                length(train_month_ids),
                paste(test_month_ids, collapse=", ")))
    cat('────────────────────────────────────────────────────────────────────────────\n\n')

    train_data_list <- lapply(train_month_ids, function(m) month_list[[m]])
    train_data <- do.call(rbind, train_data_list)

    test_data_list <- lapply(test_month_ids, function(m) month_list[[m]])
    test_data <- do.call(rbind, test_data_list)

    cat(sprintf('训练数据: %d根K线 (%d个月累积)\n', nrow(train_data), length(train_month_ids)))
    cat(sprintf('测试数据: %d根K线\n\n', nrow(test_data)))

    cat('阶段1: 训练期参数优化 (10000次采样)...\n')
    opt_start <- Sys.time()
    opt_result <- standard_optimize_2stage(train_data, cores=cores)
    opt_time <- as.numeric(difftime(Sys.time(), opt_start, units='secs'))

    best_params <- opt_result$best_params

    cat(sprintf('OK 优化完成 (%.1f秒)\n', opt_time))
    cat(sprintf('  最佳参数: lookback=%d, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n',
                best_params$lookback, best_params$minDrop,
                best_params$TP, best_params$SL))
    cat(sprintf('  训练期绩效: 收益%.2f%%, 胜率%.1f%%, 回撤%.1f%%, %d笔\n\n',
                best_params$return_pct, best_params$win_rate,
                best_params$max_dd, best_params$trades))

    cat('阶段2: 测试期样本外回测...\n')
    test_result <- backtest_tradingview_aligned(
      data = test_data,
      lookbackDays = best_params$lookback,
      minDropPercent = best_params$minDrop,
      takeProfitPercent = best_params$TP,
      stopLossPercent = best_params$SL,
      initialCapital = 10000,
      feeRate = 0.00075,
      processOnClose = TRUE,
      verbose = FALSE,
      logIgnoredSignals = FALSE
    )

    test_return <- if (!is.null(test_result)) test_result$ReturnPercent else 0
    test_winrate <- if (!is.null(test_result)) test_result$WinRate else 0
    test_maxdd <- if (!is.null(test_result)) test_result$MaxDrawdown else 0
    test_trades <- if (!is.null(test_result)) test_result$TradeCount else 0

    cat(sprintf('OK 测试完成\n'))
    cat(sprintf('  测试期绩效: 收益%.2f%%, 胜率%.1f%%, 回撤%.1f%%, %d笔\n\n',
                test_return, test_winrate, test_maxdd, test_trades))

    all_window_results[[window_id]] <- data.frame(
      window_id = window_id,
      train_start = train_month_ids[1],
      train_end = train_month_ids[length(train_month_ids)],
      train_months_count = length(train_month_ids),
      test_month = paste(test_month_ids, collapse="|"),
      lookback = best_params$lookback,
      minDrop = best_params$minDrop,
      TP = best_params$TP,
      SL = best_params$SL,
      train_return_pct = best_params$return_pct,
      train_win_rate = best_params$win_rate,
      train_max_dd = best_params$max_dd,
      train_trades = best_params$trades,
      test_return_pct = test_return,
      test_win_rate = test_winrate,
      test_max_dd = test_maxdd,
      test_trades = test_trades,
      opt_time_secs = opt_time,
      stringsAsFactors = FALSE
    )
  }

  total_time <- as.numeric(difftime(Sys.time(), start_total, units='mins'))

  cat('\n')
  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat('Expanding Window回测完成\n')
  cat('════════════════════════════════════════════════════════════════════════════\n\n')
  cat(sprintf('总耗时: %.1f分钟\n', total_time))
  cat(sprintf('完成窗口数: %d\n\n', length(all_window_results)))

  results_df <- do.call(rbind, all_window_results)
  return(results_df)
}

aggregate_results <- function(results_df) {
  test_returns <- results_df$test_return_pct / 100
  cumulative_return <- prod(1 + test_returns) - 1

  total_test_trades <- sum(results_df$test_trades)
  avg_winrate <- sum(results_df$test_win_rate * results_df$test_trades) / total_test_trades

  n_test_months <- nrow(results_df)
  avg_trades_per_month <- total_test_trades / n_test_months

  equity_curve <- cumprod(1 + test_returns)
  peak <- cummax(equity_curve)
  drawdown <- (equity_curve - peak) / peak
  max_drawdown <- min(drawdown) * 100

  monthly_return_mean <- mean(test_returns)
  monthly_return_sd <- sd(test_returns)
  sharpe_ratio <- if (monthly_return_sd > 0) {
    (monthly_return_mean / monthly_return_sd) * sqrt(12)
  } else {
    0
  }

  calmar_ratio <- if (max_drawdown < 0) {
    (cumulative_return * 100 / n_test_months * 12) / abs(max_drawdown)
  } else {
    0
  }

  param_stability <- data.frame(
    lookback_mean = mean(results_df$lookback),
    lookback_sd = sd(results_df$lookback),
    minDrop_mean = mean(results_df$minDrop),
    minDrop_sd = sd(results_df$minDrop),
    TP_mean = mean(results_df$TP),
    TP_sd = sd(results_df$TP),
    SL_mean = mean(results_df$SL),
    SL_sd = sd(results_df$SL)
  )

  is_os_ratio <- mean(results_df$test_return_pct) / mean(results_df$train_return_pct)

  summary <- list(
    cumulative_return_pct = cumulative_return * 100,
    avg_winrate_pct = avg_winrate,
    avg_trades_per_month = avg_trades_per_month,
    max_drawdown_pct = max_drawdown,
    sharpe_ratio = sharpe_ratio,
    calmar_ratio = calmar_ratio,
    param_stability = param_stability,
    in_sample_out_sample_ratio = is_os_ratio,
    n_windows = nrow(results_df)
  )

  return(summary)
}

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('执行Expanding Window回测\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

results_df <- walk_forward_expanding(full_data, initial_train_end, cores=n_cores)

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('汇总结果\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

summary <- aggregate_results(results_df)

cat('🏆 综合绩效指标\n')
cat('────────────────────────────────────────────────────────────────────────────\n')
cat(sprintf('累积收益率:      %.2f%%\n', summary$cumulative_return_pct))
cat(sprintf('平均胜率:        %.1f%%\n', summary$avg_winrate_pct))
cat(sprintf('月均交易数:      %.1f笔\n', summary$avg_trades_per_month))
cat(sprintf('最大回撤:        %.1f%%\n', summary$max_drawdown_pct))
cat(sprintf('夏普比率:        %.2f\n', summary$sharpe_ratio))
cat(sprintf('卡尔马比率:      %.2f\n', summary$calmar_ratio))
cat(sprintf('IS/OS比率:       %.2f\n', summary$in_sample_out_sample_ratio))
cat('\n')

cat('📊 参数稳定性\n')
cat('────────────────────────────────────────────────────────────────────────────\n')
ps <- summary$param_stability
cat(sprintf('lookback:  %.2f ± %.2f\n', ps$lookback_mean, ps$lookback_sd))
cat(sprintf('minDrop:   %.2f%% ± %.2f%%\n', ps$minDrop_mean, ps$minDrop_sd))
cat(sprintf('TP:        %.2f%% ± %.2f%%\n', ps$TP_mean, ps$TP_sd))
cat(sprintf('SL:        %.2f%% ± %.2f%%\n', ps$SL_mean, ps$SL_sd))
cat('\n')

detail_file <- file.path(output_dir, sprintf('%s_expanding_details.csv', dataset_name))
write.csv(results_df, detail_file, row.names = FALSE)
cat(sprintf('OK 详细结果已保存: %s\n', detail_file))

summary_file <- file.path(output_dir, sprintf('%s_expanding_summary.txt', dataset_name))
sink(summary_file)
cat(sprintf('Expanding Window Walk-Forward Analysis\n'))
cat(sprintf('Initial Training: [Start ~ %s]\n\n', initial_train_end))
cat('综合绩效指标\n')
cat('────────────────────────────────────────────────────\n')
cat(sprintf('累积收益率:      %.2f%%\n', summary$cumulative_return_pct))
cat(sprintf('平均胜率:        %.1f%%\n', summary$avg_winrate_pct))
cat(sprintf('月均交易数:      %.1f笔\n', summary$avg_trades_per_month))
cat(sprintf('最大回撤:        %.1f%%\n', summary$max_drawdown_pct))
cat(sprintf('夏普比率:        %.2f\n', summary$sharpe_ratio))
cat(sprintf('卡尔马比率:      %.2f\n', summary$calmar_ratio))
cat(sprintf('IS/OS比率:       %.2f\n', summary$in_sample_out_sample_ratio))
cat('\n')
cat('参数稳定性\n')
cat('────────────────────────────────────────────────────\n')
cat(sprintf('lookback:  %.2f ± %.2f\n', ps$lookback_mean, ps$lookback_sd))
cat(sprintf('minDrop:   %.2f%% ± %.2f%%\n', ps$minDrop_mean, ps$minDrop_sd))
cat(sprintf('TP:        %.2f%% ± %.2f%%\n', ps$TP_mean, ps$TP_sd))
cat(sprintf('SL:        %.2f%% ± %.2f%%\n', ps$SL_mean, ps$SL_sd))
sink()
cat(sprintf('OK 摘要已保存: %s\n\n', summary_file))

cat('🎉 Expanding Window Walk-Forward Analysis 完成!\n\n')
