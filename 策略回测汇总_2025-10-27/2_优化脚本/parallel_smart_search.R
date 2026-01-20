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
cat('PEPEUSDT 32核真并行智能搜索系统 (加权加法目标函数)\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat('目标函数: 加权加法模型\n')
cat('  Score = 0.35×收益率 + 0.30×回撤控制 + 0.05×胜率 + 0.30×交易数量\n')
cat('  • 收益率权重 (35%) - 盈利目标\n')
cat('  • 回撤控制保持 (30%) - 风险管理不可忽视\n')
cat('  • 交易数量强调 (30%) - 高频策略优先\n')
cat('  • 胜率降低 (5%) - 可通过频率弥补\n\n')

source("backtest_tradingview_aligned.R")

cat('正在加载数据...\n')
load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]
cat(sprintf('OK 数据行数: %d\n', nrow(data)))
cat(sprintf('OK 时间范围: %s 至 %s\n\n',
            as.character(index(data)[1]),
            as.character(index(data)[nrow(data)])))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('多阶段智能采样策略\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

n_phase1 <- 5000
n_phase2 <- 10000
n_phase3 <- 5000

cat(sprintf('阶段1: 全空间随机采样   %d次 (精度0.05)\n', n_phase1))
cat(sprintf('阶段2: Top区域聚焦采样  %d次 (精度0.05, 聚焦Top 20%%)\n', n_phase2))
cat(sprintf('阶段3: 精英区域细化搜索 %d次 (精度0.05, 聚焦Top 10%%)\n', n_phase3))
cat(sprintf('\n总试验次数: %d\n', n_phase1 + n_phase2 + n_phase3))
cat(sprintf('并行核心数: 32\n\n'))
cat('参数空间: 10 × 401³ = 645,210,010 种组合\n')
cat('  • lookbackDays:      1-10\n')
cat('  • minDropPercent:    0%-20% (步长0.05)\n')
cat('  • takeProfitPercent: 0%-20% (步长0.05)\n')
cat('  • stopLossPercent:   0%-20% (步长0.05)\n\n')

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

objective_function <- function(params_df) {
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

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('阶段1: 粗粒度随机采样 (步长1.0)\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

start_time <- Sys.time()

set.seed(42)
phase1_params <- data.frame(
  lookback = sample(1:10, n_phase1, replace = TRUE),
  minDrop = round(runif(n_phase1, 0, 20) * 20) / 20,
  TP = round(runif(n_phase1, 0, 20) * 20) / 20,
  SL = round(runif(n_phase1, 0, 20) * 20) / 20
)

phase1_results <- objective_function(phase1_params)

phase1_time <- as.numeric(difftime(Sys.time(), start_time, units='secs'))
cat(sprintf('\n阶段1完成: %.1f秒 (%.2f次/秒)\n', phase1_time, n_phase1/phase1_time))
cat(sprintf('当前最佳得分: %.4f\n\n', max(phase1_results$score)))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('阶段2: 中粒度聚焦采样 (步长0.5)\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

top20_pct_threshold <- quantile(phase1_results$score, 0.80)
top_params <- phase1_results[phase1_results$score >= top20_pct_threshold, ]

if (nrow(top_params) < 5) {
  top_params <- phase1_results[order(-phase1_results$score), ][1:min(10, nrow(phase1_results)), ]
}

cat(sprintf('聚焦Top 20%%区域 (得分 >= %.4f)\n', top20_pct_threshold))
cat(sprintf('基准参数数量: %d\n\n', nrow(top_params)))

set.seed(43)
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

phase2_start <- Sys.time()
phase2_results <- objective_function(phase2_params)
phase2_time <- as.numeric(difftime(Sys.time(), phase2_start, units='secs'))

all_results <- rbind(phase1_results, phase2_results)

cat(sprintf('\n阶段2完成: %.1f秒 (%.2f次/秒)\n', phase2_time, n_phase2/phase2_time))
cat(sprintf('当前最佳得分: %.4f\n\n', max(all_results$score)))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('阶段3: 细粒度精细搜索 (步长0.1)\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

top10_pct_threshold <- quantile(all_results$score, 0.90)
elite_params <- all_results[all_results$score >= top10_pct_threshold, ]

if (nrow(elite_params) < 5) {
  elite_params <- all_results[order(-all_results$score), ][1:min(10, nrow(all_results)), ]
}

cat(sprintf('聚焦Top 10%%精英区域 (得分 >= %.4f)\n', top10_pct_threshold))
cat(sprintf('精英参数数量: %d\n\n', nrow(elite_params)))

set.seed(44)
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

phase3_start <- Sys.time()
phase3_results <- objective_function(phase3_params)
phase3_time <- as.numeric(difftime(Sys.time(), phase3_start, units='secs'))

final_results <- rbind(all_results, phase3_results)

stopCluster(cl)

total_time <- as.numeric(difftime(Sys.time(), start_time, units='secs'))

cat(sprintf('\n阶段3完成: %.1f秒 (%.2f次/秒)\n', phase3_time, n_phase3/phase3_time))
cat(sprintf('最终最佳得分: %.4f\n\n', max(final_results$score)))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('优化完成\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('总耗时: %.1f秒 (%.2f分钟)\n', total_time, total_time/60))
cat(sprintf('总试验次数: %d\n', nrow(final_results)))
cat(sprintf('平均速度: %.2f次/秒\n', nrow(final_results)/total_time))
cat(sprintf('理论加速比: %.1fx\n\n', nrow(final_results)/(total_time/32)))

best_idx <- which.max(final_results$score)
best_params <- final_results[best_idx, ]

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('🏆 最佳参数\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')
cat(sprintf('lookbackDays:      %d\n', best_params$lookback))
cat(sprintf('minDropPercent:    %.1f%%\n', best_params$minDrop))
cat(sprintf('takeProfitPercent: %.1f%%\n', best_params$TP))
cat(sprintf('stopLossPercent:   %.1f%%\n\n', best_params$SL))

cat('【绩效指标】\n')
cat(sprintf('综合评分:   %.4f\n', best_params$score))
cat(sprintf('总收益率:   %.2f%%\n', best_params$return_pct))
cat(sprintf('胜率:       %.1f%%\n', best_params$win_rate))
cat(sprintf('最大回撤:   %.1f%%\n', best_params$max_dd))
cat(sprintf('交易数量:   %d\n\n', best_params$trades))

output_dir <- 'optimization'

write.csv(final_results,
          file.path(output_dir, 'parallel_search_all_results.csv'),
          row.names = FALSE)
cat(sprintf('OK 已保存: %s\n', file.path(output_dir, 'parallel_search_all_results.csv')))

top20 <- final_results[order(-final_results$score), ][1:20, ]
write.csv(top20,
          file.path(output_dir, 'parallel_search_top20.csv'),
          row.names = FALSE)
cat(sprintf('OK 已保存: %s\n\n', file.path(output_dir, 'parallel_search_top20.csv')))

cat('🎉 真32核并行优化完成!\n\n')
