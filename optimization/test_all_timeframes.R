suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
  library(parallel)
  library(doParallel)
  library(foreach)
})

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('全时间周期参数网格测试系统\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

source("backtest_tradingview_aligned.R")

load('data/liaochu.RData')

dataset_names <- names(cryptodata)
cat(sprintf('发现 %d 个数据集\n\n', length(dataset_names)))

n_phase1 <- 5000
n_phase2 <- 10000
n_phase3 <- 5000

cat('优化配置:\n')
cat(sprintf('  • 阶段1: %d次随机采样\n', n_phase1))
cat(sprintf('  • 阶段2: %d次聚焦采样\n', n_phase2))
cat(sprintf('  • 阶段3: %d次精英搜索\n', n_phase3))
cat(sprintf('  • 总试验: %d次/数据集\n', n_phase1 + n_phase2 + n_phase3))
cat(sprintf('  • 并行核心: 32\n\n'))

cat('目标函数: 加权加法\n')
cat('  0.35×收益率 + 0.30×回撤控制 + 0.05×胜率 + 0.30×交易数量\n\n')

cl <- makeCluster(32)
registerDoParallel(cl)

clusterExport(cl, c('backtest_tradingview_aligned', 'generate_drop_signals',
                    'detect_timeframe_minutes', 'days_to_bars'))
clusterEvalQ(cl, {
  suppressMessages({
    library(xts)
    library(data.table)
    library(RcppRoll)
  })
})

cat('OK 32核并行集群已启动\n\n')

objective_function <- function(params_df, data) {
  results <- foreach(i = 1:nrow(params_df),
                     .combine = 'rbind',
                     .errorhandling = 'pass',
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

all_results <- list()

start_total <- Sys.time()

for (idx in 1:length(dataset_names)) {
  dataset_name <- dataset_names[idx]

  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat(sprintf('[%d/%d] %s\n', idx, length(dataset_names), dataset_name))
  cat('════════════════════════════════════════════════════════════════════════════\n\n')

  data <- cryptodata[[dataset_name]]
  cat(sprintf('数据行数: %d\n', nrow(data)))
  cat(sprintf('时间范围: %s 至 %s\n\n',
              as.character(index(data)[1]),
              as.character(index(data)[nrow(data)])))

  clusterExport(cl, 'data', envir=environment())

  dataset_start <- Sys.time()

  set.seed(42 + idx)
  phase1_params <- data.frame(
    lookback = sample(1:10, n_phase1, replace = TRUE),
    minDrop = round(runif(n_phase1, 0, 20) * 20) / 20,
    TP = round(runif(n_phase1, 0, 20) * 20) / 20,
    SL = round(runif(n_phase1, 0, 20) * 20) / 20
  )

  cat('阶段1: 全空间随机采样...\n')
  phase1_results <- objective_function(phase1_params, data)
  cat(sprintf('  完成，最佳得分: %.4f\n\n', max(phase1_results$score)))

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

  cat('阶段2: Top区域聚焦采样...\n')
  phase2_results <- objective_function(phase2_params, data)

  all_results_so_far <- rbind(phase1_results, phase2_results)
  cat(sprintf('  完成，最佳得分: %.4f\n\n', max(all_results_so_far$score)))

  top10_pct_threshold <- quantile(all_results_so_far$score, 0.90)
  elite_params <- all_results_so_far[all_results_so_far$score >= top10_pct_threshold, ]

  if (nrow(elite_params) < 5) {
    elite_params <- all_results_so_far[order(-all_results_so_far$score), ][1:min(10, nrow(all_results_so_far)), ]
  }

  phase3_params <- data.frame(
    lookback = integer(n_phase3),
    minDrop = numeric(n_phase3),
    TP = numeric(n_phase3),
    SL = numeric(n_phase3)
  )

  for (i in 1:n_phase3) {
    base <- elite_params[sample(nrow(elite_params), 1), ]
    phase3_params$lookback[i] <- pmax(1, pmin(10, round(base$lookback + rnorm(1, 0, 0.5))))
    phase3_params$minDrop[i] <- round(pmax(0, pmin(20, base$minDrop + rnorm(1, 0, 1))) * 20) / 20
    phase3_params$TP[i] <- round(pmax(0, pmin(20, base$TP + rnorm(1, 0, 1))) * 20) / 20
    phase3_params$SL[i] <- round(pmax(0, pmin(20, base$SL + rnorm(1, 0, 1))) * 20) / 20
  }

  cat('阶段3: 精英区域细化搜索...\n')
  phase3_results <- objective_function(phase3_params, data)

  final_results <- rbind(all_results_so_far, phase3_results)

  dataset_time <- as.numeric(difftime(Sys.time(), dataset_start, units='secs'))

  best_idx <- which.max(final_results$score)
  best_params <- final_results[best_idx, ]

  cat(sprintf('  完成，最佳得分: %.4f\n\n', best_params$score))

  cat('🏆 最佳参数:\n')
  cat(sprintf('  lookback=%d, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n',
              best_params$lookback, best_params$minDrop,
              best_params$TP, best_params$SL))
  cat(sprintf('  收益: %.2f%%, 胜率: %.1f%%, 回撤: %.1f%%, 交易: %d\n',
              best_params$return_pct, best_params$win_rate,
              best_params$max_dd, best_params$trades))
  cat(sprintf('  耗时: %.1f秒\n\n', dataset_time))

  all_results[[dataset_name]] <- list(
    dataset = dataset_name,
    best_params = best_params,
    all_trials = final_results,
    time_seconds = dataset_time
  )
}

stopCluster(cl)

total_time <- as.numeric(difftime(Sys.time(), start_total, units='secs'))

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('全部优化完成\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('总耗时: %.1f秒 (%.2f分钟)\n', total_time, total_time/60))
cat(sprintf('平均每数据集: %.1f秒\n\n', total_time/length(dataset_names)))

summary_df <- data.frame(
  dataset = character(),
  lookback = integer(),
  minDrop = numeric(),
  TP = numeric(),
  SL = numeric(),
  score = numeric(),
  return_pct = numeric(),
  win_rate = numeric(),
  max_dd = numeric(),
  trades = integer(),
  time_seconds = numeric(),
  stringsAsFactors = FALSE
)

for (dataset_name in names(all_results)) {
  result <- all_results[[dataset_name]]
  best <- result$best_params

  summary_df <- rbind(summary_df, data.frame(
    dataset = dataset_name,
    lookback = best$lookback,
    minDrop = best$minDrop,
    TP = best$TP,
    SL = best$SL,
    score = best$score,
    return_pct = best$return_pct,
    win_rate = best$win_rate,
    max_dd = best$max_dd,
    trades = best$trades,
    time_seconds = result$time_seconds,
    stringsAsFactors = FALSE
  ))
}

output_dir <- 'optimization'

write.csv(summary_df,
          file.path(output_dir, 'all_timeframes_best_params.csv'),
          row.names = FALSE)

cat(sprintf('OK 已保存: %s\n', file.path(output_dir, 'all_timeframes_best_params.csv')))

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('TOP 10 交易对×时间周期组合 (按综合评分)\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

summary_df_sorted <- summary_df[order(-summary_df$score), ]

cat(sprintf('%-20s %-8s %-8s %-6s %-6s %-9s %-9s %-8s %-8s %-7s\n',
            'Dataset', 'Lookback', 'Drop%', 'TP%', 'SL%', 'Score', 'Return%', 'WinRate%', 'MaxDD%', 'Trades'))
cat(paste(rep('─', 110), collapse=''), '\n')

for (i in 1:min(10, nrow(summary_df_sorted))) {
  r <- summary_df_sorted[i, ]
  cat(sprintf('%-20s %-8d %-8.1f %-6.1f %-6.1f %-9.4f %-9.2f %-8.1f %-8.1f %-7d\n',
              r$dataset, r$lookback, r$minDrop, r$TP, r$SL,
              r$score, r$return_pct, r$win_rate, r$max_dd, r$trades))
}

cat('\n\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('按交易对分组的最佳时间周期\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

pairs <- c('BNB', 'BOME', 'BTC', 'DOGE', 'ETH', 'PEPE', 'SOL')

for (pair in pairs) {
  pair_data <- summary_df[grepl(pair, summary_df$dataset), ]

  if (nrow(pair_data) > 0) {
    best_idx <- which.max(pair_data$score)
    best_row <- pair_data[best_idx, ]

    cat(sprintf('%sUSDT:\n', pair))
    cat(sprintf('  最佳时间周期: %s\n', best_row$dataset))
    cat(sprintf('  参数: lookback=%d, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n',
                best_row$lookback, best_row$minDrop, best_row$TP, best_row$SL))
    cat(sprintf('  绩效: 收益%.2f%%, 胜率%.1f%%, 回撤%.1f%%, %d笔交易\n',
                best_row$return_pct, best_row$win_rate, best_row$max_dd, best_row$trades))
    cat(sprintf('  综合评分: %.4f\n\n', best_row$score))
  }
}

cat('🎉 全时间周期参数网格测试完成!\n\n')
