# ============================================================================
# PEPEUSDT 参数优化系统
# ============================================================================
#
# 目标：找出最优参数组合
# 方法：网格搜索 (Grid Search)
# 评估指标：夏普比率、收益率、胜率、最大回撤等
#
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
})

# 加载回测引擎
source("backtest_tradingview_aligned.R")

# 加载数据
cat('\n正在加载数据...\n')
load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]
cat(sprintf('数据行数: %d\n', nrow(data)))
cat(sprintf('时间范围: %s 至 %s\n\n',
            as.character(index(data)[1]),
            as.character(index(data)[nrow(data)])))

# ============================================================================
# 参数空间定义（细粒度搜索）
# ============================================================================

tp_seq <- seq(5, 20, by = 1)
param_grid <- expand.grid(
  lookbackDays = 3:7,                                  # 回看周期：3-7天
  minDropPercent = seq(5, 20, by = 1),                 # 触发跌幅：5%-20%，步长1%
  takeProfitPercent = tp_seq,                          # 止盈：5%-20%，步长1%
  stopLossPercent = tp_seq,                            # 止损：5%-20%，步长1%
  stringsAsFactors = FALSE
)

total_combinations <- nrow(param_grid)

cat('============================================================================\n')
cat('参数优化配置\n')
cat('============================================================================\n\n')
cat(sprintf('参数组合总数: %d\n', total_combinations))
cat('\n参数范围:\n')
cat(sprintf('  lookbackDays:      %s\n', paste(unique(param_grid$lookbackDays), collapse=', ')))
cat(sprintf('  minDropPercent:    %s%%\n', paste(unique(param_grid$minDropPercent), collapse='%, ')))
cat(sprintf('  takeProfitPercent: %s%%\n', paste(unique(param_grid$takeProfitPercent), collapse='%, ')))
cat(sprintf('  stopLossPercent:   %s%%\n\n', paste(unique(param_grid$stopLossPercent), collapse='%, ')))

# ============================================================================
# 执行参数优化
# ============================================================================

cat('开始参数优化...\n\n')
start_time <- Sys.time()

# 结果存储
results <- list()
result_idx <- 0

# 进度条设置
progress_interval <- max(1, floor(total_combinations / 20))

for (i in 1:total_combinations) {
  params <- param_grid[i, ]

  # 显示进度
  if (i %% progress_interval == 0 || i == total_combinations) {
    progress_pct <- (i / total_combinations) * 100
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units='secs'))
    eta <- (elapsed / i) * (total_combinations - i)

    cat(sprintf('\r进度: %d/%d (%.1f%%) | 已用时: %.1fs | 预计剩余: %.1fs',
                i, total_combinations, progress_pct, elapsed, eta))
  }

  # 运行回测（禁用详细输出）
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

    # 只保存有效结果（至少有1笔交易）
    if (!is.null(result) && result$TradeCount > 0) {
      result_idx <- result_idx + 1

      # 计算额外指标
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

      # 保存结果
      results[[result_idx]] <- list(
        # 参数
        lookbackDays = params$lookbackDays,
        minDropPercent = params$minDropPercent,
        takeProfitPercent = params$takeProfitPercent,
        stopLossPercent = params$stopLossPercent,

        # 绩效指标
        TradeCount = result$TradeCount,
        SignalCount = result$SignalCount,
        ReturnPercent = result$ReturnPercent,
        WinRate = result$WinRate,
        MaxDrawdown = result$MaxDrawdown,
        AvgPnL = result$AvgPnL,
        SharpeRatio = sharpe_ratio,
        ProfitFactor = profit_factor,

        # 交易统计
        WinCount = result$WinCount,
        LossCount = result$LossCount,
        AvgWin = result$AvgWin,
        AvgLoss = result$AvgLoss,
        MaxWin = result$MaxWin,
        MaxLoss = result$MaxLoss,

        # 成本
        TotalFees = result$TotalFees,

        # 完整结果
        FullResult = result
      )
    }
  }, error = function(e) {
    # 忽略错误，继续下一个参数组合
  })
}

cat('\n\n')

end_time <- Sys.time()
total_time <- as.numeric(difftime(end_time, start_time, units='secs'))

cat('============================================================================\n')
cat('优化完成\n')
cat('============================================================================\n\n')
cat(sprintf('总耗时: %.1f秒 (%.1f分钟)\n', total_time, total_time/60))
cat(sprintf('有效结果数: %d / %d\n\n', length(results), total_combinations))

# ============================================================================
# 结果分析和排序
# ============================================================================

