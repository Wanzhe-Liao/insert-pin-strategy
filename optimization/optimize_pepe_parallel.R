# ============================================================================
# PEPEUSDT 并行参数优化系统 (32核心)
# ============================================================================
#
# 优化方法：网格搜索 + 32核并行计算
# 性能提升：32倍加速（理论）
#
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
  library(parallel)
  library(foreach)
  library(doParallel)
})

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('PEPEUSDT 32核并行参数优化系统\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

# 加载回测引擎
source("backtest_tradingview_aligned.R")

# 加载数据
cat('正在加载数据...\n')
load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]
cat(sprintf('OK 数据行数: %d\n', nrow(data)))
cat(sprintf('OK 时间范围: %s 至 %s\n\n',
            as.character(index(data)[1]),
            as.character(index(data)[nrow(data)])))

# ============================================================================
# 参数空间定义
# ============================================================================

cat('定义参数空间...\n')

param_grid <- expand.grid(
  lookbackDays = 1:10,
  minDropPercent = seq(0, 20, by = 0.1),
  takeProfitPercent = seq(0, 20, by = 0.1),
  stopLossPercent = seq(0, 20, by = 0.1),
  stringsAsFactors = FALSE
)

total_combinations <- nrow(param_grid)

cat(sprintf('OK 参数组合总数: %d\n\n', total_combinations))

cat('参数范围:\n')
cat(sprintf('  lookbackDays:      %s\n',
            paste(unique(param_grid$lookbackDays), collapse=', ')))
cat(sprintf('  minDropPercent:    %s%%\n',
            paste(range(param_grid$minDropPercent), collapse='%-')))
cat(sprintf('  takeProfitPercent: %s%%\n',
            paste(range(param_grid$takeProfitPercent), collapse='%-')))
cat(sprintf('  stopLossPercent:   %s%%\n\n',
            paste(range(param_grid$stopLossPercent), collapse='%-')))

# ============================================================================
# 设置并行计算
# ============================================================================

n_cores <- 32
cat(sprintf('正在设置并行计算环境...\n'))
cat(sprintf('OK 使用核心数: %d\n', n_cores))

cl <- makeCluster(n_cores)
registerDoParallel(cl)

# 将必要的对象导出到各个核心
cat('OK 导出数据和函数到各核心...\n')
clusterExport(cl, c('data', 'backtest_tradingview_aligned',
                    'generate_drop_signals', 'detect_timeframe_minutes',
                    'days_to_bars'))

# 加载必要的库到各个核心
clusterEvalQ(cl, {
  suppressMessages({
    library(xts)
    library(data.table)
    library(RcppRoll)
  })
})

cat('OK 并行环境设置完成\n\n')

