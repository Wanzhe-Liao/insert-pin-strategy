# ============================================================================
# Debug: PEPEUSDT_15m trade mismatch (close mode)
# ----------------------------------------------------------------------------
# Helps determine whether mismatches vs `data/tradingview_trades.csv` are:
# - code/logic bugs (exit condition not triggering when it should), or
# - data feed differences (OHLC differs vs TradingView)
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
})

source("backtest_tradingview_aligned.R", encoding = "UTF-8")
load("data/liaochu.RData")

d <- cryptodata[["PEPEUSDT_15m"]]

res <- backtest_tradingview_aligned(
  data = d,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,
  logIgnoredSignals = TRUE,
  includeCurrentBar = TRUE,
  exitMode = "close"
)

stopifnot(length(res$Trades) >= 3)
t3 <- res$Trades[[3]]

entry_bar <- t3$EntryBar
exit_bar <- t3$ExitBar
entry_price <- t3$EntryPrice
tp_price <- entry_price * 1.10
sl_price <- entry_price * 0.90

close_vec <- as.numeric(d[, "Close"])
window_close <- close_vec[entry_bar:exit_bar]

first_tp_rel <- which(window_close >= tp_price)[1]
first_sl_rel <- which(window_close <= sl_price)[1]

cat("Trade #3 (R close mode)\n")
cat(sprintf("EntryBar=%d EntryTime=%s EntryPrice=%.10f\n", entry_bar, t3$EntryTime, entry_price))
cat(sprintf("TP=%.10f SL=%.10f\n", tp_price, sl_price))
cat(sprintf("Recorded ExitBar=%d ExitTime=%s ExitPrice=%.10f Reason=%s\n\n",
            exit_bar, t3$ExitTime, t3$ExitPrice, t3$ExitReason))

cat("Close path diagnostics within [EntryBar..ExitBar]\n")
cat(sprintf("- Max close: %.10f\n", max(window_close, na.rm = TRUE)))
cat(sprintf("- Min close: %.10f\n", min(window_close, na.rm = TRUE)))
cat(sprintf("- First bar where close>=TP: %s\n",
            ifelse(is.na(first_tp_rel), "NONE", as.character(entry_bar + first_tp_rel - 1))))
cat(sprintf("- First bar where close<=SL: %s\n",
            ifelse(is.na(first_sl_rel), "NONE", as.character(entry_bar + first_sl_rel - 1))))