if (length(results) > 0) {
  cat('正在分析结果...\n\n')

  # 转换为数据框
  results_df <- do.call(rbind, lapply(results, function(r) {
    data.frame(
      lookback = r$lookbackDays,
      minDrop = r$minDropPercent,
      TP = r$takeProfitPercent,
      SL = r$stopLossPercent,
      Trades = r$TradeCount,
      Signals = r$SignalCount,
      Return = r$ReturnPercent,
      WinRate = r$WinRate,
      MaxDD = r$MaxDrawdown,
      AvgPnL = r$AvgPnL,
      Sharpe = r$SharpeRatio,
      ProfitFactor = r$ProfitFactor,
      Wins = r$WinCount,
      Losses = r$LossCount,
      AvgWin = r$AvgWin,
      AvgLoss = r$AvgLoss,
      MaxWin = r$MaxWin,
      MaxLoss = r$MaxLoss,
      Fees = r$TotalFees,
      stringsAsFactors = FALSE
    )
  }))

  # ============================================================================
  # Top 20 按不同指标排序
  # ============================================================================

  cat('============================================================================\n')
  cat('TOP 20 参数组合（按总收益率）\n')
  cat('============================================================================\n\n')

  top20_return <- head(results_df[order(-results_df$Return), ], 20)

  cat(sprintf('%-4s %-8s %-8s %-6s %-6s %-7s %-9s %-8s %-8s %-10s\n',
              'Rank', 'Lookback', 'MinDrop', 'TP', 'SL', 'Trades',
              'Return%', 'WinRate%', 'MaxDD%', 'Sharpe'))
  cat(paste(rep('─', 100), collapse=''), '\n')

  for (i in 1:nrow(top20_return)) {
    r <- top20_return[i, ]
    cat(sprintf('%-4d %-8d %-8.0f%% %-6.0f%% %-6.0f%% %-7d %-9.2f %-8.1f %-8.1f %-10.2f\n',
                i, r$lookback, r$minDrop, r$TP, r$SL, r$Trades,
                r$Return, r$WinRate, r$MaxDD,
                ifelse(is.na(r$Sharpe), 0, r$Sharpe)))
  }

  cat('\n\n')
  cat('============================================================================\n')
  cat('TOP 20 参数组合（按夏普比率）\n')
  cat('============================================================================\n\n')

  # 过滤掉NA的夏普比率
  valid_sharpe <- results_df[!is.na(results_df$Sharpe), ]
  top20_sharpe <- head(valid_sharpe[order(-valid_sharpe$Sharpe), ], 20)

  cat(sprintf('%-4s %-8s %-8s %-6s %-6s %-7s %-10s %-9s %-8s %-8s\n',
              'Rank', 'Lookback', 'MinDrop', 'TP', 'SL', 'Trades',
              'Sharpe', 'Return%', 'WinRate%', 'MaxDD%'))
  cat(paste(rep('─', 100), collapse=''), '\n')

  for (i in 1:min(20, nrow(top20_sharpe))) {
    r <- top20_sharpe[i, ]
    cat(sprintf('%-4d %-8d %-8.0f%% %-6.0f%% %-6.0f%% %-7d %-10.2f %-9.2f %-8.1f %-8.1f\n',
                i, r$lookback, r$minDrop, r$TP, r$SL, r$Trades,
                r$Sharpe, r$Return, r$WinRate, r$MaxDD))
  }

  cat('\n\n')
  cat('============================================================================\n')
  cat('TOP 20 参数组合（按胜率）\n')
  cat('============================================================================\n\n')

  # 只考虑至少5笔交易的参数组合
  min_trades_for_winrate <- results_df[results_df$Trades >= 5, ]
  top20_winrate <- head(min_trades_for_winrate[order(-min_trades_for_winrate$WinRate), ], 20)

  cat(sprintf('%-4s %-8s %-8s %-6s %-6s %-7s %-9s %-9s %-8s\n',
              'Rank', 'Lookback', 'MinDrop', 'TP', 'SL', 'Trades',
              'WinRate%', 'Return%', 'MaxDD%'))
  cat(paste(rep('─', 100), collapse=''), '\n')

  for (i in 1:min(20, nrow(top20_winrate))) {
    r <- top20_winrate[i, ]
    cat(sprintf('%-4d %-8d %-8.0f%% %-6.0f%% %-6.0f%% %-7d %-9.1f %-9.2f %-8.1f\n',
                i, r$lookback, r$minDrop, r$TP, r$SL, r$Trades,
                r$WinRate, r$Return, r$MaxDD))
  }

  # ============================================================================
  # 综合评分排名
  # ============================================================================

  cat('\n\n')
  cat('============================================================================\n')
  cat('TOP 20 参数组合（综合评分）\n')
  cat('============================================================================\n\n')
  cat('评分公式: Return * WinRate * (1 - MaxDD/100) * sqrt(Trades) / 1000\n')
  cat('（权衡收益、胜率、回撤和交易数量）\n\n')

  # 计算综合评分
  results_df$Score <- with(results_df, {
    # 归一化处理
    return_score <- Return / max(Return, na.rm = TRUE)
    winrate_score <- WinRate / 100
    drawdown_penalty <- 1 - abs(MaxDD) / 100
    trade_score <- sqrt(Trades) / sqrt(max(Trades, na.rm = TRUE))

    # 综合评分
    return_score * winrate_score * drawdown_penalty * trade_score
  })

  top20_score <- head(results_df[order(-results_df$Score), ], 20)

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

  # ============================================================================
  # 保存结果
  # ============================================================================

  cat('\n\n正在保存结果...\n')

  # 保存完整结果
  write.csv(results_df,
            'outputs/optimization_results.csv',
            row.names = FALSE)

  # 保存Top参数组合的详细回测结果
  best_params <- top20_score[1, ]
  best_result_idx <- which(
    results_df$lookback == best_params$lookback &
    results_df$minDrop == best_params$minDrop &
    results_df$TP == best_params$TP &
    results_df$SL == best_params$SL
  )[1]

  if (!is.na(best_result_idx)) {
    best_full_result <- results[[best_result_idx]]$FullResult

    # 保存最佳参数的交易详情
    if (length(best_full_result$Trades) > 0) {
      best_trades_df <- format_trades_df(best_full_result)
      write.csv(best_trades_df,
                'outputs/best_params_trades.csv',
                row.names = FALSE)
    }
  }

  cat('\nOK 结果已保存:\n')
  cat('   - optimization_results.csv (所有参数组合)\n')
  cat('   - best_params_trades.csv (最佳参数的交易详情)\n')

  # ============================================================================
  # 最佳参数推荐
  # ============================================================================

  cat('\n\n')
  cat('════════════════════════════════════════════════════════════════════════════\n')
  cat('最佳参数推荐\n')
  cat('════════════════════════════════════════════════════════════════════════════\n\n')

  cat('【综合评分最优】\n')
  cat(sprintf('  lookbackDays:      %d\n', best_params$lookback))
  cat(sprintf('  minDropPercent:    %.0f%%\n', best_params$minDrop))
  cat(sprintf('  takeProfitPercent: %.0f%%\n', best_params$TP))
  cat(sprintf('  stopLossPercent:   %.0f%%\n\n', best_params$SL))

  cat('【绩效指标】\n')
  cat(sprintf('  交易数量:   %d\n', best_params$Trades))
  cat(sprintf('  总收益率:   %.2f%%\n', best_params$Return))
  cat(sprintf('  胜率:       %.1f%%\n', best_params$WinRate))
  cat(sprintf('  最大回撤:   %.1f%%\n', best_params$MaxDD))
  cat(sprintf('  夏普比率:   %.2f\n', ifelse(is.na(best_params$Sharpe), 0, best_params$Sharpe)))
  cat(sprintf('  综合评分:   %.4f\n\n', best_params$Score))

  # 收益率最高的参数
  best_return <- top20_return[1, ]
  cat('【收益率最高】\n')
  cat(sprintf('  参数: lookback=%d, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n',
              best_return$lookback, best_return$minDrop,
              best_return$TP, best_return$SL))
  cat(sprintf('  收益率: %.2f%% (%d笔交易)\n\n',
              best_return$Return, best_return$Trades))

  # 胜率最高的参数
  if (nrow(top20_winrate) > 0) {
    best_winrate <- top20_winrate[1, ]
    cat('【胜率最高】\n')
    cat(sprintf('  参数: lookback=%d, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n',
                best_winrate$lookback, best_winrate$minDrop,
                best_winrate$TP, best_winrate$SL))
    cat(sprintf('  胜率: %.1f%% (%d笔交易, 收益%.2f%%)\n\n',
                best_winrate$WinRate, best_winrate$Trades, best_winrate$Return))
  }

  cat('════════════════════════════════════════════════════════════════════════════\n\n')

} else {
  cat('FAIL 没有找到有效的参数组合\n')
}

cat('优化完成!\n\n')