# ============================================================================
# 执行并行优化
# ============================================================================

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('开始32核并行参数优化\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

start_time <- Sys.time()

# 并行执行回测
results <- foreach(i = 1:nrow(param_grid),
                   .combine = 'rbind',
                   .errorhandling = 'pass',
                   .packages = c('xts', 'data.table', 'RcppRoll')) %dopar% {

  params <- param_grid[i, ]

  tryCatch({
    result <- backtest_tradingview_aligned(
      data = data,
      lookbackDays = params$lookbackDays,
      minDropPercent = params$minDropPercent,
      takeProfitPercent = params$takeProfitPercent,
      stopLossPercent = params$stopLossPercent,
      initialCapital = 10000,
      feeRate = 0.00075,
      processOnClose = TRUE,
      verbose = FALSE,
      logIgnoredSignals = FALSE
    )

    # 只保存有效结果
    if (!is.null(result) && result$TradeCount > 0) {
      # 计算夏普比率
      sharpe_ratio <- NA
      if (result$TradeCount >= 3 && !is.na(result$AvgPnL) &&
          length(result$Trades) > 0) {
        pnls <- sapply(result$Trades, function(t) t$PnLPercent)
        sd_pnl <- sd(pnls, na.rm = TRUE)
        if (!is.na(sd_pnl) && sd_pnl > 0) {
          sharpe_ratio <- result$AvgPnL / sd_pnl
        }
      }

      # 计算盈亏比
      profit_factor <- NA
      if (!is.na(result$AvgWin) && !is.na(result$AvgLoss) &&
          result$AvgLoss != 0) {
        profit_factor <- abs(result$AvgWin / result$AvgLoss)
      }

      # 返回结果行
      data.frame(
        lookback = params$lookbackDays,
        minDrop = params$minDropPercent,
        TP = params$takeProfitPercent,
        SL = params$stopLossPercent,
        Trades = result$TradeCount,
        Signals = result$SignalCount,
        Return = result$ReturnPercent,
        WinRate = result$WinRate,
        MaxDD = result$MaxDrawdown,
        AvgPnL = result$AvgPnL,
        Sharpe = sharpe_ratio,
        ProfitFactor = profit_factor,
        Wins = result$WinCount,
        Losses = result$LossCount,
        AvgWin = result$AvgWin,
        AvgLoss = result$AvgLoss,
        MaxWin = result$MaxWin,
        MaxLoss = result$MaxLoss,
        Fees = result$TotalFees,
        stringsAsFactors = FALSE
      )
    } else {
      NULL
    }
  }, error = function(e) {
    NULL
  })
}

# 关闭并行集群
stopCluster(cl)

end_time <- Sys.time()
total_time <- as.numeric(difftime(end_time, start_time, units='secs'))

cat('\n\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('优化完成\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('总耗时: %.1f秒 (%.2f分钟)\n', total_time, total_time/60))
cat(sprintf('有效结果数: %d / %d\n', nrow(results), total_combinations))
cat(sprintf('加速比: %.1fx (相比串行)\n\n',
            (total_combinations * 0.018) / total_time))  # 假设单个回测0.018秒

# ============================================================================
# 结果分析
# ============================================================================

if (nrow(results) > 0) {

  cat('正在分析结果...\n\n')

  # 计算综合评分
  results$Score <- with(results, {
    return_score <- Return / max(Return, na.rm = TRUE)
    winrate_score <- WinRate / 100
    drawdown_penalty <- 1 - abs(MaxDD) / 100
    trade_score <- sqrt(Trades) / sqrt(max(Trades, na.rm = TRUE))
    return_score * winrate_score * drawdown_penalty * trade_score
  })

  # ============================================================================
  # TOP 20 结果展示
  # ============================================================================

  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat('TOP 20 参数组合（按综合评分）\n')
  cat('════════════════════════════════════════════════════════════════════════════\n\n')

  top20_score <- head(results[order(-results$Score), ], 20)

  cat(sprintf('%-4s %-8s %-8s %-6s %-6s %-7s %-9s %-8s %-8s %-10s\n',
              'Rank', 'Lookback', 'MinDrop', 'TP', 'SL', 'Trades',
              'Score', 'Return%', 'WinRate%', 'MaxDD%'))
  cat(paste(rep('─', 100), collapse=''), '\n')

  for (i in 1:nrow(top20_score)) {
    r <- top20_score[i, ]
    cat(sprintf('%-4d %-8d %-8.0f%% %-6.0f%% %-6.0f%% %-7d %-9.4f %-8.2f %-8.1f %-10.1f\n',
                i, r$lookback, r$minDrop, r$TP, r$SL, r$Trades,
                r$Score, r$Return, r$WinRate, r$MaxDD))
  }

  cat('\n\n')
  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat('TOP 20 参数组合（按总收益率）\n')
  cat('════════════════════════════════════════════════════════════════════════════\n\n')

  top20_return <- head(results[order(-results$Return), ], 20)

  cat(sprintf('%-4s %-8s %-8s %-6s %-6s %-7s %-9s %-8s %-8s\n',
              'Rank', 'Lookback', 'MinDrop', 'TP', 'SL', 'Trades',
              'Return%', 'WinRate%', 'MaxDD%'))
  cat(paste(rep('─', 100), collapse=''), '\n')

  for (i in 1:nrow(top20_return)) {
    r <- top20_return[i, ]
    cat(sprintf('%-4d %-8d %-8.0f%% %-6.0f%% %-6.0f%% %-7d %-9.2f %-8.1f %-8.1f\n',
                i, r$lookback, r$minDrop, r$TP, r$SL, r$Trades,
                r$Return, r$WinRate, r$MaxDD))
  }

  cat('\n\n')
  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat('TOP 20 参数组合（按夏普比率）\n')
  cat('════════════════════════════════════════════════════════════════════════════\n\n')

  valid_sharpe <- results[!is.na(results$Sharpe), ]
  top20_sharpe <- head(valid_sharpe[order(-valid_sharpe$Sharpe), ], 20)

  cat(sprintf('%-4s %-8s %-8s %-6s %-6s %-7s %-10s %-9s %-8s\n',
              'Rank', 'Lookback', 'MinDrop', 'TP', 'SL', 'Trades',
              'Sharpe', 'Return%', 'WinRate%'))
  cat(paste(rep('─', 100), collapse=''), '\n')

  for (i in 1:min(20, nrow(top20_sharpe))) {
    r <- top20_sharpe[i, ]
    cat(sprintf('%-4d %-8d %-8.0f%% %-6.0f%% %-6.0f%% %-7d %-10.2f %-9.2f %-8.1f\n',
                i, r$lookback, r$minDrop, r$TP, r$SL, r$Trades,
                r$Sharpe, r$Return, r$WinRate))
  }

  # ============================================================================
  # 保存结果
  # ============================================================================

  cat('\n\n正在保存结果...\n')

  output_dir <- 'optimization'

  write.csv(results,
            file.path(output_dir, 'optimization_results_parallel.csv'),
            row.names = FALSE)

  write.csv(top20_score,
            file.path(output_dir, 'top20_by_score.csv'),
            row.names = FALSE)

  write.csv(top20_return,
            file.path(output_dir, 'top20_by_return.csv'),
            row.names = FALSE)

  write.csv(top20_sharpe,
            file.path(output_dir, 'top20_by_sharpe.csv'),
            row.names = FALSE)

  cat('\nOK 结果已保存:\n')
  cat(sprintf('   - %s (所有结果)\n',
              file.path(output_dir, 'optimization_results_parallel.csv')))
  cat(sprintf('   - %s\n', file.path(output_dir, 'top20_by_score.csv')))
  cat(sprintf('   - %s\n', file.path(output_dir, 'top20_by_return.csv')))
  cat(sprintf('   - %s\n\n', file.path(output_dir, 'top20_by_sharpe.csv')))

  # ============================================================================
  # 最佳参数推荐
  # ============================================================================

  best_params <- top20_score[1, ]

  cat('\n')
  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat('🏆 最佳参数推荐（综合评分）\n')
  cat('════════════════════════════════════════════════════════════════════════════\n\n')

  cat('【参数配置】\n')
  cat(sprintf('  lookbackDays:      %d\n', best_params$lookback))
  cat(sprintf('  minDropPercent:    %.0f%%\n', best_params$minDrop))
  cat(sprintf('  takeProfitPercent: %.0f%%\n', best_params$TP))
  cat(sprintf('  stopLossPercent:   %.0f%%\n\n', best_params$SL))

  cat('【绩效指标】\n')
  cat(sprintf('  交易数量:   %d\n', best_params$Trades))
  cat(sprintf('  总收益率:   %.2f%%\n', best_params$Return))
  cat(sprintf('  胜率:       %.1f%% (%d胜/%d负)\n',
              best_params$WinRate, best_params$Wins, best_params$Losses))
  cat(sprintf('  最大回撤:   %.1f%%\n', best_params$MaxDD))
  cat(sprintf('  夏普比率:   %.2f\n',
              ifelse(is.na(best_params$Sharpe), 0, best_params$Sharpe)))
  cat(sprintf('  盈亏比:     %.2f\n',
              ifelse(is.na(best_params$ProfitFactor), 0, best_params$ProfitFactor)))
  cat(sprintf('  综合评分:   %.4f\n\n', best_params$Score))

  # 其他推荐
  best_return <- top20_return[1, ]
  cat('【收益率最高】\n')
  cat(sprintf('  参数: lookback=%d, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n',
              best_return$lookback, best_return$minDrop,
              best_return$TP, best_return$SL))
  cat(sprintf('  收益率: %.2f%% (%d笔交易, 胜率%.1f%%)\n\n',
              best_return$Return, best_return$Trades, best_return$WinRate))

  if (nrow(top20_sharpe) > 0) {
    best_sharpe <- top20_sharpe[1, ]
    cat('【夏普比率最高】\n')
    cat(sprintf('  参数: lookback=%d, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n',
                best_sharpe$lookback, best_sharpe$minDrop,
                best_sharpe$TP, best_sharpe$SL))
    cat(sprintf('  夏普比率: %.2f (收益%.2f%%, %d笔交易)\n\n',
                best_sharpe$Sharpe, best_sharpe$Return, best_sharpe$Trades))
  }

  cat('════════════════════════════════════════════════════════════════════════════\n\n')

} else {
  cat('FAIL 没有找到有效的参数组合\n')
}

cat('\n🎉 32核并行优化完成!\n\n')
