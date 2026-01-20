suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
  library(ParBayesianOptimization)
  library(parallel)
  library(doParallel)
})

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('PEPEUSDT 贝叶斯优化系统 (32核并行)\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

source("backtest_tradingview_aligned.R")

cat('正在加载数据...\n')
load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]
cat(sprintf('OK 数据行数: %d\n', nrow(data)))
cat(sprintf('OK 时间范围: %s 至 %s\n\n',
            as.character(index(data)[1]),
            as.character(index(data)[nrow(data)])))

objective_function <- function(lookbackDays, minDropPercent, takeProfitPercent, stopLossPercent) {

  lookback_int <- round(lookbackDays)

  tryCatch({
    result <- backtest_tradingview_aligned(
      data = data,
      lookbackDays = lookback_int,
      minDropPercent = minDropPercent,
      takeProfitPercent = takeProfitPercent,
      stopLossPercent = stopLossPercent,
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
      drawdown_penalty <- 1 - abs(result$MaxDrawdown) / 100
      normalized_trades <- min(sqrt(result$TradeCount) / sqrt(max_trades), 1.0)

      composite_score <- normalized_return * normalized_winrate * drawdown_penalty * normalized_trades

      return(list(Score = composite_score))
    } else {
      return(list(Score = 0))
    }
  }, error = function(e) {
    return(list(Score = 0))
  })
}

