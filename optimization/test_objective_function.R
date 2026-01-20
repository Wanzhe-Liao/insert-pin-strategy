suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
})

cat('\n测试贝叶斯优化目标函数\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

source("backtest_tradingview_aligned.R")

cat('加载数据...\n')
load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]
cat(sprintf('OK 数据行数: %d\n\n', nrow(data)))

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
    cat(sprintf('错误: %s\n', e$message))
    return(list(Score = 0))
  })
}

cat('测试已知最优参数 (lookback=3, drop=8%, TP=6%, SL=20%)...\n\n')

test_result <- objective_function(
  lookbackDays = 3,
  minDropPercent = 8.0,
  takeProfitPercent = 6.0,
  stopLossPercent = 20.0
)

cat(sprintf('OK 目标函数返回值: %.4f\n\n', test_result$Score))

cat('测试另一组参数 (lookback=5, drop=10%, TP=10%, SL=10%)...\n\n')

test_result2 <- objective_function(
  lookbackDays = 5,
  minDropPercent = 10.0,
  takeProfitPercent = 10.0,
  stopLossPercent = 10.0
)

cat(sprintf('OK 目标函数返回值: %.4f\n\n', test_result2$Score))

cat('════════════════════════════════════════════════════════════════════════════\n')
cat('OK 目标函数测试通过！可以开始贝叶斯优化。\n\n')