bounds <- list(
  lookbackDays = c(1L, 10L),
  minDropPercent = c(5.0, 20.0),
  takeProfitPercent = c(5.0, 20.0),
  stopLossPercent = c(5.0, 20.0)
)

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('参数配置\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat('参数边界:\n')
cat('  lookbackDays:      1-10\n')
cat('  minDropPercent:    5.0%-20.0%\n')
cat('  takeProfitPercent: 5.0%-20.0%\n')
cat('  stopLossPercent:   5.0%-20.0%\n\n')

n_init <- 100
n_iters <- 153
n_iters_k <- 32
total_trials <- n_init + (n_iters * n_iters_k)

cat('优化策略:\n')
cat(sprintf('  初始随机采样:     %d次 (并行)\n', n_init))
cat(sprintf('  贝叶斯迭代epoch:  %d次\n', n_iters))
cat(sprintf('  每epoch并行评估: %d次\n', n_iters_k))
cat(sprintf('  总试验次数:       %d次\n', total_trials))
cat(sprintf('  并行核心数:       32\n\n'))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('开始贝叶斯优化\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

start_time <- Sys.time()

cl <- makeCluster(32)
registerDoParallel(cl)

clusterExport(cl, c('data', 'backtest_tradingview_aligned', 'generate_drop_signals',
                    'detect_timeframe_minutes', 'days_to_bars'))
clusterEvalQ(cl, {
  suppressMessages({
    library(xts)
    library(data.table)
    library(RcppRoll)
  })
})

cat('OK 32核并行集群已启动\n\n')

opt_result <- bayesOpt(
  FUN = objective_function,
  bounds = bounds,
  initPoints = n_init,
  iters.n = n_iters,
  iters.k = n_iters_k,
  parallel = TRUE,
  acq = "ucb",
  kappa = 2.576,
  eps = 0.0,
  verbose = 1
)

stopCluster(cl)
stopImplicitCluster()

end_time <- Sys.time()
total_time <- as.numeric(difftime(end_time, start_time, units='secs'))

cat('\n\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('优化完成\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('总耗时: %.1f秒 (%.2f分钟)\n', total_time, total_time/60))
cat(sprintf('平均每次试验: %.2f秒\n\n', total_time/total_trials))

best_params <- getBestPars(opt_result)

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('🏆 最佳参数\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('lookbackDays:      %d\n', round(best_params[1])))
cat(sprintf('minDropPercent:    %.1f%%\n', best_params[2]))
cat(sprintf('takeProfitPercent: %.1f%%\n', best_params[3]))
cat(sprintf('stopLossPercent:   %.1f%%\n\n', best_params[4]))

cat('运行最佳参数的完整回测...\n\n')

final_result <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = round(best_params[1]),
  minDropPercent = best_params[2],
  takeProfitPercent = best_params[3],
  stopLossPercent = best_params[4],
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = TRUE,
  logIgnoredSignals = FALSE
)

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('保存结果\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

output_dir <- 'optimization'

all_results <- opt_result$scoreSummary
write.csv(all_results,
          file.path(output_dir, 'bayesian_optimization_history.csv'),
          row.names = FALSE)
cat(sprintf('OK 已保存: %s\n', file.path(output_dir, 'bayesian_optimization_history.csv')))

best_params_df <- data.frame(
  lookbackDays = round(best_params[1]),
  minDropPercent = best_params[2],
  takeProfitPercent = best_params[3],
  stopLossPercent = best_params[4],
  composite_score = opt_result$scoreSummary$Score[which.max(opt_result$scoreSummary$Score)],
  return_percent = final_result$ReturnPercent,
  win_rate = final_result$WinRate,
  max_drawdown = final_result$MaxDrawdown,
  trade_count = final_result$TradeCount,
  optimization_date = as.character(Sys.time())
)

write.csv(best_params_df,
          file.path(output_dir, 'best_params_bayesian.csv'),
          row.names = FALSE)
cat(sprintf('OK 已保存: %s\n', file.path(output_dir, 'best_params_bayesian.csv')))

if (final_result$TradeCount > 0) {
  trades_df <- format_trades_df(final_result)
  write.csv(trades_df,
            file.path(output_dir, 'best_params_trades_bayesian.csv'),
            row.names = FALSE)
  cat(sprintf('OK 已保存: %s\n', file.path(output_dir, 'best_params_trades_bayesian.csv')))
}

report_path <- file.path(output_dir, 'bayesian_optimization_report.txt')
sink(report_path)

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('PEPEUSDT 贝叶斯优化报告\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('优化完成时间: %s\n', Sys.time()))
cat(sprintf('总试验次数: %d\n', total_trials))
cat(sprintf('初始采样: %d次\n', n_init))
cat(sprintf('贝叶斯迭代: %d次\n', n_iters))
cat(sprintf('总耗时: %.1f秒 (%.2f分钟)\n\n', total_time, total_time/60))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('🏆 最佳参数配置\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('lookbackDays:      %d\n', round(best_params[1])))
cat(sprintf('minDropPercent:    %.1f%%\n', best_params[2]))
cat(sprintf('takeProfitPercent: %.1f%%\n', best_params[3]))
cat(sprintf('stopLossPercent:   %.1f%%\n\n', best_params[4]))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('📊 绩效指标\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('综合评分:   %.4f\n', best_params_df$composite_score))
cat(sprintf('总收益率:   %.2f%%\n', final_result$ReturnPercent))
cat(sprintf('胜率:       %.1f%% (%d胜/%d负)\n',
            final_result$WinRate, final_result$WinCount, final_result$LossCount))
cat(sprintf('最大回撤:   %.1f%%\n', final_result$MaxDrawdown))
cat(sprintf('交易数量:   %d\n', final_result$TradeCount))
cat(sprintf('夏普比率:   %.2f\n', ifelse(is.na(final_result$AvgPnL), 0,
                                        final_result$AvgPnL / sd(sapply(final_result$Trades, function(t) t$PnLPercent)))))
cat(sprintf('平均盈亏:   %.2f%%\n\n', final_result$AvgPnL))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('优化收敛分析\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

scores <- opt_result$scoreSummary$Score
cat(sprintf('最佳得分:   %.4f\n', max(scores)))
cat(sprintf('平均得分:   %.4f\n', mean(scores)))
cat(sprintf('得分标准差: %.4f\n', sd(scores)))
cat(sprintf('得分中位数: %.4f\n\n', median(scores)))

top_10_pct_idx <- which(scores >= quantile(scores, 0.9))
cat(sprintf('Top 10%%得分阈值: %.4f\n', quantile(scores, 0.9)))
cat(sprintf('Top 10%%试验数:   %d\n\n', length(top_10_pct_idx)))

cat('════════════════════════════════════════════════════════════════════════════\n\n')

sink()

cat(sprintf('OK 已保存: %s\n\n', report_path))

cat('🎉 贝叶斯优化完成!\n\n')
